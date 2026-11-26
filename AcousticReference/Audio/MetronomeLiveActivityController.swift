import ActivityKit
import Foundation

/// 節拍器 Live Activity 控制器（階段 6）：與 MetronomeEngine
/// 生命週期嚴格同步——ViewModel 的 isPlaying 訂閱呼叫 start／
/// stop、每主拍呼叫 update。ActivityKit 失敗（權限關閉、系統
/// 拒絕）一律吞掉：活動只是系統整合層，絕不反噬音訊主路徑。
///
/// 防殭屍三重：
/// 1. stop() 以 .immediate 結束系統上全部同屬性活動；
/// 2. start() 前先結束系統上全部同屬性活動（上一進程殘留、
///    本控制器遺失引用等），保證同時只存在一個；
/// 3. 每次 request／update 都帶 staleDate（約 2.2 拍後）：App
///    被殺或崩潰後活動先被系統標記為過期（變暗），不再冒充
///    「正在運行」；ContentView 啟動時若節拍器未播放再呼叫
///    endAllActivities() 徹底清除。
///
/// Swift 6 並發修復（階段 7，CI run #23 實證）：原實作把
/// Activity 存於 @MainActor 隔離的可變屬性，update／stop 在
/// 非同步 Task 閉包內讀取該屬性再 await 其方法，編譯器判定
/// "sending 'activity' risks causing data races"（2 處 error）。
/// 修法：不再持有 Activity 引用——start 的「先清後建」不變量
/// 保證同屬性活動同時至多一個，update／stop 每次自
/// Activity.activities 靜態清單現取（與 start 內清殘留、
/// endAllActivities 相同的已驗證模式，值自成獨立 region、
/// 不跨隔離域發送被隔離屬性）。語義不變且更強：stop／update
/// 對「本控制器未持有引用」的同屬性活動（上一進程殘留等）
/// 同樣生效。
@MainActor
final class MetronomeLiveActivityController {
    static let shared = MetronomeLiveActivityController()

    private var lastState: MetronomeActivityAttributes.ContentState?
    /// start 的 Task 句柄：stop 須取消未落定的 request，避免
    /// request 後到反成殭屍（另有 staleDate 兜底，見檔頭）。
    private var startTask: Task<Void, Never>?

    private init() {}

    private func staleDate(for state: MetronomeActivityAttributes.ContentState) -> Date {
        let beatInterval = 60.0 / Double(max(20, state.bpm))
        return Date().addingTimeInterval(max(3, 2.2 * beatInterval))
    }

    func start(state: MetronomeActivityAttributes.ContentState, timbreName: String) {
        lastState = state
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 先清殘留（含上一進程的），再建新活動。
            for existing in Activity<MetronomeActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            guard !Task.isCancelled else { return }
            do {
                _ = try Activity.request(
                    attributes: MetronomeActivityAttributes(timbreName: timbreName),
                    content: ActivityContent(state: state,
                                             staleDate: self.staleDate(for: state)),
                    pushType: nil)
            } catch {
                // 權限或系統拒絕：靜默放棄（檔頭原則）。
            }
        }
    }

    func update(state: MetronomeActivityAttributes.ContentState) {
        guard state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        Task { @MainActor in
            for activity in Activity<MetronomeActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    func stop() {
        lastState = nil
        startTask?.cancel()
        startTask = nil
        Task { @MainActor in
            for activity in Activity<MetronomeActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 啟動清理（ContentView onAppear、節拍器未播放時）：結束
    /// 系統上全部同屬性活動，清上一進程的殘留。
    func endAllActivities() {
        stop()
    }
}
