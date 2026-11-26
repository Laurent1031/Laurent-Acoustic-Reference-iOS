import Foundation

/// 平滑後的一幀讀數，供 UI 與診斷記錄使用。
struct PitchReading: Sendable {
    /// 是否有有效音高（母本 rawFreq > 0 分支）。
    var hasPitch: Bool
    /// 原始檢測頻率（未平滑），無效時為 nil。
    var rawFrequency: Double?
    /// 平滑後頻率（母本 state.smoothedFreq），顯示 0.1 Hz 精度。
    var smoothedFrequency: Double
    /// 目標音 MIDI（母本 targetConcertMidi，實音）。
    var targetMidi: Int?
    /// 音名（含八度，如 "E♭4"），依母本 NOTE_NAMES 拼法。
    var noteName: String?
    /// 平滑後音分偏差（母本 state.smoothedCents，spring 輸出），顯示 0.1¢ 精度。
    var cents: Double
    /// 針尾跡兩層跟隨值（母本 trail1C／trail2C，行 9501），階段 2 錶盤用。
    var trail1Cents: Double
    var trail2Cents: Double
    /// |smoothedCents| ≤ 容差（母本 isInTune，行 9648）。
    var isInTune: Bool
    /// 本幀檢測清晰度（NSDF globalMax），診斷用。
    var clarity: Double
    /// 本幀置中 RMS，診斷用。
    var rms: Double
    /// 本幀置中訊號峰值（線性 0–1；補強段削波警示用，與音高
    /// 有效性無關——無有效音高的過載幀同樣攜帶）。預設 0。
    var peak: Double = 0
    /// 頻閃顯示狀態（頻閃主模式段）：由 EngineCore 在 smoother
    /// 之後以 StrobePhaseTracker 填入；smoother 本身不寫此欄，
    /// 預設為無訊號（相位 0、角速度 0、可信度 0）。
    var strobe: StrobeState = StrobeState()
}

/// 中位數＋阻尼平滑狀態機，逐項對照母本 pitchLoop（行 9577–9600）與
/// stepCentsSpring（行 9487）。
///
/// 行為要點：
/// - 距上次有效音高 > 280 ms → 清空頻率歷史；
/// - 歷史 push 原始頻率、裁至阻尼檔 win；中位數取排序後 floor(len/2)
///   （偶數取上中位，母本原式）；
/// - smoothedFreq 為 0 或 |中位數 − smoothed| / smoothed > 0.04 → 直接 snap，
///   否則 EMA（freqAlpha）；
/// - 音分 = clamp((exactMidi − target)·100 − 純律偏移, −50, +50)，
///   再經臨界阻尼 spring（response 依阻尼檔）輸出為顯示音分；
/// - 無有效音高時 spring 目標回 0、response 固定 0.26（母本行 9730）；
/// - 母本 centsAlpha 在音高路徑未被使用，音分不走 EMA（見 TunerSettings）。
///
/// 與母本的節律差異（有意、已記錄）：母本在 rAF（≈60 Hz）逐幀 push
/// （worklet 結果會被重複 push），原生版在每個分析 hop（512 樣本 ≈ 93.75 Hz
/// @48k）push 一次新結果。spring 以真實 dt 積分，牆鐘響應一致；中位數窗
/// 覆蓋的時間跨度略短（5 hop ≈ 53 ms vs 母本 5 幀 ≈ 83 ms）。
struct PitchSmoother {
    var settings: TunerSettings

    private var frequencyHistory: [Double] = []
    private var smoothedFrequency: Double = 0
    private var smoothedCents: Double = 0
    private var centsVelocity: Double = 0
    private var trail1C: Double = 0
    private var trail1V: Double = 0
    private var trail2C: Double = 0
    private var trail2V: Double = 0
    private var lastValidTime: TimeInterval = -.infinity
    private var lastStepTime: TimeInterval?

    init(settings: TunerSettings) {
        self.settings = settings
    }

    /// 處理一幀檢測結果。
    /// - Parameters:
    ///   - detection: PitchDetector 的輸出（frequency 為 nil 表示回絕／無聲）。
    ///   - now: 單調時鐘秒數（母本 performance.now() / 1000）。
    ///   - lockedTargetMidi: 鎖定目標音（母本 state.lockedTargetNote）；
    ///     階段 1 恆為 nil（自動取最近音），階段 2/3 接入。
    mutating func process(
        detection: PitchDetection,
        now: TimeInterval,
        lockedTargetMidi: Int? = nil
    ) -> PitchReading {
        guard let rawFreq = detection.frequency, rawFreq > 0 else {
            // 無有效音高：spring 回 0（母本行 9730，response 0.26）。
            stepSpring(target: 0, response: 0.26, now: now)
            return PitchReading(
                hasPitch: false,
                rawFrequency: nil,
                smoothedFrequency: smoothedFrequency,
                targetMidi: nil,
                noteName: nil,
                cents: smoothedCents,
                trail1Cents: trail1C,
                trail2Cents: trail2C,
                isInTune: false,
                clarity: detection.clarity,
                rms: detection.rms,
                peak: detection.peak
            )
        }

        // 中位數平滑（母本行 9584–9595）。
        if now - lastValidTime > 0.280 {
            frequencyHistory.removeAll()
        }
        lastValidTime = now
        frequencyHistory.append(rawFreq)
        let win = settings.damping.medianWindow
        while frequencyHistory.count > win {
            frequencyHistory.removeFirst()
        }
        let sorted = frequencyHistory.sorted()
        let median = sorted[sorted.count / 2] // floor(len/2)，母本原式

        // 頻率 EMA / snap（母本行 9593–9597）。
        if smoothedFrequency == 0
            || abs(median - smoothedFrequency) / smoothedFrequency > 0.04 {
            smoothedFrequency = median
        } else {
            let alpha = settings.damping.frequencyAlpha
            smoothedFrequency = smoothedFrequency * (1 - alpha) + median * alpha
        }

        // 音分（母本行 9598–9600）＋spring（行 9487）。
        let exactMidi = PitchMath.exactMidi(frequency: smoothedFrequency, a4: settings.a4)
        // JS Math.round 為 half-up；MIDI 值恆正，與 Swift .rounded()
        // （half away from zero）在此等價。
        let targetMidi = lockedTargetMidi ?? Int(exactMidi.rounded())
        let cents = PitchMath.cents(
            exactMidi: exactMidi,
            targetMidi: targetMidi,
            temperament: settings.temperament,
            justTonicPc: settings.justTonicPc
        )
        stepSpring(target: cents, response: settings.damping.springResponse, now: now)

        return PitchReading(
            hasPitch: true,
            rawFrequency: rawFreq,
            smoothedFrequency: smoothedFrequency,
            targetMidi: targetMidi,
            noteName: PitchMath.noteName(midi: targetMidi),
            cents: smoothedCents,
            trail1Cents: trail1C,
            trail2Cents: trail2C,
            isInTune: abs(smoothedCents) <= settings.toleranceCents,
            clarity: detection.clarity,
            rms: detection.rms,
            peak: detection.peak
        )
    }

    /// 臨界阻尼 spring（母本 stepCentsSpring，行 9487–9513）：
    /// omega = 2π / max(0.08, response)；dt 鉗 [0.001, 0.05]（首幀 0.016）；
    /// 2 個子步半隱式 Euler；其後兩層針尾跡以同一 dt 單步跟隨。
    private mutating func stepSpring(target: Double, response: Double, now: TimeInterval) {
        let dt: Double
        if let last = lastStepTime {
            dt = min(0.05, max(0.001, now - last))
        } else {
            dt = 0.016
        }
        lastStepTime = now

        let omega = (2 * Double.pi) / max(0.08, response)
        let h = dt / 2
        for _ in 0..<2 {
            let accel = omega * omega * (target - smoothedCents) - 2 * omega * centsVelocity
            centsVelocity += accel * h
            smoothedCents += centsVelocity * h
        }

        // 針尾跡（母本行 9501–9506，常數原樣）。
        let a1 = (smoothedCents - trail1C) * 110 - trail1V * 15
        trail1V += a1 * dt
        trail1C += trail1V * dt
        let a2 = (smoothedCents - trail2C) * 55 - trail2V * 11
        trail2V += a2 * dt
        trail2C += trail2V * dt
    }
}
