import ActivityKit
import Foundation

/// 節拍器 Live Activity 控制器（階段 6）：與 MetronomeEngine
/// 生命週期嚴格同步——ViewModel 的 isPlaying 訂閱呼叫 start／
/// stop、每主拍呼叫 update。ActivityKit 失敗（權限關閉、系統
/// 拒絕）一律吞掉：活動只是系統整合層，絕不反噬音訊主路徑。
///
/// 防殭屍三重：
/// 1. stop() 以 .immediate 結束本控制器持有的活動；
/// 2. start() 前先結束系統上全部同屬性活動（上一進程殘留、
///    本控制器遺失引用等），保證同時只存在一個；
/// 3. 每次 request／update 都帶 staleDate（約 2.2 拍後）：App
///    被殺或崩潰後活動先被系統標記為過期（變暗），不再冒充
///    「正在運行」；ContentView 啟動時若節拍器未播放再呼叫
///    endAllActivities() 徹底清除。
@MainActor
final class MetronomeLiveActivityController {
    static let shared = MetronomeLiveActivityController()

    private var activity: Activity<MetronomeActivityAttributes>?
    private var lastState: MetronomeActivityAttributes.ContentState?
    /// start 的 Task 句柄：stop／update 須等其落定，避免
    /// request 未回先 end 的競態（end 到空活動、request 後到
    /// 反成殭屍）。
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
            // 先清殘留（含本控制器上一輪的），再建新活動。
            for existing in Activity<MetronomeActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            guard !Task.isCancelled else { return }
            do {
                self.activity = try Activity.request(
                    attributes: MetronomeActivityAttributes(timbreName: timbreName),
                    content: ActivityContent(state: state,
                                             staleDate: self.staleDate(for: state)),
                    pushType: nil)
            } catch {
                self.activity = nil
            }
        }
    }

    func update(state: MetronomeActivityAttributes.ContentState) {
        guard state != lastState else { return }
        lastState = state
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        Task {
            await activity.update(content)
        }
    }

    func stop() {
        lastState = nil
        startTask?.cancel()
        startTask = nil
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 啟動清理（ContentView onAppear、節拍器未播放時）：結束
    /// 系統上全部同屬性活動，清上一進程的殘留。
    func endAllActivities() {
        lastState = nil
        startTask?.cancel()
        startTask = nil
        activity = nil
        Task {
            for existing in Activity<MetronomeActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
