import AVFoundation
import Foundation
import os

/// Drone 音色（母本 DRONE_TIMBRES，行 10217；順序與母本陣列一致）。
enum DroneTimbre: String, Codable, CaseIterable, Sendable {
    case oboe
    case fork
    case organ
    case clarinet
    case sine
    case strings
    case brass

    /// zh-TW 顯示名（母本 zh-TW 渲染值）。
    var displayName: String {
        switch self {
        case .oboe: return "雙簧管"
        case .fork: return "標準音叉"
        case .organ: return "溫潤合奏"
        case .clarinet: return "單簧管"
        case .sine: return "純淨正弦"
        case .strings: return "大提琴"
        case .brass: return "銅管泛音"
        }
    }

    /// 合成參數（母本 startDroneGraph，行 9940–10217，逐值對照；
    /// 見 DroneSynthSpec 的欄位說明）。
    var spec: DroneSynthSpec {
        switch self {
        case .sine:
            return DroneSynthSpec(
                harmonics: [0, 1], lowpassRatio: 2.5, lowpassQ: 0.7071,
                bodyEQ: .lowShelf(freq: 280, gainDB: 2.0),
                chorusDetuneCents: 0, chorusGain: 0,
                vibratoRate: 0, vibratoDepth: 0, targetAmplitude: 0.30,
                hasTine: false)
        case .fork:
            return DroneSynthSpec(
                harmonics: [0, 1, 0.025], lowpassRatio: 3.2, lowpassQ: 0.7071,
                bodyEQ: .lowShelf(freq: 280, gainDB: 2.0),
                chorusDetuneCents: 0, chorusGain: 0,
                vibratoRate: 0, vibratoDepth: 0, targetAmplitude: 0.32,
                hasTine: true)
        case .clarinet:
            return DroneSynthSpec(
                harmonics: [0, 1, 0.06, 0.58, 0.05, 0.30, 0.03, 0.12, 0.02],
                lowpassRatio: 4.8, lowpassQ: 0.7071,
                bodyEQ: .peaking(freq: 680, q: 1.1, gainDB: 2.8),
                chorusDetuneCents: 2.8, chorusGain: 0.18,
                vibratoRate: 4.4, vibratoDepth: 0.0011, targetAmplitude: 0.26,
                hasTine: false)
        case .organ:
            return DroneSynthSpec(
                harmonics: [0, 1, 0.68, 0.36, 0.22, 0.11, 0.06, 0.025],
                lowpassRatio: 4.2, lowpassQ: 0.7071,
                bodyEQ: .lowShelf(freq: 280, gainDB: 2.0),
                chorusDetuneCents: 5.5, chorusGain: 0.34,
                vibratoRate: 4.4, vibratoDepth: 0.0011, targetAmplitude: 0.24,
                hasTine: false)
        case .strings:
            return DroneSynthSpec(
                harmonics: [0, 1, 0.72, 0.55, 0.48, 0.38, 0.22, 0.12, 0.06],
                lowpassRatio: 5.0, lowpassQ: 0.7071,
                bodyEQ: .peaking(freq: 300, q: 1.0, gainDB: 2.5),
                chorusDetuneCents: 4.5, chorusGain: 0.26,
                vibratoRate: 4.8, vibratoDepth: 0.0014, targetAmplitude: 0.24,
                hasTine: false)
        case .brass:
            return DroneSynthSpec(
                harmonics: [0, 1, 0.85, 0.78, 0.62, 0.55, 0.42, 0.30, 0.20, 0.12],
                lowpassRatio: 6.0, lowpassQ: 0.7071,
                bodyEQ: .peaking(freq: 900, q: 1.2, gainDB: 2.0),
                chorusDetuneCents: 0, chorusGain: 0,
                vibratoRate: 0, vibratoDepth: 0, targetAmplitude: 0.22,
                hasTine: false)
        case .oboe:
            return DroneSynthSpec(
                harmonics: [0, 0.78, 0.92, 0.85, 0.42, 0.22, 0.11, 0.05],
                lowpassRatio: 5.4, lowpassQ: 1.15,
                bodyEQ: .peaking(freq: 1120, q: 1.4, gainDB: 3.5),
                chorusDetuneCents: 2.8, chorusGain: 0.18,
                vibratoRate: 5.2, vibratoDepth: 0.0018, targetAmplitude: 0.26,
                hasTine: false)
        }
    }
}

/// 一種音色的合成參數（母本 startDroneGraph 內的常數表）。
struct DroneSynthSpec: Sendable {
    enum BodyEQ: Sendable {
        case peaking(freq: Double, q: Double, gainDB: Double)
        case lowShelf(freq: Double, gainDB: Double)
    }

    /// PeriodicWave 的 imag 陣列：索引 = 諧波次數（0 為 DC 恆 0）。
    var harmonics: [Double]
    /// 低通截止 = min(8000, freq × lowpassRatio)（母本原式）。
    var lowpassRatio: Double
    var lowpassQ: Double
    var bodyEQ: BodyEQ
    /// 合唱聲失諧（¢，雙聲 ∓）；0 = 無合唱聲。
    var chorusDetuneCents: Double
    var chorusGain: Double
    /// 顫音（僅中心聲）：速率 Hz、深度為 freq 的比例（母本 lfoGain = freq × 比例）。
    var vibratoRate: Double
    var vibratoDepth: Double
    /// 目標振幅（母本 gain.setTargetAtTime 的目標值）。
    var targetAmplitude: Double
    /// 音叉 tine 高頻敲擊聲（母本僅 fork）。
    var hasTine: Bool

    /// PeriodicWave 峰值歸一的等價係數（母本 disableNormalization=false）：
    /// 以 16384 點取樣一個週期求峰值，scale = 1/peak。
    var normalizationScale: Double {
        var peak = 0.0
        let steps = 16384
        for i in 0..<steps {
            let phase = Double(i) / Double(steps)
            var sum = 0.0
            for k in 1..<harmonics.count where harmonics[k] != 0 {
                sum += harmonics[k] * sin(2 * Double.pi * phase * Double(k))
            }
            peak = max(peak, abs(sum))
        }
        return peak > 0 ? 1.0 / peak : 1.0
    }
}

/// RBJ biquad 係數（已以 a0 歸一：y = b0x + b1x1 + b2x2 − a1y1 − a2y2）。
private struct BiquadCoefficients: Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    static func lowpass(freq: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        let w = 2 * Double.pi * freq / sampleRate
        let alpha = sin(w) / (2 * q)
        let cosw = cos(w)
        let a0 = 1 + alpha
        return BiquadCoefficients(
            b0: (1 - cosw) / 2 / a0, b1: (1 - cosw) / a0, b2: (1 - cosw) / 2 / a0,
            a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }

    static func peaking(freq: Double, q: Double, gainDB: Double, sampleRate: Double) -> BiquadCoefficients {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * freq / sampleRate
        let alpha = sin(w) / (2 * q)
        let cosw = cos(w)
        let a0 = 1 + alpha / a
        return BiquadCoefficients(
            b0: (1 + alpha * a) / a0, b1: -2 * cosw / a0, b2: (1 - alpha * a) / a0,
            a1: -2 * cosw / a0, a2: (1 - alpha / a) / a0)
    }

    /// 低架（母本 BiquadFilterNode lowshelf，斜率 S=1 的 Web Audio
    /// 公式以等效 alpha 近似；增益僅 +2 dB，差異不可聞）。
    static func lowShelf(freq: Double, gainDB: Double, sampleRate: Double) -> BiquadCoefficients {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * freq / sampleRate
        let alpha = sin(w) / (2 * 0.7071)
        let cosw = cos(w)
        let sq = 2 * sqrt(a) * alpha
        let a0 = (a + 1) + (a - 1) * cosw + sq
        return BiquadCoefficients(
            b0: a * ((a + 1) - (a - 1) * cosw + sq) / a0,
            b1: 2 * a * ((a - 1) - (a + 1) * cosw) / a0,
            b2: a * ((a + 1) - (a - 1) * cosw - sq) / a0,
            a1: -2 * ((a - 1) + (a + 1) * cosw) / a0,
            a2: ((a + 1) + (a - 1) * cosw - sq) / a0)
    }
}

private struct BiquadState {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func process(_ x: Double, _ c: BiquadCoefficients) -> Double {
        let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// 渲染核心：AVAudioSourceNode 的即時合成（諧波＋body EQ＋低通＋
/// 合唱雙聲＋顫音＋Haas room），逐項對照母本 Web Audio 圖。
/// 參數以 OSAllocatedUnfairLock 快照自 facade 傳入（跨線程只傳
/// Sendable 快照）；相位／濾波器狀態只在渲染線程存取（引擎啟動前
/// 由 facade 以 prime(frequency:) 設定初值，此時渲染線程未運行）。
private final class DroneRenderCore: @unchecked Sendable {
    struct Snapshot: Sendable {
        var frequency: Double = 440
        var harmonics: [Double] = [0, 1]
        var normScale: Double = 1
        var body: BiquadCoefficients = .lowpass(freq: 1000, q: 0.7071, sampleRate: 48000)
        var lowpass: BiquadCoefficients = .lowpass(freq: 1000, q: 0.7071, sampleRate: 48000)
        var roomL: BiquadCoefficients = .lowpass(freq: 2600, q: 0.7071, sampleRate: 48000)
        var roomR: BiquadCoefficients = .lowpass(freq: 2400, q: 0.7071, sampleRate: 48000)
        var chorusDetuneRatioL: Double = 1
        var chorusDetuneRatioR: Double = 1
        var chorusGain: Double = 0
        var vibratoRate: Double = 0
        var vibratoDepth: Double = 0
        var targetAmplitude: Double = 0.26
        /// 0 = 靜音目標；1 = 以 targetAmplitude 發聲（母本 gain 斜坡目標）。
        var gainTarget: Double = 0
        var gainTau: Double = 0.045
        /// 頻率滑音時間常數（母本 setTargetAtTime τ：一般 0.045、滑奏 0.09）。
        var glideTau: Double = 0.045
        var tineFrequency: Double = 0
        var tineTrigger: Int = 0
    }

    let state = OSAllocatedUnfairLock(initialState: Snapshot())
    private(set) var sampleRate: Double = 48000

    // 渲染線程狀態。
    private var phase = 0.0
    private var phaseChorusL = 0.0
    private var phaseChorusR = 0.0
    private var lfoPhase = 0.0
    private var currentFreq = 440.0
    private var currentGain = 0.0
    private var bodyState = BiquadState()
    private var lpStateL = BiquadState()
    private var lpStateR = BiquadState()
    private var roomStateL = BiquadState()
    private var roomStateR = BiquadState()
    private var delayL: [Double] = []
    private var delayR: [Double] = []
    private var delayIndex = 0
    private var lastTineTrigger = 0
    private var tinePhase = 0.0
    private var tineTime = 1.0

    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        let cap = Int(sampleRate * 0.05) + 2
        delayL = [Double](repeating: 0, count: cap)
        delayR = [Double](repeating: 0, count: cap)
        delayIndex = 0
    }

    /// 引擎啟動前設定初始頻率（母本 osc 起始即目標頻率，無滑音）。
    func prime(frequency: Double) {
        currentFreq = frequency
        currentGain = 0
        phase = 0; phaseChorusL = 0; phaseChorusR = 0; lfoPhase = 0
        bodyState = BiquadState(); lpStateL = BiquadState(); lpStateR = BiquadState()
        roomStateL = BiquadState(); roomStateR = BiquadState()
        lastTineTrigger = 0; tineTime = 1
    }

    private static func panGains(_ pan: Double) -> (l: Double, r: Double) {
        let angle = (pan + 1) * Double.pi / 4
        return (cos(angle), sin(angle))
    }

    private func wave(phase: Double, snap: Snapshot) -> Double {
        var sum = 0.0
        for k in 1..<snap.harmonics.count where snap.harmonics[k] != 0 {
            sum += snap.harmonics[k] * sin(2 * Double.pi * phase * Double(k))
        }
        return sum * snap.normScale
    }

    func render(isSilence: UnsafeMutablePointer<ObjCBool>,
                frameCount: AVAudioFrameCount,
                audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let snap = state.withLock { $0 }
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard abl.count >= 2,
              let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
              let outR = abl[1].mData?.assumingMemoryBound(to: Float.self)
        else {
            isSilence.pointee = true
            return noErr
        }
        let sr = sampleRate
        let frames = Int(frameCount)
        let freqAlpha = 1 - exp(-1 / (sr * snap.glideTau))
        let gainAlpha = 1 - exp(-1 / (sr * snap.gainTau))
        let delaySamplesL = min(delayL.count - 1, Int((0.011 * sr).rounded()))
        let delaySamplesR = min(delayR.count - 1, Int((0.016 * sr).rounded()))
        let chorusPanL = Self.panGains(-0.55)
        let chorusPanR = Self.panGains(0.55)
        let tinePan = Self.panGains(0.15)
        if snap.tineTrigger != lastTineTrigger {
            lastTineTrigger = snap.tineTrigger
            tinePhase = 0
            tineTime = 0
        }

        for frame in 0..<frames {
            // 頻率／增益一階平滑（母本 setTargetAtTime 的指數趨近）。
            currentFreq += (snap.frequency - currentFreq) * freqAlpha
            let gainGoal = snap.gainTarget * snap.targetAmplitude
            currentGain += (gainGoal - currentGain) * gainAlpha

            lfoPhase += snap.vibratoRate / sr
            if lfoPhase >= 1 { lfoPhase -= 1 }
            let vib = 1 + snap.vibratoDepth * sin(2 * Double.pi * lfoPhase)

            phase += currentFreq * vib / sr
            if phase >= 1 { phase -= floor(phase) }
            phaseChorusL += currentFreq * snap.chorusDetuneRatioL / sr
            if phaseChorusL >= 1 { phaseChorusL -= floor(phaseChorusL) }
            phaseChorusR += currentFreq * snap.chorusDetuneRatioR / sr
            if phaseChorusR >= 1 { phaseChorusR -= floor(phaseChorusR) }

            let main = bodyState.process(wave(phase: phase, snap: snap), snap.body)
            var inL = main * 0.70710678
            var inR = main * 0.70710678
            if snap.chorusGain > 0 {
                let chL = wave(phase: phaseChorusL, snap: snap) * snap.chorusGain
                let chR = wave(phase: phaseChorusR, snap: snap) * snap.chorusGain
                inL += chL * chorusPanL.l + chR * chorusPanR.l
                inR += chL * chorusPanL.r + chR * chorusPanR.r
            }
            var dryL = lpStateL.process(inL, snap.lowpass) * currentGain
            var dryR = lpStateR.process(inR, snap.lowpass) * currentGain

            // 音叉 tine：觸發後 0.42 s 指數衰減的高頻敲擊（母本原式近似：
            // 0.08 → 0.0001 的 exponentialRamp，速率 ln(800)/0.42）。
            if tineTime < 0.5, snap.tineFrequency > 0 {
                tinePhase += snap.tineFrequency / sr
                if tinePhase >= 1 { tinePhase -= floor(tinePhase) }
                let env = 0.08 * exp(-15.92 * tineTime)
                let tine = sin(2 * Double.pi * tinePhase) * env
                dryL += tine * tinePan.l
                dryR += tine * tinePan.r
                tineTime += 1 / sr
            }

            // Haas room：延遲 11/16 ms → 低通 2600/2400 → wet 0.14。
            delayL[delayIndex] = dryL
            delayR[delayIndex] = dryR
            let cap = delayL.count
            let readL = delayL[(delayIndex - delaySamplesL + cap) % cap]
            let readR = delayR[(delayIndex - delaySamplesR + cap) % cap]
            delayIndex = (delayIndex + 1) % cap
            let wetL = roomStateL.process(readL, snap.roomL) * 0.14
            let wetR = roomStateR.process(readR, snap.roomR) * 0.14

            outL[frame] = Float(dryL + wetL)
            outR[frame] = Float(dryR + wetR)
        }
        isSilence.pointee = false
        return noErr
    }
}

/// 通知觀察者代幣保管袋（同 AudioEngine 的 SessionObserverBag 模式：
/// facade 的 deinit 為 nonisolated，不直接持有代幣）。
private final class DroneObserverBag {
    private var tokens: [NSObjectProtocol] = []
    func add(_ token: NSObjectProtocol) { tokens.append(token) }
    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Drone 引擎 facade（主線程）：AVAudioEngine 生命週期、session
/// 共存（經 AudioSessionCoordinator 登記 .drone，與調音／節拍器
/// 同規則：最後一個使用者退出才停用 session）、參數快照組裝。
///
/// 與母本的實現差異（行為等價）：母本換音色／停止是 Web Audio
/// 整圖重建；原生版以同一渲染核心做增益交叉淡化（停 0.025 τ
/// 淡出後拆引擎；換音色先淡出 0.14 s 再換參數淡入），聽感等價。
/// 頻率／A4／律制變更走 updateDroneFrequency 等價路徑（僅改目標
/// 頻率，濾波器維持建圖時參數——母本同）。
@MainActor
final class DroneEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var targetMidi: Int = 69
    @Published private(set) var lastError: String?

    private(set) var timbre: DroneTimbre = .oboe

    // 發聲上下文（由 ContentView 自 store 同步；預設對照母本初始值）。
    private var a4: Double = 442
    private var temperament: Temperament = .equal
    private var justTonicPc: Int = 0

    private let core = DroneRenderCore()
    private var avEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var sessionAcquired = false
    private var generation = 0
    private let observerBag = DroneObserverBag()
    private var observersRegistered = false

    /// 母本 droneTargetFreq（行 9994）：midiToFreq（現行 A4）×
    /// 2^(純律偏移/1200)。
    private func targetFrequency(midi: Int) -> Double {
        PitchMath.frequency(midi: Double(midi), a4: a4)
            * pow(2, PitchMath.temperamentOffsetCents(
                targetMidi: midi, temperament: temperament,
                justTonicPc: justTonicPc) / 1200)
    }

    // MARK: - 上下文同步

    /// A4／律制／純律主音變更（母本 updateA4UI 與律制切換呼叫點）：
    /// 播放中即改頻（τ 0.045）。
    func updateContext(a4: Double, temperament: Temperament, justTonicPc: Int) {
        self.a4 = a4
        self.temperament = temperament
        self.justTonicPc = justTonicPc
        if isPlaying {
            applyFrequency(glide: false)
        }
    }

    // MARK: - 啟停

    func start(targetMidi: Int, timbre: DroneTimbre) {
        self.targetMidi = targetMidi
        self.timbre = timbre
        guard !isPlaying else {
            retarget(midi: targetMidi, glide: false)
            return
        }
        lastError = nil
        generation += 1
        // stop() 的延遲拆卸尚在途時，先同步拆掉舊引擎，避免兩個
        // 引擎同時渲染同一核心。
        if avEngine != nil {
            teardownEngine()
        }

        let session = AVAudioSession.sharedInstance()
        if !sessionAcquired {
            AudioSessionCoordinator.shared.acquire(.drone)
            sessionAcquired = true
        }
        do {
            // 動態 Mode（補強段）：與 MetronomeEngine 同——category
            // /mode 由協調器依使用者組成統一裁決（調音在場走錄音
            // 型、僅播放走播放型恢復外放電平），此處不自設。
            AudioSessionCoordinator.shared.applyProfile()
            try session.setActive(true)
        } catch {
            lastError = "音訊工作階段啟動失敗：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }

        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48000
        core.configure(sampleRate: sampleRate)
        let freq = targetFrequency(midi: targetMidi)
        core.prime(frequency: freq)
        let tineTrigger = core.state.withLock { $0.tineTrigger } + 1
        let snapshot = makeSnapshot(timbre: timbre, frequency: freq,
                                    sampleRate: sampleRate, tineTrigger: tineTrigger)
        core.state.withLock { $0 = snapshot }

        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 2)
        else {
            lastError = "音訊格式建立失敗"
            releaseSessionIfUnused()
            return
        }
        let coreRef = core
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            coreRef.render(isSilence: isSilence, frameCount: frameCount,
                           audioBufferList: audioBufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            lastError = "Drone 引擎啟動失敗：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }
        avEngine = engine
        sourceNode = node
        isPlaying = true
        registerObservers()
        HapticsEngine.shared.warmUp()
    }

    /// 停止（母本 stopDrone）：增益 0.08 s 級淡出後拆引擎。
    func stop() {
        guard isPlaying else { return }
        generation += 1
        let gen = generation
        core.state.withLock {
            $0.gainTarget = 0
            $0.gainTau = 0.025
        }
        isPlaying = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, self.generation == gen else { return }
            self.teardownEngine()
        }
    }

    private func teardownEngine() {
        avEngine?.stop()
        avEngine = nil
        sourceNode = nil
        releaseSessionIfUnused()
    }

    private func releaseSessionIfUnused() {
        guard sessionAcquired else { return }
        sessionAcquired = false
        if AudioSessionCoordinator.shared.release(.drone) {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation])
        } else {
            // 組成改變可能觸發型態切換，交協調器裁決。
            AudioSessionCoordinator.shared.applyProfile()
        }
    }

    // MARK: - 播放中調整

    /// 目標音變更（母本 updateDroneFrequency）：只改目標頻率與
    /// 滑音常數；濾波器維持建圖參數（母本同）。
    func retarget(midi: Int, glide: Bool) {
        targetMidi = midi
        guard isPlaying else { return }
        applyFrequency(glide: glide)
    }

    private func applyFrequency(glide: Bool) {
        let freq = targetFrequency(midi: targetMidi)
        core.state.withLock {
            $0.frequency = freq
            $0.glideTau = glide ? 0.09 : 0.045
        }
    }

    /// 音色變更（母本 changeDroneTimbre → 整圖重建）：播放中先
    /// 淡出、換參數快照、再淡入（含 tine 重新觸發）；未播放只記值。
    func setTimbre(_ newTimbre: DroneTimbre) {
        timbre = newTimbre
        guard isPlaying else { return }
        generation += 1
        let gen = generation
        core.state.withLock {
            $0.gainTarget = 0
            $0.gainTau = 0.03
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, self.generation == gen, self.isPlaying else { return }
            let sampleRate = self.core.sampleRate
            let freq = self.targetFrequency(midi: self.targetMidi)
            let tineTrigger = self.core.state.withLock { $0.tineTrigger } + 1
            let snapshot = self.makeSnapshot(
                timbre: newTimbre, frequency: freq,
                sampleRate: sampleRate, tineTrigger: tineTrigger)
            self.core.state.withLock { $0 = snapshot }
        }
    }

    // MARK: - 快照組裝

    private func makeSnapshot(timbre: DroneTimbre, frequency: Double,
                              sampleRate: Double,
                              tineTrigger: Int) -> DroneRenderCore.Snapshot {
        let spec = timbre.spec
        var snap = DroneRenderCore.Snapshot()
        snap.frequency = frequency
        snap.harmonics = spec.harmonics
        snap.normScale = spec.normalizationScale
        switch spec.bodyEQ {
        case .peaking(let freq, let q, let gainDB):
            snap.body = .peaking(freq: freq, q: q, gainDB: gainDB, sampleRate: sampleRate)
        case .lowShelf(let freq, let gainDB):
            snap.body = .lowShelf(freq: freq, gainDB: gainDB, sampleRate: sampleRate)
        }
        snap.lowpass = .lowpass(
            freq: min(8000, frequency * spec.lowpassRatio),
            q: spec.lowpassQ, sampleRate: sampleRate)
        snap.roomL = .lowpass(freq: 2600, q: 0.7071, sampleRate: sampleRate)
        snap.roomR = .lowpass(freq: 2400, q: 0.7071, sampleRate: sampleRate)
        snap.chorusDetuneRatioL = pow(2, -spec.chorusDetuneCents / 1200)
        snap.chorusDetuneRatioR = pow(2, spec.chorusDetuneCents / 1200)
        snap.chorusGain = spec.chorusGain
        snap.vibratoRate = spec.vibratoRate
        snap.vibratoDepth = spec.vibratoDepth
        snap.targetAmplitude = spec.targetAmplitude
        snap.gainTarget = 1
        snap.gainTau = 0.045
        snap.glideTau = 0.045
        snap.tineFrequency = spec.hasTine ? min(10000, frequency * 6.27) : 0
        snap.tineTrigger = tineTrigger
        return snap
    }

    // MARK: - 中斷處理（比照 AudioEngine：中斷即停、媒體服務重置即停）

    private func registerObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observerBag.add(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: nil
        ) { [weak self] note in
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began
            else { return }
            Task { @MainActor in
                self?.stop()
            }
        })
        observerBag.add(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.generation += 1
                self.isPlaying = false
                self.teardownEngine()
            }
        })
    }
}
