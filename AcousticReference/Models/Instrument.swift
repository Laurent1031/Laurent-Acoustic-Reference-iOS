import Foundation

/// 樂器分類（母本 INSTRUMENTS 的 cat 與樂器庫分段鈕，行 5521）。
/// rawValue 與母本 cat 字串一致；順序即樂器庫分頁順序。
enum InstrumentCategory: String, Codable, CaseIterable, Sendable {
    case westernWind = "western_wind"
    case westernStr = "western_str"
    case chinese
    case band
    case custom
}

/// 樂器快捷目標音（母本 refTargets 的 {label, note}）。
struct InstrumentRefTarget: Codable, Equatable, Sendable {
    var note: String
    var label: String
}

/// 一種樂器（母本 INSTRUMENTS 一筆／自訂樂器一筆，同構）。
///
/// 內建 40 種由 `tools/extract-instruments.mjs` 自母本程式化抽取至
/// Resources/instruments.json（禁手工謄抄；核對報告見
/// tools/extraction-report.txt，逐種 trans/minF/maxF 與原文比對
/// 零不一致）。`name`、`categoryLabel`、refTarget `label` 為 zh-TW
/// 渲染值（抽取時查母本 I18N["zh-TW"]）；其餘欄位為母本原值。
struct Instrument: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var category: InstrumentCategory
    /// 母本 catLabel 的 zh-TW 渲染（如 "WOODWIND · 西洋木管"），
    /// 調音頁頂行分類標籤用；自訂樂器恆 "CUSTOM · 自訂樂器"（母本行 7847）。
    var categoryLabel: String
    /// zh-TW 顯示名（母本 name 的 zh-TW 渲染）。
    var name: String
    var englishName: String
    var keyName: String
    /// 母本 trans：記譜音 midi = 實音 midi − transposition。
    var transposition: Int
    var minFrequency: Double
    var maxFrequency: Double
    var refTargets: [InstrumentRefTarget]?
    var stringNotes: [String]?
    var isGuzheng: Bool
    var isCustom: Bool

    /// 母本 instDisplayName／頂行樂器名格式：`${name} · ${en}`。
    var displayName: String { "\(name) · \(englishName)" }

    /// 檢測音域（未含古箏調號移調覆寫；覆寫在 AppStore.effectiveRange）。
    var range: InstrumentRange {
        InstrumentRange(
            id: id, transposition: transposition,
            minFrequency: minFrequency, maxFrequency: maxFrequency)
    }
}

/// 樂器庫分頁一筆（分類＋zh-TW 名稱）。
struct InstrumentCategoryEntry: Identifiable, Sendable {
    var category: InstrumentCategory
    var name: String
    var id: InstrumentCategory { category }
}

/// 目錄 JSON 的頂層形狀（與 extract-instruments.mjs 輸出同構）。
private struct InstrumentCatalogFile: Codable {
    struct CategoryEntry: Codable {
        var id: String
        var name: String
    }
    struct GuzhengData: Codable {
        var keyOrder: [String]
        var keySemitones: [String: Int]
        var tunings: [String: [String]]
    }
    var version: Int
    var categories: [CategoryEntry]
    var instruments: [Instrument]
    var guzheng: GuzhengData
}

/// 內建樂器目錄：自 Bundle 資源 instruments.json 載入（Resources
/// build phase）。載入失敗（資源缺失／解碼錯誤）時退回僅含預設
/// 樂器的最小目錄，保證 App 仍可運行；此路徑只作保險絲，正常
/// 發布不應觸發（CI 打包後以 IPA 內容核查資源在位）。
enum InstrumentCatalog {
    private static let data: InstrumentCatalogFile? = load()

    private static func load() -> InstrumentCatalogFile? {
        guard let url = Bundle.main.url(forResource: "instruments", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(InstrumentCatalogFile.self, from: raw),
              !decoded.instruments.isEmpty
        else { return nil }
        return decoded
    }

    /// 目錄是否處於保險絲降級態（資源載入失敗、僅剩兜底
    /// 樂器）。AppStore.init 據此跳過收藏健全化，避免一
    /// 次性資源故障把用戶收藏永久修剪寫回（全邏輯複查
    /// ・低的破壞鏈防線）。
    static var isDegraded: Bool { data == nil }

    /// 母本 allInstruments() 的內建部分，順序與母本 INSTRUMENTS 一致。
    static var builtins: [Instrument] {
        data?.instruments ?? [fallbackAltoSax]
    }

    static func builtin(id: String) -> Instrument? {
        builtins.first { $0.id == id }
    }

    /// 樂器庫分頁（五大類，順序與母本分段鈕一致）；名稱為 zh-TW。
    static var categories: [InstrumentCategoryEntry] {
        if let entries = data?.categories {
            let mapped = entries.compactMap { entry -> InstrumentCategoryEntry? in
                guard let cat = InstrumentCategory(rawValue: entry.id) else { return nil }
                return InstrumentCategoryEntry(category: cat, name: entry.name)
            }
            if mapped.count == InstrumentCategory.allCases.count { return mapped }
        }
        return [
            InstrumentCategoryEntry(category: .westernWind, name: "西洋管樂"),
            InstrumentCategoryEntry(category: .westernStr, name: "弦樂鍵盤"),
            InstrumentCategoryEntry(category: .chinese, name: "民族樂團"),
            InstrumentCategoryEntry(category: .band, name: "現代樂隊"),
            InstrumentCategoryEntry(category: .custom, name: "自訂"),
        ]
    }

    static func categoryName(_ category: InstrumentCategory) -> String {
        categories.first { $0.category == category }?.name ?? ""
    }

    // MARK: - 古箏

    /// 調號選擇順序（母本 guzhengKeySelect，行 5284）：D、G、C、F、A。
    static var guzhengKeyOrder: [String] {
        data?.guzheng.keyOrder ?? ["D", "G", "C", "F", "A"]
    }

    /// 母本 GUZHENG_KEY_SEMITONES（行 6196）。
    static var guzhengKeySemitones: [String: Int] {
        data?.guzheng.keySemitones ?? ["C": 0, "D": 2, "F": 5, "G": 7, "A": 9]
    }

    /// 母本 GUZHENG_TUNINGS：調號 → 21 弦實音（高→低）。
    static func guzhengTuning(key: String) -> [String] {
        data?.guzheng.tunings[key] ?? data?.guzheng.tunings["D"] ?? []
    }

    /// 資源缺失時的保險絲預設樂器（母本 INSTRUMENTS[0]，行 6139）。
    static let fallbackAltoSax = Instrument(
        id: "alto_sax", category: .westernWind,
        categoryLabel: "WOODWIND · 西洋木管",
        name: "中音薩克斯", englishName: "Alto Sax", keyName: "1 = E♭",
        transposition: -9, minFrequency: 130, maxFrequency: 1200,
        refTargets: [
            InstrumentRefTarget(note: "A4", label: "樂團A4（記F♯5）"),
            InstrumentRefTarget(note: "B♭4", label: "管樂B♭4（記G5）"),
            InstrumentRefTarget(note: "E♭4", label: "本調Do（實E♭4）"),
        ],
        stringNotes: nil, isGuzheng: false, isCustom: false)
}
