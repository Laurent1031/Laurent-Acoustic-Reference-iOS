import Foundation

/// 噪聲門三檔（母本 gateMap，行 9530）：以置中訊號 RMS 為門檻，
/// 低於門檻視為無聲、檢測直接回絕。
enum NoiseGateProfile: String, CaseIterable, Sendable {
    case low
    case mid
    case high

    /// 母本 gateMap：low 0.004／mid 0.009／high 0.022。
    var rmsThreshold: Double {
        switch self {
        case .low: return 0.004
        case .mid: return 0.009
        case .high: return 0.022
        }
    }
}

/// 阻尼（平滑）三檔（母本 dampingCfg，行 9577）。
enum DampingProfile: String, CaseIterable, Sendable {
    case fast
    case balanced
    case smooth

    /// 中位數窗長（母本 win）。
    var medianWindow: Int {
        switch self {
        case .fast: return 3
        case .balanced: return 5
        case .smooth: return 7
        }
    }

    /// 頻率 EMA 係數（母本 freqAlpha）。
    var frequencyAlpha: Double {
        switch self {
        case .fast: return 0.48
        case .balanced: return 0.28
        case .smooth: return 0.16
        }
    }

    /// 音分臨界阻尼 spring 的 response（母本 springResponse）。
    var springResponse: Double {
        switch self {
        case .fast: return 0.16
        case .balanced: return 0.22
        case .smooth: return 0.30
        }
    }

    /// 母本 centsAlpha（fast 0.5／balanced 0.32／smooth 0.18）。
    /// 注意：母本音高路徑實際未使用此值（音分一律走 spring），
    /// 此處僅為參數對照完整性保留，勿在平滑邏輯中使用。
    var centsAlphaUnused: Double {
        switch self {
        case .fast: return 0.5
        case .balanced: return 0.32
        case .smooth: return 0.18
        }
    }
}

/// 調音器設定快照。預設值 = 母本 createDefaultProfile（行 6211）與
/// state 初始值（行 6249 起）：A4 442.0、容差 3、阻尼 balanced、
/// 噪聲門 mid、律制 equal、純律主音 pc 0。
struct TunerSettings: Equatable, Sendable {
    /// A4 基準頻率，範圍 430–450（母本 setA4 鉗制，行 8631）。
    var a4: Double = 442.0
    /// 準音容差（音分），母本預設 3（行 6222）。
    var toleranceCents: Double = 3.0
    var damping: DampingProfile = .balanced
    var noiseGate: NoiseGateProfile = .mid
    var temperament: Temperament = .equal
    /// 純律主音 pitch class（母本 justTonicPc，預設 0）。
    var justTonicPc: Int = 0
    /// 震動回饋總開關（母本 state.hapticsOn，預設 true）：
    /// 門控 HapticsEngine 全部輸出（規格書 §3.6）。
    var hapticsOn: Bool = true

    /// A4 步進（母本行 8638／8645）：±0.5 Hz，先 round 到 0.1，再鉗 [430, 450]。
    mutating func stepA4(by delta: Double) {
        let stepped = ((a4 + delta) * 10).rounded() / 10
        a4 = min(450, max(430, stepped))
    }

    /// A4 讀數點擊循環預設（母本行 8653）：[440, 442, 443]。
    static let a4Presets: [Double] = [440, 442, 443]
}
