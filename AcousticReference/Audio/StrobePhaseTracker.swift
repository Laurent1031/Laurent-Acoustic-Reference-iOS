import Accelerate
import Foundation

/// 頻閃顯示的一幀狀態（由 StrobePhaseTracker 在分析佇列產生，
/// 經 PitchReading.strobe 攜帶至 UI）。
struct StrobeState: Sendable {
    /// 圖案旋轉相位（弧度，[0, 2π)）：在 `time` 時刻的值。
    /// UI 以 angularRate 自此錨點外推至顯示時刻（120 Hz 內插）。
    var phase: Double = 0
    /// 圖案角速度（弧度／秒）：正值＝圖案順時針轉（偏高），
    /// 負值＝逆時針（偏低），0¢ 時恆為 0（圖案靜止）。
    var angularRate: Double = 0
    /// 可信度 0…1：由 MPM 清晰度與解調相干性合成，驅動環的
    /// 不透明度；無訊號時衰減至 0（圖案凍結並淡化）。
    var confidence: Double = 0
    /// 本幀是否有有效音高（凍結判定供 UI 決定 TimelineView 暫停）。
    var hasSignal: Bool = false
    /// 本幀分析時刻（systemUptime 秒），UI 換算外推錨點用。
    var time: TimeInterval = 0
}

/// 基頻相位追蹤層：在既有 MPM 檢測流之上量測基頻瞬時相位，
/// 產出頻閃圖案的旋轉相位與角速度。不改動 PitchDetector／
/// PitchSmoother 的任何既有行為（僅讀取其輸出與同一分析窗）。
///
/// 方法（heterodyne 解調＋相位差分）：
/// 1. 對分析窗去 DC 後，以 MPM 量到的原始頻率 f 為解調頻率，
///    乘 Hann 窗做複數相關 Z = Σ w[n]·x[n]·e^(−i2πf·n/sr)。
///    Hann 對稱 ⇒ arg Z = 窗中心相位 − 2πf·(N−1)/(2·sr)，
///    其中偏移項只依賴解調頻率 f 本身；以同一個 f 做解析校正
///    （加回偏移）即得窗中心相位——校正與量測同源，f 的幀間
///    抖動在差分中精確抵消（數值模擬驗證：未校正時抖動經
///    (N−1)/2 放大成 0.08 rad/幀的增量噪聲，校正後降至
///    0.0001 rad 級）。解調取量測頻率使 |Z| 恆最大（偏離
///    目標 ±50¢ 也不進 Hann 旁瓣）；|Z| 歸一化得相干性
///    （純音 = 1）作可信度分量。
/// 2. 相鄰幀相位差 advSig = wrapPi(φ_k − φ_{k−1}) 是訊號在一個
///    hop 內的實際相位推進；目標推進 advTgt 由校正後目標頻率
///    f_t（見下）給出。圖案增量 incr = wrapPi(advSig − advTgt)，
///    再以量測期望 2π(f − f_t)·hop/sr 解纏繞（選最接近期望的
///    2π 整數倍），殘差 > 1 rad 時改信期望值（瞬態兜底）。
///    patternPhase 只累加增量、永不跳變。
/// 3. 目標頻率 f_t 與錶盤音分判準同源：PitchMath.frequency
///    (targetMidi, A4) × 2^(temperamentOffsetCents/1200)——即
///    PitchMath.cents 為 0 的發聲音高；純律主音切換、A4 步進、
///    鎖定目標（#12 跟隨含）全部經 targetMidi／settings 流入，
///    與指針模式的 cents 判準逐幀一致。
///
/// 方向約定：f > f_t（偏高）⇒ incr > 0 ⇒ patternPhase 遞增；
/// 顯示端以 +phase 旋轉（SwiftUI y 向下坐標系中正角為視覺
/// 順時針），故偏高順時針、偏低逆時針（StrobeView.rotationSign
/// 為唯一符號開關，裝機驗證後如需翻轉只改該常數）。
///
/// 轉速映射：角速度 = 2π·(f − f_t)（弧度／秒），即圖案轉速
/// （轉／秒）恰等於絕對頻率差 Δf——物理頻閃盤的本性（低音
/// 轉得慢、高音快），不做音分歸一化。參考值（Δf＝f_t·(2^(c/1200)−1)）：
///   A1 55 Hz：  1¢→0.032 轉/s、10¢→0.32、50¢→1.60
///   A2 110 Hz： 1¢→0.064、10¢→0.64、50¢→3.21
///   A4 442 Hz： 1¢→0.256、10¢→2.56、50¢→12.9
/// 0¢ 嚴格靜止；±1¢ 在中高音區慢到可辨（低音區更慢，屬物理
/// 頻閃的固有行為）；±50¢ 明顯流動。映射為相位差的直接結果，
/// 連續無跳變、無死區。
///
/// 守衛（任一成立 → 本幀只重錨、不累加增量，圖案不亂轉）：
/// - 尚無錨點（起音首幀／靜音逾 280 ms 後重入，與 PitchSmoother
///   的歷史清空門檻同值）；
/// - 目標鍵變更（targetMidi／A4／律制／純律主音任一變）；
/// - 頻率跳變 > 4%（八度誤判幀、換音瞬態；與 PitchSmoother
///   的 snap 門檻同值）。
/// 無有效音高時：相位凍結、角速度衰減、可信度衰減。
///
/// 線程紀律：僅在 EngineCore 的串行分析佇列上存取（與
/// PitchDetector 同），非線程安全。解調迴圈零分配：置中
/// 緩衝與 Hann 係數皆預分配／按窗長快取。
final class StrobePhaseTracker {

    /// 相干性歸一化常數：純音時 |Z| / Σw|x| = π/4，故乘 4/π 得 1。
    private static let coherenceScale = 4.0 / Double.pi
    /// 靜音後錨點失效門檻（秒），與 PitchSmoother 的 280 ms 一致。
    private static let anchorTimeout: TimeInterval = 0.280
    /// 頻率跳變守衛（相對值），與 PitchSmoother 的 snap 門檻一致。
    private static let freqJumpGuard = 0.04
    /// 解纏繞殘差上限（弧度）：超過則改信量測期望增量。
    private static let unwrapResidualLimit = 1.0

    // MARK: - 預分配緩衝

    private var centered = [Float](repeating: 0, count: 16384)
    private var hannCache: [Int: [Float]] = [:]

    // MARK: - 追蹤狀態

    private var patternPhase: Double = 0
    private var angularRate: Double = 0
    private var confidence: Double = 0
    private var anchorValid = false
    private var prevPhi: Double = 0
    private var prevFreq: Double = 0
    private var prevTargetMidi: Int = .min
    private var prevA4: Double = 0
    private var prevTemperament: Temperament = .equal
    private var prevJustTonicPc: Int = -1
    private var prevTime: TimeInterval = 0
    private var lastValidTime: TimeInterval = -.infinity

    /// 處理一幀。
    /// - Parameters:
    ///   - window: 與檢測器同一分析窗（原始樣本，未置中）。
    ///   - hopSamples: 本窗與上窗之間的實際新樣本數（EngineCore
    ///     ingest 實測；標稱 512，分析佇列掉幀時更大）。
    ///   - detection: 本幀 MPM 檢測結果（frequency 為原始頻率）。
    ///   - targetMidi: 本幀判準目標音（PitchSmoother 已計入鎖定
    ///     目標／自動最近音）；無有效音高時為 nil。
    ///   - settings: 本幀設定快照（A4／律制／純律主音取目標校正）。
    func process(
        window: [Float],
        hopSamples: Int,
        detection: PitchDetection,
        targetMidi: Int?,
        settings: TunerSettings,
        sampleRate: Double,
        now: TimeInterval
    ) -> StrobeState {
        guard let freq = detection.frequency, freq > 0, let targetMidi else {
            // 無有效音高：相位凍結，角速度與可信度衰減；
            // 逾 280 ms 錨點失效（下次起音重錨，不亂轉）。
            confidence *= 0.85
            if confidence < 0.02 { confidence = 0 }
            angularRate *= 0.6
            if now - lastValidTime > Self.anchorTimeout {
                anchorValid = false
                angularRate = 0
            }
            return snapshot(now: now, hasSignal: false)
        }
        lastValidTime = now

        // 【全邏輯複查・低】取樣率守衛：demodulate 內部有
        // 守衛，但其後的 advTgt/expected 直接除以
        // sampleRate——為 0 時 NaN 寫入 patternPhase 且永
        // 久不自愈。現行由 facade 守衛格式速率 >0 而不可
        // 達，此為核心自身防禦縱深：無速率即按無訊號回。
        guard sampleRate > 0 else {
            return snapshot(now: now, hasSignal: false)
        }

        // 校正後目標頻率（與錶盤 cents 判準同源，見類註解 3）。
        let offset = PitchMath.temperamentOffsetCents(
            targetMidi: targetMidi,
            temperament: settings.temperament,
            justTonicPc: settings.justTonicPc)
        let targetFreq = PitchMath.frequency(midi: Double(targetMidi), a4: settings.a4)
            * pow(2.0, offset / 1200.0)

        let (phi, coherence) = demodulate(
            window: window, frequency: freq, sampleRate: sampleRate)

        // 可信度：清晰度映射（0.58 門檻起、0.95 滿）× 相干性；
        // EMA 快攻（0.5）慢放（0.15）。
        let clarityMapped = min(1, max(0,
            (detection.clarity - PitchDetector.clarityThreshold) / 0.37))
        let confInst = clarityMapped * coherence
        let alpha = confInst > confidence ? 0.5 : 0.15
        confidence += (confInst - confidence) * alpha

        let keyChanged = !anchorValid
            || targetMidi != prevTargetMidi
            || settings.a4 != prevA4
            || settings.temperament != prevTemperament
            || settings.justTonicPc != prevJustTonicPc
        let freqJump = anchorValid && prevFreq > 0
            && abs(freq - prevFreq) / prevFreq > Self.freqJumpGuard
        let gapTooLong = anchorValid && (now - prevTime) > Self.anchorTimeout

        if keyChanged || freqJump || gapTooLong {
            // 重錨：只更新錨點，圖案相位不動、角速度減半衰減，
            // 後續 2–3 幀由增量自然帶回正確轉速。
            angularRate *= 0.5
        } else {
            let hop = Double(max(1, hopSamples))
            let advSig = Self.wrapPi(phi - prevPhi)
            let advTgt = Self.wrapPi(
                2 * Double.pi * targetFreq * hop / sampleRate)
            var incr = Self.wrapPi(advSig - advTgt)
            let expected = 2 * Double.pi * (freq - targetFreq) * hop / sampleRate
            // 解纏繞：把 incr 平移 2π 整數倍至最接近量測期望；
            // 殘差過大（瞬態相位不可信）→ 改信期望。
            let k = ((expected - incr) / (2 * Double.pi)).rounded()
            incr += k * 2 * Double.pi
            if abs(incr - expected) > Self.unwrapResidualLimit {
                incr = expected
            }
            patternPhase += incr

            // 角速度（供 UI 幀間外推）：以訊號時間（hop/sr）為
            // 分母，EMA 0.35；hop 異常（佇列嚴重掉幀）時跳過更新。
            let signalDt = hop / sampleRate
            if signalDt > 0.002 && signalDt < 0.1 {
                angularRate += (incr / signalDt - angularRate) * 0.35
            }
        }

        prevPhi = phi
        prevFreq = freq
        prevTargetMidi = targetMidi
        prevA4 = settings.a4
        prevTemperament = settings.temperament
        prevJustTonicPc = settings.justTonicPc
        prevTime = now
        anchorValid = true
        return snapshot(now: now, hasSignal: true)
    }

    // MARK: - 解調

    /// Hann 窗複數相關：回傳 (窗中心相位, 相干性 0…1)。
    /// 旋轉相量以 Double 遞推、每 1024 步歸一化，迴圈零分配。
    private func demodulate(
        window: [Float], frequency: Double, sampleRate: Double
    ) -> (phase: Double, coherence: Double) {
        let n = window.count
        guard n >= 4, frequency > 0, sampleRate > 0 else { return (0, 0) }
        if centered.count < n {
            centered = [Float](repeating: 0, count: n)
        }
        let hann = hannWindow(count: n)

        var mean: Float = 0
        vDSP_meanv(window, 1, &mean, vDSP_Length(n))
        var negMean = -mean
        vDSP_vsadd(window, 1, &negMean, &centered, 1, vDSP_Length(n))

        let step = -2 * Double.pi * frequency / sampleRate
        let sRe = cos(step)
        let sIm = sin(step)
        var pRe = 1.0
        var pIm = 0.0
        var zRe = 0.0
        var zIm = 0.0
        var sumAbs = 0.0
        for i in 0..<n {
            let w = Double(hann[i])
            let x = Double(centered[i])
            zRe += w * x * pRe
            zIm += w * x * pIm
            sumAbs += w * abs(x)
            let nRe = pRe * sRe - pIm * sIm
            let nIm = pRe * sIm + pIm * sRe
            pRe = nRe
            pIm = nIm
            if (i & 1023) == 1023 {
                let inv = 1.0 / max(1e-12, (pRe * pRe + pIm * pIm).squareRoot())
                pRe *= inv
                pIm *= inv
            }
        }

        // 窗中心相位校正：arg Z 含 −2πf·(N−1)/(2·sr) 偏移
        // （Hann 對稱性），加回後得窗中心相位；偏移與解調同
        // 用本幀 f，f 的抖動不進差分（見類註解方法 1）。
        let phase = Self.wrapPi(
            atan2(zIm, zRe)
                + 2 * Double.pi * frequency * Double(n - 1) / (2 * sampleRate))
        let magnitude = (zRe * zRe + zIm * zIm).squareRoot()
        let coherence = sumAbs > 0
            ? min(1, (magnitude / sumAbs) * Self.coherenceScale)
            : 0
        return (phase, coherence)
    }

    /// 對稱 Hann 係數（w[n] = w[N−1−n]，相位中心性質的前提），
    /// 按窗長快取（窗長只有 4096／8192／16384 三種）。
    private func hannWindow(count n: Int) -> [Float] {
        if let cached = hannCache[n] { return cached }
        var w = [Float](repeating: 0, count: n)
        if n > 1 {
            for i in 0..<n {
                w[i] = Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1))))
            }
        }
        hannCache[n] = w
        return w
    }

    // MARK: - 工具

    private static func wrapPi(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 2 * Double.pi)
        if r > Double.pi { r -= 2 * Double.pi }
        if r < -Double.pi { r += 2 * Double.pi }
        return r
    }

    private func snapshot(now: TimeInterval, hasSignal: Bool) -> StrobeState {
        var p = patternPhase.truncatingRemainder(dividingBy: 2 * Double.pi)
        if p < 0 { p += 2 * Double.pi }
        return StrobeState(
            phase: p,
            angularRate: angularRate,
            confidence: min(1, max(0, confidence)),
            hasSignal: hasSignal,
            time: now)
    }
}
