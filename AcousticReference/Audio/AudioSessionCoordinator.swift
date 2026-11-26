import AVFoundation
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

    // MARK: - 動態 Mode 切換（補強段，採納自 iOS 藍圖）

    /// Session 型態：有調音（錄音）在場 → 錄音型；只剩播放型
    /// 使用者（節拍器／Drone）→ 播放型；無人 → nil（不干預，
    /// 停用由最後退出者自行處理）。
    enum SessionProfile: Sendable {
        case record
        case playback
    }

    func desiredProfile() -> SessionProfile? {
        lock.lock()
        defer { lock.unlock() }
        if users.contains(.tuner) { return .record }
        return users.isEmpty ? nil : .playback
    }

    /// 依目前使用者組成套用 category／mode，與現況相同則不重設
    /// （避免無謂的硬體重配置）。切換時機由各引擎在 acquire／
    /// release 後呼叫：組成改變才可能觸發實際切換。
    ///
    /// 錄音型：.playAndRecord + .measurement（關 AGC／降噪，
    /// 規格書 §3.1；代價是外放電平被系統壓低——母本網頁版無
    /// 此問題，此為原生 measurement 模式的已知特性）。
    /// 播放型：.playback + .default，恢復正常外放電平（節拍器
    /// 與 Drone 在僅播放時不應被 measurement 壓低音量）。
    ///
    /// 注意：啟用中切 category 會觸發系統音訊路徑重配置，正在
    /// 播放的引擎不停止（AVAudioEngine 不因 category 變更而
    /// 停機），但可能有極短的電平瞬態——切換只發生在使用者
    /// 組成改變的邊界（調音啟停的那一刻），不在播放中途無故
    /// 發生；瞬態幅度待裝機實測（見補強段報告風險點）。
    func applyProfile() {
        guard let profile = desiredProfile() else { return }
        let session = AVAudioSession.sharedInstance()
        switch profile {
        case .record:
            if session.category != .playAndRecord || session.mode != .measurement {
                try? session.setCategory(.playAndRecord, mode: .measurement, options: [])
            }
        case .playback:
            if session.category != .playback || session.mode != .default {
                try? session.setCategory(.playback, mode: .default, options: [])
            }
        }
    }
}
