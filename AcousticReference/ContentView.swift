import SwiftUI
import UIKit

/// 頂欄 sheet 種類（ContentView.activeSheet）。
/// 【返修批10】.debug 已撤（Laurent 指示診斷入口直接
/// 去掉，診斷頁 TunerDebugView 一併刪除）。
enum TopSheet: Identifiable {
    case preferences
    case systemSettings
    var id: Self { self }
}

/// App 殼（階段 4）：頂欄（品牌＋調音/節拍分段切換，
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
    /// 【邏輯補查・低】匯入確認 sheet 的呈現副本：store
    /// 的 pendingImportPlan 為數據真源，呈現須與
    /// activeSheet 串行（兩個 item-sheet 同帧非 nil 時
    /// SwiftUI 只呈現其一、另一張可能被吞）。plan 到達
    /// 而正有 sheet 開著時先候著，該 sheet 關閉後補呈現
    /// （見下方兩條 onChange 的晉升邏輯）。
    @State private var presentedImportPlan: BackupImporter.ImportPlan?
    /// 呈現中 plan 的 id 副本：sheet(item:) 關閉時綁定
    /// 先歸 nil，onDismiss 內須靠此副本分辨「被關的就
    /// 是真源那份（滑動取消→清）」與「呈現期間有新
    /// plan 到達（→晉升呈現）」。
    @State private var presentedImportPlanID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    /// 【返修批7・C5】場景階段：離開 active 時 flush 節拍器
    /// 防抖落盤（見下方 onChange）。
    @Environment(\.scenePhase) private var scenePhase
    /// 開機動畫（返修批3 補回母本 .splash）：冷啟動覆蓋層，
    /// 徽章 FLIP 飛入頂欄品牌標記後退場；brandMarkFrame 為
    /// 頂欄標記的全局矩形（飛行落點），splashRevealed 控制
    /// 真標記在飛行期間隱藏、落地／淡出時恢復。
    @State private var showSplash = true
    @State private var splashRevealed = false
    @State private var brandMarkFrame: CGRect = .zero
    /// 背景按壓亮斑（返修批3 補回母本 #pageGlow；返修
    /// 批9 多指化）：逐指一個亮斑，狀態由窗口級被動觸
    /// 控追蹤維護（GlowTouchTracker），多指互不干擾。
    /// 【返修批10】亮斑狀態隔離：原以 ContentView 的
    /// @State 持有，手指每移動一幀（最高 120 Hz）整棵根
    /// 視圖樹跟著重算——實機「亮斑特別卡頓」的根因。改由
    /// GlowSpotModel 單獨持有，只有亮斑層觀察它、只有亮
    /// 斑層重繪，根視圖不再被觸摸牽動。
    @StateObject private var glowModel = GlowSpotModel()

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

    /// 浮動膠囊底距（五維審計 F8）：compact 級（availH
    /// <660）70、常規 76；availH 以主窗口實測（螢幕高 −
    /// 安全區上下 − 頂欄 92）。
    private var capsuleBottomPadding: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let bounds = scene?.screen.bounds ?? .zero
        let insets = scene?.windows.first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
        let availH = bounds.height - insets.top - insets.bottom - 92
        return availH < 660 ? 70 : 76
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        // 【CI 修復・run #56 嘗試 6】型別檢查超時：body 原為
        // 單一表達式（視圖樹＋約 25 個修飾器鏈），編譯器在
        // handleDeepLink 處推斷逾時（ContentView.swift:239）。
        // 拆為 content／withSheets／return 三段各自推斷
        // （編譯器建議的拆分法；行為、版面皆不變）。
        let content = VStack(spacing: 0) {
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
            }
            // 【專屬系統・動效】模式切換交叉淡化（AppMotion
            // 令牌）：舊版 opacity 硬切無過渡。
            .animation(AppMotion.pageFade, value: mode)
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
        // 背景按壓亮斑層（母本 #pageGlow）：置於內容之上以
        // screen 混合呈現「光」而非遮擋（母本在內容之下，
        // 原生頁面背景不透明、置下不可見，故改置上＋混合
        // 模式，視覺等價）；不參與命中測試。
        // 【返修批9】觸控改窗口級被動追蹤（多指）：舊版根
        // 層單一 DragGesture 只跟一根手指、第一指抬起即
        // 整體熄光，多指必卡（Laurent 點名）；且全域拖動
        // 手勢與頁內一切拖動競爭，一併撤除。
        .overlay {
            PageGlowView(model: glowModel, theme: theme)
        }
        .background {
            GlowTouchTracker { touches in
                glowModel.update(touches)
            }
        }
        .overlay(alignment: .bottom) {
            if mode == .tuner && metronomeViewModel.capsuleVisible {
                capsule(theme: theme)
                    // 【返修批7・E7】底距 18→76：舊值下膠囊
                    // 與調音頁麥克風主鈕中央 144×36 區域重疊、
                    // 該區點按被膠囊奪走；抬高至主鈕上方後
                    // 兩者命中區完全分離（膠囊僅在調音頁
                    // 出現，此分支即調音頁專屬）。
                    // 【五維審計 F8】compact 級（availH<660，
                    // SE/mini/X）底距改 70：76 下膠囊頂緣壓
                    // 數據卡底緣 ≈2.5pt；70 時膠囊帶 70–104、
                    // 距卡底 3.5、距麥克風鈕頂 16.5，兩側皆清。
                    .padding(.bottom, capsuleBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.capsule,
                   value: metronomeViewModel.capsuleVisible)
        // 開機動畫覆蓋層（返修批3）：最上層，退場後移除。
        .overlay {
            if showSplash {
                SplashView(theme: theme,
                           targetFrame: brandMarkFrame,
                           revealed: $splashRevealed) {
                    showSplash = false
                }
                .ignoresSafeArea()
                .zIndex(10)
            }
        }
        .preferredColorScheme(store.effectiveForcedColorScheme)
        let withSheets = content
        .sheet(item: $activeSheet) { sheet in
            // 【返修批2】sheet 內強制套 App 主題外觀＋以主題
            // 背景作呈現底：此前 sheet 的 glassEffect 與導航
            // 鉻件跟隨「裝置」外觀渲染，裝置淺色＋App 深色
            // 時整頁玻璃變灰白扁平、標題變黑字、選中字被
            // 淺色鏡片吃掉（Laurent 實機點名設定／偏好／
            // 診斷三頁）。根視圖的 preferredColorScheme 不
            // 保證傳進 sheet 呈現層，故在 sheet 內容根部
            // 再套一次，雙保險。
            Group {
                switch sheet {
                case .preferences:
                    PreferencesView(store: store,
                                    currentMetronomeSettings: metronomeViewModel.settings)
                case .systemSettings:
                    SystemSettingsView(store: store,
                                       metronomeViewModel: metronomeViewModel)
                }
            }
            .preferredColorScheme(store.effectiveForcedColorScheme)
            .presentationBackground { theme.background }
        }
        .onAppear {
            // 同屏模式已取消（2026-11-26 Laurent 指示）：舊存檔
            // 若停在 .dual 就地收斂為調音頁，避免落入無入口頁面。
            if store.appMode == .dual { store.appMode = .tuner }
            HapticsEngine.shared.isEnabled = engine.settings.hapticsOn
            UISoundEngine.shared.isEnabled = engine.settings.soundsOn
            // 【返修批10】啟動即預熱震動／音效引擎：引擎
            // 建立＋圖案 player 預建＋音效預渲染的成本在
            // 啟動時先付清，第一拍震動與首個 UI 音效不
            // 再被懶建立吞掉（批9 實機「震動一開始沒有」）。
            HapticsEngine.shared.warmUp()
            UISoundEngine.shared.warmUp()
            updateIdleTimer()
            startMicIfAutoEnabled()
            refreshMetronomePageVisibility()
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
        // 【邏輯補查・低】呈現改走 presentedImportPlan 副本
        // 與 activeSheet 串行（見其宣告註）：plan 在另一
        // sheet 開著時到達不再同帧相撞被吞。
        .sheet(item: $presentedImportPlan,
               onDismiss: handleImportSheetDismissed) { plan in
            BackupImportSheet(store: store, plan: plan)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationBackground { theme.background }
        }
        return withSheets
        // 【二次驗證・高】觀察值改 plan 的 id：ImportPlan
        // 僅 Identifiable、未 conform Equatable，
        // Optional<ImportPlan> 不滿足 onChange 的型別約
        // 束（原寫法無法編譯）；UUID 觀察＋閉包內讀真源。
        .onChange(of: store.pendingImportPlan?.id) { _, id in
            if id != nil, activeSheet == nil,
               presentedImportPlan == nil,
               let plan = store.pendingImportPlan {
                presentedImportPlan = plan
                presentedImportPlanID = plan.id
            }
        }
        .onChange(of: activeSheet) { _, sheet in
            if sheet == nil, let plan = store.pendingImportPlan,
               presentedImportPlan == nil {
                presentedImportPlan = plan
                presentedImportPlanID = plan.id
            }
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
            // 【五維審計 F-1 雙保險】.dual 恆收斂（源頭已在
            // BackupImporter 映射層處理，此處防其他路徑直
            // 寫）：.dual 下兩頁皆透明、內容區全空白。
            if newMode == .dual { store.appMode = .tuner }
            if newMode != .metronome { startMicIfAutoEnabled() }
            refreshMetronomePageVisibility()
        }
        // 【返修批7・F11】膠囊顯隱（播放起停／暫停）改變
        // 節拍器 DisplayLink 的可見條件，同需刷新門控。
        .onChange(of: metronomeViewModel.isPlaying) { _, _ in
            refreshMetronomePageVisibility()
        }
        .onChange(of: metronomeViewModel.capsulePaused) { _, _ in
            refreshMetronomePageVisibility()
        }
        // 【返修批7・C5】離開前景（inactive／background）時
        // flush 節拍器 VM 的防抖 persist：600ms 防抖期間被殺
        // 會丟最後變更，進背景先即時落盤即無此窗。
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                metronomeViewModel.flushPersist()
            } else {
                // 【返修批7・D4】回前台：先對齊麥克風權限狀態
                // （用戶可能在系統設定改過，App 內提示須跟上），
                // 再沿既有路徑補啟動自動麥克風（守衛：autoMic
                // 開、非節拍頁、未運行；權限未授時 start 內自
                // 落 permissionDenied）。
                engine.refreshPermissionState()
                startMicIfAutoEnabled()
                // 【返修批10】回前台重預熱：後台期間震動
                // 引擎可能已被系統停機、音效引擎已閒置拆
                // 建——回到前台先把兩者喚醒並重建 player
                // 池，恢復後的第一拍／第一個音效即刻就緒，
                // 前後台手感一致。
                HapticsEngine.shared.warmUp()
                UISoundEngine.shared.warmUp()
                // 【返修批8】節拍器中斷殭屍對帳：中斷凍結
                // 調度後若恢復路徑未跑完，回前台在此收斂
                // （仍播但調度已死 → 恢復；恢復失敗走引擎
                // 內 stop＋lastError，不留無聲假播放）。
                metronomeEngine.reconcileAfterForeground()
                // 【全邏輯複查／S-2】調音引擎同型對帳：
                // 中斷 .ended 未達的 pause 凍結在此收斂。
                engine.reconcileAfterForeground()
            }
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
        // 編輯自訂樂器後引擎音域同步（審計修復）：編輯「目前已
        // 選中」的自訂樂器音域／移調並保存時，selectedInstrumentId
        // 值未變、其 onChange 不觸發，引擎會繼續以舊音域檢測；
        // 自訂樂器清單變更（編輯／新增／刪除／匯入）統一在此
        // 刷新 effectiveRange。
        .onChange(of: store.customInstruments) { _, _ in
            engine.range = store.effectiveRange
        }
        // 備份匯入的節拍器預置同步進運行中的 VM（審計修復，
        // 見 MetronomeViewModel.syncUserPresetsFromStore）。
        .onChange(of: store.metronomeUserPresets) { _, newPresets in
            metronomeViewModel.syncUserPresetsFromStore(newPresets)
        }
        .onChange(of: store.droneTimbre) { _, newTimbre in
            droneEngine.setTimbre(newTimbre)
        }
        .onChange(of: engine.isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: metronomeEngine.isPlaying) { _, _ in updateIdleTimer() }
        .onChange(of: droneEngine.isPlaying) { _, _ in updateIdleTimer() }
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
                    // 開機動畫的飛行落點：量取全局矩形；動畫
                    // 期間真標記隱藏，落地／淡出時恢復（母本
                    // .brand-mark 飛行期 opacity 0 同義）。
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { newFrame in
                        brandMarkFrame = newFrame
                    }
                    .opacity(showSplash && !splashRevealed ? 0 : 1)
                    // 【返修批7・開屏絲滑】落地交接時真標記
                    // 0.2s 淡入，與飛行徽章淡出交叉（見
                    // SplashView.startExit）。
                    .animation(.easeOut(duration: 0.2), value: splashRevealed)

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
                // 【返修批10】診斷圓鈕已依 Laurent 指示移除
                // （頂欄右側只剩偏好／設置裸文字鈕靠右）。
            }
            .frame(height: 36)

            GlassSegmentedControl(
                options: [
                    (option: AppMode.tuner, title: L10n.t("调音"), symbol: "tuningfork"),
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
                // 【返修批7・E13】命中區 32→40 高：上下各
                // 加 4pt 透明 padding（視覺尺寸不變；頂欄
                // 列高固定 36，命中溢出列外對稱延伸）。
                .padding(.vertical, 4)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 背景膠囊（母本 #9 metroCapsule）

    /// 【返修批7・F1】膠囊本體抽成 MetronomeCapsuleView
    /// 單獨觀察脈衝：舊版 capsule 為 ContentView 本體函數
    /// 直讀 VM 脈衝值，120 Hz 脈衝令 App 外殼整殼重算。
    /// isPlaying／文字／主題為低頻值輸入、由外殼重算時
    /// 帶入；脈衝幀只重繪膠囊本身。
    /// 多指亮斑狀態維護（返修批9）：按著的指逐幀更新位
    /// 置；剛離開的指轉衰減態、0.35 s 後移除，其餘指完
    /// 全不受影響。
    private func capsule(theme: TunerTheme) -> some View {
        MetronomeCapsuleView(
            isPlaying: metronomeViewModel.isPlaying,
            text: metronomeViewModel.capsuleText,
            theme: theme,
            glassOpacity: store.glassOpacity,
            pulse: metronomeViewModel.pulseRender,
            onTap: { metronomeViewModel.capsuleTapped() })
    }

    // MARK: - 頁面可見性門控（返修批7・F11）

    /// 節拍器 DisplayLink 的可見條件：節拍器頁在前台，
    /// 或背景膠囊在調音頁上可見（膠囊脈衝由該 link 驅動，
    /// 見 MetronomeViewModel.setPageVisible 註解）。調音
    /// 側的門控在 TunerView 內接線（TunerViewModel 歸其
    /// @StateObject 持有，本殼觸不到）。
    private func refreshMetronomePageVisibility() {
        metronomeViewModel.setPageVisible(
            store.appMode == .metronome || metronomeViewModel.capsuleVisible)
    }

    // MARK: - 螢幕常亮（母本 Wake Lock 的原生等價）

    /// want = 麥克風運行 || 節拍器播放 || Drone 播放（母本
    /// updateWakeLock；【返修批7・D8】補 Drone：單獨放基準音
    /// 時同需常亮，舊版漏列、播放中會熄屏）。
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            engine.isRunning || metronomeEngine.isPlaying || droneEngine.isPlaying
    }

    // MARK: - 深連結（階段 6，小組件入口）

    /// laurent-acoustic:// 的三條路徑；未知路徑不動作。
    /// start 路徑在節拍器已播放時不重啟（ViewModel.start 的
    /// 引擎側亦有冪等守衛，此處先擋避免多餘的啟動觸感）。
    /// 匯入確認 sheet 關閉收尾（自 onDismiss 閉包抽出，
    /// 同為 run #56 型別超時拆分的一部分）：真源仍是剛關
    /// 掉的那份（滑動關閉＝取消）才清；呈現期間有新 plan
    /// 到達（連續分享入）時不清、直接晉升呈現新份。按鈕
    /// 路徑已先清真源者，此處比對不中、為冪等空操作。
    private func handleImportSheetDismissed() {
        if store.pendingImportPlan?.id == presentedImportPlanID {
            store.pendingImportPlan = nil
        }
        presentedImportPlanID = nil
        if let waiting = store.pendingImportPlan {
            presentedImportPlan = waiting
            presentedImportPlanID = waiting.id
        }
    }

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

/// 背景膠囊本體（返修批7・F1 抽出）：單獨觀察
/// PulseRenderState，脈衝驅動的圓點透明度／縮放只重繪
/// 本 View；外殼（ContentView）不再被 120 Hz 脈衝牽動。
/// 視覺參數與舊 capsule 函數逐項一致。
private struct MetronomeCapsuleView: View {
    let isPlaying: Bool
    let text: String
    let theme: TunerTheme
    let glassOpacity: Int
    @ObservedObject var pulse: PulseRenderState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                    .opacity(isPlaying
                             ? 0.35 + 0.65 * pulse.value
                             : 0.5)
                    .scaleEffect(isPlaying
                                 ? 1 + 0.3 * pulse.value
                                 : 1)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    // 【五維審計・排版項11】膠囊含 BPM 數字：
                    // 補等寬數字，播放中數字跳動不改字寬。
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: glassOpacity)
            // 【五維審計・設計項5】手繪平色描邊刪除（同
            // 麥克風鈕理由）：批9 漸變描邊為唯一真源。
            .opacity(isPlaying ? 1 : 0.75)
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

/// 亮斑一指份（返修批9 多指化）：id 為 UITouch 物件身
/// 份、同指存續期間穩定；fading 為離手衰減態。
struct GlowSpot: Identifiable {
    let id: Int
    var point: CGPoint
    var fading: Bool
}

/// 亮斑狀態模型（返修批10・卡頓修復）：獨立於根視圖的
/// 狀態持有者——觸摸更新只令 PageGlowView 重繪（幾團徑
/// 向漸層圓），不再觸發 ContentView 整樹重算。發布帶
/// 變更守衛：落點與狀態皆未變的事件（多指中靜止指的
/// 重複回報）不發布。離手移除的 0.35 s 延時在本模型內
/// 自行收尾，語義與舊 updateGlowSpots 逐項一致。線程
/// 紀律：全部呼叫點皆在主線程（手勢識別器回調＋main
/// 佇列延時），故不加 actor 隔離、免 Swift 6 隔離摩擦。
final class GlowSpotModel: ObservableObject {
    @Published private(set) var spots: [GlowSpot] = []

    func update(_ touches: [(id: Int, point: CGPoint)]) {
        var next = spots
        var changed = false
        for touch in touches {
            if let i = next.firstIndex(where: { $0.id == touch.id }) {
                if next[i].point != touch.point || next[i].fading {
                    next[i].point = touch.point
                    next[i].fading = false
                    changed = true
                }
            } else {
                next.append(GlowSpot(id: touch.id, point: touch.point,
                                     fading: false))
                changed = true
            }
        }
        let activeIds = Set(touches.map { $0.id })
        for i in next.indices
        where !next[i].fading && !activeIds.contains(next[i].id) {
            next[i].fading = true
            changed = true
            let id = next[i].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                [weak self] in
                self?.spots.removeAll { $0.id == id && $0.fading }
            }
        }
        if changed { spots = next }
    }
}

/// 背景按壓亮斑（母本 #pageGlow，行 1960–1980／12352–12398）：
/// 每指一團 340×340 徑向光、1:1 跟隨。深色 screen 混合
/// （中心 rgba(130,175,255,0.15) → 白 0.05 @42% → 透
/// 明 @70%）；淺色 normal（白 0.55 → 0.12 → 透明）。
/// 亮起 0.12 s、熄滅 0.3 s（單指視圖 onAppear 淡入、
/// fading 淡出，位置永不動畫——跟隨必須 1:1）。
struct PageGlowView: View {
    /// 【返修批10】改觀察獨立模型（見 GlowSpotModel）：
    /// 觸摸幀只重繪本層。
    @ObservedObject var model: GlowSpotModel
    let theme: TunerTheme

    var body: some View {
        ZStack {
            ForEach(model.spots) { spot in
                GlowSpotView(spot: spot, theme: theme)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct GlowSpotView: View {
    let spot: GlowSpot
    let theme: TunerTheme
    @State private var shown = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: theme.isDark
                    ? [.init(color: Color(red: 130 / 255, green: 175 / 255, blue: 255 / 255).opacity(0.15), location: 0),
                       .init(color: Color.white.opacity(0.05), location: 0.42),
                       .init(color: .clear, location: 0.70)]
                    : [.init(color: Color.white.opacity(0.55), location: 0),
                       .init(color: Color.white.opacity(0.12), location: 0.42),
                       .init(color: .clear, location: 0.70)],
                center: .center, startRadius: 0, endRadius: 170))
            .frame(width: 340, height: 340)
            .blendMode(theme.isDark ? .screen : .normal)
            .position(spot.point)
            .opacity(spot.fading ? 0 : (shown ? 1 : 0))
            .animation(spot.fading ? AppMotion.glowOut : AppMotion.glowIn,
                       value: spot.fading)
            .animation(AppMotion.glowIn, value: shown)
            .onAppear { shown = true }
    }
}

/// 多指觸控追蹤（返修批9）：被動觀察全窗觸控——自訂手
/// 勢識別器掛在窗口上、永不進入 recognized 狀態、不取
/// 消不延遲任何既有手勢，逐指回報當前落點（窗口座標，
/// 與根層全局座標一致）。
private struct GlowTouchTracker: UIViewRepresentable {
    var onUpdate: ([(id: Int, point: CGPoint)]) -> Void

    /// 【CI 修復・run #55】自訂 Coordinator 類別在場時
    /// 框架的預設 makeCoordinator（Coordinator == Void
    /// 專用）不再適用，須顯式給出——原實現漏寫，協議
    /// 符合性失敗（唯一的編譯錯誤）。
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GlowAnchorView {
        let view = GlowAnchorView()
        view.isUserInteractionEnabled = false
        view.onMoveToWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window: window)
        }
        return view
    }

    func updateUIView(_ uiView: GlowAnchorView, context: Context) {
        context.coordinator.onUpdate = onUpdate
        context.coordinator.attach(window: uiView.window)
    }

    static func dismantleUIView(_ uiView: GlowAnchorView,
                                coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onUpdate: ([(id: Int, point: CGPoint)]) -> Void = { _ in }
        private var recognizer: GlowTouchRecognizer?
        private weak var window: UIWindow?

        func attach(window: UIWindow?) {
            guard let window else { return }
            if recognizer != nil {
                if self.window === window { return }
                detach()
            }
            let recognizer = GlowTouchRecognizer()
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.onUpdate = { [weak self] touches in
                self?.onUpdate(touches)
            }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            self.window = window
        }

        func detach() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }
    }
}

private final class GlowAnchorView: UIView {
    var onMoveToWindow: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?(window)
    }
}

private final class GlowTouchRecognizer: UIGestureRecognizer {
    var onUpdate: (([(id: Int, point: CGPoint)]) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        report(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        report(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        report(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        report(event)
    }

    private func report(_ event: UIEvent) {
        guard let view else { return }
        let active = (event.allTouches ?? []).filter {
            $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
        }
        onUpdate?(active.map {
            (id: ObjectIdentifier($0).hashValue, point: $0.location(in: view))
        })
    }
}

/// 開機動畫（返修批3 補回母本 .splash，規格見
/// docs/2026-11-27_母本規格提取-返修批3.md 第 1 節）。
/// 【返修批7・絲滑重做（Laurent 點名：好絲滑、不要卡頓）】
/// 舊版卡頓三源：徽章飛行走 frame＋position 的版面動畫
/// （逐幀 layout）、雙層陰影逐幀重繪、各元素混用三種曲線
/// 家族分段進場（段落感）。改為蘋果式單一彈簧系統：
/// 全部動效同一 spring 家族、相位重疊無死區；徽章飛行
/// 改純 transform（scale＋offset，合成器路徑、零 layout）；
/// 陰影收為單層隨 transform 走；落地最後 0.16s 與真標記
/// 交叉淡化交接。視覺內容（柔光底、字標、副標、落點、
/// 總時長 ≈2.0s）與母本規格不變。點按任意處跳過；減
/// 動效或無落點矩形時走淡出路徑。
struct SplashView: View {
    let theme: TunerTheme
    let targetFrame: CGRect
    @Binding var revealed: Bool
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var played = false
    @State private var exitStarted = false
    @State private var flying = false
    @State private var crossfaded = false
    @State private var landingFade = false
    @State private var faded = false
    @State private var finished = false

    private var dark: Bool { theme.isDark }

    // 單一彈簧家族：入場微彈、飛行近臨界阻尼（落點不彈跳、
    // 只輕輕收住），全體元素共用同一物理語言。
    private static let entrySpring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    private static let wordSpring = Animation.spring(response: 0.55, dampingFraction: 0.85)
    private static let subSpring = Animation.spring(response: 0.6, dampingFraction: 0.85)
    private static let flightSpring = Animation.spring(response: 0.62, dampingFraction: 0.88)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // core 居中、底部 padding 8.5vh → 整體上移 4.25%h；
            // core 高 ≈ 74＋12＋14＋30＋14＋12 = 156。
            let coreCY = h / 2 - h * 0.0425
            // 徽章飛行改純 transform：版面恆為 74×74 居中於
            // 起點，飛行＝scale（74→落點邊長）＋offset（起點
            // 中心→落點中心）；圓角與字形隨 scale 同步縮放
            // （20 × 34/74 ≈ 9.2，與真標記圓角 9 幾乎一致）。
            let badgeCenter = CGPoint(x: w / 2, y: coreCY - 41)
            let canFly = targetFrame != .zero
            let flyScale = canFly ? targetFrame.width / 74 : 1
            let flyOffset = canFly
                ? CGSize(width: targetFrame.midX - badgeCenter.x,
                         height: targetFrame.midY - badgeCenter.y)
                : .zero
            ZStack {
                backdrop(w: w, h: h)
                    .opacity(flying || faded ? 0 : 1)
                    .animation(Self.flightSpring.delay(0.05), value: flying)
                    .animation(.easeInOut(duration: 0.34), value: faded)

                Group {
                    // 字標與副標（彈簧上浮入場；飛行時同彈簧淡出）
                    Text("LAURENT")
                        .font(.system(size: 25, weight: .heavy))
                        .tracking(8.5)
                        .foregroundStyle(dark ? Color(red: 238 / 255, green: 243 / 255, blue: 255 / 255)
                                             : Color(red: 18 / 255, green: 32 / 255, blue: 58 / 255))
                        .position(x: w / 2 + 4.25, y: coreCY + 28)
                        .opacity(flying || faded ? 0 : (played ? 1 : 0))
                        .offset(y: flying ? -5 : (played ? 0 : 7))
                        .animation(Self.wordSpring.delay(0.06), value: played)
                        .animation(Self.flightSpring, value: flying)
                    Text("STUDIO EDITION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(4.2)
                        .foregroundStyle(dark ? Color(red: 160 / 255, green: 178 / 255, blue: 214 / 255).opacity(0.85)
                                             : Color(red: 70 / 255, green: 90 / 255, blue: 130 / 255).opacity(0.8))
                        .position(x: w / 2 + 2.1, y: coreCY + 56)
                        .opacity(flying || faded ? 0 : (played ? 1 : 0))
                        .offset(y: flying ? -5 : (played ? 0 : 5))
                        .animation(Self.subSpring.delay(0.16), value: played)
                        .animation(Self.flightSpring, value: flying)

                    // 徽章本體：版面固定 74×74，入場彈簧縮放
                    // 淡入、飛行 transform 直達落點、落地交叉
                    // 淡化交接給真標記；單層陰影隨 transform。
                    badgeFace
                        .frame(width: 74, height: 74)
                        .shadow(color: Color(red: 31 / 255, green: 107 / 255, blue: 255 / 255).opacity(0.38),
                                radius: 24, x: 0, y: 8)
                        .position(x: badgeCenter.x, y: badgeCenter.y)
                        .scaleEffect(faded ? 0.97 : (flying ? flyScale : (played ? 1 : 0.94)))
                        .offset(flying ? flyOffset : .zero)
                        .opacity(faded || landingFade ? 0 : (played ? 1 : 0))
                        .animation(Self.entrySpring, value: played)
                        .animation(Self.flightSpring, value: flying)
                        .animation(.easeOut(duration: 0.18), value: landingFade)
                        .animation(.easeInOut(duration: 0.3), value: faded)
                }
                .opacity(faded ? 0 : 1)
                .animation(.easeInOut(duration: 0.34), value: faded)
            }
            .contentShape(Rectangle())
            .onTapGesture { skip() }
            .onAppear { run() }
        }
    }

    /// 徽章面：splash 漸變面與品牌標記面疊放，飛行末段
    /// （crossfaded）交叉淡化為標記本色。圓角恆 20——飛行
    /// 靠父層 transform 縮放，渲染圓角隨之縮至 ≈9.2，與
    /// 真標記 9 幾乎一致，不再逐幀改版面圓角。
    private var badgeFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 47 / 255, green: 123 / 255, blue: 255 / 255),
                             Color(red: 10 / 255, green: 92 / 255, blue: 255 / 255)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(crossfaded ? 0 : 1)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.accent)
                .opacity(crossfaded ? 1 : 0)
            Text("L")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .animation(.easeInOut(duration: 0.22), value: crossfaded)
    }

    /// 三團柔光＋基底（母本 .splash 背景四層 radial）。
    private func backdrop(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: dark
                    ? [Color(red: 20 / 255, green: 31 / 255, blue: 56 / 255),
                       Color(red: 9 / 255, green: 14 / 255, blue: 26 / 255),
                       Color(red: 7 / 255, green: 9 / 255, blue: 14 / 255)]
                    : [Color(red: 232 / 255, green: 238 / 255, blue: 252 / 255),
                       Color(red: 223 / 255, green: 231 / 255, blue: 248 / 255),
                       Color(red: 207 / 255, green: 219 / 255, blue: 242 / 255)],
                center: .top, startRadius: 0, endRadius: h * 0.95)
            RadialGradient(colors: [Color(red: 64 / 255, green: 120 / 255, blue: 255 / 255)
                                        .opacity(dark ? 0.20 : 0.16), .clear],
                           center: UnitPoint(x: 0.16, y: 0.06),
                           startRadius: 0, endRadius: w * 0.62)
            RadialGradient(colors: [Color(red: 124 / 255, green: 92 / 255, blue: 255 / 255)
                                        .opacity(dark ? 0.13 : 0.10), .clear],
                           center: UnitPoint(x: 0.88, y: 0.30),
                           startRadius: 0, endRadius: w * 0.56)
            RadialGradient(colors: [Color(red: 48 / 255, green: 160 / 255, blue: 190 / 255)
                                        .opacity(dark ? 0.10 : 0.08), .clear],
                           center: UnitPoint(x: 0.5, y: 1.1),
                           startRadius: 0, endRadius: w * 0.72)
        }
    }

    private func run() {
        played = true
        Task { @MainActor in
            if reduceMotion {
                try? await Task.sleep(nanoseconds: 450_000_000)
                // 【邏輯補查・低】守衛補 !exitStarted 與
                // 非 RM 分支齊平：RM 下點按 skip 已走淡出
                // 退場時，本 Task 醒來不得再疊一條淡出。
                guard !finished, !exitStarted else { return }
                exitStarted = true
                revealed = true
                withAnimation(.easeInOut(duration: 0.34)) { faded = true }
                try? await Task.sleep(nanoseconds: 380_000_000)
                finish()
            } else {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !finished, !exitStarted else { return }
                startExit()
            }
        }
    }

    private func startExit() {
        guard !exitStarted else { return }
        exitStarted = true
        // 【邏輯補查・低】Reduce Motion 下一律走淡出路徑：
        // 舊版 skip() 不判 RM、停留期點按直入飛行退場，
        // 與 RM 意圖相違且與 run() 的 450ms 淡出路徑疊加
        // 截斷。RM 與無落點同路（淡出），飛行僅留常規路徑。
        if reduceMotion || targetFrame == .zero {
            revealed = true
            withAnimation(.easeInOut(duration: 0.34)) { faded = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 380_000_000)
                finish()
            }
        } else {
            withAnimation(Self.flightSpring) { flying = true }
            withAnimation(.easeInOut(duration: 0.22).delay(0.5)) {
                crossfaded = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 680_000_000)
                guard !finished else { return }
                // 落地交接：真標記同帧恢復（ContentView 側
                // 0.2s 淡入）、飛行徽章 0.18s 淡出——位置
                // 重合，讀作無縫落地而非硬切。
                revealed = true
                withAnimation(.easeOut(duration: 0.18)) { landingFade = true }
                try? await Task.sleep(nanoseconds: 220_000_000)
                finish()
            }
        }
    }

    /// 點按跳過：飛行中立即交接淡出；停留中直接進退場。
    private func skip() {
        if flying {
            revealed = true
            withAnimation(.easeOut(duration: 0.2)) { landingFade = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 240_000_000)
                finish()
            }
        } else if !faded {
            startExit()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        revealed = true
        onFinished()
    }
}

#Preview {
    ContentView()
}
