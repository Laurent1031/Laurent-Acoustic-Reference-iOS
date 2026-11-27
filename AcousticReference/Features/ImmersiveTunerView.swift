import SwiftUI

/// 橫屏沉浸調音（階段 6）：母本沉浸式全屏（index.html 行 1192
/// CSS／5142 HTML／6339 JS）的原生等價，亦是橫屏鐵律下唯一
/// 合法的橫屏狀態——由 TunerView 的「全屏」鈕以
/// fullScreenCover 呈現，進入即經 OrientationManager 鎖
/// 橫屏、退出（onDisappear）即還原豎屏鎖。
///
/// 版面（對照母本 overlay）：恆暗色舞台（pit 偏好時走 pit
/// token，護夜視——母本無 pit 態，此為原生適配註明）；頂列
/// 樂器膠囊（名｜調號）＋麥克風開關膠囊＋退出膠囊；中央左
/// 主顯示（與豎屏同一顯示模式：頻閃／錶盤，讀數同源
/// TunerViewModel）、右讀數列（大音名＋八度、音分、頻率、
/// 唱名與副音名行）。準音時全屏轉翡翠綠（母本 .in-tune-
/// screen，0.22 s 過渡）為母本標誌行為，原生照搬。
struct ImmersiveTunerView: View {
    @ObservedObject var viewModel: TunerViewModel
    /// 高頻渲染狀態（返修批4）：本頁直接觀察 render（針／頻閃／
    /// 讀數），不再經 ViewModel 訂閱——沉浸頁本身即高速顯示區。
    @ObservedObject var render: TunerRenderState
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// 沉浸主題：母本恆暗；pit 偏好沿 pit（見類註解）。
    private var theme: TunerTheme {
        store.themePreference == .pit ? .pit : .dark
    }

    var body: some View {
        let theme = theme
        GeometryReader { geo in
            ZStack {
                background(theme: theme)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    topBar(theme: theme)

                    HStack(spacing: 22) {
                        displayContent(theme: theme, height: geo.size.height * 0.66)
                            .frame(maxWidth: .infinity)

                        readoutColumn(theme: theme)
                            .frame(width: min(300, geo.size.width * 0.34))
                    }
                    .frame(maxHeight: .infinity)
                }
                // 【返修批7・E6】四邊內縮改隨 safeAreaInsets：
                // 舊固定水平 26 在橫屏靈動島側（內縮 ≈59）
                // 不足，頂列膠囊左段可落入島體範圍；改每邊
                // max(原值, 內縮＋12)，島側自動讓出 ≈71，
                // 無內縮邊維持原 26/14、視覺不變。
                .padding(.leading, max(26, geo.safeAreaInsets.leading + 12))
                .padding(.trailing, max(26, geo.safeAreaInsets.trailing + 12))
                .padding(.top, max(14, geo.safeAreaInsets.top + 8))
                .padding(.bottom, max(14, geo.safeAreaInsets.bottom + 8))
            }
        }
        .onAppear {
            OrientationManager.shared.apply(.landscape)
            // 母本：開啟全屏時自動開啟麥克風（autoMicOnEnter
            // 的三觸發點之一，設定文案行 5680）。
            if store.autoMicOnEnter, !engine.isRunning {
                Task { await engine.start() }
            }
        }
        .onDisappear {
            OrientationManager.shared.apply(.portrait)
        }
    }

    // MARK: - 背景（母本行 1211／1231）

    /// 舞台底：深色徑向（藍紫微光三團 → 黑）；準音時整屏
    /// 翡翠綠徑向（#10B981 → #059669 → #047857）。pit 時底
    /// 沿 pit 背景（暗紅近黑），準音綠改走 pit 的 ok 朱紅
    /// 低亮版，避免夜視被綠光擊穿（原生適配註明）。
    @ViewBuilder
    private func background(theme: TunerTheme) -> some View {
        if render.isInTune {
            RadialGradient(
                colors: theme.isPit
                    ? [Color(hex: 0x5A1408), Color(hex: 0x2A0803)]
                    : [Color(hex: 0x10B981), Color(hex: 0x059669), Color(hex: 0x047857)],
                center: UnitPoint(x: 0.5, y: 0.85),
                startRadius: 0, endRadius: 620
            )
            .animation(.easeInOut(duration: 0.22), value: render.isInTune)
        } else if theme.isPit {
            theme.background
        } else {
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Color(hex: 0x0A54FF).opacity(0.15), Color.clear],
                    center: UnitPoint(x: 0.18, y: 0),
                    startRadius: 0, endRadius: 520)
                RadialGradient(
                    colors: [Color(hex: 0x5E5CE6).opacity(0.11), Color.clear],
                    center: UnitPoint(x: 0.85, y: 1.1),
                    startRadius: 0, endRadius: 480)
                RadialGradient(
                    colors: [Color(hex: 0x1C1C1E), Color.clear],
                    center: UnitPoint(x: 0.5, y: 1),
                    startRadius: 0, endRadius: 560)
            }
        }
    }

    // MARK: - 頂列（母本 .imm-top-bar）

    private func topBar(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.localizedName(store.selectedInstrument.name))
                    .font(.system(size: 12, weight: .bold))
                Text("|")
                    .opacity(0.65)
                Text(store.keyLabel(of: store.selectedInstrument))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)

            Spacer()

            Button {
                if engine.isRunning {
                    engine.stop()
                } else {
                    Task { await engine.start() }
                }
                HapticsEngine.shared.tap(milliseconds: 6)
            } label: {
                Text(engine.isRunning ? L10n.t("校音中 · 点击停止") : L10n.t("开启麦克风"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
                HapticsEngine.shared.tap(milliseconds: 6)
            } label: {
                Text(L10n.t("退出全屏"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("退出全屏"))
        }
    }

    // MARK: - 主顯示（與豎屏同源同模式）

    @ViewBuilder
    private func displayContent(theme: TunerTheme, height: CGFloat) -> some View {
        if store.tunerDisplayMode == .strobe {
            StrobeView(
                phase: render.strobePhase,
                rate: render.strobeRate,
                anchorDate: render.strobeAnchorDate,
                confidence: render.strobeConfidence,
                micActive: engine.isRunning,
                inTune: render.isInTune,
                theme: theme
            )
            .frame(height: height)
        } else {
            GaugeView(
                cents: render.needleCents,
                trail1Cents: render.trail1Cents,
                trail2Cents: render.trail2Cents,
                ghostCents: render.ghostCents,
                ghostOpacity: render.ghostOpacity,
                micActive: engine.isRunning,
                inTune: render.isInTune,
                tolerance: engine.settings.toleranceCents,
                theme: theme
            )
            .frame(width: height * 320.0 / 190.0, height: height)
        }
    }

    // MARK: - 讀數列（母本 .imm-readout-box）

    private func readoutColumn(theme: TunerTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(render.noteText)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .foregroundStyle(render.isInTune ? theme.okText : .white)
                    .opacity(render.hasNote ? 1 : 0.4)
                Text(render.octaveText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text(render.centsDisplayText)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(render.isInTune ? theme.okText : .white)

            Text(render.frequencyText)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))

            Divider()
                .overlay(Color.white.opacity(0.18))

            Text(L10n.t(render.solfegeText))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(store.pitchMode == .written
                 ? L10n.t("实音 ") + render.concertText
                 : L10n.t("记谱 ") + render.writtenText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            if engine.permissionDenied {
                Text(L10n.t("麦克风权限被拒绝，请到系统设置开启"))
                    .font(.footnote)
                    .foregroundStyle(theme.clipWarning)
            }
            if let error = engine.lastError {
                Text(L10n.t(error))
                    .font(.footnote)
                    .foregroundStyle(theme.clipWarning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
