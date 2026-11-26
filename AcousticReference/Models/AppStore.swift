import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// App 模式（母本 state.mode 的 tuner/metro 子集）。階段 3 時以
/// ContentView 的 UserDefaults 佔位鍵保存，階段 4 起歸 AppStore
/// 統一落盤（遷移見 AppStore.migratedSnapshot）。
enum AppMode: String, Codable, Sendable {
    case tuner
    case metronome
    /// 同屏（母本 mode "dual"，頂欄 btnModeDual，行 5209）：
    /// 調音與節拍器雙面板同時在場（各自緊湊形態）。階段 7
    /// 驗收審計發現前段漏項、就地補齊（DualModeView）；rawValue
    /// 與母本 settings.mode 的 "dual" 一致，備份匯入直通。
    case dual
}

/// 主顯示音名模式（母本 profile.pitchMode，行 6223）：written 記譜／
/// concert 實音；母本預設 "written"。
enum PitchMode: String, Codable, Sendable {
    case written
    case concert
}

/// 調音主顯示模式（頻閃主模式段，Laurent 2026-11-26 定版）：
/// strobe 頻閃為預設主模式、needle 錶盤指針為輔助；母本無此
/// 概念（母本只有錶盤），屬原生版新增的顯示層偏好，不影響
/// 檢測與判準。state-v1 缺此欄時預設 strobe。
enum TunerDisplayMode: String, Codable, Sendable {
    case strobe
    case needle
}

/// 外觀主題偏好（補強段：樂池暗紅為第三態）。母本主題為
/// 深／淺＋隨系統三態（profile.theme），原生版在其上加 .pit
/// 樂池暗紅（近黑底＋暗紅前景、低亮度護夜視，母本無此態）。
/// 正式選擇 UI 屬階段 5 設定頁；本段先打通主題值與全 App
/// 渲染，過渡期經診斷頁的外觀 Picker 可達。缺欄預設 .system
/// （與母本「主題隨系統」預設一致）。
enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
    /// 樂池暗紅：系統層強制深色（材質／選單／彈窗走深色渲染），
    /// 品牌 token 改走 TunerTheme 的 pit 調色盤。
    case pit
    /// 自訂背景（裝機返修批補齊，母本 themeMode=custom）：
    /// 純色漸層或自選圖片作頁面背景，淺／深 token 由背景
    /// 亮度自動判定（母本 hexLuminance／圖片亮度分析同義）。
    /// 系統層 forcedColorScheme 須隨判定走，故根視圖改用
    /// AppStore.effectiveForcedColorScheme，本屬性對 custom
    /// 回 nil（不干預）僅作保底。
    case custom

    /// 套到根視圖的 preferredColorScheme（system 為 nil＝不干預）。
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .system, .custom: return nil
        case .light: return .light
        case .dark, .pit: return .dark
        }
    }

    /// 顯示名走 L10n（階段 5）：system／pit 為原生專屬字串
    /// （supplement），light／dark 為母本字典鍵。
    var displayName: String {
        switch self {
        case .system: return L10n.t("跟随系统")
        case .light: return L10n.t("浅色")
        case .dark: return L10n.t("深色")
        case .pit: return L10n.t("乐池暗红")
        case .custom: return L10n.t("自定义")
        }
    }
}

/// 收藏切換結果（母本 toggleFavoriteInstrument，行 6769）：
/// 加入／移除／因「至少保留 1 個」被拒。
enum FavoriteToggleOutcome: Sendable {
    case added
    case removed
    case rejectedMinimum
}

/// 落盤快照（state-v1.json 的形狀）。逐欄 decodeIfPresent＋預設值：
/// 任一欄缺失或型別漂移只退回該欄預設，不整份丟棄。
private struct AppStateFile: Codable {
    var version: Int = 1
    var tunerSettings: TunerSettings = TunerSettings()
    var pitchMode: PitchMode = .written
    var selectedInstrumentId: String = "alto_sax"
    var favoriteInstrumentIds: [String] = ["alto_sax", "piano", "violin"]
    var customInstruments: [Instrument] = []
    var droneTimbre: DroneTimbre = .oboe
    var droneFollow: Bool = false
    var metronomeSettings: MetronomeSettings = MetronomeSettings()
    var metronomeUserPresets: [MetronomePreset] = []
    var appMode: String = AppMode.tuner.rawValue
    var guzhengFavMigrationDone: Bool = false
    var tunerDisplayMode: TunerDisplayMode = .strobe
    var themePreference: AppTheme = .system
    // 階段 5 新增欄（缺欄退母本預設，舊檔無痛遷移）：
    /// 顯示語言（母本 state.lang，預設 zh-TW）。
    var language: AppLanguage = .zhTW
    /// 玻璃不透明度（母本 state.glassAlpha，8–96、預設 50）。
    var glassOpacity: Int = 50
    /// 預設啟動主樂器（母本 profile.primaryInstId）：舊檔缺欄時
    /// 以當時 selectedInstrumentId 為遷移預設（見 AppStore.init
    /// 的遷移註記），不改變既有啟動選中行為。
    var primaryInstrumentId: String = "alto_sax"
    /// 自動開啟麥克風（母本 profile.autoMicOnEnter，預設 false）。
    var autoMicOnEnter: Bool = false
    /// 節拍器預設參數（母本 profile 的 defaultBpm 等五欄的整體
    /// 快照）：nil = 用戶未按過「設為默認」，啟動沿用上次值。
    var metronomeDefault: MetronomeSettings? = nil
    // 裝機返修批新增欄（自訂背景，母本 profile 三欄同名同義；
    // 缺欄退空值，舊檔無痛遷移）：
    /// 背景種類：""／"color"／"image"（母本 bgKind 原值）。
    var bgKind: String = ""
    /// 純色背景色票（母本 bgColor，#RRGGBB；"" = 未設）。
    var bgColor: String = ""
    /// 自選背景圖（母本 customBgDataUrl 的原生形：圖片 Data；
    /// 選圖時已縮放至長邊 ≤1600 並轉 JPEG，落盤體積可控）。
    var customBgData: Data? = nil

    private enum CodingKeys: String, CodingKey {
        case version, tunerSettings, pitchMode, selectedInstrumentId
        case favoriteInstrumentIds, customInstruments, droneTimbre
        case droneFollow, metronomeSettings, metronomeUserPresets
        case appMode, guzhengFavMigrationDone, tunerDisplayMode
        case themePreference
        case language, glassOpacity, primaryInstrumentId
        case autoMicOnEnter, metronomeDefault
        case bgKind, bgColor, customBgData
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tunerSettings = try c.decodeIfPresent(TunerSettings.self, forKey: .tunerSettings) ?? TunerSettings()
        pitchMode = try c.decodeIfPresent(PitchMode.self, forKey: .pitchMode) ?? .written
        selectedInstrumentId = try c.decodeIfPresent(String.self, forKey: .selectedInstrumentId) ?? "alto_sax"
        favoriteInstrumentIds = try c.decodeIfPresent([String].self, forKey: .favoriteInstrumentIds)
            ?? ["alto_sax", "piano", "violin"]
        customInstruments = try c.decodeIfPresent([Instrument].self, forKey: .customInstruments) ?? []
        droneTimbre = try c.decodeIfPresent(DroneTimbre.self, forKey: .droneTimbre) ?? .oboe
        droneFollow = try c.decodeIfPresent(Bool.self, forKey: .droneFollow) ?? false
        metronomeSettings = try c.decodeIfPresent(MetronomeSettings.self, forKey: .metronomeSettings)
            ?? MetronomeSettings()
        metronomeUserPresets = try c.decodeIfPresent([MetronomePreset].self, forKey: .metronomeUserPresets) ?? []
        appMode = try c.decodeIfPresent(String.self, forKey: .appMode) ?? AppMode.tuner.rawValue
        guzhengFavMigrationDone = try c.decodeIfPresent(Bool.self, forKey: .guzhengFavMigrationDone) ?? false
        tunerDisplayMode = try c.decodeIfPresent(TunerDisplayMode.self, forKey: .tunerDisplayMode) ?? .strobe
        themePreference = try c.decodeIfPresent(AppTheme.self, forKey: .themePreference) ?? .system
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhTW
        glassOpacity = min(96, max(8, try c.decodeIfPresent(Int.self, forKey: .glassOpacity) ?? 50))
        primaryInstrumentId = try c.decodeIfPresent(String.self, forKey: .primaryInstrumentId)
            ?? selectedInstrumentId
        autoMicOnEnter = try c.decodeIfPresent(Bool.self, forKey: .autoMicOnEnter) ?? false
        metronomeDefault = try c.decodeIfPresent(MetronomeSettings.self, forKey: .metronomeDefault)
        bgKind = try c.decodeIfPresent(String.self, forKey: .bgKind) ?? ""
        bgColor = try c.decodeIfPresent(String.self, forKey: .bgColor) ?? ""
        customBgData = try c.decodeIfPresent(Data.self, forKey: .customBgData)
    }
}

/// 單一持久化數據層（規格書階段 4）：設定、收藏、自訂樂器、Drone
/// 偏好、節拍器設定與自訂預置、App 模式，統一由此管理與落盤，
/// 取代階段 3 的 MetronomeStore 佔位與 ContentView 的 mode 佔位鍵。
///
/// 落盤格式：Application Support/AcousticReference/state-v1.json，
/// 單一 JSON 文件（AppStateFile，version 1），變更即存（原子寫入
/// .atomic），啟動同步載入。寫入頻率與母本 localStorage 同步存檔
/// 同級（每次狀態變更一次小檔寫入）。
///
/// 隔離設計：@MainActor 單例式 store，所有 @Published 變更只在主
/// 線程發生；落盤為同步小檔 I/O（數 KB），不引入背景佇列與跨域
/// 傳遞。引擎側（AudioEngine／MetronomeEngine／DroneEngine）不直接
/// 持有 store，由 ContentView 以 onChange 單向同步（store 為唯一
/// 真源），避免循環依賴與雙寫。
@MainActor
final class AppStore: ObservableObject {
    // MARK: - 落盤狀態（didSet 即存）

    @Published var tunerSettings = TunerSettings() { didSet { persist() } }
    @Published var pitchMode: PitchMode = .written { didSet { persist() } }
    @Published var selectedInstrumentId = "alto_sax" { didSet { persist() } }
    @Published var favoriteInstrumentIds: [String] = [] { didSet { persist() } }
    @Published var customInstruments: [Instrument] = [] { didSet { persist() } }
    @Published var droneTimbre: DroneTimbre = .oboe { didSet { persist() } }
    @Published var droneFollow = false { didSet { persist() } }
    @Published var metronomeSettings = MetronomeSettings() { didSet { persist() } }
    @Published var metronomeUserPresets: [MetronomePreset] = [] { didSet { persist() } }
    @Published var appMode: AppMode = .tuner { didSet { persist() } }
    /// 調音主顯示模式（頻閃／指針）：純顯示偏好，引擎不感知。
    @Published var tunerDisplayMode: TunerDisplayMode = .strobe { didSet { persist() } }
    /// 外觀主題偏好（補強段）：system／light／dark／pit 四態。
    @Published var themePreference: AppTheme = .system { didSet { persist() } }
    /// 顯示語言（階段 5）：唯一真源；ContentView 的 onChange
    /// 單向同步進 L10n 服務（init 內另有一次同步，保證首幀正確）。
    @Published var language: AppLanguage = .zhTW { didSet { persist() } }
    /// 玻璃不透明度（階段 5）：8–96、預設 50；didSet 鉗制並落盤，
    /// 全 App 玻璃材質經 GlassBackground 修飾器讀此值。
    @Published var glassOpacity: Int = 50 {
        didSet {
            let clamped = min(96, max(8, glassOpacity))
            if clamped != glassOpacity { glassOpacity = clamped }
            persist()
        }
    }
    /// 預設啟動主樂器（階段 5，母本 profile.primaryInstId）：
    /// 變更入口為 setPrimaryInstrument（連動選樂器與收藏）。
    @Published var primaryInstrumentId = "alto_sax" { didSet { persist() } }
    /// 自動開啟麥克風（階段 5，母本 profile.autoMicOnEnter）。
    @Published var autoMicOnEnter = false { didSet { persist() } }
    /// 節拍器預設參數快照（階段 5）：nil = 未設定（啟動沿用
    /// 上次值）；非 nil 時 ContentView 啟動以此播種 ViewModel
    /// （對齊母本啟動套用 profile 默認的語義）。
    @Published var metronomeDefault: MetronomeSettings? = nil { didSet { persist() } }
    /// 自訂背景三欄（裝機返修批，母本 bgKind／bgColor／
    /// customBgDataUrl）：bgKind 為 ""／"color"／"image"；
    /// 僅 themePreference == .custom 時生效（母本同：背景
    /// 只在 custom 模式渲染，其他模式保留值不顯示）。
    @Published var bgKind: String = "" { didSet { persist() } }
    @Published var bgColorHex: String = "" { didSet { persist() } }
    @Published var customBgData: Data? = nil { didSet { persist() } }

    /// 待確認的備份匯入計劃（階段 8）：檔案選取／分享表單入的
    /// 備份先組裝成 plan 掛在此處，ContentView 以 sheet 呈現
    /// 確認畫面，用戶按下匯入才 applyImport；不落盤（AppStateFile
    /// 不含此欄，persist 的顯式組裝天然不寫它）。
    @Published var pendingImportPlan: BackupImporter.ImportPlan?

    /// 選樂器脈衝：每次 selectInstrument 呼叫 +1（含同名重選——
    /// 母本 selectInstrument 連重選也清鎖定與軌跡，行 8485）。
    /// TunerViewModel 訂閱此脈衝執行選樂器副作用；不落盤。
    @Published private(set) var selectionPulse = 0

    /// 選樂器入口（母本 selectInstrument）：設定選中 id 並發脈衝。
    func selectInstrument(id: String) {
        selectedInstrumentId = id
        selectionPulse += 1
    }

    /// 設定預設啟動主樂器（母本偏好頁主樂器 select 的 handler，
    /// 行 6949）：寫入 primary、即選中該樂器、未收藏則插入
    /// 收藏首位。偏好頁以交易式草稿操作，「完成」時才呼叫此
    /// 入口（母本為即時套用＋取消回滾，淨效果相同、時機差異
    /// 見階段 5 報告）。
    func setPrimaryInstrument(id: String) {
        primaryInstrumentId = id
        selectInstrument(id: id)
        if !favoriteInstrumentIds.contains(id) {
            favoriteInstrumentIds.insert(id, at: 0)
        }
    }

    /// 將目前節拍器參數設為預設（母本 btnSaveCurrentMetroAsDefault）：
    /// 存整份設定快照（countIn 本就不落盤，Codable 已排除）。
    func setMetronomeDefault(_ settings: MetronomeSettings) {
        metronomeDefault = settings
    }

    /// 偏好頁摘要（母本 profMetroSummaryText）：「默认：」前綴
    /// （字典前綴鍵）＋ BPM · 拍號 · 音色本地化名。有預設顯示
    /// 預設值、無預設顯示出廠默認（120 · 4/4 · 木魚）——母本
    /// 摘要恆顯示 profile 現值，原生以 metronomeDefault ??
    /// 出廠值等價呈現。static 版供設定頁草稿摘要共用。
    static func metroSummaryText(for settings: MetronomeSettings?) -> String {
        let s = settings ?? MetronomeSettings()
        return L10n.t("默认：") + "\(s.bpm) BPM · \(s.beatsPerBar)/\(s.beatUnit) · "
            + L10n.t(s.timbre.sourceName)
    }

    var metronomeDefaultSummary: String {
        Self.metroSummaryText(for: metronomeDefault)
    }

    // MARK: - 自訂背景（裝機返修批，母本 themeMode=custom）

    /// 目前背景 payload（僅 .custom 模式由 resolvedTheme 採用）。
    var customBackgroundPayload: TunerTheme.CustomBackground? {
        switch bgKind {
        case "color":
            guard let hex = Self.parseHexColor(bgColorHex) else { return nil }
            return .color(hex)
        case "image":
            guard let customBgData else { return nil }
            return .image(customBgData)
        default:
            return nil
        }
    }

    /// 背景亮度判定（母本：色彩 hexLuminance > 0.62 → 淺；
    /// 圖片走亮度分析）。無背景可判時回深色側（保守，與
    /// 母本 custom 未設背景的深色底一致）。
    var customBackgroundIsLight: Bool {
        switch bgKind {
        case "color":
            guard let hex = Self.parseHexColor(bgColorHex) else { return false }
            return Self.hexLuminance(hex) > 0.62
        case "image":
            guard let customBgData,
                  let lum = Self.imageLuminance(customBgData) else { return false }
            return lum > 0.62
        default:
            return false
        }
    }

    /// 根視圖 preferredColorScheme：custom 時隨背景判定，
    /// 其餘沿 AppTheme.forcedColorScheme。
    var effectiveForcedColorScheme: ColorScheme? {
        if themePreference == .custom {
            return customBackgroundIsLight ? .light : .dark
        }
        return themePreference.forcedColorScheme
    }

    /// 全 App 主題解析唯一入口（各頁 body 呼叫，取代散列的
    /// TunerTheme.resolve(preference:system:) 直呼）。
    func resolvedTheme(system: ColorScheme) -> TunerTheme {
        TunerTheme.resolve(preference: themePreference, system: system,
                           customBackground: customBackgroundPayload,
                           customIsLight: customBackgroundIsLight)
    }

    /// 設定純色背景並切到自訂模式（母本在 custom 模式內
    /// 操作背景；原生入口自動切換，免用戶找不到開關）。
    func setCustomBackgroundColor(_ hex: String) {
        bgColorHex = hex
        bgKind = "color"
        themePreference = .custom
    }

    /// 設定圖片背景並切到自訂模式（data 須已縮放編碼，
    /// 由設定頁選圖流程負責）。
    func setCustomBackgroundImage(_ data: Data) {
        customBgData = data
        bgKind = "image"
        themePreference = .custom
    }

    func clearCustomBackground() {
        bgKind = ""
        bgColorHex = ""
        customBgData = nil
    }

    /// 純函數（字串→色值），供 nonisolated 的匯入器呼叫，
    /// 故標 nonisolated（CI run #27 實證：否則隔離錯誤）。
    nonisolated static func parseHexColor(_ string: String) -> UInt32? {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return value
    }

    /// 母本 hexLuminance 同式（線性加權）。
    static func hexLuminance(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF)
        let g = Double((hex >> 8) & 0xFF)
        let b = Double(hex & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    }

    /// 圖片平均亮度：縮繪至 16×16 後逐像素同式加權平均。
    static func imageLuminance(_ data: Data) -> Double? {
        guard let image = UIImage(data: data), let cg = image.cgImage
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        guard let ctx = CGContext(
            data: &pixels, width: 16, height: 16, bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.2126 * Double(pixels[i])
                 + 0.7152 * Double(pixels[i + 1])
                 + 0.0722 * Double(pixels[i + 2])
        }
        return sum / Double(16 * 16) / 255
    }

    // MARK: - 僅執行期狀態（母本 state 層，不落盤）

    /// 古箏調號（母本 state.guzhengKey，預設 "D"；母本不入 profile，
    /// 重開即回 D，原生版同）。
    @Published var guzhengKey = "D"

    /// 演奏態附加模式（補強段採納，母本無）：調音頁開關——開啟
    /// 時隱藏輔助列（收藏／A4／目標音／Drone）、主顯示區放大。
    /// 純顯示層的執行期開關，不落盤（重開 App 回預設版面，
    /// 與防誤觸鎖同取捨：避免重啟後停在非預設版面造成困惑）。
    @Published var performanceMode = false

    private var guzhengFavMigrationDone = false
    private var loading = true

    // MARK: - 檔案位置

    static var stateFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AcousticReference/state-v1.json")
    }

    // MARK: - 載入與遷移

    init() {
        let snapshot: AppStateFile
        if let loaded = Self.loadStateFile() {
            snapshot = loaded
        } else {
            snapshot = Self.migratedSnapshot()
        }
        tunerSettings = snapshot.tunerSettings
        pitchMode = snapshot.pitchMode
        customInstruments = snapshot.customInstruments
        droneTimbre = snapshot.droneTimbre
        droneFollow = snapshot.droneFollow
        metronomeSettings = snapshot.metronomeSettings
        metronomeUserPresets = snapshot.metronomeUserPresets
        appMode = AppMode(rawValue: snapshot.appMode) ?? .tuner
        tunerDisplayMode = snapshot.tunerDisplayMode
        themePreference = snapshot.themePreference
        language = snapshot.language
        glassOpacity = snapshot.glassOpacity
        primaryInstrumentId = snapshot.primaryInstrumentId
        autoMicOnEnter = snapshot.autoMicOnEnter
        metronomeDefault = snapshot.metronomeDefault
        bgKind = snapshot.bgKind
        bgColorHex = snapshot.bgColor
        customBgData = snapshot.customBgData
        guzhengFavMigrationDone = snapshot.guzhengFavMigrationDone
        // 首幀前同步語言進 L10n（其後由 ContentView onChange 維護）。
        L10n.setLanguage(snapshot.language)

        // 收藏／選中樂器健全化：剔除無法解析的 id；收藏為空時回母本
        // 預設 [INSTRUMENTS[0], piano, violin]（createDefaultProfile）。
        var favorites = snapshot.favoriteInstrumentIds.filter { instrument(id: $0) != nil }
        if favorites.isEmpty {
            favorites = ["alto_sax", "piano", "violin"].filter { instrument(id: $0) != nil }
        }
        favoriteInstrumentIds = favorites
        selectedInstrumentId = instrument(id: snapshot.selectedInstrumentId) != nil
            ? snapshot.selectedInstrumentId
            : InstrumentCatalog.builtins[0].id
        // 主樂器健全化：指向已刪除的自訂樂器時退回目前選中樂器。
        if instrument(id: primaryInstrumentId) == nil {
            primaryInstrumentId = selectedInstrumentId
        }

        // 古箏收藏遷移（母本行 6550，旗標 laurent_fav_guzheng_removed_v1）：
        // 未遷移過且收藏 >1 且含古箏 → 移除一次；其後手動加回保留。
        if !guzhengFavMigrationDone {
            if favoriteInstrumentIds.count > 1,
               favoriteInstrumentIds.contains("guzheng") {
                favoriteInstrumentIds.removeAll { $0 == "guzheng" }
            }
            guzhengFavMigrationDone = true
        }

        loading = false
        persist()
    }

    private static func loadStateFile() -> AppStateFile? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let decoded = try? JSONDecoder().decode(AppStateFile.self, from: data)
        else { return nil }
        return decoded
    }

    /// 階段 3 佔位鍵遷移：MetronomeStore 的兩個 UserDefaults 鍵與
    /// ContentView 的 mode 鍵。遷移後刪除舊鍵，僅執行一次（state
    /// 文件存在後不再走此路徑）。節拍器設定／自訂預置以原 Codable
    /// 形狀直讀，內容零轉換、零遺失。
    private static func migratedSnapshot() -> AppStateFile {
        var snapshot = AppStateFile()
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "laurent.metro.settings.v1"),
           let settings = try? decoder.decode(MetronomeSettings.self, from: data) {
            snapshot.metronomeSettings = settings
        }
        if let data = defaults.data(forKey: "laurent.metro.userPresets.v1"),
           let presets = try? decoder.decode([MetronomePreset].self, from: data) {
            snapshot.metronomeUserPresets = presets
        }
        if let mode = defaults.string(forKey: "laurent.app.mode") {
            snapshot.appMode = mode
        }
        defaults.removeObject(forKey: "laurent.metro.settings.v1")
        defaults.removeObject(forKey: "laurent.metro.userPresets.v1")
        defaults.removeObject(forKey: "laurent.app.mode")
        return snapshot
    }

    private func persist() {
        guard !loading else { return }
        var snapshot = AppStateFile()
        snapshot.tunerSettings = tunerSettings
        snapshot.pitchMode = pitchMode
        snapshot.selectedInstrumentId = selectedInstrumentId
        snapshot.favoriteInstrumentIds = favoriteInstrumentIds
        snapshot.customInstruments = customInstruments
        snapshot.droneTimbre = droneTimbre
        snapshot.droneFollow = droneFollow
        snapshot.metronomeSettings = metronomeSettings
        snapshot.metronomeUserPresets = metronomeUserPresets
        snapshot.appMode = appMode.rawValue
        snapshot.guzhengFavMigrationDone = guzhengFavMigrationDone
        snapshot.tunerDisplayMode = tunerDisplayMode
        snapshot.themePreference = themePreference
        snapshot.language = language
        snapshot.glassOpacity = glassOpacity
        snapshot.primaryInstrumentId = primaryInstrumentId
        snapshot.autoMicOnEnter = autoMicOnEnter
        snapshot.metronomeDefault = metronomeDefault
        snapshot.bgKind = bgKind
        snapshot.bgColor = bgColorHex
        snapshot.customBgData = customBgData
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = Self.stateFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
        publishWidgetSnapshot()
    }

    // MARK: - 小組件快照（階段 6）

    /// 上次發布的快照（內容未變不重寫、不刷 timeline——
    /// persist 觸發頻率高，快照相關欄位只是其中一小子集）。
    private var lastPublishedSnapshot: WidgetSnapshot?

    /// 自現行狀態組裝快照：顯示字串一律在此依目前語言
    /// 本地化（擴展側不持有字典）；節拍器值取 store 現行
    /// metronomeSettings（ViewModel 變更經防抖回存，與 App
    /// 內顯示收斂一致）。
    private func makeWidgetSnapshot() -> WidgetSnapshot {
        let inst = selectedInstrument
        let a4 = tunerSettings.a4
        let a4Text = a4 == a4.rounded()
            ? "A4 \(Int(a4))"
            : String(format: "A4 %.1f", a4)
        return WidgetSnapshot(
            instrumentName: L10n.localizedName(inst.name),
            instrumentKey: keyLabel(of: inst),
            a4Text: a4Text,
            favoriteNames: favoriteInstrumentIds.prefix(4).compactMap { id in
                instrument(id: id).map { L10n.localizedName($0.name) }
            },
            bpm: metronomeSettings.bpm,
            timeSignature: metronomeSettings.currentSignatureKey,
            timbreName: L10n.t(metronomeSettings.timbre.sourceName),
            tunerLabel: L10n.t("调音"),
            metronomeLabel: L10n.t("节拍"))
    }

    private func publishWidgetSnapshot() {
        let snapshot = makeWidgetSnapshot()
        guard snapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snapshot
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 目錄解析

    /// 母本 allInstruments()：內建（目錄序）＋自訂（新增序）。
    var allInstruments: [Instrument] {
        InstrumentCatalog.builtins + customInstruments
    }

    func instrument(id: String) -> Instrument? {
        customInstruments.first { $0.id == id } ?? InstrumentCatalog.builtin(id: id)
    }

    var selectedInstrument: Instrument {
        instrument(id: selectedInstrumentId) ?? InstrumentCatalog.builtins[0]
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteInstrumentIds.contains(id)
    }

    /// 有效移調：古箏隨目前調號（母本行 8615，選調即改寫
    /// currentInst.trans = GUZHENG_KEY_SEMITONES[key]）。
    func effectiveTransposition(of inst: Instrument) -> Int {
        if inst.isGuzheng {
            return InstrumentCatalog.guzhengKeySemitones[guzhengKey] ?? inst.transposition
        }
        return inst.transposition
    }

    /// 選中樂器的有效檢測音域（供 AudioEngine.range）。
    var effectiveRange: InstrumentRange {
        let inst = selectedInstrument
        return InstrumentRange(
            id: inst.id,
            transposition: effectiveTransposition(of: inst),
            minFrequency: inst.minFrequency,
            maxFrequency: inst.maxFrequency)
    }

    /// 頂行調號標籤（母本行 8498）：古箏顯示目前調號，其餘 keyName。
    func keyLabel(of inst: Instrument) -> String {
        inst.isGuzheng ? "1 = \(guzhengKey)" : inst.keyName
    }

    // MARK: - 收藏（母本 toggleFavoriteInstrument，行 6769）

    @discardableResult
    func toggleFavorite(id: String) -> FavoriteToggleOutcome {
        if favoriteInstrumentIds.contains(id) {
            guard favoriteInstrumentIds.count > 1 else { return .rejectedMinimum }
            favoriteInstrumentIds.removeAll { $0 == id }
            return .removed
        }
        favoriteInstrumentIds.append(id)
        return .added
    }

    /// 收藏步進切換（母本 stepFavoriteInstrument，行 6837，階段 4
    /// 遺留補完）：dir +1 下一個／−1 上一個，環繞；收藏 <2 不動作；
    /// 目前樂器不在收藏中時，+1 自第一個起、−1 自最後一個起
    /// （母本 idx 缺省：dir>0 → −1、dir≤0 → 0，再加 dir 取模）。
    /// 經 selectInstrument 走完整選樂器路徑（清鎖定等副作用）。
    func stepFavoriteInstrument(dir: Int) {
        let favs = favoriteInstrumentIds.filter { instrument(id: $0) != nil }
        guard favs.count >= 2, dir != 0 else { return }
        let step = dir > 0 ? 1 : -1
        var idx = favs.firstIndex(of: selectedInstrumentId)
        if idx == nil { idx = step > 0 ? -1 : 0 }
        let next = favs[(idx! + step + favs.count) % favs.count]
        selectInstrument(id: next)
    }

    /// 收藏拖曳排序提交（母本 wireFavChipDrag 的 drop 提交，
    /// 行 6704）：新序必須是現有收藏的同一集合（防手勢狀態
    /// 漂移寫入異物），不同則忽略；相同不觸發落盤。
    func reorderFavorites(_ newOrder: [String]) {
        guard newOrder.count == favoriteInstrumentIds.count,
              Set(newOrder) == Set(favoriteInstrumentIds),
              newOrder != favoriteInstrumentIds
        else { return }
        favoriteInstrumentIds = newOrder
    }

    // MARK: - 自訂樂器（母本保存處理，行 7836）

    /// 新增或更新一筆自訂樂器，回傳保存後的樂器。換算逐項對照
    /// 母本：en 空 → "Custom"；keyName 空 → `1 = ${NOTE_NAMES[trans 的 pc]}`；
    /// minF = max(20, freqOf440(low)×0.85)、maxF = freqOf440(high)×1.15；
    /// catLabel 恆 "CUSTOM · 自訂樂器"；新 id = `custom_${毫秒時間戳}`。
    @discardableResult
    func saveCustomInstrument(
        editingId: String?, name: String, englishName: String, keyName: String,
        transposition: Int, category: InstrumentCategory,
        lowMidi: Int, highMidi: Int
    ) -> Instrument {
        let trimmedEn = englishName.trimmingCharacters(in: .whitespaces)
        let trimmedKey = keyName.trimmingCharacters(in: .whitespaces)
        let pc = ((transposition % 12) + 12) % 12
        let inst = Instrument(
            id: editingId ?? "custom_\(Int(Date().timeIntervalSince1970 * 1000))",
            category: category,
            categoryLabel: "CUSTOM · 自訂樂器",
            name: name,
            englishName: trimmedEn.isEmpty ? "Custom" : trimmedEn,
            keyName: trimmedKey.isEmpty ? "1 = \(PitchMath.noteNames[pc])" : trimmedKey,
            transposition: transposition,
            minFrequency: max(20, PitchMath.frequency440(midi: Double(lowMidi)) * 0.85),
            maxFrequency: PitchMath.frequency440(midi: Double(highMidi)) * 1.15,
            refTargets: nil, stringNotes: nil,
            isGuzheng: false, isCustom: true)
        if let editingId, let idx = customInstruments.firstIndex(where: { $0.id == editingId }) {
            customInstruments[idx] = inst
        } else {
            customInstruments.append(inst)
        }
        return inst
    }

    /// 刪除自訂樂器（母本 deleteCustomInstrument，行 7693）：連帶移出
    /// 收藏；若為目前選中樂器，選回 INSTRUMENTS[0]。
    func deleteCustomInstrument(id: String) {
        customInstruments.removeAll { $0.id == id }
        favoriteInstrumentIds.removeAll { $0 == id }
        if selectedInstrumentId == id {
            selectInstrument(id: InstrumentCatalog.builtins[0].id)
        }
    }
}
