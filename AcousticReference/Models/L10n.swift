import Foundation
import os

/// App 顯示語言（階段 5）：八語，rawValue 與母本 state.lang 一致。
/// 預設 zh-TW（Laurent 定版）；App 內設定覆寫系統語言（母本
/// langSelect 的語義）。displayName 為各語言原生名——母本語言
/// 選單標了 data-i18n-skip（恆不翻譯），原生比照：Picker 選項
/// 恆顯示原生名。
enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case zhTW = "zh-TW"
    case zhCN = "zh-CN"
    case en
    case ja
    case ko
    case de
    case fr
    case ru

    /// 原生名（母本 langSelect 選項原文，data-i18n-skip 不譯）。
    var displayName: String {
        switch self {
        case .zhTW: return "繁體中文"
        case .zhCN: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .ru: return "Русский"
        }
    }

    /// 母本 LANG_HTML 映射（zh-TW→zh-Hant、zh-CN→zh-Hans，其餘同
    /// rawValue）；供日後需要 Locale 的呼叫點使用。
    var localeIdentifier: String {
        switch self {
        case .zhTW: return "zh-Hant"
        case .zhCN: return "zh-Hans"
        default: return rawValue
        }
    }
}

/// 運行期本地化服務（階段 5）：1:1 複刻母本的字典模型——
///
/// - 資源 `Resources/localization.json` 由 `tools/extract-i18n.mjs`
///   自母本 I18N 字面量程式化抽取（逐條核對報告見
///   tools/i18n-extraction-report.txt），另含 supplement 段
///   （原生專屬字串，母本字典沒有者，出處分開標明）。
/// - 查表 = 母本 translateString（行 8131）：trim 後先 exact、
///   未中走 I18N_PREFIXES 前綴匹配（且字典須含該前綴鍵）、
///   再未中回源串；zh-CN 恆回源串（母本 translateTree 對
///   zh-CN 直接跳過、tStr 的 dict 即源串本身）。
/// - 查表順序：supplement → 母本字典 → 源串。【五維審
///   計・排版項2】supplement 原為純補缺層（與字典鍵零
///   重疊，2026-11-27 機械核查 overlap=0）；改置字典之
///   前成為覆寫層，供個別過長譯文以短形覆寫（如俄語
///   平均律、德語記譜音——分段/晶片在等寬格位下被縮至
///   不可讀）。覆寫項同步登記於 tools/i18n-supplement
///   .json，重抽取時不丟失。
/// - 選型不用 .xcstrings：母本模型即運行期「源串為鍵」字典，
///   JSON 可 1:1 複刻（含前綴回退與即時切換）；App 內覆寫語言
///   下 .xcstrings 需逐呼叫點 locale 管道、動態組裝字串
///   （前綴＋用戶內容）處理差；專案已有 instruments.json
///   運行期資源先例且 CI 已驗；.xcstrings 在 CI runner
///   （Xcode 26.6／SDK 26.5 vs deployment target 27.0）的
///   編譯行為本機不可驗，JSON 零建置風險。
/// - 載入失敗保險絲：字典視為空，t() 恆回源串——App 照常運行
///   （顯示簡體源串），與母本 dict 缺失時的行為同構。
/// - 反查表 localizedName：instruments.json 的樂器名／分類標籤
///   存的是 zh-TW 渲染值（抽取時查表轉換），顯示時須先經
///   母本 normI18nSrc 的反查（zh-TW 值 → 簡體源串）再走 t()，
///   與母本 TreeWalker 對樂器名的接線完全一致。
///
/// 並發：呼叫點含 View body（任意隔離域）與 @MainActor 的
/// ViewModel，故以 OSAllocatedUnfairLock 保護全部可變狀態，
/// 服務本身 nonisolated；語言切換由 ContentView 的 onChange
/// 單向同步（AppStore.language 為唯一真源，比照 HapticsEngine
/// 的同步模式）。
enum L10n {
    private struct Tables {
        var dict: [String: [String: String]] = [:]
        var supplement: [String: [String: String]] = [:]
        var prefixes: [String] = []
        /// zh-TW 渲染值 → 簡體源串（母本 _TW_TO_CN：遍歷 zh-TW
        /// 字典、後寫覆蓋——JS 物件字面量插入序下同值鍵的後者
        /// 勝出；Swift Dictionary 遍歷序不確定，此處改以鍵排序
        /// 後建立，結果確定；同值多鍵的歧義在母本同樣存在）。
        var twToSource: [String: String] = [:]
        var language: AppLanguage = .zhTW
    }

    private static let lock = OSAllocatedUnfairLock(initialState: Tables())
    private static let didLoad: Void = loadTables()

    /// 目前語言（由 AppStore 同步寫入；直接讀取供組合邏輯判斷，
    /// 如 headerInstLabel 的語言分支）。
    static var currentLanguage: AppLanguage {
        _ = didLoad
        return lock.withLock { $0.language }
    }

    static func setLanguage(_ language: AppLanguage) {
        _ = didLoad
        lock.withLock { $0.language = language }
    }

    /// CJK 語言旗標（五維審計・排版項16）：方塊字加字距
    /// （tracking）會破壞字面，CJK 介面下字距恆應為 0。
    static var isCJK: Bool {
        switch currentLanguage {
        case .zhTW, .zhCN, .ja, .ko: return true
        default: return false
        }
    }

    private static func loadTables() {
        guard let url = Bundle.main.url(forResource: "localization", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LocalizationFile.self, from: raw)
        else { return }
        lock.withLock { tables in
            tables.dict = file.dict
            tables.supplement = file.supplement ?? [:]
            tables.prefixes = file.prefixes
            var reverse: [String: String] = [:]
            let tw = file.dict["zh-TW"] ?? [:]
            for key in tw.keys.sorted() {
                if let value = tw[key] { reverse[value] = key }
            }
            tables.twToSource = reverse
        }
    }

    /// 母本 translateString 的 1:1 複刻（作用於單一字典）。
    /// JS 的 String.replace（字串模式）只換首個匹配，Swift 側以
    /// range(of:) 定位首個匹配比照，不得用 replacingOccurrences
    /// 的全量替換。
    private static func translate(_ src: String, dict: [String: String],
                                  prefixes: [String]) -> String {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return src }
        if let hit = dict[trimmed], let range = src.range(of: trimmed) {
            return src.replacingCharacters(in: range, with: hit)
        }
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            if let hit = dict[prefix], let range = src.range(of: prefix) {
                return src.replacingCharacters(in: range, with: hit)
            }
        }
        return src
    }

    /// 命中才回值（含與源串恆等的命中），未命中回 nil：
    /// translate 的 Optional 核心，供覆寫層區分「覆寫為
    /// 恆等譯文」與「無覆寫條目」。
    private static func translateHit(_ source: String, dict: [String: String],
                                     prefixes: [String]) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let hit = dict[trimmed], let range = source.range(of: trimmed) {
            return source.replacingCharacters(in: range, with: hit)
        }
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            if let hit = dict[prefix], let range = source.range(of: prefix) {
                return source.replacingCharacters(in: range, with: hit)
            }
        }
        return nil
    }

    /// 主查表：源串（zh-CN）→ 目前語言渲染。zh-CN 恆回源串。
    static func t(_ source: String) -> String {
        _ = didLoad
        return lock.withLock { tables in
            let lang = tables.language
            guard lang != .zhCN, let key = langKey(lang) else { return source }
            // supplement 先行（覆寫層，見檔頭查表順序註）。
            // 【全邏輯複查・低】判準改「有命中」而非「結果
            // ≠ 源串」：舊版以值比較判覆寫，譯文恰與源串
            // 恆等的覆寫條目（現存 34 條、與 dict 零衝突
            // 故當時輸出正確）會穿透到 dict——機制上覆寫
            // 失效。改以命中與否為準，恆等覆寫亦生效。
            if let fromSupplement = translateHit(
                source, dict: tables.supplement[key] ?? [:],
                prefixes: tables.prefixes) {
                return fromSupplement
            }
            return translate(source, dict: tables.dict[key] ?? [:],
                             prefixes: tables.prefixes)
        }
    }

    /// 字典／supplement 是否有此源串的任一語言渲染（供自審與
    /// 診斷；運行期不依賴）。
    static func hasEntry(_ source: String, for lang: AppLanguage) -> Bool {
        _ = didLoad
        guard let key = langKey(lang) else { return lang == .zhCN }
        return lock.withLock {
            ($0.dict[key]?[source] != nil) || ($0.supplement[key]?[source] != nil)
        }
    }

    /// zh-TW 渲染值 → 目前語言（母本 normI18nSrc＋tStr 的合成）：
    /// 先反查回簡體源串（查無保留原值），再走 t()。供 instruments
    /// .json 的 name／categoryLabel／refTarget label／分類名使用。
    /// 複合標籤（"WOODWIND · 西洋木管"）比照母本抽取期的處理：
    /// 全串先查、未中以 " · " 分段各查再拼回。
    static func localizedName(_ zhTWRendered: String) -> String {
        _ = didLoad
        let source = lock.withLock { tables -> String in
            if let hit = tables.twToSource[zhTWRendered] { return hit }
            let parts = zhTWRendered.components(separatedBy: " · ")
            if parts.count == 2 {
                let mapped = parts.map { tables.twToSource[$0] ?? $0 }
                return mapped.joined(separator: " · ")
            }
            return zhTWRendered
        }
        return t(source)
    }

    /// 母本 headerInstLabel（行 8153）：en → 英文名 alone；
    /// zh 兩語 → 本地化名 · 英文名；其餘語言 → 本地化名 alone
    /// （雙語尾巴會把頂行標籤擠到省略，母本註解明言）。
    static func headerInstrumentLabel(name zhTWName: String, englishName: String) -> String {
        switch currentLanguage {
        case .en:
            return englishName
        case .zhTW, .zhCN:
            return "\(localizedName(zhTWName)) · \(englishName)"
        default:
            return localizedName(zhTWName)
        }
    }

    private static func langKey(_ lang: AppLanguage) -> String? {
        lang == .zhCN ? nil : lang.rawValue
    }
}

/// localization.json 的頂層形狀（與 extract-i18n.mjs 輸出同構）。
private struct LocalizationFile: Decodable {
    var version: Int
    var sourceLanguage: String
    var defaultLanguage: String
    var languages: [String]
    var prefixes: [String]
    var dict: [String: [String: String]]
    var supplement: [String: [String: String]]?
}
