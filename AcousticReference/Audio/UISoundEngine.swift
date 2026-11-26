import AVFoundation
import Foundation

/// UI 音效引擎（補強段補債）：母本 uiSound（index.html 行 12212）
/// 的原生等價。母本以 WebAudio 即時合成六種短音（無音檔資產），
/// 原生版以相同參數離線預渲染為立體聲 PCM 緩衝、經專屬
/// AVAudioEngine 播放——參數逐項對照母本 tone()：
/// 正弦波；頻率起訖不同時指數滑音（全程 dur）；增益包絡 =
/// 0.0001 起、3 ms 線性升至 gain、其後指數衰減至 0.0001（於
/// at+dur）；聲像以等功率律近似母本 connectStereo 的 pan
/// （pan 值僅 ±0.25，差異低於可辨閾，註明為近似）。
///
/// 觸發紀律（母本註解 行 12206）：只由用戶手勢觸發，永不在
/// 調音檢測中或播放排程中自發鳴響；總開關 state.soundsOn
/// （TunerSettings.soundsOn）由 ContentView 同步至 isEnabled。
///
/// Session 紀律：協調器有任何使用者（調音／節拍器／Drone）
/// 時不碰 category（共用現行 session 播放）；無人使用時自設
/// .playback 並啟用，閒置 3 s 後停引擎並停用 session（僅在
/// 協調器仍無人時），不與三引擎的 session 會計打架。
@MainActor
final class UISoundEngine {
    static let shared = UISoundEngine()

    /// 母本 uiSound 的 kind 全集（行 12232–12252）。
    enum Kind: CaseIterable {
        case tick
        case `switch`
        case success
        case lock
        case close
        case warn
    }

    /// 總開關（母本 state.soundsOn）。ContentView 於啟動與
    /// store.tunerSettings 變更時同步。
    var isEnabled = true

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var bufferCache: [Double: [Kind: AVAudioPCMBuffer]] = [:]
    /// 本引擎是否自行啟用了 session（無人使用路徑）。
    private var ownsSession = false
    private var idleTask: Task<Void, Never>?

    private init() {}

    // MARK: - 播放

    func play(_ kind: Kind) {
        guard isEnabled else { return }
        idleTask?.cancel()
        guard ensureEngine() else { return }
        guard let player, let rate = currentSampleRate,
              let buffer = buffers(for: rate)[kind] else { return }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
        scheduleIdleTeardown()
    }

    private var currentSampleRate: Double? {
        player?.outputFormat(forBus: 0).sampleRate
    }

    private func buffers(for sampleRate: Double) -> [Kind: AVAudioPCMBuffer] {
        if let cached = bufferCache[sampleRate] { return cached }
        let rendered = Self.renderAll(sampleRate: sampleRate)
        bufferCache[sampleRate] = rendered
        return rendered
    }

    /// 建立（或重用）播放引擎；回傳 false 表示啟動失敗、本次不響。
    private func ensureEngine() -> Bool {
        if let engine, engine.isRunning { return true }
        let coordinatorBusy = AudioSessionCoordinator.shared.isActive(.tuner)
            || AudioSessionCoordinator.shared.isActive(.metronome)
            || AudioSessionCoordinator.shared.isActive(.drone)
        let session = AVAudioSession.sharedInstance()
        if !coordinatorBusy {
            do {
                if session.category != .playback {
                    try session.setCategory(.playback, mode: .default, options: [])
                }
                try session.setActive(true)
                ownsSession = true
            } catch {
                return false
            }
        }
        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()
        newEngine.attach(newPlayer)
        newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: nil)
        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            if ownsSession {
                ownsSession = false
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            return false
        }
        engine = newEngine
        player = newPlayer
        return true
    }

    /// 閒置 3 s 後拆引擎；若 session 是本引擎啟用的且協調器
    /// 仍無人使用，一併停用（交還系統）。
    private func scheduleIdleTeardown() {
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.player?.stop()
            self.engine?.stop()
            self.engine = nil
            self.player = nil
            if self.ownsSession {
                self.ownsSession = false
                let busy = AudioSessionCoordinator.shared.isActive(.tuner)
                    || AudioSessionCoordinator.shared.isActive(.metronome)
                    || AudioSessionCoordinator.shared.isActive(.drone)
                if !busy {
                    try? AVAudioSession.sharedInstance().setActive(
                        false, options: .notifyOthersOnDeactivation)
                }
            }
        }
    }

    // MARK: - 預渲染（母本 tone 參數逐項對照，行 12232–12252）

    /// 一記 tone：(起始 Hz, 結束 Hz, 起始偏移 s, 時長 s, 增益, pan)。
    private struct ToneSpec {
        var fStart: Double
        var fEnd: Double
        var at: Double
        var dur: Double
        var gain: Double
        var pan: Double
    }

    private static func specs(for kind: Kind) -> [ToneSpec] {
        switch kind {
        case .success:
            return [
                ToneSpec(fStart: 587.33, fEnd: 587.33, at: 0, dur: 0.11, gain: 0.045, pan: -0.2),
                ToneSpec(fStart: 880.0, fEnd: 880.0, at: 0.055, dur: 0.18, gain: 0.05, pan: 0.2),
            ]
        case .lock:
            return [
                ToneSpec(fStart: 659.25, fEnd: 659.25, at: 0, dur: 0.14, gain: 0.032, pan: -0.25),
                ToneSpec(fStart: 987.77, fEnd: 987.77, at: 0.035, dur: 0.20, gain: 0.030, pan: 0.25),
            ]
        case .switch:
            return [ToneSpec(fStart: 440.0, fEnd: 523.25, at: 0, dur: 0.038, gain: 0.032, pan: 0.1)]
        case .close:
            return [ToneSpec(fStart: 480.0, fEnd: 360.0, at: 0, dur: 0.042, gain: 0.028, pan: -0.1)]
        case .warn:
            return [ToneSpec(fStart: 330.0, fEnd: 293.66, at: 0, dur: 0.09, gain: 0.04, pan: 0)]
        case .tick:
            return [ToneSpec(fStart: 520.0, fEnd: 380.0, at: 0, dur: 0.018, gain: 0.026, pan: 0)]
        }
    }

    private static func renderAll(sampleRate: Double) -> [Kind: AVAudioPCMBuffer] {
        var result: [Kind: AVAudioPCMBuffer] = [:]
        for kind in Kind.allCases {
            if let buffer = render(kind: kind, sampleRate: sampleRate) {
                result[kind] = buffer
            }
        }
        return result
    }

    /// 母本 tone() 的取樣級重現：每 tone 的相位以瞬時頻率逐樣本
    /// 累積（指數滑音的精確積分近似）；增益包絡分三段——at 前 0、
    /// 3 ms 線性 attack（0.0001 → gain）、其後指數 decay
    /// （gain → 0.0001，於 at+dur 到達）。多 tone 直接相加
    /// （母本各 tone 獨立 gain node 後混音，線性等價）。
    /// 緩衝長 = 最晚 tone 的 at+dur + 0.015 尾（母本 stop 時刻）。
    private static func render(kind: Kind, sampleRate: Double) -> AVAudioPCMBuffer? {
        let tones = specs(for: kind)
        let totalDuration = (tones.map { $0.at + $0.dur }.max() ?? 0) + 0.015
        let frameCount = Int((totalDuration * sampleRate).rounded()) + 1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = channels[0]
        let right = channels[1]
        for tone in tones {
            // 等功率聲像（WebAudio StereoPanner 律）。
            let angle = (tone.pan + 1) * Double.pi / 4
            let leftGain = cos(angle)
            let rightGain = sin(angle)
            var phase = 0.0
            let startFrame = Int((tone.at * sampleRate).rounded())
            let endFrame = min(frameCount,
                               Int(((tone.at + tone.dur) * sampleRate).rounded()))
            guard endFrame > startFrame else { continue }
            for frame in startFrame..<endFrame {
                let t = Double(frame) / sampleRate - tone.at
                // 瞬時頻率：指數滑音 f(t) = f0 × (f1/f0)^(t/dur)。
                let freq: Double
                if tone.fEnd != tone.fStart, tone.dur > 0 {
                    freq = tone.fStart * pow(tone.fEnd / tone.fStart, t / tone.dur)
                } else {
                    freq = tone.fStart
                }
                phase += 2 * Double.pi * freq / sampleRate
                // 增益包絡（母本三段設定點的取樣重現）。
                let env: Double
                if t < 0.003 {
                    env = 0.0001 + (tone.gain - 0.0001) * (t / 0.003)
                } else if tone.dur > 0.003 {
                    let k = (t - 0.003) / (tone.dur - 0.003)
                    env = tone.gain * pow(0.0001 / tone.gain, k)
                } else {
                    env = tone.gain
                }
                let sample = Float(sin(phase) * env)
                left[frame] += sample * Float(leftGain)
                right[frame] += sample * Float(rightGain)
            }
        }
        return buffer
    }
}
