import SwiftUI
import UIKit

/// 階段 1 最小驗證介面：文字顯示頻率／音名／音分＋診斷值＋引擎控制。
/// 階段 2 起降為診斷頁：由主畫面頂欄以 sheet 喚出，與主畫面共用
/// 同一個 AudioEngine 實例（外部注入），本視圖不再自建引擎。
struct TunerDebugView: View {
    @ObservedObject var engine: AudioEngine
    /// 節拍器診斷（階段 3 起由 ContentView 殼注入；缺省時不顯示該段）。
    var metronomeEngine: MetronomeEngine?
    var metronomeViewModel: MetronomeViewModel?
    /// 階段 5 起本頁回歸純診斷：過渡開關（外觀主題、音效、
    /// 震動、藍牙補償）已全數遷往設定頁單一真源，本頁不再
    /// 持有任何設定入口。此頁為固定黑底診斷頁，不隨主題
    /// 變色（有意差異，見補強段報告）。
    @ObservedObject var store: AppStore
    @State private var logCopied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("LAURENT")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 12)

                Spacer(minLength: 0)

                // 音名（實音）
                Text(engine.latestReading?.noteName ?? "——")
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                // 音分偏差（spring 輸出，0.1¢ 顯示）
                Text(centsText)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(centsColor)
                    .monospacedDigit()

                // 頻率（平滑後，0.1 Hz 顯示）
                VStack(spacing: 4) {
                    Text(frequencyText)
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .monospacedDigit()
                    Text(rawFrequencyText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                }

                diagnosticsText
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)

                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 顯示文字

    private var centsText: String {
        guard let reading = engine.latestReading else { return "— ¢" }
        return String(format: "%+.1f ¢", reading.cents)
    }

    private var centsColor: Color {
        guard let reading = engine.latestReading, reading.hasPitch else {
            return .white.opacity(0.5)
        }
        return reading.isInTune ? .green : .white
    }

    private var frequencyText: String {
        guard let reading = engine.latestReading else { return "— Hz" }
        return String(format: "%.1f Hz", reading.smoothedFrequency)
    }

    private var rawFrequencyText: String {
        guard let raw = engine.latestReading?.rawFrequency else {
            return L10n.t("原始") + " — Hz"
        }
        return String(format: "%@ %.1f Hz", L10n.t("原始"), raw)
    }

    private var diagnosticsText: Text {
        let reading = engine.latestReading
        let clarity = reading.map { String(format: "%.3f", $0.clarity) } ?? "—"
        let rms = reading.map { String(format: "%.4f", $0.rms) } ?? "—"
        var line = L10n.t("清晰度") + " \(clarity) · RMS \(rms)"
        if let d = engine.diagnostics {
            line += String(
                format: "\n%@ %.0f Hz · %@ %.1f ms · %@ %.1f ms",
                L10n.t("取样率"), d.sampleRate,
                L10n.t("IO 缓冲"), d.ioBufferDuration * 1000,
                L10n.t("采集延迟"), d.captureLatency * 1000)
        }
        return Text(line)
    }

    /// 目前樂器檢測範圍＋容差（動態，取代原寫死的中音薩克斯值）。
    private var rangeInfoText: String {
        let inst = store.selectedInstrument
        return "\(L10n.localizedName(inst.name)) · \(L10n.t("检测范围")) "
            + String(format: "%.0f–%.0f Hz", inst.minFrequency, inst.maxFrequency)
            + " · \(L10n.t("容差")) ±"
            + String(format: "%.1f", store.tunerSettings.toleranceCents) + "¢"
    }

    // MARK: - 控制

    private var controls: some View {
        VStack(spacing: 14) {
            if engine.permissionDenied {
                Text(L10n.t("麦克风权限被拒绝，请到系统设置开启"))
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
                Text(engine.isRunning ? L10n.t("停止校音") : L10n.t("开启麦克风校音"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.039, green: 0.518, blue: 1.0)) // #0A84FF

            // A4／噪聲門／阻尼的診斷直控（階段 5 改綁 store
            // 單一真源：與設定頁、調音頁步進器同值，ContentView
            // 的 onChange 統一同步進引擎，不再有 engine 直寫的
            // 第二路徑）。
            HStack {
                Text("A4")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("−") { store.tunerSettings.stepA4(by: -0.5) }
                    .font(.system(size: 20, weight: .semibold))
                Text(String(format: "%.1f Hz", store.tunerSettings.a4))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(minWidth: 86)
                Button("＋") { store.tunerSettings.stepA4(by: 0.5) }
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(.white)

            // 【返修批3】原 .segmented 原生 Picker 是 UIKit
            // 控件，未選中字色跟裝置外觀走：裝置淺色＋本頁
            // 固定黑底時未選中字成深色壓深軌道，實機看不見
            // （Laurent 截圖點名）。改全 App 同款玻璃分段，
            // 字色恆走主題 token，與裝置外觀脫鉤。
            GlassSegmentedControl(
                options: [
                    (option: NoiseGateProfile.low, title: L10n.t("低"), symbol: nil),
                    (option: NoiseGateProfile.mid, title: L10n.t("中"), symbol: nil),
                    (option: NoiseGateProfile.high, title: L10n.t("高"), symbol: nil),
                ],
                selection: $store.tunerSettings.noiseGate,
                theme: .dark,
                glassOpacity: store.glassOpacity)
                .accessibilityLabel(L10n.t("噪声门"))

            GlassSegmentedControl(
                options: [
                    (option: DampingProfile.fast, title: L10n.t("快速"), symbol: nil),
                    (option: DampingProfile.balanced, title: L10n.t("标准"), symbol: nil),
                    (option: DampingProfile.smooth, title: L10n.t("平稳"), symbol: nil),
                ],
                selection: $store.tunerSettings.damping,
                theme: .dark,
                glassOpacity: store.glassOpacity)
                .accessibilityLabel(L10n.t("阻尼"))

            // 範圍資訊列（階段 5 改為隨目前樂器動態生成；
            // 原寫死「中音薩克斯 130–1200」在選其他樂器時
            // 為錯誤資訊，此處一併修正）。
            Text(rangeInfoText)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            if let metronomeEngine {
                MetronomeDebugSection(metronomeEngine: metronomeEngine)
            }

            HStack(spacing: 12) {
                Button(logCopied ? L10n.t("已复制") : L10n.t("复制诊断记录")) {
                    UIPasteboard.general.string = engine.exportDetectionLog()
                    logCopied = true
                }
                Button(L10n.t("清除记录")) {
                    engine.clearDetectionLog()
                    logCopied = false
                }
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// 節拍器診斷段（階段 3）：調度漂移統計（排程樣本時間計算）
/// 與 Core Haptics 可用性。階段 5：原在此的震動總開關與藍牙
/// 補償已遷往系統設定頁（單一真源），本段回歸純診斷。
private struct MetronomeDebugSection: View {
    @ObservedObject var metronomeEngine: MetronomeEngine

    var body: some View {
        VStack(spacing: 10) {
            Divider().overlay(.white.opacity(0.25))

            Text(metronomeDiagnosticsText)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
                .multilineTextAlignment(.center)

            Text(HapticsEngine.shared.supportsHaptics
                 ? L10n.t("Core Haptics 可用")
                 : L10n.t("Core Haptics 不可用（降级为系统震动）"))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var metronomeDiagnosticsText: String {
        let d = metronomeEngine.diagnostics
        let state = metronomeEngine.isPlaying ? L10n.t("运行中") : L10n.t("已停止")
        let head = L10n.t("节拍器") + " " + state
        guard d.beatsScheduled > 0 else {
            return head + " · " + L10n.t("尚无排程拍")
        }
        return String(
            format: "%@ · %@ %d · %@ %.2f ms\n%@ %.3f ms · %@ %.3f ms · %@ %.1f ms",
            head, L10n.t("已排程主拍"), d.beatsScheduled,
            L10n.t("最近拍距"), d.lastIntervalMs,
            L10n.t("平均|偏差|"), d.meanAbsDeviationMs,
            L10n.t("最大"), d.maxAbsDeviationMs,
            L10n.t("最小调度余量"), d.minHeadroomMs)
    }
}

#Preview {
    TunerDebugView(engine: AudioEngine(), store: AppStore())
}
