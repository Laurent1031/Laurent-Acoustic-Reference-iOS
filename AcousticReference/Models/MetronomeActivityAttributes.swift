import ActivityKit
import Foundation

/// 節拍器 Live Activity 的屬性與內容狀態（階段 6）：本檔同
/// 時編入 App 與 AcousticWidgets 擴展兩 target——App 側由
/// MetronomeLiveActivityController 建立／更新／結束活動，
/// 擴展側由 ActivityConfiguration 渲染鎖屏與靈動島。
///
/// 全部動態量（BPM、拍號、目前拍）放 ContentState：屬性本身
/// 在活動建立後不可變，拍號等運行中可改的量不得放屬性層。
struct MetronomeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var bpm: Int
        /// 拍號字串（如 "4/4"）。
        var timeSignature: String
        /// 目前拍（1 起；預備拍期間為預備拍序）。
        var beat: Int
        /// 本小節拍數（拍點圓點列長度）。
        var beatsInBar: Int
        /// 預備拍期間（靈動島／鎖屏以琥珀語義區分，渲染側處理）。
        var isCountIn: Bool
        /// 【邏輯補查】標籤字串由 App 側以 L10n 組裝（擴展
        /// 無查表能力）：舊版擴展側寫死簡體中文，非中文
        /// 語言下鎖屏/靈動島恆顯示中文。預設值＝源串，
        /// App 側組裝時恆覆寫。
        var titleText: String = "节拍器"
        var countInText: String = "预备拍"
        /// 「第 N 拍」整串（App 側按語言格式組裝）。
        var beatText: String = ""
        /// 速度詞（GRAVE／LARGO／…，返修批13 靈動島優
        /// 化）：App 側以 MetronomeSettings.tempoTerm 組
        /// 裝隨狀態下發，靈動島展開態與鎖屏面顯示。
        var tempoText: String = ""
    }

    /// 音色顯示名（建立時定格；運行中改音色不重建活動——
    /// 音色非活動的身份資訊，鎖屏不顯示，僅備日後擴充）。
    var timbreName: String = ""
}
