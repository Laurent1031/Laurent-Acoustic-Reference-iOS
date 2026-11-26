import SwiftUI

/// 同屏模式（母本 mode-dual，階段 7 補齊）：調音與節拍器雙面板
/// 同時在場——母本以 CSS 把兩面板各自緊湊化（錶盤縮小、推子
/// 變矮、選項列收合），原生版同義：上半緊湊調音（主顯示＋音名
/// 列＋麥克風鈕，與調音頁同一 TunerViewModel／同一判準），下半
/// 緊湊節拍器（拍點＋BPM＋步進／TAP／啟停，與節拍器頁同一
/// MetronomeViewModel）。完整控件（收藏、目標音、推子、預置等）
/// 留在各自專頁，同屏只承載「邊練邊校」的核心回路——母本同屏
/// 亦為緊湊形態而非兩頁原樣堆疊。
///
/// 版面紀律：外層 GeometryReader 分配兩區高度（調音 47%／
/// 節拍器 53%），區內皆為固定行高堆疊，不重疊、不遮擋；
/// 兩引擎可同時運行（音訊組成由 AudioSessionCoordinator 的
/// record+playback 組成態承接，與 Drone＋麥克風同存同路）。
struct DualModeView: View {
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    @ObservedObject var drone: DroneEngine
    @ObservedObject var metronomeViewModel: MetronomeViewModel
    @StateObject private var tunerViewModel: TunerViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(engine: AudioEngine, store: AppStore, drone: DroneEngine,
         metronomeViewModel: MetronomeViewModel) {
        self.engine = engine
        self.store = store
        self.drone = drone
        self.metronomeViewModel = metronomeViewModel
        // 純顯示實例：副作用（觸感／音效／Drone 改頻／鎖定）
        // 由調音頁的正規 TunerViewModel 單一發出，防雙實例
        // 重複觸發（見 TunerViewModel.drivesSideEffects）。
        let displayVM = TunerViewModel(engine: engine, store: store, drone: drone)
        displayVM.drivesSideEffects = false
        _tunerViewModel = StateObject(wrappedValue: displayVM)
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        GeometryReader { geo in
            // 【裝機返修】舊版雙面板以分數定高、節拍面板內容
            // 僅約 170pt 卻占 0.53 高，餘白全壓在面板內造成
            // 中段大片空白（實機回報）。改：調音面板 0.46 定
            // 高（主顯示在面板內以明確邊長繪製），節拍面板
            // 吃滿剩餘高度、內容以上下 Spacer 均分餘白，
            // 任何機型都不出現單側死區。
            VStack(spacing: 8) {
                tunerPanel(theme: theme,
                           displaySize: min(geo.size.width * 0.56,
                                            geo.size.height * 0.27))
                    .frame(height: geo.size.height * 0.46)
                Divider().overlay(theme.textMuted.opacity(0.25))
                metronomePanel(theme: theme)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: geo.size.height)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if store.autoMicOnEnter, !engine.isRunning {
                    Task { await engine.start() }
                }
            }
        )
        .metroKeyboardShortcuts(viewModel: metronomeViewModel)
        .onDisappear { tunerViewModel.viewDidDisappear() }
    }

    // MARK: - 緊湊調音（與調音頁同源：顯示模式、判準、鎖定全同）

    private func tunerPanel(theme: TunerTheme, displaySize: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(store.selectedInstrument.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(tunerViewModel.frequencyText)
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }

            Group {
                if store.tunerDisplayMode == .strobe {
                    StrobeView(
                        phase: tunerViewModel.strobePhase,
                        rate: tunerViewModel.strobeRate,
                        anchorDate: tunerViewModel.strobeAnchorDate,
                        confidence: tunerViewModel.strobeConfidence,
                        micActive: engine.isRunning,
                        inTune: tunerViewModel.isInTune,
                        theme: theme)
                } else {
                    GaugeView(
                        cents: tunerViewModel.needleCents,
                        trail1Cents: tunerViewModel.trail1Cents,
                        trail2Cents: tunerViewModel.trail2Cents,
                        ghostCents: tunerViewModel.ghostCents,
                        ghostOpacity: tunerViewModel.ghostOpacity,
                        micActive: engine.isRunning,
                        inTune: tunerViewModel.isInTune,
                        tolerance: engine.settings.toleranceCents,
                        theme: theme)
                }
            }
            .frame(width: displaySize, height: displaySize)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tunerViewModel.noteText)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(tunerViewModel.isInTune ? theme.ok : theme.textPrimary)
                Text(tunerViewModel.octaveText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text(String(format: "%+.0f ¢", tunerViewModel.displayCents))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }

            Button {
                if engine.isRunning {
                    engine.stop()
                } else {
                    Task { await engine.start() }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(engine.isRunning ? theme.ok : theme.textMuted)
                        .frame(width: 8, height: 8)
                    Text(engine.isRunning ? L10n.t("校音中 · 点击停止") : L10n.t("开启麦克风校音"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassBackground(in: Capsule(), theme: theme,
                                 glassOpacity: store.glassOpacity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 緊湊節拍器（與節拍器頁同一 ViewModel）

    private func metronomePanel(theme: TunerTheme) -> some View {
        let vm = metronomeViewModel
        return VStack(spacing: 8) {
            Spacer(minLength: 0)
            // 拍點列（母本 beat dots 的緊湊形）：圓點大小隨重音
            // 等級，現行拍以 pulse 放大＋ accent 色標記。
            HStack(spacing: 7) {
                ForEach(0..<vm.displayBeatsInBar, id: \.self) { i in
                    let level = i < vm.settings.beatAccents.count
                        ? vm.settings.beatAccents[i] : 1
                    Circle()
                        .fill(dotColor(level: level, active: vm.displayBeat == i,
                                       theme: theme))
                        .frame(width: level >= 3 ? 13 : (level == 2 ? 11 : 9),
                               height: level >= 3 ? 13 : (level == 2 ? 11 : 9))
                        .scaleEffect(vm.displayBeat == i ? 1 + 0.35 * vm.pulseValue : 1)
                }
            }
            .frame(height: 18)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(vm.settings.bpm)")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BPM")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                    Text(MetronomeSettings.tempoTerm(vm.settings.bpm))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(theme.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(vm.settings.currentSignatureKey)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(vm.settings.timbre.displayName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            HStack(spacing: 6) {
                stepper(theme: theme, title: "−5") { vm.stepBpm(-5) }
                stepper(theme: theme, title: "−1") { vm.stepBpm(-1) }
                stepper(theme: theme, title: "+1") { vm.stepBpm(1) }
                stepper(theme: theme, title: "+5") { vm.stepBpm(5) }
            }

            HStack(spacing: 8) {
                Button {
                    vm.tapTempo()
                } label: {
                    Text(L10n.t("TAP 测速"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassBackground(in: Capsule(), theme: theme,
                                         glassOpacity: store.glassOpacity)
                }
                .buttonStyle(.plain)

                Button {
                    vm.togglePlay()
                } label: {
                    Text(vm.isPlaying ? L10n.t("停止节拍器 · STOP") : L10n.t("启动节拍器 · START"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vm.isPlaying ? theme.clipWarning : theme.accent,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func dotColor(level: Int, active: Bool, theme: TunerTheme) -> Color {
        if active { return theme.accent }
        switch level {
        case 3: return theme.textPrimary.opacity(0.85)
        case 2: return theme.textSecondary.opacity(0.7)
        case 0: return theme.textMuted.opacity(0.25)
        default: return theme.textMuted.opacity(0.5)
        }
    }

    private func stepper(theme: TunerTheme, title: String,
                         action: @escaping () -> Void) -> some View {
        HoldRepeatButton(action: action, label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .glassBackground(in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                 theme: theme, glassOpacity: store.glassOpacity)
        })
    }
}

// MARK: - 外接鍵盤快捷鍵（母本行 12152：metro／dual 模式）

/// 母本鍵盤支援：↑／↓ ±1 BPM、PageUp／PageDown ±10 BPM
/// （metro 與 dual 模式生效）。原生以 onKeyPress 承接（外接
/// 鍵盤／iPad 鍵盤）；無鍵盤時完全惰性，不影響觸控路徑。
extension View {
    func metroKeyboardShortcuts(viewModel: MetronomeViewModel) -> some View {
        self
            .focusable()
            .onKeyPress(.upArrow) { viewModel.stepBpm(1); return .handled }
            .onKeyPress(.downArrow) { viewModel.stepBpm(-1); return .handled }
            .onKeyPress(.pageUp) { viewModel.stepBpm(10); return .handled }
            .onKeyPress(.pageDown) { viewModel.stepBpm(-10); return .handled }
    }
}
