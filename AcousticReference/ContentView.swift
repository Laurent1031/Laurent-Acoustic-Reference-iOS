import SwiftUI
import UIKit

/// 頂欄 sheet 種類（ContentView.activeSheet）。
enum TopSheet: Identifiable {
    case debug
    case preferences
    case systemSettings
    var id: Self { self }
}

/// App 殼（階段 4）：頂欄（品牌＋調音/節拍分段切換＋診斷入口，
/// 對照母本頂欄）＋兩頁保活切換＋節拍器背景膠囊＋螢幕常亮管理。
/// 兩頁以 ZStack 疊放、僅切透明度與命中測試：任一頁的執行期
/// 狀態（調音分析、節拍調度、動畫時鐘）在切頁後不中斷——
/// 對照母本「兩者可同時運行」（節拍器運行時切回調音頁，
/// 節拍器照常發聲、膠囊常駐）。
///
/// 數據流（階段 4 數據層）：AppStore 為唯一真源——啟動時以
/// store 的已存值初始化三個引擎；其後 store 變更經下方 onChange
/// 單向同步進引擎（設定／音域／Drone 上下文與音色），節拍器
/// ViewModel 的持久化出口反向注入 store。mode 自階段 4 起亦
/// 歸 store 落盤（取代階段 3 的 UserDefaults 佔位鍵，已遷移）。
struct ContentView: View {
    @StateObject private var store: AppStore
    @StateObject private var engine: AudioEngine
    @StateObject private var metronomeEngine: MetronomeEngine
    @StateObject private var metronomeViewModel: MetronomeViewModel
    @StateObject private var droneEngine: DroneEngine
    /// 頂欄喚出的 sheet（診斷／偏好／系統設定，階段 5 統一以
    /// item 呈現，避免多個 .sheet 修飾器互相衝突）。
    @State private var activeSheet: TopSheet?
    /// 排練防誤觸鎖（補強段）：僅執行期狀態，不落盤——重啟 App
    /// 恆為未鎖定，避免「開機即鎖死」的困惑（取捨註明於報告）。
    @State private var rehearsalLocked = false
    @Environment(\.colorScheme) private var colorScheme

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)

        let tunerEngine = AudioEngine()
        tunerEngine.settings = store.tunerSettings
        tunerEngine.range = store.effectiveRange
        _engine = StateObject(wrappedValue: tunerEngine)

        // 節拍器啟動播種（階段 5）：用戶設過「設為默認」時以
        // 預設參數啟動（母本 applyUserProfileToWorkspace 語義），
        // 未設時沿用上次值（階段 3/4 既有行為）；運行中的變更
        // 仍回存 metronomeSettings（上次值），與預設並存。
        let metroSeed = store.metronomeDefault ?? store.metronomeSettings
        let metroEngine = MetronomeEngine(settings: metroSeed)
        _metronomeEngine = StateObject(wrappedValue: metroEngine)
        let metroViewModel = MetronomeViewModel(
            engine: metroEngine,
            persisted: (settings: metroSeed,
                        userPresets: store.metronomeUserPresets))
        metroViewModel.persistSettings = { store.metronomeSettings = $0 }
        metroViewModel.persistUserPresets = { store.metronomeUserPresets = $0 }
        _metronomeViewModel = StateObject(wrappedValue: metroViewModel)

        let drone = DroneEngine()
        drone.updateContext(
            a4: store.tunerSettings.a4,
            temperament: store.tunerSettings.temperament,
            justTonicPc: store.tunerSettings.justTonicPc)
        _droneEngine = StateObject(wrappedValue: drone)
    }

    private var mode: AppMode { store.appMode }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        VStack(spacing: 0) {
            topBar(theme: theme)

            ZStack {
                TunerView(engine: engine, store: store, drone: droneEngine)
                    .opacity(mode == .tuner ? 1 : 0)
                    .allowsHitTesting(mode == .tuner)
                    .accessibilityHidden(mode != .tuner)
                MetronomeView(engine: metronomeEngine,
                              viewModel: metronomeViewModel,
                              store: store)
                    .opacity(mode == .metronome ? 1 : 0)
                    .allowsHitTesting(mode == .metronome)
                    .accessibilityHidden(mode != .metronome)
                DualModeView(engine: engine, store: store,
                             drone: droneEngine,
                             metronomeViewModel: metronomeViewModel)
                    .opacity(mode == .dual ? 1 : 0)
                    .allowsHitTesting(mode == .dual)
                    .accessibilityHidden(mode != .dual)
            }
        }
        // 【裝機返修】根層背景：頂欄區與狀態欄區一律鋪當前
        // 主題背景（延伸至全部安全區）。此前根 VStack 無背景，
        // 頂欄區透出的是跟隨 preferredColorScheme 的窗口底色，
        // 與頁面主題不一致時（如深色頁面＋淺色方案）頂部會
        // 留一條異色帶（Laurent 實機回報：切演奏態時上面留
        // 一條白）。頁面各自的背景保留（同色疊加無副作用）。
        .background {
            theme.background.ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if mode == .tuner && metronomeViewModel.capsuleVisible {
                capsule(theme: theme)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 防誤觸鎖遮罩（最外層，蓋住頂欄與背景膠囊）：鎖定時
        // 凍結全部控件，僅保留長按解鎖；音訊引擎不受影響
        // （節拍器／Drone／調音照常運行，只是碰不到）。
        .overlay {
            if rehearsalLocked {
                lockOverlay(theme: theme)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9),
                   value: metronomeViewModel.capsuleVisible)
        .animation(.easeOut(duration: 0.2), value: rehearsalLocked)
        .preferredColorScheme(store.effectiveForcedColorScheme)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .debug:
                TunerDebugView(engine: engine,
                               metronomeEngine: metronomeEngine,
                               metronomeViewModel: metronomeViewModel,
                               store: store)
            case .preferences:
                PreferencesView(store: store,
                                currentMetronomeSettings: metronomeViewModel.settings)
            case .systemSettings:
                SystemSettingsView(store: store,
                                   metronomeViewModel: metronomeViewModel)
            }
        }
        .onAppear {
            HapticsEngine.shared.isEnabled = engine.settings.hapticsOn
            UISoundEngine.shared.isEnabled = engine.settings.soundsOn
            updateIdleTimer()
            startMicIfAutoEnabled()
            // Live Activity 防殭屍（階段 6）：啟動時節拍器未
            // 播放卻有殘留活動（上一進程被殺等）→ 全數結束。
            if !metronomeViewModel.isPlaying {
                MetronomeLiveActivityController.shared.endAllActivities()
            }
        }
        // 小組件深連結（階段 6）：laurent-acoustic://tuner／
        // metronome／metronome/start（切頁並直接開始）。
        // 備份分享入（階段 8）：檔案 App／分享表單送入的 .json
        // 檔案 URL → 組裝 plan 掛 store，確認 sheet 隨之呈現；
        // 組裝失敗靜默忽略（設定頁的檔案選取路徑有完整錯誤提示）。
        .onOpenURL { url in
            if url.isFileURL {
                if case .success(let plan) = BackupFileAccess.loadPlan(from: url) {
                    store.pendingImportPlan = plan
                }
            } else {
                handleDeepLink(url)
            }
        }
        // 備份匯入確認（階段 8）：兩個入口（設定頁選檔／分享入）
        // 共用此 sheet；確認才套用、取消零副作用。
        .sheet(item: $store.pendingImportPlan) { plan in
            BackupImportSheet(store: store, plan: plan)
        }
        // 語言唯一真源在 store；變更單向同步進 L10n（所有
        // @ObservedObject store 的視圖隨 @Published 變更重繪，
        // 渲染時即以新語言查表——即時生效）。
        .onChange(of: store.language) { _, newLanguage in
            L10n.setLanguage(newLanguage)
        }
        // 自動開啟麥克風（母本 autoMicOnEnter）：切換到調音
        // 模式時啟動（啟動落在調音由 onAppear 處理；調音頁
        // 點按任意處由 TunerView 的手勢處理）。
        .onChange(of: store.appMode) { _, newMode in
            if newMode != .metronome { startMicIfAutoEnabled() }
        }
        // store → 引擎單向同步（store 為唯一真源）。
        .onChange(of: store.tunerSettings) { _, newSettings in
            engine.settings = newSettings
            HapticsEngine.shared.isEnabled = newSettings.hapticsOn
            UISoundEngine.shared.isEnabled = newSettings.soundsOn
            droneEngine.updateContext(
                a4: newSettings.a4,
                temperament: newSettings.temperament,
                justTonicPc: newSettings.justTonicPc)
        }
        .onChange(of: store.selectedInstrumentId) { _, _ in
            engine.range = store.effectiveRange
        }
        .onChange(of: store.guzhengKey) { _, _ in
            engine.range = store.effectiveRange
        }
        .onChange(of: store.droneTimbre) { _, newTimbre in
            droneEngine.setTimbre(newTimbre)
        }
        .onChange(of: engine.isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: metronomeEngine.isPlaying) { _, _ in updateIdleTimer() }
    }

    // MARK: - 頂欄（母本 topBar：品牌＋分段＋偏好／设置＋鎖＋診斷）

    /// 【裝機返修・2026-11-26】舊版單列塞品牌＋三段分段＋
    /// 兩文字鈕＋兩圖標鈕，iPhone 寬度必溢出、右側圓鈕被裁
    /// （實機回報）。改兩列制：第一列品牌徽章＋字標＋偏好／
    /// 设置＋鎖＋診斷；第二列模式分段全寬（液態玻璃鏡片
    /// 切換、三段等寬、圖標＋文字恆顯示）。品牌字標全尺寸
    /// 保留，絕不縮放／截斷（版面鐵律）。
    private func topBar(theme: TunerTheme) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.accent)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text("L")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("LAURENT")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .tracking(2.5)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize()
                    Text("STUDIO EDITION")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(theme.textMuted)
                        .fixedSize()
                }

                Spacer(minLength: 8)

                topTextButton(title: L10n.t("偏好"), theme: theme) {
                    activeSheet = .preferences
                }
                topTextButton(title: L10n.t("设置"), theme: theme) {
                    activeSheet = .systemSettings
                }

                Button {
                    rehearsalLocked = true
                    HapticsEngine.shared.tap(milliseconds: 12)
                } label: {
                    Image(systemName: "lock.open")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .glassBackground(in: Circle(), theme: theme, glassOpacity: store.glassOpacity)
                }
                .buttonStyle(GlassPressButtonStyle())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel(L10n.t("排练锁定"))

                Button {
                    activeSheet = .debug
                } label: {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .glassBackground(in: Circle(), theme: theme, glassOpacity: store.glassOpacity)
                }
                .buttonStyle(GlassPressButtonStyle())
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel(L10n.t("诊断"))
            }
            .frame(height: 36)

            GlassSegmentedControl(
                options: [
                    (option: AppMode.tuner, title: L10n.t("调音"), symbol: "tuningfork"),
                    (option: AppMode.dual, title: L10n.t("同屏"), symbol: "rectangle.split.2x1"),
                    (option: AppMode.metronome, title: L10n.t("节拍"), symbol: "metronome"),
                ],
                selection: Binding(
                    get: { store.appMode },
                    set: { newMode in
                        guard newMode != store.appMode else { return }
                        store.appMode = newMode
                        HapticsEngine.shared.tap(milliseconds: 6)
                    }),
                theme: theme, glassOpacity: store.glassOpacity,
                fontSize: 13, height: 32, equalWidth: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    /// 頂欄文字鈕（母本 .icon-btn 形制：純文字、次級色）。
    private func topTextButton(title: String, theme: TunerTheme,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(theme.textSecondary)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 防誤觸鎖遮罩（補強段）

    /// 鎖定遮罩：半透明壓暗＋底部低調指示膠囊。整層攔截全部
    /// 觸控（下層控件凍結）；解鎖 = 長按指示膠囊 0.8 s（防口袋
    /// 與譜架誤觸，單擊不解）。鎖定指示刻意低調（muted 色、
    /// 小字），舞台／樂池環境不搶眼；暗紅模式下同樣走 token。
    private func lockOverlay(theme: TunerTheme) -> some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.55 : 0.35)
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.t("排练锁定 · 长按解锁"))
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                .overlay {
                    Capsule().strokeBorder(
                        theme.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                        lineWidth: 1)
                }
                .padding(.bottom, 26)
                .contentShape(Capsule())
                .gesture(
                    LongPressGesture(minimumDuration: 0.8, maximumDistance: 12)
                        .onEnded { _ in
                            rehearsalLocked = false
                            HapticsEngine.shared.tap(milliseconds: 12)
                        }
                )
                .accessibilityLabel(L10n.t("排练锁定中，长按解锁"))
            }
        }
    }

    // MARK: - 背景膠囊（母本 #9 metroCapsule）

    private func capsule(theme: TunerTheme) -> some View {
        Button {
            metronomeViewModel.capsuleTapped()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                    .opacity(metronomeViewModel.isPlaying
                             ? 0.35 + 0.65 * metronomeViewModel.pulseValue
                             : 0.5)
                    .scaleEffect(metronomeViewModel.isPlaying
                                 ? 1 + 0.3 * metronomeViewModel.pulseValue
                                 : 1)
                Text(metronomeViewModel.capsuleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            .overlay {
                Capsule().strokeBorder(
                    theme.isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                    lineWidth: 1)
            }
            .opacity(metronomeViewModel.isPlaying ? 1 : 0.75)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 螢幕常亮（母本 Wake Lock 的原生等價）

    /// want = 麥克風運行 || 節拍器播放（母本 updateWakeLock）。
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            engine.isRunning || metronomeEngine.isPlaying
    }

    // MARK: - 深連結（階段 6，小組件入口）

    /// laurent-acoustic:// 的三條路徑；未知路徑不動作。
    /// start 路徑在節拍器已播放時不重啟（ViewModel.start 的
    /// 引擎側亦有冪等守衛，此處先擋避免多餘的啟動觸感）。
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "laurent-acoustic" else { return }
        switch url.host {
        case "tuner":
            store.appMode = .tuner
        case "metronome":
            store.appMode = .metronome
            if url.path == "/start", !metronomeViewModel.isPlaying {
                metronomeViewModel.start()
            }
        default:
            break
        }
    }

    // MARK: - 自動開啟麥克風（母本 ensureMicOn，階段 5 接線）

    /// autoMicOnEnter 開且目前在調音模式、引擎未運行時啟動
    /// （engine.start 自帶權限申請；權限被拒時引擎自行落入
    /// permissionDenied 狀態，調音頁顯示提示）。關時全不觸發
    /// （母本預設關，零回退）。
    private func startMicIfAutoEnabled() {
        guard store.autoMicOnEnter, store.appMode != .metronome,
              !engine.isRunning else { return }
        Task { await engine.start() }
    }
}

#Preview {
    ContentView()
}
