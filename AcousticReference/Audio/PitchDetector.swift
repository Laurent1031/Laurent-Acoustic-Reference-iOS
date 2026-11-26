import Accelerate
import Foundation

/// 一次檢測的結果。`frequency == nil` 表示回絕（低於噪聲門或清晰度不足），
/// 對應母本 detectPitchMPM 回傳 −1 的兩種情形；clarity／rms 額外保留供
/// 診斷記錄（規格書 §3.2 診斷模式），不影響檢測行為。
struct PitchDetection: Sendable {
    var frequency: Double?
    /// NSDF 全局最大峰值（母本 globalMax），回絕門檻 0.58。
    var clarity: Double
    /// 置中訊號 RMS（母本在 detectPitchMPM 內計算）。
    var rms: Double
    /// 置中訊號峰值絕對值（0–1，線性；補強段削波警示用，母本
    /// 檢測路徑無此值——母本無削波警示，此為原生新增診斷量，
    /// 不參與檢測判定）。在噪聲門回絕前計算，被回絕的過載幀
    /// 同樣帶峰值（削波恰恰發生在這類幀）。
    var peak: Double
    /// 是否因 RMS 低於噪聲門回絕（與清晰度不足區分，供診斷）。
    var rejectedByGate: Bool
}

/// MPM/NSDF 音高檢測，與母本 detectPitchMPM（`index.html` 行 8891）行為等價。
///
/// 等價要點（逐項對照母本）：
/// - 先去 DC（減均值），置中訊號 RMS < rmsGate → 回絕；
/// - minTau = max(2, floor(sr/maxFreq))，maxTau = min(floor(N/2), ceil(sr/minFreq))；
/// - NSDF(τ) = 2·acf(τ) / divisor(τ)，divisor = Σ(x[i]² + x[i+τ]²)；
/// - 選峰：跳過初始正值段與其後非正段，逐正 lobe 取最大值為峰；
/// - 無峰或 globalMax < 0.58 → 回絕；threshold = 0.88 × globalMax，
///   取第一個 ≥ threshold 的峰（找不到則取 peaks[0]）；
/// - 拋物線插值：僅 t 嚴格在 (minTau, maxTau) 內、|denom| > 1e-6 時；
/// - 回傳 sr / refinedTau。
///
/// 加速路徑（規格書 §3.2 的 vDSP 要求）：acf(τ) 改以 FFT 自相關
/// （Wiener–Khinchin：FFT → 功率譜 → IFFT）一次算出全部 τ，數學上與
/// 母本逐 τ 內積相同；divisor 以 MPM 原論文的遞歸式
/// m(τ) = m(τ−1) − x[τ−1]² − x[N−τ]² 在 Double 下計算（母本為逐 τ
/// 直接求和＋Float32Array 存 NSDF，兩者差異在浮點精度級別）。
/// FFT 尺度以 r(0) 對 Σx² 自校準，不依賴 vDSP 逆 FFT 的縮放慣例假設。
///
/// 本類別僅供單一串行佇列（AudioEngine 的分析佇列）使用，非線程安全。
final class PitchDetector {

    /// MPM 清晰度門檻（母本行 8948：globalMax < 0.58 回絕）。
    static let clarityThreshold = 0.58
    /// 峰值挑選門檻比例（母本行 8950：0.88 × globalMax）。
    static let peakThresholdRatio = 0.88

    private var fftSetups: [Int: FFTSetup] = [:]      // key: log2(FFT size)
    private var scaleCalibration: [Int: Double] = [:] // key: FFT size

    deinit {
        for setup in fftSetups.values { vDSP_destroy_fftsetup(setup) }
    }

    /// - Parameters:
    ///   - samples: 一個分析窗的原始（未置中）樣本。
    ///   - sampleRate: 取樣率（Hz）。
    ///   - minFreq / maxFreq: 檢測範圍（由 InstrumentRange.detectionBounds 給出）。
    ///   - rmsGate: 噪聲門（NoiseGateProfile.rmsThreshold）。
    func detect(samples: [Float], sampleRate: Double, minFreq: Double, maxFreq: Double, rmsGate: Double) -> PitchDetection {
        let n = samples.count
        guard n >= 4 else {
            return PitchDetection(frequency: nil, clarity: 0, rms: 0, peak: 0, rejectedByGate: true)
        }

        // 去 DC（母本行 8893–8899）。
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(n))
        var centered = [Float](repeating: 0, count: n)
        var negMean = -mean
        vDSP_vsadd(samples, 1, &negMean, &centered, 1, vDSP_Length(n))

        // 峰值（補強段削波警示）：置中訊號最大絕對值，門檻判定前
        // 先算，任何回絕路徑都帶得出。
        var peakValue: Float = 0
        vDSP_maxmgv(centered, 1, &peakValue, vDSP_Length(n))
        let peak = Double(peakValue)

        // 置中 RMS 與噪聲門（母本行 8901–8907）。
        var rms: Float = 0
        vDSP_rmsqv(centered, 1, &rms, vDSP_Length(n))
        guard Double(rms) >= rmsGate else {
            return PitchDetection(frequency: nil, clarity: 0, rms: Double(rms), peak: peak, rejectedByGate: true)
        }

        let minTau = max(2, Int(floor(sampleRate / maxFreq)))
        let maxTau = min(n / 2, Int(ceil(sampleRate / minFreq)))
        guard maxTau > minTau else {
            return PitchDetection(frequency: nil, clarity: 0, rms: Double(rms), peak: peak, rejectedByGate: false)
        }

        // NSDF：acf 走 FFT 自相關；divisor 走遞歸（Double 累加）。
        let acf = autocorrelation(centered, maxTau: maxTau)
        var nsdf = [Double](repeating: 0, count: maxTau + 1)
        var divisor = 2.0 * acf[0] // m(0) = Σx² + Σx²（minTau ≥ 2，τ<minTau 不需填）
        for tau in 1...maxTau {
            // m(τ) = m(τ−1) − x[τ−1]² − x[N−τ]²
            let a = Double(centered[tau - 1])
            let b = Double(centered[n - tau])
            divisor -= a * a + b * b
            if tau >= minTau {
                nsdf[tau] = divisor > 0 ? (2 * acf[tau]) / divisor : 0
            }
        }

        // 選峰（母本行 8930–8952，迴圈結構原樣移植）。
        var peaks: [(tau: Int, val: Double)] = []
        var globalMax = 0.0
        var tau = minTau
        while tau <= maxTau && nsdf[tau] > 0 { tau += 1 }
        while tau <= maxTau && nsdf[tau] <= 0 { tau += 1 }

        var curMaxTau = -1
        var curMaxVal = -1.0
        while tau <= maxTau {
            if nsdf[tau] > 0 {
                if nsdf[tau] > curMaxVal {
                    curMaxVal = nsdf[tau]
                    curMaxTau = tau
                }
            } else if curMaxTau != -1 {
                peaks.append((tau: curMaxTau, val: curMaxVal))
                if curMaxVal > globalMax { globalMax = curMaxVal }
                curMaxTau = -1
                curMaxVal = -1
            }
            tau += 1
        }
        if curMaxTau != -1 {
            peaks.append((tau: curMaxTau, val: curMaxVal))
            if curMaxVal > globalMax { globalMax = curMaxVal }
        }

        guard !peaks.isEmpty, globalMax >= PitchDetector.clarityThreshold else {
            return PitchDetection(frequency: nil, clarity: globalMax, rms: Double(rms), peak: peak, rejectedByGate: false)
        }

        let threshold = PitchDetector.peakThresholdRatio * globalMax
        let chosen = peaks.first(where: { $0.val >= threshold }) ?? peaks[0]

        // 拋物線插值（母本行 8956–8967）。
        let t = chosen.tau
        var refinedTau = Double(t)
        if t > minTau && t < maxTau {
            let y1 = nsdf[t - 1]
            let y2 = nsdf[t]
            let y3 = nsdf[t + 1]
            let denom = y1 - 2 * y2 + y3
            if abs(denom) > 1e-6 {
                refinedTau = Double(t) + (0.5 * (y1 - y3)) / denom
            }
        }

        return PitchDetection(
            frequency: sampleRate / refinedTau,
            clarity: globalMax,
            rms: Double(rms),
            peak: peak,
            rejectedByGate: false
        )
    }

    // MARK: - FFT 自相關

    /// 回傳 r(τ) = Σ_{i<N−τ} x[i]·x[i+τ]，τ ∈ [0, maxTau]（Double）。
    /// 零填充至 ≥ 2N 的 2 的冪次長度做循環自相關，τ < N 區間與線性自相關一致。
    private func autocorrelation(_ x: [Float], maxTau: Int) -> [Double] {
        let n = x.count
        var m = 1
        while m < 2 * n { m <<= 1 }
        let log2n = Int(log2(Double(m)))

        let setup: FFTSetup
        if let existing = fftSetups[log2n] {
            setup = existing
        } else {
            guard let created = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(FFT_RADIX2)) else {
                return directAutocorrelation(x, maxTau: maxTau)
            }
            fftSetups[log2n] = created
            setup = created
        }

        var inReal = [Float](repeating: 0, count: m)
        var inImag = [Float](repeating: 0, count: m)
        var outReal = [Float](repeating: 0, count: m)
        var outImag = [Float](repeating: 0, count: m)
        inReal.replaceSubrange(0..<n, with: x)

        var power = [Float](repeating: 0, count: m)
        var resultReal = [Float](repeating: 0, count: m)
        var resultImag = [Float](repeating: 0, count: m)

        inReal.withUnsafeMutableBufferPointer { inRealPtr in
            inImag.withUnsafeMutableBufferPointer { inImagPtr in
                outReal.withUnsafeMutableBufferPointer { outRealPtr in
                    outImag.withUnsafeMutableBufferPointer { outImagPtr in
                        var input = DSPSplitComplex(
                            realp: inRealPtr.baseAddress!, imagp: inImagPtr.baseAddress!)
                        var output = DSPSplitComplex(
                            realp: outRealPtr.baseAddress!, imagp: outImagPtr.baseAddress!)
                        vDSP_fft_zop(setup, &input, 1, &output, 1,
                                     vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&output, 1, &power, 1, vDSP_Length(m))
                    }
                }
            }
        }

        // 功率譜作為實數序列（虛部 0）做逆 FFT，實部即自相關。
        power.withUnsafeMutableBufferPointer { powerPtr in
            resultImag.withUnsafeMutableBufferPointer { zeroImagPtr in
                resultReal.withUnsafeMutableBufferPointer { resultRealPtr in
                    outImag.withUnsafeMutableBufferPointer { resultImagOutPtr in
                        var input = DSPSplitComplex(
                            realp: powerPtr.baseAddress!, imagp: zeroImagPtr.baseAddress!)
                        var output = DSPSplitComplex(
                            realp: resultRealPtr.baseAddress!, imagp: resultImagOutPtr.baseAddress!)
                        vDSP_fft_zop(setup, &input, 1, &output, 1,
                                     vDSP_Length(log2n), FFTDirection(FFT_INVERSE))
                    }
                }
            }
        }
        // 逆 FFT 結果實部在 resultReal（虛部寫入 outImag 緩衝，棄置不用）；
        // resultImag 全程只是逆 FFT 輸入端的零虛部。

        // 尺度自校準：r(0) 必須等於 Σx²（vDSP_svesq 直算）。
        var sumSquares: Float = 0
        vDSP_svesq(x, 1, &sumSquares, vDSP_Length(n))
        let factor: Double
        if let cached = scaleCalibration[m] {
            factor = cached
        } else if resultReal[0] != 0 {
            factor = Double(sumSquares) / Double(resultReal[0])
            scaleCalibration[m] = factor
        } else {
            factor = 1
        }

        var r = [Double](repeating: 0, count: maxTau + 1)
        for tau in 0...maxTau {
            r[tau] = Double(resultReal[tau]) * factor
        }
        return r
    }

    /// FFT 建立失敗時的兜底：逐 τ 內積（母本原算法，慢但正確）。
    private func directAutocorrelation(_ x: [Float], maxTau: Int) -> [Double] {
        let n = x.count
        var r = [Double](repeating: 0, count: maxTau + 1)
        for tau in 0...maxTau {
            var acc = 0.0
            let limit = n - tau
            for i in 0..<limit {
                acc += Double(x[i]) * Double(x[i + tau])
            }
            r[tau] = acc
        }
        return r
    }
}
