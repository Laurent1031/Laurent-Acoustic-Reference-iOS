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
        guard let profile = desiredProfile() else {
            notifyProfileObservers(nil)
            return
        }
        let session = AVAudioSession.sharedInstance()
        switch profile {
        case .record:
            if session.category != .playAndRecord || session.mode != .measurement
                || !session.categoryOptions.contains(.defaultToSpeaker) {
                // 【返修批2 根因修正】options 必須含
                // .defaultToSpeaker：.playAndRecord 預設把
                // 播放輸出導向聽筒（earpiece），音量極低——
                // 實機「基準音放不了（聽不見）／所有音效
                // 尤其是節拍器很小」的共同根因（調音開麥後
                // session 停在錄音型，全部播放都被導去
                // 聽筒）。調音 App 的播放恆應走揚聲器。
                try? session.setCategory(.playAndRecord, mode: .measurement,
                                         options: [.defaultToSpeaker])
            }
        case .playback:
            if session.category != .playback || session.mode != .default {
                try? session.setCategory(.playback, mode: .default, options: [])
            }
        }
        notifyProfileObservers(profile)
    }

    // MARK: - 型態觀察（階段 6：播放增益補償接線）

    /// 型態觀察者：applyProfile 每次裁決出與上次不同的型態時
    /// 通知（播放引擎據此開／關 measurement 增益補償）。閉包
    /// 在呼叫 applyProfile 的線程同步觸發（現行呼叫點全在
    /// MainActor），觀察者自行跳回所需隔離域；註冊回傳的
    /// token 供移除（引擎為長生命週期單例式對象，實務上不
    /// 移除，接口備齊）。
    private var profileObservers: [UUID: (SessionProfile?) -> Void] = [:]
    private var lastNotifiedProfile: SessionProfile?
    private var hasNotifiedProfile = false

    @discardableResult
    func addProfileObserver(_ observer: @escaping (SessionProfile?) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        profileObservers[token] = observer
        lock.unlock()
        return token
    }

    func removeProfileObserver(_ token: UUID) {
        lock.lock()
        profileObservers[token] = nil
        lock.unlock()
    }

    private func notifyProfileObservers(_ profile: SessionProfile?) {
        lock.lock()
        if hasNotifiedProfile, lastNotifiedProfile == profile {
            lock.unlock()
            return
        }
        hasNotifiedProfile = true
        lastNotifiedProfile = profile
        let observers = Array(profileObservers.values)
        lock.unlock()
        // 鎖外觸發：觀察者可能回呼協調器（如引擎在回調內再
        // applyProfile），持鎖觸發會死鎖。
        for observer in observers {
            observer(profile)
        }
    }
}

/// measurement 模式播放增益補償（階段 6）：
///
/// 依據：《架構演進方案》§04 音頻子系統表 iOS 列——
/// .measurement「可能降低外放電平，需在播放節拍器/Drone 時
/// 動態切換或在軟體層適當增益補償」；藍圖 §4.1 同旨。動態
/// 切換已於補強段落地（僅播放 → .playback＋.default 恢復
/// 電平）；本補償針對「測量中同時播放」的組成態（調音開麥
/// ＋節拍器／Drone／UI 音效同場），該態下 category 必須留在
/// .playAndRecord＋.measurement，只能在播放鏈內補增益。
///
/// 兩份文件均未給 dB 數值，以下為工程值，推導自各播放鏈的
/// 合成峰值餘量（程式碼內的振幅表），待階段 7 以 SPL 實測
/// 校準（量測 .measurement 與 .default 兩態的外放電平差，
/// 若實測差異與此不符以實測為準回調本表）：
/// - Drone：DroneSynthSpec.targetAmplitude ≤ 0.32，疊合唱與
///   Haas wet 後峰值 ≲ 0.5 → +6 dB（×2.0）後 ≲ 1.0。
/// - 節拍器：ClickSynth.amp 強拍 0.78 × 包絡峰值係數 1.1
///   ≈ 0.86 理論峰值 → +3 dB（×1.41）；帶通路徑的實際樣本
///   峰值低於包絡峰值，此值留削波觀察項（階段 7 驗）。
/// - UI 音效：母本 uiSound 增益 ≤ 0.25 級 → +6 dB 餘量充足。
/// 補償以 AVAudioUnitEQ 的 globalGain 實現（播放鏈各插一
/// 級），型態離開 .record 即歸 0 dB——補償只存在於
/// measurement 組成態，不污染僅播放型態的母本電平。
enum PlaybackGainCompensation {
    static let droneDB: Float = 6.0
    /// 【返修批2・增益審計】3.0 → 6.0：舊值按理論峰值推導、
    /// 對 measurement 的實際電平損失明顯不足；點擊緩衝已
    /// 逐音色正規化至 0.80 峰值（ClickSynth.renderAll），
    /// 疊 +6 dB 後的削波風險由 measurement 輸出衰減對沖，
    /// SPL 實測校準仍列後續（見 enum 頭註）。
    static let metronomeDB: Float = 6.0
    /// 【返修批2・增益審計】6.0 → 9.0，且 UISoundEngine 的
    /// specs 增益已整體 ×2（母本 WebAudio 原值在原生環境
    /// 先天過小，峰值原僅 −32 至 −26 dBFS）。
    static let uiSoundDB: Float = 9.0

    /// 型態 → 補償值：.record（measurement）回 path 值，
    /// 其餘（.playback／nil）回 0。
    static func gainDB(profile: AudioSessionCoordinator.SessionProfile?,
                       pathValue: Float) -> Float {
        profile == .record ? pathValue : 0
    }
}
