import SwiftUI

/// 調音主畫面：樂器名行＋錶盤＋音名大字
/// ＋四格數據卡（記譜／實音／音分／頻率）＋穩定度徽章＋麥克風主按鈕。
/// 頂欄（品牌＋分段切換＋診斷入口）自階段 3 起上移至 ContentView
/// 殼（調音／節拍兩頁共用），本畫面不再自帶頂欄與診斷 sheet。
/// 版面：單欄直向堆疊、間距固定、提示列與徽章列預留固定高度，
/// 任何狀態切換不重排、不遮擋、不重疊；尺寸以螢幕物理高錨定
/// （音名字級 clamp(36, 6.4vh, 64)，與母本 .pitch-note 同式）。
/// 樂器庫／設定／節拍器頁面屬後續階段，本畫面不含。
struct TunerView: View {
    @ObservedObject var engine: AudioEngine
    @StateObject private var viewModel: TunerViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(engine: AudioEngine) {
        self.engine = engine
        _viewModel = StateObject(wrappedValue: TunerViewModel(engine: engine))
    }

    var body: some View {
        let theme = TunerTheme.resolve(colorScheme)

        GeometryReader { geo in
            // 母本 .pitch-note：clamp(36px, 6.4vh, 64px)；
            // .pitch-octave：clamp(16px, 2.8vh, 26px)。
            let noteSize = min(64, max(36, geo.size.height * 0.064))
            let octaveSize = min(26, max(16, geo.size.height * 0.028))
            let gaugeHeight = min(
                (geo.size.width - 32) * 190.0 / 320.0,
                geo.size.height * 0.34
            )

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 10) {
                    instrumentRow(theme: theme)

                    GaugeView(
                        cents: viewModel.needleCents,
                        trail1Cents: viewModel.trail1Cents,
                        trail2Cents: viewModel.trail2Cents,
                        ghostCents: viewModel.ghostCents,
                        ghostOpacity: viewModel.ghostOpacity,
                        micActive: engine.isRunning,
                        inTune: viewModel.isInTune,
                        tolerance: engine.settings.toleranceCents,
                        theme: theme
                    )
                    .frame(height: gaugeHeight)

                    noteRow(theme: theme, noteSize: noteSize, octaveSize: octaveSize)

                    statusHint(theme: theme)

                    metricsCard(theme: theme)

                    stabilityRow(theme: theme)

                    Spacer(minLength: 0)

                    micControls(theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
        }
        .onDisappear { viewModel.viewDidDisappear() }
    }

    // MARK: - 樂器名行（頂欄已上移 ContentView 殼；此處只保留
    // 目前樂器名，右對齊小字——版面高度因此比階段 2 略增，
    // 其餘錶盤區由 Spacer 吸收，不遮擋、不重排）

    private func instrumentRow(theme: TunerTheme) -> some View {
        HStack {
            Spacer()
            Text(viewModel.instrumentDisplayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(height: 18)
    }

    // MARK: - 音名行

    private func noteRow(theme: TunerTheme, noteSize: CGFloat, octaveSize: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(viewModel.noteText)
                    .font(.system(size: noteSize, weight: .bold))
                    .foregroundStyle(noteColor(theme: theme))
                    .shadow(
                        color: (viewModel.isInTune || viewModel.noteLocked)
                            ? theme.ok.opacity(theme.isDark ? 0.42 : 0.28) : .clear,
                        radius: theme.isDark ? 11 : 7
                    )
                    .animation(.easeOut(duration: 0.18), value: viewModel.isInTune)
                    .animation(.easeOut(duration: 0.18), value: viewModel.noteLocked)

                Text(viewModel.octaveText)
                    .font(.system(size: octaveSize, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }

            // 唱名標籤（母本 .solfege-tag；鎖定時轉 ok 色，母本行 3398）。
            Text(viewModel.solfegeText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(viewModel.noteLocked ? theme.ok : theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        (viewModel.noteLocked ? theme.ok : theme.accent).opacity(0.35),
                        lineWidth: 1
                    )
                }
                .animation(.easeOut(duration: 0.18), value: viewModel.noteLocked)
        }
        .frame(maxWidth: .infinity)
    }

    private func noteColor(theme: TunerTheme) -> Color {
        if viewModel.isInTune || viewModel.noteLocked { return theme.okText }
        if !viewModel.hasNote { return theme.textMuted }
        return theme.textPrimary
    }

    // MARK: - 狀態提示（固定高度，防重排）

    private func statusHint(theme: TunerTheme) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(theme.accent)
                .frame(width: 7, height: 7)
            Text("點擊下方「開啟麥克風校音」開始檢測")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 18)
        .opacity(engine.isRunning ? 0 : 1)
    }

    // MARK: - 數據卡（母本 Row 5 四格：WRITTEN／CONCERT／CENTS／FREQ）

    private func metricsCard(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            metricBox(theme: theme, label: "WRITTEN 記譜", value: viewModel.writtenText)
            metricBox(theme: theme, label: "CONCERT 實音", value: viewModel.concertText)
            metricBox(
                theme: theme, label: "CENTS 音分",
                value: viewModel.centsDisplayText,
                valueColor: viewModel.isInTune ? theme.ok : theme.textPrimary
            )
            metricBox(theme: theme, label: "FREQ 頻率", value: viewModel.frequencyText)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private func metricBox(
        theme: TunerTheme, label: String, value: String, valueColor: Color? = nil
    ) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            theme.isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - 穩定度徽章（母本 trace-stats-badge；輕點切換定格）

    private func stabilityRow(theme: TunerTheme) -> some View {
        HStack {
            Spacer()
            Button {
                viewModel.toggleFreeze()
            } label: {
                Text(viewModel.stabilityBadgeText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        viewModel.stabilityFrozen ? theme.accent : theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 24)
    }

    // MARK: - 麥克風控制

    private func micControls(theme: TunerTheme) -> some View {
        VStack(spacing: 8) {
            if engine.permissionDenied {
                Text("麥克風權限被拒絕，請到系統設定開啟")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let error = engine.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                if engine.isRunning {
                    engine.stop()
                } else {
                    Task { await engine.start() }
                }
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(engine.isRunning ? theme.ok : theme.textMuted)
                        .frame(width: 9, height: 9)
                    Text(engine.isRunning ? "校音中 · 點擊停止" : "開啟麥克風校音")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TunerView(engine: AudioEngine())
}
