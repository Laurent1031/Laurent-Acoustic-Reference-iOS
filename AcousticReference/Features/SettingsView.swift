import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 設定兩面（階段 5），入口在 ContentView 頂欄（比照母本頂欄的
/// 「偏好」「设置」兩鈕與兩張頂部錨定 sheet）：
/// - PreferencesView = 母本 profileModal「校音与节拍偏好」：
///   交易式——開啟時以 store 現值初始化草稿，編輯只動草稿，
///   「完成」一次套用、「取消」整份丟棄。母本為即時套用＋
///   取消回滾快照，淨效果相同；差異在時機：母本的主樂器
///   切換與律制 toast／Drone 改頻在編輯當下發生，原生改於
///   「完成」時發生（sheet 覆蓋下主畫面不可見，Drone 改頻
///   經 ContentView 的 tunerSettings 同步在完成後即刻跟上）。
///   母本的完成／取消 toast（偏好参数已保存／已取消偏好更改）
///   未移植：原生調音頁無 toast 通道，sheet 關閉＋主畫面
///   數值即回饋（有意差異，報告註明）。
/// - SystemSettingsView = 母本 settingsModal「系统设置」：
///   即時生效（母本同），含語言／外觀／玻璃不透明度（本頁
///   卡片即以 GlassSurface 渲染，拖動當下即預覽）／震動／
///   音效／藍牙補償＋屏幕常亮資訊列。數據備份導入於階段 8
///   補齊；自訂背景與備份導出於裝機返修批補齊（Laurent
///   實機點名缺失）。未移植僅剩：贊賞支持／聯繫我們
///   （內容性條目）。

// MARK: - 共用組件

/// 設定分組卡（玻璃面＋組內分隔線）。
struct SettingsGroup<Content: View>: View {
    let theme: TunerTheme
    let glassOpacity: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                         theme: theme, glassOpacity: glassOpacity)
    }
}

/// 標籤＋副標（母本 .setting-label/.setting-sub）。
struct SettingsLabel: View {
    let theme: TunerTheme
    let title: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            if let sub {
                Text(sub)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 母本 .mini-chip 列：等寬分配、單行、長字串語言縮放不擠爆。
/// 軌道玻璃同樣受 glassOpacity 驅動（與全 App 一致）。
private struct SettingsChips<Option: Hashable>: View {
    let theme: TunerTheme
    let glassOpacity: Int
    let options: [(value: Option, label: String)]
    @Binding var selection: Option

    var body: some View {
        // 【返修批12・統一分段】改全 App 統一的 Segmen-
        // tedSwitch（見 TunerTheme）：批11 的原生分段
        // Picker 在偏好頁實機全部切換不過去，Laurent
        // 定版所有切換向調音頁記譜／實音看齊（按鈕式
        // 切換＋選中變色／變底）。等寬分配由組件的等分
        // 格位提供。
        SegmentedSwitch(
            options: options.map {
                (option: $0.value, title: $0.label, symbol: nil)
            },
            selection: $selection,
            theme: theme, glassOpacity: glassOpacity,
            fontSize: 12.5, height: 30)
    }
}

// MARK: - 偏好（交易式）

struct PreferencesView: View {
    @ObservedObject var store: AppStore
    /// 目前節拍器參數（「設為默認」的來源，ContentView 注入
    /// ViewModel 現值快照；本頁不直接改節拍器現行值）。
    let currentMetronomeSettings: MetronomeSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draftPrimaryId: String
    @State private var draftPitchMode: PitchMode
    @State private var draftDamping: DampingProfile
    @State private var draftTolerance: Double
    @State private var draftNoiseGate: NoiseGateProfile
    @State private var draftAutoMic: Bool
    @State private var draftTemperament: Temperament
    @State private var draftJustTonicPc: Int
    @State private var draftA4: Double
    /// 「設為默認」的待套用值（nil = 本次未動此項）。
    @State private var draftMetroDefault: MetronomeSettings?

    init(store: AppStore, currentMetronomeSettings: MetronomeSettings) {
        self.store = store
        self.currentMetronomeSettings = currentMetronomeSettings
        let settings = store.tunerSettings
        _draftPrimaryId = State(initialValue: store.primaryInstrumentId)
        _draftPitchMode = State(initialValue: store.pitchMode)
        _draftDamping = State(initialValue: settings.damping)
        _draftTolerance = State(initialValue: settings.toleranceCents)
        _draftNoiseGate = State(initialValue: settings.noiseGate)
        _draftAutoMic = State(initialValue: store.autoMicOnEnter)
        _draftTemperament = State(initialValue: settings.temperament)
        _draftJustTonicPc = State(initialValue: settings.justTonicPc)
        _draftA4 = State(initialValue: settings.a4)
        _draftMetroDefault = State(initialValue: nil)
    }

    /// 容差選項（審計修復）：固定三檔之外，草稿值若為匯入等
    /// 路徑帶入的任意值（如網頁版常見的 2.5），動態插入一檔
    /// 令選中態如實對應生效值——此前分段控件找不到匹配時
    /// 回退第一格，顯示「严苛 ±1.5¢」而實際生效 2.5，顯示
    /// 與生效不一致（數據本身不丟）。
    private var toleranceOptions: [(Double, String)] {
        var options: [(Double, String)] = [
            (1.5, L10n.t("严苛 ±1.5¢")),
            (3.0, L10n.t("乐团 ±3.0¢")),
            (4.0, L10n.t("宽容 ±4.0¢")),
        ]
        if !options.contains(where: { $0.0 == draftTolerance }) {
            let label = String(format: "±%.1f¢", draftTolerance)
            let idx = options.firstIndex { $0.0 > draftTolerance } ?? options.count
            options.insert((draftTolerance, label), at: idx)
        }
        return options
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        instrumentGroup(theme: theme)
                        responseGroup(theme: theme)
                        temperamentGroup(theme: theme)
                        metroDefaultGroup(theme: theme)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(L10n.t("校音与节拍偏好"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("完成")) { applyAndDismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: 組一：主樂器＋顯示制式＋A4

    private func instrumentGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            HStack {
                SettingsLabel(theme: theme,
                              title: L10n.t("默认启动主乐器"),
                              sub: L10n.t("启动时自动载入的首选乐器"))
                Spacer(minLength: 8)
                Picker(L10n.t("默认启动主乐器"), selection: $draftPrimaryId) {
                    ForEach(store.allInstruments) { inst in
                        Text(L10n.localizedName(inst.name)).tag(inst.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            HStack {
                SettingsLabel(theme: theme,
                              title: L10n.t("默认音高显示制式"),
                              sub: L10n.t("大字读数优先展示记谱音或实音"))
                Spacer(minLength: 8)
                SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                              options: [(PitchMode.written, L10n.t("记谱音")),
                                        (PitchMode.concert, L10n.t("实音"))],
                              selection: $draftPitchMode)
                    .frame(maxWidth: 190)
            }

            Divider()

            HStack {
                SettingsLabel(theme: theme,
                              title: L10n.t("默认 A4"),
                              sub: L10n.t("与调音页的 A4 步进器同步"))
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    HoldRepeatButton(action: { stepDraftA4(-0.5) }, label: {
                        Text("−")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 30, height: 32)
                    })
                    Button {
                        let presets = TunerSettings.a4Presets
                        draftA4 = presets.first { $0 > draftA4 } ?? presets[0]
                    } label: {
                        Text(String(format: "A4=%.1f", draftA4))
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                            .frame(height: 32)
                    }
                    // 【返修批7・E13】命中高 32→40（透明
                    // padding，視覺不變）。
                    .padding(.vertical, 4)
                    .buttonStyle(GlassPressButtonStyle())
                    HoldRepeatButton(action: { stepDraftA4(0.5) }, label: {
                        Text("+")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 30, height: 32)
                    })
                }
                .padding(.horizontal, 4)
                .glassBackground(in: Capsule(), theme: theme,
                                 glassOpacity: store.glassOpacity)
            }
        }
    }

    private func stepDraftA4(_ delta: Double) {
        let stepped = ((draftA4 + delta) * 10).rounded() / 10
        draftA4 = min(450, max(430, stepped))
    }

    // MARK: 組二：阻尼／容差／抗噪／自動麥克風

    private func responseGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("指针阻尼与响应速度"),
                          sub: L10n.t("独奏抓音头选灵敏，长音稳定训练选平稳"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: [(DampingProfile.fast, L10n.t("灵敏 Fast")),
                                    (DampingProfile.balanced, L10n.t("标准 Balanced")),
                                    (DampingProfile.smooth, L10n.t("平稳 Smooth"))],
                          selection: $draftDamping)

            SettingsLabel(theme: theme,
                          title: L10n.t("准音判定容差范围"),
                          sub: L10n.t("决定指针与沉浸式全屏变绿的判定松紧"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: toleranceOptions,
                          selection: $draftTolerance)

            SettingsLabel(theme: theme,
                          title: L10n.t("环境抗噪阈值 (Noise Gate)"),
                          sub: L10n.t("合奏排练时调高可过滤身旁乐手串音"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: [(NoiseGateProfile.low, L10n.t("安静琴房")),
                                    (NoiseGateProfile.mid, L10n.t("常规排练")),
                                    (NoiseGateProfile.high, L10n.t("合奏抗串音"))],
                          selection: $draftNoiseGate)

            SettingsLabel(theme: theme,
                          title: L10n.t("自动开启麦克风"),
                          sub: L10n.t("在调音页点按任意处或切换到调音时自动开启"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: [(true, L10n.t("自动开启")),
                                    (false, L10n.t("仅手动开启"))],
                          selection: $draftAutoMic)
        }
    }

    // MARK: 組三：律制＋純律主音（階段 4 欠筆，本階段補齊）

    private func temperamentGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("律制 · Temperament"),
                          sub: L10n.t("纯律以主音为基准修正各音级音分，适合弦乐四重奏与合唱"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: [(Temperament.equal, L10n.t("平均律")),
                                    (Temperament.just, L10n.t("纯律"))],
                          selection: $draftTemperament)
            HStack {
                Text(L10n.t("纯律主音"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Picker(L10n.t("纯律主音"), selection: $draftJustTonicPc) {
                    ForEach(0..<12, id: \.self) { pc in
                        Text(PitchMath.noteNames[pc]).tag(pc)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .opacity(draftTemperament == .just ? 1 : 0.45)
            // 【返修批2・按鍵審計】平均律時純律主音不生效，
            // 視覺變暗之外同步禁用，避免「能點但沒用」。
            .disabled(draftTemperament != .just)
        }
    }

    // MARK: 組四：節拍器設為默認

    private func metroDefaultGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            HStack {
                SettingsLabel(
                    theme: theme,
                    title: L10n.t("将当前节拍器参数设为默认"),
                    sub: AppStore.metroSummaryText(
                        for: draftMetroDefault ?? store.metronomeDefault))
                Spacer(minLength: 8)
                Button(L10n.t("设为默认")) {
                    draftMetroDefault = currentMetronomeSettings
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.accent)
                // 【返修批7・E13】純文字鈕命中高僅 ≈18，
                // 上下透明 padding 擴至 ≈42（視覺不變）。
                .padding(.vertical, 12)
                .buttonStyle(GlassPressButtonStyle())
            }
        }
    }

    // MARK: 套用（「完成」）

    private func applyAndDismiss() {
        var settings = store.tunerSettings
        settings.damping = draftDamping
        settings.toleranceCents = draftTolerance
        settings.noiseGate = draftNoiseGate
        settings.temperament = draftTemperament
        settings.justTonicPc = draftJustTonicPc
        settings.a4 = draftA4
        store.tunerSettings = settings
        store.pitchMode = draftPitchMode
        store.autoMicOnEnter = draftAutoMic
        if draftPrimaryId != store.primaryInstrumentId {
            store.setPrimaryInstrument(id: draftPrimaryId)
        }
        if let draftMetroDefault {
            store.setMetronomeDefault(draftMetroDefault)
        }
        dismiss()
    }
}

// MARK: - 系統設定（即時式）

struct SystemSettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var metronomeViewModel: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// 備份匯入（階段 8）：檔案選取器與錯誤提示的本地狀態；
    /// plan 組裝成功後掛 store.pendingImportPlan，由根視圖的
    /// 確認 sheet 接手（本 sheet 關閉後仍能呈現）。
    @State private var showBackupImporter = false
    /// 【五維審計 F-2／專屬規範 S-5】備份錯誤單一通道：
    /// 同層兩個 .alert(isPresented:) 互相遮蔽（後掛者可
    /// 令先掛者永不呈現）——匯入/導出錯誤合併為單一
    /// item 式 alert，以 messageKey 區分文案。
    @State private var backupAlertKey: String?
    /// 自訂背景（裝機返修批）：選圖與自選色的本地狀態。
    @State private var backgroundPhotoItem: PhotosPickerItem?
    /// 選圖讀取／解碼失敗的提示（審計修復）：此前靜默無反應，
    /// 用戶無從分辨未選中還是失敗。
    @State private var backgroundPhotoError = false
    @State private var customColor: Color = Color(hex: 0x0A84FF)
    /// 備份導出（返修批9 重構）：item 式呈現＋失敗彈錯。
    /// 舊版 isPresented＋可選 URL 雙狀態在按鈕 action 內
    /// 同幀寫入、sheet 掛在按鈕本體，實機點按無反應
    /// （Laurent 點名「导出备份没有效果」）；改根層
    /// .sheet(item:) 單一狀態驅動，生成失敗不再靜默。
    @State private var exportShareItem: ExportShareItem?
    /// 恢復初始設置（返修批10）：頁內兩段式確認（不用
    /// alert——本頁根層已有兩個 alert，再疊第三個會重蹈
    /// F-2 互相遮蔽；頁內展開確認亦與本頁玻璃語言一致）。
    @State private var confirmReset = false

    /// 滑桿 draft（返修批9・拖動卡頓）：拖動期間只寫本地
    /// draft（僅設定頁本地重繪），向全域狀態節流提交
    /// （50 ms）＋放手終提交。舊版逐幀直寫 AppStore／
    /// 節拍器 VM 的 @Published——全 App 玻璃面隨拖動逐
    /// 幀重採樣重繪，實機拖動卡頓（Laurent 點名）。
    @State private var glassDraft: Double = 50
    @State private var glassEditing = false
    @State private var glassLastCommit: TimeInterval = 0
    @State private var bluetoothDraft: Double = 0
    @State private var bluetoothEditing = false
    @State private var bluetoothLastCommit: TimeInterval = 0

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        languageGroup(theme: theme)
                        appearanceGroup(theme: theme)
                        feedbackGroup(theme: theme)
                        bluetoothGroup(theme: theme)
                        screenOnGroup(theme: theme)
                        backupGroup(theme: theme)
                        resetGroup(theme: theme)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(L10n.t("系统设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("关闭")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .fileImporter(isPresented: $showBackupImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                switch BackupFileAccess.loadPlan(from: url) {
                case .success(let plan):
                    // 先關本 sheet，待其退場後再掛 plan 觸發根視圖
                    // 的確認 sheet，避免兩 sheet 同帧競態被吞。
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        store.pendingImportPlan = plan
                    }
                case .failure:
                    backupAlertKey = "备份文件无法识别，请确认选择的是网页版导出的备份"
                }
            case .failure(let error):
                // 【邏輯補查・中】取消選檔亦走 .failure
                // （CancellationError）：舊版一律映射為損壞
                // 錯誤，「取消也報錯」。取消直接返回、零提示。
                if error is CancellationError { return }
                backupAlertKey = "备份文件无法识别，请确认选择的是网页版导出的备份"
            }
        }
        // 【返修批9】導出分享表改根層 item 式呈現（見
        // exportShareItem 註解）；生成失敗彈錯，不靜默。
        .sheet(item: $exportShareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(L10n.t(backupAlertKey ?? ""),
               isPresented: Binding(
                   get: { backupAlertKey != nil },
                   set: { if !$0 { backupAlertKey = nil } })) {
            Button(L10n.t("关闭"), role: .cancel) {}
        }
        // 【邏輯補查・低】選圖失敗提示由 PhotosPicker 掛載
        // 改掛本頁根層：舊掛點只存在於自訂外觀段內，讀圖
        // 在途時切離自訂 → 旗標無處呈現、切回時陳舊補彈。
        // 根層掛載令其與當下介面狀態無關、即時呈現。
        .alert(L10n.t("图片读取失败，请重新选择"),
               isPresented: $backgroundPhotoError) {
            Button(L10n.t("关闭"), role: .cancel) {}
        }
        .onAppear {
            glassDraft = Double(store.glassOpacity)
            bluetoothDraft = Double(
                metronomeViewModel.settings.bluetoothCompMs)
        }
        .onChange(of: store.glassOpacity) { _, v in
            if !glassEditing { glassDraft = Double(v) }
        }
        .onChange(of: metronomeViewModel.settings.bluetoothCompMs) { _, v in
            if !bluetoothEditing { bluetoothDraft = Double(v) }
        }
    }

    // MARK: 數據備份（階段 8：網頁版備份匯入）

    private func backupGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("数据备份 · Backup"),
                          sub: L10n.t("导出自订乐器、收藏与全部设置，换机或清数据后可导入恢复"))
            Button {
                showBackupImporter = true
            } label: {
                Text(L10n.t("选择备份文件"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            // 【返修批7・E13】命中高 ≈18→≈42（透明 padding）。
            .padding(.vertical, 12)
            .buttonStyle(GlassPressButtonStyle())
            Divider()
            // 導出單擊呈現（返修批9 再修）：批6 改單擊後實機
            // 仍無反應——sheet 掛按鈕本體＋isPresented/可選
            // URL 雙狀態同幀寫入的呈現競態。改根層 item 式
            // 呈現（見 exportShareItem），點按當下生成最新
            // 快照；生成失敗彈錯，不再石沉大海。
            Button {
                if let url = BackupExporter.writeTempFile(store: store) {
                    exportShareItem = ExportShareItem(url: url)
                } else {
                    backupAlertKey = "导出失败，请重试"
                }
            } label: {
                Text(L10n.t("导出备份"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            // 【返修批7・E13】命中高 ≈18→≈42（透明 padding）。
            .padding(.vertical, 12)
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    // MARK: 語言

    private func languageGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            HStack {
                SettingsLabel(theme: theme,
                              title: L10n.t("界面语言 · Language"),
                              sub: L10n.t("选择界面显示语言，切换立即生效"))
                Spacer(minLength: 8)
                Picker(L10n.t("界面语言 · Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        // 原生名恆不翻譯（母本 data-i18n-skip）。
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: 外觀＋玻璃不透明度

    private func appearanceGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("外观与背景模式"),
                          sub: L10n.t("界面色彩、文字对比度与玻璃通透度随背景自动适配"))
            SettingsChips(theme: theme, glassOpacity: store.glassOpacity,
                          options: AppTheme.allCases.map {
                              (value: $0, label: $0.displayName)
                          },
                          selection: $store.themePreference)

            HStack {
                Text(L10n.t("玻璃不透明度"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text("\(Int(glassDraft.rounded()))%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            // 【返修批9】draft 節流提交：數值逐幀跟指（本地
            // draft），全域玻璃以 20 Hz 節流跟隨、放手終提
            // 交——拖動不再卡頓（根因見 glassDraft 註解）。
            // 【返修批11・全原生化】滑塊改系統原生 Slider
            // （iOS 27 玻璃拇指由系統提供），自製 Glass-
            // Slider 退役；draft／節流接線原樣保留。
            Slider(value: $glassDraft, in: 8...96, step: 1) { editing in
                glassEditing = editing
                if !editing { commitGlassDraft(final: true) }
            }
            .tint(theme.accent)
            .accessibilityValue("\(Int(glassDraft.rounded()))%")
            .onChange(of: glassDraft) { _, _ in
                if glassEditing { commitGlassDraft(final: false) }
            }
            HStack {
                Text(L10n.t("透明"))
                Spacer()
                Text(L10n.t("不透明"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(theme.textMuted)

            if store.themePreference == .custom {
                Divider()
                backgroundControls(theme: theme)
            }
        }
    }

    // MARK: 自訂背景（裝機返修批，母本 themeConsole 背景段）

    /// 母本預置色票（index.html 行 5774–5783 原值）。
    private static let backgroundSwatches: [UInt32] = [
        0x0A84FF, 0x5E5CE6, 0xBF5AF2, 0xFF375F, 0xFF453A,
        0xFF9F0A, 0xFFD60A, 0x30D158, 0x64D2FF, 0x8E8E93,
    ]

    @ViewBuilder
    private func backgroundControls(theme: TunerTheme) -> some View {
        SettingsLabel(theme: theme,
                      title: L10n.t("自定义背景"),
                      sub: backgroundStatusText)
        // 色票列（母本 .bg-swatch-row）：點選即套用純色背景。
        // 【返修批3】改固定 5 列 × 2 行：adaptive 依寬度湊列
        // 實機成 8＋2 參差（Laurent 點名設定頁布局亂），定列
        // 後兩行整齊對位。
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9),
                                 count: 5),
                  spacing: 9) {
            ForEach(Self.backgroundSwatches, id: \.self) { hex in
                Button {
                    store.setCustomBackgroundColor(
                        String(format: "#%06X", hex))
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if store.bgKind == "color",
                               AppStore.parseHexColor(store.bgColorHex) == hex {
                                Circle().strokeBorder(.white, lineWidth: 2)
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(GlassPressButtonStyle())
                .accessibilityLabel(String(format: "#%06X", hex))
            }
        }

        HStack(spacing: 10) {
            ColorPicker(L10n.t("自选色彩"), selection: $customColor,
                        supportsOpacity: false)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .onAppear {
                    // 初值對齊目前背景色（審計修復）：此前固定
                    // 藍色起手，用戶此前以色票／匯入設過其他
                    // 顏色時，色樣顯示與實際背景不符。
                    if store.bgKind == "color",
                       let rgb = AppStore.parseHexColor(store.bgColorHex) {
                        customColor = Color(hex: rgb)
                    }
                }
                .onChange(of: customColor) { _, newColor in
                    if let hex = newColor.hexString {
                        store.setCustomBackgroundColor(hex)
                    }
                }
            Spacer(minLength: 8)
            PhotosPicker(selection: $backgroundPhotoItem,
                         matching: .images) {
                Text(L10n.t("选择图片"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    // 【返修批7・E13】命中高 ≈18→≈42
                    // （透明 padding，視覺不變）。
                    .padding(.vertical, 12)
            }
            .onChange(of: backgroundPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(
                        type: Data.self),
                       let processed = Self.processBackgroundImage(data) {
                        // 【邏輯補查・低】讀取在途競態：用戶
                        // 已切離自訂外觀時只存圖、不搶改主題
                        // （仍在自訂則走原路徑含切換語義）。
                        if store.themePreference == .custom {
                            store.setCustomBackgroundImage(processed)
                        } else {
                            store.storeCustomBackgroundImageData(processed)
                        }
                    } else {
                        backgroundPhotoError = true
                    }
                    backgroundPhotoItem = nil
                }
            }
        }

        if store.bgKind != "" {
            Button {
                store.clearCustomBackground()
            } label: {
                Text(L10n.t("清除背景"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.clipWarning)
            }
            // 【返修批7・E13】命中高 ≈18→≈42（透明 padding）。
            .padding(.vertical, 12)
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    /// 背景現況說明（母本 bgPrevLabel 等價）。
    private var backgroundStatusText: String {
        switch store.bgKind {
        case "color":
            return L10n.t("当前色彩背景") + " " + store.bgColorHex.uppercased()
        case "image":
            return L10n.t("自定义背景已保存")
        default:
            return L10n.t("尚未设置自定义背景")
        }
    }

    /// 選圖處理：長邊縮至 ≤1600、轉 JPEG 0.8（落盤體積與
    /// 解碼成本可控；母本以 data URL 存 localStorage 亦有
    /// 體積上限，口徑一致）。
    static func processBackgroundImage(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxEdge: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else {
            return image.jpegData(compressionQuality: 0.8)
        }
        let scale = maxEdge / longest
        let newSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    // MARK: 滑桿節流提交（返修批9・拖動卡頓修復）

    /// 拖動期每 50 ms 最多提交一次全域狀態，放手終提交
    /// 保證落值精確。提交仍走既有 @Published 通道（persist
    /// 冪等守衛＋節拍器設定防抖寫盤不變）。
    private func commitGlassDraft(final: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard final || now - glassLastCommit >= 0.05 else { return }
        glassLastCommit = now
        let v = Int(glassDraft.rounded())
        if store.glassOpacity != v { store.glassOpacity = v }
    }

    private func commitBluetoothDraft(final: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard final || now - bluetoothLastCommit >= 0.05 else { return }
        bluetoothLastCommit = now
        let v = Int(bluetoothDraft.rounded())
        if metronomeViewModel.settings.bluetoothCompMs != v {
            metronomeViewModel.settings.bluetoothCompMs = v
        }
    }

    // MARK: 震動／音效

    private func feedbackGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            Toggle(isOn: $store.tunerSettings.hapticsOn) {
                SettingsLabel(theme: theme,
                              title: L10n.t("震动反馈 · Haptics"),
                              sub: L10n.t("节拍器逐拍震动（强拍更明显）、音准达标轻震确认、按键轻触反馈"))
            }
            .tint(theme.accent)

            Divider()

            Toggle(isOn: soundsBinding) {
                SettingsLabel(theme: theme,
                              title: L10n.t("音效反馈 · Sounds"),
                              sub: L10n.t("操作成功与选取确认的轻提示音（不影响节拍器和基准音）"))
            }
            .tint(theme.accent)
        }
    }

    /// 音效開關（自診斷頁收編）：開啟當下即播 "success" 作回饋
    /// （母本行 12275）——先行啟用引擎再寫 store，避免
    /// ContentView 的 onChange 同步到達前被舊旗標擋下。
    private var soundsBinding: Binding<Bool> {
        Binding(
            get: { store.tunerSettings.soundsOn },
            set: { newValue in
                if newValue {
                    UISoundEngine.shared.isEnabled = true
                    UISoundEngine.shared.play(.success)
                }
                store.tunerSettings.soundsOn = newValue
            })
    }

    // MARK: 藍牙補償（自診斷頁收編；母本 android-only，原生 iOS 實際生效）

    private func bluetoothGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("蓝牙延迟补偿"),
                          sub: L10n.t("用蓝牙耳机时把节拍画面延后，与声音对齐"))
            HStack(spacing: 10) {
                // 【返修批9】同不透明度：draft 節流提交（舊
                // 版逐幀直寫節拍器 VM 設定，整頁連同玻璃逐
                // 幀重繪、拖動卡頓）。
                // 【返修批11・全原生化】改系統原生 Slider。
                Slider(value: $bluetoothDraft, in: 0...300, step: 10) { editing in
                    bluetoothEditing = editing
                    if !editing { commitBluetoothDraft(final: true) }
                }
                .tint(theme.accent)
                .accessibilityValue("\(Int(bluetoothDraft.rounded())) ms")
                .onChange(of: bluetoothDraft) { _, _ in
                    if bluetoothEditing { commitBluetoothDraft(final: false) }
                }
                Text("\(Int(bluetoothDraft.rounded())) ms")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 58)
            }
        }
    }

    // MARK: 屏幕常亮（資訊列：母本無開關、原生自動行為）

    private func screenOnGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("屏幕常亮"),
                          sub: L10n.t("校音或节拍器运行时自动保持屏幕常亮，无需手动设置"))
        }
    }

    // MARK: 恢復初始設置（返修批10・Laurent 指示）

    private func resetGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("恢复初始设置"),
                          sub: L10n.t("将全部设置、收藏、自订乐器与预设恢复为出厂状态，无法撤销"))
            if confirmReset {
                HStack(spacing: 10) {
                    Button {
                        confirmReset = false
                    } label: {
                        Text(L10n.t("取消"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    Button {
                        performFactoryReset()
                    } label: {
                        Text(L10n.t("确认恢复"))
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(theme.clipWarning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            } else {
                Button {
                    confirmReset = true
                } label: {
                    Text(L10n.t("恢复初始设置"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(theme.clipWarning)
                }
                .padding(.vertical, 12)
                .buttonStyle(GlassPressButtonStyle())
            }
        }
    }

    /// 恢復執行：先停節拍器（播放中換設定會即時改拍，
    /// 且重置語義本就是回到靜止出廠態），再重置 store，
    /// 最後把 VM 的運行時設定副本同步回出廠值（預置副
    /// 本經 ContentView 的 onChange 自動同步）。
    private func performFactoryReset() {
        if metronomeViewModel.isPlaying || metronomeViewModel.capsulePaused {
            metronomeViewModel.stop()
        }
        store.resetToFactoryDefaults()
        metronomeViewModel.syncSettingsFromStore(store.metronomeSettings)
        confirmReset = false
    }
}

/// 導出分享表的 item 包裝（返修批9）：根層 .sheet(item:)
/// 單一狀態驅動，消除舊版 isPresented＋可選 URL 雙狀態
/// 同幀寫入的呈現競態（實機點按無反應的修復）。
private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 系統分享表包裝（備份導出單擊化，審計修復）：點按導出即
/// 生成最新快照並呈現，不再經 ShareLink 兩段式。
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController,
                                  context: Context) {}
}
