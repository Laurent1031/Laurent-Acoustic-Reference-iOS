import AVFoundation
import Foundation

/// 節拍器點音的鍵：音色 × 重音等級 × 是否細分拍。
/// 細分拍的頻率在 wittner／rimshot 由「父拍等級」決定（母本
/// triggerMetroSound 以 accentLevel 選頻、僅增益被細分值覆蓋），
/// 故 level 在 isSub 時代表父拍等級。
struct ClickKey: Hashable, Sendable {
    let timbre: MetronomeTimbre
    let level: Int
    let isSub: Bool
}

/// 點音色合成：母本以 WebAudio 即時合成（triggerMetroSound，
/// index.html 行 11291 起），原生改為「同參數離線預渲染 PCM」——
/// 參數（頻率、包絡時常、增益、聲像、房間反射）逐項照母本，
/// 渲染結果在引擎啟動時一次算好，調度時零合成開銷、時序精確。
///
/// 母本信號鏈：音源 → 包絡增益 → 等功率聲像（gL/gR）→ 混音 →
/// DynamicsCompressor（threshold −0.5、ratio 12）→ destination；
/// 另有 room send：未聲像的單聲道 → delay 11 ms（左）／16 ms（右）
/// → lowpass 2600／2400 Hz → wet 0.14 → 回同側聲道。
/// 本渲染烘焙 room send，但「不」烘焙主匯流 compressor——母本的
/// compressor 作用於調音＋節拍共用的總線，屬全域母帶處理；
/// 單點增益最高 0.78×1.1 未及 −0.5 dBFS 門檻，影響可忽略，
/// 此為有意差異（見階段 3 報告）。
enum ClickSynth {

    /// 渲染全部 5 音色 × 3 等級 × 細分旗標 = 30 個立體聲緩衝。
    static func renderAll(sampleRate: Double) -> [ClickKey: AVAudioPCMBuffer] {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 2,
                                         interleaved: false) else { return [:] }
        var rng = SplitMix64(state: 0x9E37_79B9_7F4A_7C15)
        var out: [ClickKey: AVAudioPCMBuffer] = [:]
        for timbre in MetronomeTimbre.allCases {
            for level in 1...3 {
                for isSub in [false, true] {
                    let key = ClickKey(timbre: timbre, level: level, isSub: isSub)
                    let (l, r) = render(timbre: timbre, level: level, isSub: isSub,
                                        sampleRate: sampleRate, rng: &rng)
                    if let buffer = makeBuffer(l: l, r: r, format: format) {
                        out[key] = buffer
                    }
                }
            }
        }
        return out
    }

    // MARK: - 母本增益／聲像（行 11298–11305）

    private static func amp(level: Int, isSub: Bool) -> Double {
        if isSub { return 0.20 }
        switch level {
        case 3: return 0.78
        case 2: return 0.50
        default: return 0.34
        }
    }

    private static func pan(level: Int, isSub: Bool) -> Double {
        if isSub { return 0.22 }
        switch level {
        case 3: return 0.0
        case 2: return -0.14
        default: return 0.12
        }
    }

    /// 等功率聲像（母本行 11314–11316）。
    private static func panGains(_ pan: Double) -> (l: Double, r: Double) {
        let angle = (pan + 1) * 0.25 * Double.pi
        return (cos(angle), sin(angle))
    }

    // MARK: - 包絡（對照 WebAudio ramp 語義）

    /// setValueAtTime(0.0001) → linearRamp(peak, attack) →
    /// exponentialRamp(0.0001, decayEnd) 的逐樣本等價。
    private static func envAD(t: Double, peak: Double, attack: Double, decayEnd: Double) -> Double {
        if t < attack {
            return 0.0001 + (peak - 0.0001) * (t / max(attack, 1e-6))
        }
        let span = max(decayEnd - attack, 1e-6)
        let u = (t - attack) / span
        if u >= 1 { return 0.0001 }
        return peak * pow(0.0001 / peak, u)
    }

    /// setValueAtTime(v1) → exponentialRamp(v2, dur)：到達後保持 v2。
    private static func envExpHold(t: Double, from v1: Double, to v2: Double, dur: Double) -> Double {
        if t >= dur { return v2 }
        return v1 * pow(v2 / v1, t / dur)
    }

    // MARK: - 單一音色渲染

    private static func render(timbre: MetronomeTimbre, level: Int, isSub: Bool,
                               sampleRate sr: Double,
                               rng: inout SplitMix64) -> (l: [Double], r: [Double]) {
        let a = amp(level: level, isSub: isSub)
        let p = pan(level: level, isSub: isSub)
        var mix = Mixer(sampleRate: sr, duration: duration(timbre))

        switch timbre {
        case .digital:
            // 母本：sine f0 ＋ sine 2f0×0.22 共用一條包絡。
            let f0 = isSub ? 659.25 : (level == 3 ? 1760 : level == 2 ? 1318.51 : 880)
            let sig = tonePair(f0: f0, ratio: 2.0, harmonicGain: { _ in 0.22 },
                               seconds: 0.046, sr: sr) { t in
                envAD(t: t, peak: a * 0.68, attack: 0.002, decayEnd: 0.042)
            }
            mix.add(mono: sig, pan: p, room: true)

        case .woodblock:
            // 母本：sine f1 ＋ sine 1.48f1（g2 包絡 0.32→0.01@18ms），
            // 外加敲擊噪聲（bandpass f1×2.2、Q 3.0、無 room send）。
            let f1: Double = isSub ? 680 : (level == 3 ? 988 : level == 2 ? 830 : 740)
            let sig = tonePair(f0: f1, ratio: 1.48,
                               harmonicGain: { t in envExpHold(t: t, from: 0.32, to: 0.01, dur: 0.018) },
                               seconds: 0.048, sr: sr) { t in
                envAD(t: t, peak: a * 0.85, attack: 0.0018, decayEnd: 0.044)
            }
            mix.add(mono: sig, pan: p, room: true)
            let tap = noise(seconds: 0.012, sr: sr, rng: &rng,
                            bandpassFreq: f1 * 2.2, q: 3.0) { t in
                envExpHold(t: t, from: a * 0.45, to: 0.0001, dur: 0.008)
            }
            mix.add(stereo: tap, pan: p, room: false)

        case .wittner:
            // 母本：噪聲 bandpass（強拍 2850／其餘 2250、Q 3.6）＋
            // triangle 箱體共鳴（620／490），共鳴聲像取 −pan×0.5。
            let click = noise(seconds: 0.018, sr: sr, rng: &rng,
                              bandpassFreq: level == 3 ? 2850 : 2250, q: 3.6) { t in
                envAD(t: t, peak: a * 1.1, attack: 0.001, decayEnd: 0.014)
            }
            mix.add(stereo: click, pan: p, room: true)
            let box = tone(freq: level == 3 ? 620 : 490, wave: .triangle,
                           seconds: 0.024, sr: sr) { t in
                envAD(t: t, peak: a * 0.42, attack: 0.0015, decayEnd: 0.020)
            }
            mix.add(mono: box, pan: -p * 0.5, room: true)

        case .rimshot:
            // 母本：噪聲 bandpass（2450／1920、Q 2.8）＋ sine＋triangle
            // 模態對（370＋740／315＋630），模態聲像 pan×0.6。
            let snap = noise(seconds: 0.032, sr: sr, rng: &rng,
                             bandpassFreq: level == 3 ? 2450 : 1920, q: 2.8) { t in
                envAD(t: t, peak: a * 0.95, attack: 0.001, decayEnd: 0.028)
            }
            mix.add(stereo: snap, pan: p, room: true)
            let modes = tonePair(f0: level == 3 ? 370 : 315, ratio: 2.0,
                                 secondWave: .triangle, harmonicGain: { _ in 1.0 },
                                 seconds: 0.034, sr: sr) { t in
                envAD(t: t, peak: a * 0.52, attack: 0.0015, decayEnd: 0.030)
            }
            mix.add(mono: modes, pan: p * 0.6, room: true)

        case .marimba:
            // 母本：sine f0 ＋ sine 3.98f0（增益 0.26→0.001@22ms）。
            let f0 = isSub ? 523.25 : (level == 3 ? 1046.50 : level == 2 ? 783.99 : 659.25)
            let sig = tonePair(f0: f0, ratio: 3.98,
                               harmonicGain: { t in envExpHold(t: t, from: 0.26, to: 0.001, dur: 0.022) },
                               seconds: 0.10, sr: sr) { t in
                envAD(t: t, peak: a * 0.82, attack: 0.003, decayEnd: 0.095)
            }
            mix.add(mono: sig, pan: p, room: true)
        }
        return (mix.l, mix.r)
    }

    private static func duration(_ timbre: MetronomeTimbre) -> Double {
        // 最長組件 stop 時間 + room send 尾巴（延遲 16 ms + 低通拖尾）。
        switch timbre {
        case .digital: return 0.09
        case .woodblock: return 0.09
        case .wittner: return 0.07
        case .rimshot: return 0.08
        case .marimba: return 0.14
        }
    }

    // MARK: - 信號產生器

    private enum Wave { case sine, triangle }

    private static func tone(freq: Double, wave: Wave, seconds: Double, sr: Double,
                             env: (Double) -> Double) -> [Double] {
        let n = Int(seconds * sr)
        var out = [Double](repeating: 0, count: n)
        var phase = 0.0
        let inc = freq / sr
        for i in 0..<n {
            let t = Double(i) / sr
            let v = wave == .sine ? sin(phase * 2 * Double.pi)
                : (2 / Double.pi) * asin(sin(phase * 2 * Double.pi))
            out[i] = v * env(t)
            phase += inc
        }
        return out
    }

    /// 基頻＋泛音對，共用主包絡；泛音增益可隨時間變化（母本 g2/g4）。
    private static func tonePair(f0: Double, ratio: Double,
                                 secondWave: Wave = .sine,
                                 harmonicGain: (Double) -> Double,
                                 seconds: Double, sr: Double,
                                 env: (Double) -> Double) -> [Double] {
        let n = Int(seconds * sr)
        var out = [Double](repeating: 0, count: n)
        var p1 = 0.0
        var p2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let s1 = sin(p1 * 2 * Double.pi)
            let raw2 = sin(p2 * 2 * Double.pi)
            let s2 = secondWave == .sine ? raw2
                : (2 / Double.pi) * asin(raw2)
            out[i] = (s1 + harmonicGain(t) * s2) * env(t)
            p1 += f0 / sr
            p2 += f0 * ratio / sr
        }
        return out
    }

    /// 母本噪聲緩衝：45 ms 雙聲道去相關白噪聲 ×exp(−i/(len×0.22))，
    /// 經 bandpass 後再乘組件包絡。種子 PRNG 保證每次渲染一致。
    private static func noise(seconds: Double, sr: Double, rng: inout SplitMix64,
                              bandpassFreq: Double, q: Double,
                              env: (Double) -> Double) -> (l: [Double], r: [Double]) {
        let n = Int(seconds * sr)
        let bufLen = Int(0.045 * sr)
        var bpL = Biquad.bandpass(freq: bandpassFreq, q: q, sr: sr)
        var bpR = Biquad.bandpass(freq: bandpassFreq, q: q, sr: sr)
        var l = [Double](repeating: 0, count: n)
        var r = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let decay = i < bufLen ? exp(-Double(i) / (Double(bufLen) * 0.22)) : 0
            let e = env(t)
            l[i] = bpL.process(rng.nextUnit() * decay) * e
            r[i] = bpR.process(rng.nextUnit() * decay) * e
        }
        return (l, r)
    }

    // MARK: - 混音（聲像＋room send）

    private struct Mixer {
        let sr: Double
        var l: [Double]
        var r: [Double]

        init(sampleRate: Double, duration: Double) {
            sr = sampleRate
            let n = Int(duration * sampleRate)
            l = [Double](repeating: 0, count: n)
            r = [Double](repeating: 0, count: n)
        }

        mutating func add(mono sig: [Double], pan: Double, room: Bool) {
            let (gL, gR) = panGains(pan)
            let n = min(sig.count, l.count)
            for i in 0..<n {
                l[i] += sig[i] * gL
                r[i] += sig[i] * gR
            }
            if room { addRoom(send: sig) }
        }

        mutating func add(stereo sig: (l: [Double], r: [Double]), pan: Double, room: Bool) {
            let (gL, gR) = panGains(pan)
            let n = min(sig.l.count, l.count)
            for i in 0..<n {
                l[i] += sig.l[i] * gL
                r[i] += sig.r[i] * gR
            }
            if room {
                // room send 在母本取聲像前的立體聲源；此處以雙聲道
                // 均值作單聲道 send（振盪器組件 L==R、與母本一致；
                // 噪聲組件差異僅在反射的細微寬度，聽感可忽略）。
                let mono = (0..<n).map { (sig.l[$0] + sig.r[$0]) * 0.5 }
                addRoom(send: mono)
            }
        }

        /// 母本 room send：delay 11/16 ms → lowpass 2600/2400 → ×0.14。
        private mutating func addRoom(send sig: [Double]) {
            let dL = Int(0.011 * sr)
            let dR = Int(0.016 * sr)
            var lpL = Biquad.lowpass(freq: 2600, q: 0.7071, sr: sr)
            var lpR = Biquad.lowpass(freq: 2400, q: 0.7071, sr: sr)
            for i in 0..<l.count {
                let inL = i - dL >= 0 && i - dL < sig.count ? sig[i - dL] : 0
                let inR = i - dR >= 0 && i - dR < sig.count ? sig[i - dR] : 0
                l[i] += lpL.process(inL) * 0.14
                r[i] += lpR.process(inR) * 0.14
            }
        }
    }

    // MARK: - 濾波器（RBJ；bandpass 為 WebAudio 的恆 0 dB 峰值增益型）

    private struct Biquad {
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }

        static func bandpass(freq: Double, q: Double, sr: Double) -> Biquad {
            let w = 2 * Double.pi * freq / sr
            let alpha = sin(w) / (2 * q)
            let a0 = 1 + alpha
            return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0,
                          a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
        }

        static func lowpass(freq: Double, q: Double, sr: Double) -> Biquad {
            let w = 2 * Double.pi * freq / sr
            let alpha = sin(w) / (2 * q)
            let cs = cos(w)
            let a0 = 1 + alpha
            return Biquad(b0: (1 - cs) / 2 / a0, b1: (1 - cs) / a0, b2: (1 - cs) / 2 / a0,
                          a1: -2 * cs / a0, a2: (1 - alpha) / a0)
        }
    }

    // MARK: - 確定性 PRNG（母本用 Math.random 白噪聲；渲染一次即
    // 固定緩衝，種子化只影響噪聲細節、不影響音色性格）

    private struct SplitMix64 {
        var state: UInt64

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    private static func makeBuffer(l: [Double], r: [Double],
                                   format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(l.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        for i in 0..<l.count {
            channels[0][i] = Float(l[i])
            channels[1][i] = Float(r[i])
        }
        return buffer
    }
}
