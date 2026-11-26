import Foundation

/// AVAudioSession 的共享使用者登記：調音（錄音）與節拍器（播放）
/// 可同時運行（母本兩者並行、WebAudio 同一 AudioContext），只有
/// 最後一個使用者退出時才允許 setActive(false)，避免一方停機
/// 誤殺另一方的音訊。
final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()

    enum User: Hashable, Sendable {
        case tuner
        case metronome
        /// Drone 持續音（階段 4）：純播放，與調音錄音／節拍器同
        /// session 共存，規則一致。
        case drone
    }

    private let lock = NSLock()
    private var users: Set<User> = []

    func acquire(_ user: User) {
        lock.lock()
        users.insert(user)
        lock.unlock()
    }

    /// 登記退出；回傳 true 表示已無任何使用者，呼叫方應停用 session。
    @discardableResult
    func release(_ user: User) -> Bool {
        lock.lock()
        users.remove(user)
        let empty = users.isEmpty
        lock.unlock()
        return empty
    }

    func isActive(_ user: User) -> Bool {
        lock.lock()
        let value = users.contains(user)
        lock.unlock()
        return value
    }
}
