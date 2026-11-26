import Foundation

/// 樂器檢測音域（母本 INSTRUMENTS 表，行 6138–6183）。
///
/// 階段 1 只內建預設樂器（母本 state.currentInst 初始值 = INSTRUMENTS[0] =
/// alto_sax，行 6256）；全 40 種樂器表與自訂樂器在階段 4 數據層落地。
/// `transposition` 為母本 trans（記譜音 = 實音 − trans 的反向關係見母本
/// writtenMidi = targetConcertMidi − inst.trans，行 9606），階段 1 驗證介面
/// 顯示實音，欄位先行保留。
struct InstrumentRange: Equatable, Sendable {
    let id: String
    let transposition: Int
    let minFrequency: Double
    let maxFrequency: Double

    /// 母本 alto_sax（行 6139）：trans −9、130–1200 Hz。
    static let altoSax = InstrumentRange(
        id: "alto_sax", transposition: -9, minFrequency: 130, maxFrequency: 1200
    )

    /// 傳入檢測器的限幅範圍（母本行 8686 與 9560 兩處同式）：
    /// minF = max(25, inst.minF × 0.8)、maxF = min(4500, inst.maxF × 1.2)。
    var detectionBounds: (minFrequency: Double, maxFrequency: Double) {
        (max(25, minFrequency * 0.8), min(4500, maxFrequency * 1.2))
    }

    /// 分析窗大小（母本 pitchWindowFor，行 8673）：
    /// inst.minF < 80 → 16384；< 160 → 8192；否則 4096。
    var analysisWindowSize: Int {
        if minFrequency < 80 { return 16384 }
        if minFrequency < 160 { return 8192 }
        return 4096
    }

    /// 自訂樂器音域公式（母本行 7855–7862，階段 4 用）：
    /// minF = max(20, freqOf440(lowMidi) × 0.85)、maxF = freqOf440(highMidi) × 1.15。
    /// 注意母本此處固定以 440 換算，不用當前 A4。
    static func customRange(id: String, transposition: Int, lowMidi: Int, highMidi: Int) -> InstrumentRange {
        InstrumentRange(
            id: id,
            transposition: transposition,
            minFrequency: max(20, PitchMath.frequency440(midi: Double(lowMidi)) * 0.85),
            maxFrequency: PitchMath.frequency440(midi: Double(highMidi)) * 1.15
        )
    }
}
