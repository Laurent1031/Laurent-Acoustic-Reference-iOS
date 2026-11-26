import Foundation

/// Core Haptics 編排常數表（階段 6 數值化）：節拍與鎖定的全部
/// transient 參數集中於此，HapticsEngine 只負責播放機制、不再
/// 內嵌數值。數值出處逐項標明：
///
/// - 強拍／次強拍／弱拍／細分拍：《架構演進方案》§05（第 5 頁）
///   「iOS Core Haptics 声学触觉编排」——強拍 Intensity 1.0＋
///   Sharpness 0.25 的沉厚敲擊；次強拍／弱拍中低強度 0.6／0.35
///   ＋高銳度 0.75；細分拍極輕柔微觸感 0.18。細分拍的銳度方案
///   原文未給數值，藍圖 §4.3 對細分拍的定性為「低強度高銳度
///   短點」，故與次強／弱拍同取 0.75（推導值，註明備查）。
/// - 準音鎖定棘輪：方案 §05／藍圖 §4.3 的「機械棘輪咬合」輕震
///   無具體數值；形制沿母本鎖定震動圖案 vibrate([8, 35, 16])
///   的雙擊結構（兩記 transient、間隔 = 8＋35 = 43 ms），
///   intensity 沿 HapticsEngine 既有 pattern() 的 ms→intensity
///   映射（seg／30、鉗 [0.3, 1]：8 ms→0.30、16 ms→0.53），
///   sharpness 取 0.9 表棘輪的高銳度咬合感（原生映射值）。
/// - 步進 detent：方案與藍圖僅定性要求（BPM／A4 步進棘輪
///   頓挫），數值沿階段 3 既有實作（0.35／0.95），不變。
///
/// 與階段 3 舊值的差異（本段有意變更，源自上述採納值）：
/// 強拍 sharpness 0.75→0.25（沉厚化）、次強拍 0.62／0.6→
/// 0.6／0.75、弱拍 sharpness 0.45→0.75；細分拍震動為新增
/// （母本與階段 3 皆無細分拍震動，此為架構方案採納項）。
enum HapticPatternTable {
    struct Transient: Sendable {
        let intensity: Float
        let sharpness: Float
    }

    /// 強拍（Downbeat）：高強度、低銳度的沉厚敲擊。
    static let downbeat = Transient(intensity: 1.0, sharpness: 0.25)
    /// 次強拍：中強度、高銳度清脆短點。
    static let secondaryBeat = Transient(intensity: 0.6, sharpness: 0.75)
    /// 弱拍：低強度、高銳度清脆短點。
    static let weakBeat = Transient(intensity: 0.35, sharpness: 0.75)
    /// 細分拍（八分／三連／十六分）：極輕柔微觸感，不喧賓奪主。
    static let subdivision = Transient(intensity: 0.18, sharpness: 0.75)

    /// 拍點等級 → 圖樣（等級 3 強／2 次強／1 弱；0 靜音不震，
    /// 由呼叫方排除）。
    static func beat(level: Int) -> Transient {
        switch level {
        case 3...: return downbeat
        case 2: return secondaryBeat
        default: return weakBeat
        }
    }

    /// 準音鎖定棘輪：雙記 transient（相對時刻秒、圖樣）。
    static let lockRatchet: [(offset: Double, transient: Transient)] = [
        (0, Transient(intensity: 0.30, sharpness: 0.9)),
        (0.043, Transient(intensity: 0.53, sharpness: 0.9)),
    ]

    /// 步進 detent（BPM／A4 步進鈕）：短促高銳度。
    static let detent = Transient(intensity: 0.35, sharpness: 0.95)
}
