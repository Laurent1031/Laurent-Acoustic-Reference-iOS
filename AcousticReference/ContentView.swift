import SwiftUI
import UIKit

/// App 模式（母本 state.mode 的 tuner/metro 子集；母本的 dual
/// 同屏模式在豎屏手機上不適用——母本自身在豎屏亦強制單頁，
/// 見階段 3 報告的有意差異）。
enum AppMode: String {
    case tuner
    case metronome
}

/// App 殼（階段 3）：頂欄（品牌＋調音/節拍分段切換＋診斷入口，
/// 對照母本頂欄）＋兩頁保活切換＋節拍器背景膠囊＋螢幕常亮管理。
/// 兩頁以 ZStack 疊放、僅切透明度與命中測試：任一頁的執行期
/// 狀態（調音分析、節拍調度、動畫時鐘）在切頁後不中斷——
/// 對照母本「兩者可同時運行」（節拍器運行時切回調音頁，
/// 節拍器照常發聲、膠囊常駐）。
struct ContentView: View {
    /// 全 App 共用同一個調音引擎實例（主畫面與診斷頁共用）。
    @StateObject private var engine = AudioEngine()
    @StateObject private var metronomeEngine: MetronomeEngine
    @StateObject private var metronomeViewModel: MetronomeViewModel
    @State private var mode: AppMode
    @State private var showDebug = false
    @Environment(\.colorScheme) private var colorScheme

    private static let modeKey = "laurent.app.mode"

    init() {
        let metroEngine = MetronomeEngine(settings: MetronomeSettings())
        _metronomeEngine = StateObject(wrappedValue: metroEngine)
        _metronomeViewModel = StateObject(
            wrappedValue: MetronomeViewModel(engine: metroEngine))
        let saved = UserDefaults.standard.string(forKey: Self.modeKey)
        _mode = State(initialValue: AppMode(rawValue: saved ?? "") ?? .tuner)
    }

    var body: some View {
        let theme = TunerTheme.resolve(colorScheme)
        VStack(spacing: 0) {
            topBar(theme: theme)

            ZStack {
                TunerView(engine: engine)
                    .opacity(mode == .tuner ? 1 : 0)
                    .allowsHitTesting(mode == .tuner)
                    .accessibilityHidden(mode != .tuner)
                MetronomeView(engine: metronomeEngine,
                              viewModel: metronomeViewModel)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.9),
                   value: metronomeViewModel.capsuleVisible)
        .sheet(isPresented: $showDebug) {
            TunerDebugView(engine: engine,
                           metronomeEngine: metronomeEngine,
                           metronomeViewModel: metronomeViewModel)
        }
        .onAppear {
            HapticsEngine.shared.isEnabled = engine.settings.hapticsOn
            updateIdleTimer()
        }
        .onChange(of: engine.settings.hapticsOn) { _, on in
            HapticsEngine.shared.isEnabled = on
        }
        .onChange(of: engine.isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: metronomeEngine.isPlaying) { _, _ in updateIdleTimer() }
        .onChange(of: mode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        }
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
            mode = target
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
