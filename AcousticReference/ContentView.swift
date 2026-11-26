import SwiftUI
import UIKit

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
    @State private var showDebug = false
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

        let metroEngine = MetronomeEngine(settings: store.metronomeSettings)
        _metronomeEngine = StateObject(wrappedValue: metroEngine)
        let metroViewModel = MetronomeViewModel(
            engine: metroEngine,
            persisted: (settings: store.metronomeSettings,
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
        let theme = TunerTheme.resolve(preference: store.themePreference,
                                       system: colorScheme)
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
            }
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
        .preferredColorScheme(store.themePreference.forcedColorScheme)
        .sheet(isPresented: $showDebug) {
            TunerDebugView(engine: engine,
                           metronomeEngine: metronomeEngine,
                           metronomeViewModel: metronomeViewModel,
                           store: store)
        }
        .onAppear {
            HapticsEngine.shared.isEnabled = engine.settings.hapticsOn
            UISoundEngine.shared.isEnabled = engine.settings.soundsOn
            updateIdleTimer()
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

    // MARK: - 頂欄（母本 topBar：品牌＋分段＋診斷）

    private func topBar(theme: TunerTheme) -> some View {
        HStack(spacing: 10) {
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
                Text("STUDIO EDITION")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(theme.textMuted)
            }

            Spacer()

            modeSegment(theme: theme)

            Button {
                rehearsalLocked = true
                HapticsEngine.shared.tap(milliseconds: 12)
            } label: {
                Image(systemName: "lock.open")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .accessibilityLabel("排練鎖定")

            Button {
                showDebug = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .accessibilityLabel("診斷")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// 分段切換（母本 seg：調音／節拍；選中滑塊以 spring 移動，
    /// 切換震動 haptic(6)——母本 segBtn 呼叫點）。
    private func modeSegment(theme: TunerTheme) -> some View {
        HStack(spacing: 2) {
            segmentButton(mode: .tuner, title: "調音",
                          symbol: "tuningfork", theme: theme)
            segmentButton(mode: .metronome, title: "節拍",
                          symbol: "metronome", theme: theme)
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func segmentButton(mode target: AppMode, title: String,
                               symbol: String, theme: TunerTheme) -> some View {
        let active = mode == target
        return Button {
            guard mode != target else { return }
            store.appMode = target
            HapticsEngine.shared.tap(milliseconds: 6)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? .white : theme.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(active ? theme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
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
                    Text("排練鎖定 · 長按解鎖")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
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
                .accessibilityLabel("排練鎖定中，長按解鎖")
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    theme.isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                    lineWidth: 1)
            }
            .opacity(metronomeViewModel.isPlaying ? 1 : 0.75)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 螢幕常亮（母本 Wake Lock 的原生等價）

    /// want = 麥克風運行 || 節拍器播放（母本 updateWakeLock）。
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            engine.isRunning || metronomeEngine.isPlaying
    }
}

#Preview {
    ContentView()
}
