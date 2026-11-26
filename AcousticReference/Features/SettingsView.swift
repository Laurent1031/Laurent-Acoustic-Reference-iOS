import SwiftUI

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
///   音效／藍牙補償＋屏幕常亮資訊列。未移植三項在報告點名：
///   自訂背景（上傳圖片＋背景色彩，web 專屬）、數據備份
///   導出／導入（規格書 §5 第 8 步範疇）、贊賞支持／聯繫
///   我們（內容性條目）。

// MARK: - 共用組件

/// 設定分組卡（玻璃面＋組內分隔線）。
private struct SettingsGroup<Content: View>: View {
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
private struct SettingsLabel: View {
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
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let active = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(active ? .white : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(active ? theme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassBackground(in: Capsule(), theme: theme, glassOpacity: glassOpacity)
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

    var body: some View {
        let theme = TunerTheme.resolve(preference: store.themePreference,
                                       system: colorScheme)
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
                    .buttonStyle(.plain)
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
                          options: [(1.5, L10n.t("严苛 ±1.5¢")),
                                    (3.0, L10n.t("乐团 ±3.0¢")),
                                    (4.0, L10n.t("宽容 ±4.0¢"))],
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
                .buttonStyle(.plain)
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

    var body: some View {
        let theme = TunerTheme.resolve(preference: store.themePreference,
                                       system: colorScheme)
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
                Text("\(store.glassOpacity)%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            Slider(value: glassBinding, in: 8...96, step: 1)
                .tint(theme.accent)
            HStack {
                Text(L10n.t("透明"))
                Spacer()
                Text(L10n.t("不透明"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(theme.textMuted)
        }
    }

    private var glassBinding: Binding<Double> {
        Binding(get: { Double(store.glassOpacity) },
                set: { store.glassOpacity = Int($0.rounded()) })
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
                Slider(value: bluetoothBinding, in: 0...300, step: 10)
                    .tint(theme.accent)
                Text("\(metronomeViewModel.settings.bluetoothCompMs) ms")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 58)
            }
        }
    }

    private var bluetoothBinding: Binding<Double> {
        Binding(
            get: { Double(metronomeViewModel.settings.bluetoothCompMs) },
            set: { metronomeViewModel.settings.bluetoothCompMs = Int($0.rounded()) })
    }

    // MARK: 屏幕常亮（資訊列：母本無開關、原生自動行為）

    private func screenOnGroup(theme: TunerTheme) -> some View {
        SettingsGroup(theme: theme, glassOpacity: store.glassOpacity) {
            SettingsLabel(theme: theme,
                          title: L10n.t("屏幕常亮"),
                          sub: L10n.t("校音或节拍器运行时自动保持屏幕常亮，无需手动设置"))
        }
    }
}
