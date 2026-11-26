import SwiftUI
import UIKit

/// 階段 1 最小驗證介面：文字顯示頻率／音名／音分＋診斷值＋引擎控制。
/// 階段 2 起降為診斷頁：由主畫面頂欄以 sheet 喚出，與主畫面共用
/// 同一個 AudioEngine 實例（外部注入），本視圖不再自建引擎。
struct TunerDebugView: View {
    @ObservedObject var engine: AudioEngine
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

            Text("中音薩克斯 · 檢測範圍 130–1200 Hz · 容差 ±\(String(format: "%.1f", engine.settings.toleranceCents))¢")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

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

#Preview {
    TunerDebugView(engine: AudioEngine())
}
