import SwiftUI
import UniformTypeIdentifiers

/// 備份匯入的檔案讀取（階段 8）：fileImporter 與分享表單入的
/// URL 都可能是 security-scoped，統一在此開啟存取權、讀入、
/// 組裝 plan。任何失敗只回傳錯誤、不碰 store 現有數據。
enum BackupFileAccess {
    static func loadPlan(from url: URL) -> Result<BackupImporter.ImportPlan, Error> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            return .success(try BackupImporter.makePlan(from: data))
        } catch {
            return .failure(error)
        }
    }
}

/// 匯入確認 sheet（階段 8）：先預覽將匯入的段與逐項說明，
/// 用戶按下「確認匯入」才 applyImport；取消即零副作用
/// （pendingImportPlan 清空、store 未寫入任何欄位）。
struct BackupImportSheet: View {
    @ObservedObject var store: AppStore
    let plan: BackupImporter.ImportPlan
    @Environment(\.colorScheme) private var colorScheme
    /// 【邏輯補查】關閉改走環境 dismiss：呈現綁定已改為
    /// ContentView 的 presentedImportPlan 副本（與
    /// activeSheet 串行），只清 store 真源不再能關閉本
    /// sheet——兩按鈕均須清真源＋dismiss 雙路並行。
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section(theme: theme, title: L10n.t("将汇入的内容")) {
                            ForEach(plan.summaryLines, id: \.self) { line in
                                Text(L10n.t(line))
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(theme.textPrimary)
                            }
                        }
                        if !plan.unmappedKeys.isEmpty {
                            section(theme: theme, title: L10n.t("未随备份汇入")) {
                                ForEach(plan.unmappedKeys, id: \.self) { key in
                                    Text(key)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(theme.textMuted)
                                }
                            }
                        }
                        if !plan.warnings.isEmpty {
                            section(theme: theme, title: L10n.t("注意事项")) {
                                ForEach(plan.warnings, id: \.self) { warning in
                                    Text(L10n.t(warning))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(L10n.t("导入备份"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("取消")) {
                        store.pendingImportPlan = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("确认导入")) {
                        store.applyImport(plan)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(theme: TunerTheme, title: String,
                         @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme, title: title)
            content()
        }
    }
}
