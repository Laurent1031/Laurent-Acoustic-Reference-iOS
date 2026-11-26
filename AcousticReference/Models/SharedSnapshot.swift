import Foundation

/// App ↔ 小組件共享快照（階段 6）：App 於狀態落盤時把小組件
/// 需要的顯示資料（已本地化字串）寫入 App Group 的
/// UserDefaults，AcousticWidgets 擴展只讀不算——顯示文字一律
/// 由 App 依目前語言組裝，擴展側不持有字典，語言切換後下一次
/// 落盤即同步（AppStore.persist 為唯一寫入點，內容未變不重寫、
/// 不重刷 timeline）。
///
/// App Group 不可用時（側載重簽剝除 group 等）UserDefaults
/// (suiteName:) 為 nil：寫入靜默跳過、讀取回 placeholder，
/// App 與小組件各自照常運行（降級而非故障）。
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// 目前樂器顯示名（App 側經 L10n.localizedName 組裝）。
    var instrumentName: String
    /// 調號標籤（母本 keyLabel，如 "1 = E♭"）。
    var instrumentKey: String
    /// A4 讀數（如 "A4 442"／"A4 442.5"）。
    var a4Text: String
    /// 收藏樂器顯示名（上限 4 個，供 medium 尺寸列）。
    var favoriteNames: [String]
    /// 節拍器 BPM（store 現行值：最後使用值，與 App 內啟動
    /// 播種收斂一致）。
    var bpm: Int
    /// 拍號字串（如 "4/4"，MetronomeSettings.currentSignatureKey）。
    var timeSignature: String
    /// 節拍器音色顯示名（App 側經 L10n 組裝）。
    var timbreName: String
    /// 小組件靜態標籤（App 側依目前語言組裝）。
    var tunerLabel: String
    var metronomeLabel: String

    /// 無快照時的佔位（首次安裝、擴展先於 App 啟動被系統
    /// 載入等）：以母本出廠預設組裝（中音薩克斯／442／120 BPM
    /// 4/4 木魚），與 App 首啟畫面一致。
    static let placeholder = WidgetSnapshot(
        instrumentName: "中音薩克斯",
        instrumentKey: "1 = E♭",
        a4Text: "A4 442",
        favoriteNames: ["中音薩克斯", "交響鋼琴", "小提琴"],
        bpm: 120,
        timeSignature: "4/4",
        timbreName: "樂團木魚",
        tunerLabel: "調音",
        metronomeLabel: "節拍")
}

enum SharedStore {
    static let appGroupID = "group.com.laurent.acousticreference"
    private static let snapshotKey = "widgetSnapshot.v1"

    static func read() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return decoded
    }

    /// App 側寫入（擴展不呼叫）。
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}
