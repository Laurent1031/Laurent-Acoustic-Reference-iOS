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
    /// 補強段過渡入口：外觀主題（含樂池暗紅）與 UI 音效開關。
    /// 正式設定頁屬階段 5；此頁為固定黑底診斷頁，不隨主題
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
        guard let raw = engine.latestReading?.rawFrequency else { return "原始 — Hz" }
        return String(format: "原始 %.1f Hz", raw)
    }

    private var diagnosticsText: Text {
        let reading = engine.latestReading
        let clarity = reading.map { String(format: "%.3f", $0.clarity) } ?? "—"
        let rms = reading.map { String(format: "%.4f", $0.rms) } ?? "—"
        var line = "清晰度 \(clarity) · RMS \(rms)"
        if let d = engine.diagnostics {
            line += String(
                format: "\n取樣率 %.0f Hz · IO 緩衝 %.1f ms · 採集延遲 %.1f ms",
                d.sampleRate, d.ioBufferDuration * 1000, d.captureLatency * 1000)
        }
        return Text(line)
    }

    // MARK: - 控制

    private var controls: some View {
        VStack(spacing: 14) {
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
                Text(engine.isRunning ? "停止校音" : "開啟麥克風校音")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.039, green: 0.518, blue: 1.0)) // #0A84FF

            HStack {
                Text("A4")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("−") { engine.settings.stepA4(by: -0.5) }
                    .font(.system(size: 20, weight: .semibold))
                Text(String(format: "%.1f Hz", engine.settings.a4))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(minWidth: 86)
                Button("＋") { engine.settings.stepA4(by: 0.5) }
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(.white)

            Picker("噪聲門", selection: $engine.settings.noiseGate) {
                Text("低").tag(NoiseGateProfile.low)
                Text("中").tag(NoiseGateProfile.mid)
                Text("高").tag(NoiseGateProfile.high)
            }
            .pickerStyle(.segmented)

            Picker("阻尼", selection: $engine.settings.damping) {
                Text("快速").tag(DampingProfile.fast)
                Text("標準").tag(DampingProfile.balanced)
                Text("平穩").tag(DampingProfile.smooth)
            }
            .pickerStyle(.segmented)

            // 補強段過渡入口（正式設定頁屬階段 5）：外觀主題
            // 四態（含樂池暗紅，存入持久化）＋ UI 音效回饋開關
            // （母本 state.soundsOn，存 tunerSettings）。
            HStack {
                Text("外觀")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Picker("外觀", selection: $store.themePreference) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.white)
            }

            Toggle(isOn: Binding(
                get: { store.tunerSettings.soundsOn },
                set: { newValue in
                    store.tunerSettings.soundsOn = newValue
                    // 母本行 12275：音效開關開啟當下即播 "success"
                    // 作回饋（ContentView 的 onChange 同步會隨後
                    // 跟上，此處先行啟用引擎以免被舊旗標擋下）。
                    if newValue {
                        UISoundEngine.shared.isEnabled = true
                        UISoundEngine.shared.play(.success)
                    }
                })) {
                Text("音效回饋")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .tint(Color(red: 0.039, green: 0.518, blue: 1.0))

            Text("中音薩克斯 · 檢測範圍 130–1200 Hz · 容差 ±\(String(format: "%.1f", engine.settings.toleranceCents))¢")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            if let metronomeEngine, let metronomeViewModel {
                MetronomeDebugSection(tunerEngine: engine,
                                      metronomeEngine: metronomeEngine,
                                      viewModel: metronomeViewModel)
            }

            HStack(spacing: 12) {
                Button(logCopied ? "已複製" : "複製診斷記錄") {
                    UIPasteboard.general.string = engine.exportDetectionLog()
                    logCopied = true
                }
                Button("清除記錄") {
                    engine.clearDetectionLog()
                    logCopied = false
                }
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// 節拍器診斷段（階段 3）：調度漂移統計（排程樣本時間計算）、
/// 震動總開關（母本 state.hapticsOn；正式設定頁屬階段 5，此處為
/// 過渡入口）、藍牙補償（母本設定項，0–300 ms 步進 10）。
private struct MetronomeDebugSection: View {
    @ObservedObject var tunerEngine: AudioEngine
    @ObservedObject var metronomeEngine: MetronomeEngine
    @ObservedObject var viewModel: MetronomeViewModel

    var body: some View {
        VStack(spacing: 10) {
            Divider().overlay(.white.opacity(0.25))

            Text(metronomeDiagnosticsText)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
                .multilineTextAlignment(.center)

            Toggle("震動回饋", isOn: $tunerEngine.settings.hapticsOn)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .tint(Color(red: 0.039, green: 0.518, blue: 1.0))

            HStack(spacing: 10) {
                Text("藍牙補償")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: bluetoothBinding, in: 0...300, step: 10)
                Text("\(viewModel.settings.bluetoothCompMs) ms")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(minWidth: 58)
            }

            Text(HapticsEngine.shared.supportsHaptics
                 ? "Core Haptics 可用"
                 : "Core Haptics 不可用（降級為系統震動）")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var bluetoothBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.bluetoothCompMs) },
            set: { viewModel.settings.bluetoothCompMs = Int($0.rounded()) }
        )
    }

    private var metronomeDiagnosticsText: String {
        let d = metronomeEngine.diagnostics
        let state = metronomeEngine.isPlaying ? "運行中" : "已停止"
        guard d.beatsScheduled > 0 else {
            return "節拍器 \(state) · 尚無排程拍"
        }
        return String(
            format: "節拍器 %@ · 已排程主拍 %d · 最近拍距 %.2f ms\n平均|偏差| %.3f ms · 最大 %.3f ms · 最小調度餘量 %.1f ms",
            state, d.beatsScheduled, d.lastIntervalMs,
            d.meanAbsDeviationMs, d.maxAbsDeviationMs, d.minHeadroomMs)
    }
}

#Preview {
    TunerDebugView(engine: AudioEngine(), store: AppStore())
}
