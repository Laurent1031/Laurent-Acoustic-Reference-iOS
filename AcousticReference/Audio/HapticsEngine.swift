import AudioToolbox
import CoreHaptics
import Foundation

/// 觸感引擎（規格書 §3.6）。全部呼叫點受母本「震動回饋」總開關
/// （TunerSettings.hapticsOn）門控——開關由 ContentView 同步至
/// isEnabled；關閉時所有方法直接返回（母本 haptic() 同語義）。
///
/// 實現要點：
/// - Core Haptics：CHHapticEngine 懶啟動；每種圖案預建 player 池
///   輪替使用，支援以絕對時間（系統 uptime 秒，與 AVAudioTime
///   host time 同一 mach 時間基）預排程——節拍器排音訊的同時以
///   同一目標時刻排震動，達到毫秒對齊。
/// - 時間基保險：warmUp 時比對 CHHapticEngine.currentTime 與
///   ProcessInfo.systemUptime；偏差 >0.25 s 視為時間基不可信，
///   降級為「到點派發即時播放」（dispatch asyncAfter）。
/// - 不支持 Core Haptics 的裝置：退回 UIImpactFeedbackGenerator
///   （即時回饋類）與 AudioServices 系統震動（節拍類只能即時，
///   由內部 asyncAfter 到點觸發）。此限制見階段 3 報告。
final class HapticsEngine: @unchecked Sendable {
    static let shared = HapticsEngine()

    /// 總開關（母本 state.hapticsOn）。由主線程寫入，佇列內讀取前
    /// 先同步到佇列私有副本，避免跨線程競態。
    var isEnabled: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _enabled }
        set { stateLock.lock(); _enabled = newValue; stateLock.unlock() }
    }

    var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private let queue = DispatchQueue(label: "com.laurent.acousticreference.haptics",
                                      qos: .userInteractive)
    private let stateLock = NSLock()
    private var _enabled = true

    private var engine: CHHapticEngine?
    private var players: [String: [CHHapticPatternPlayer]] = [:]
    private var poolCursor: [String: Int] = [:]
    private var absoluteSchedulingOK = false
    /// 【返修批10】引擎被系統停機（切後台／中斷）的標記：
    /// 引擎對象與 player 池保留、只標記待重啟——批8 舊制
    /// 在 stoppedHandler 直接把引擎與池全丟棄，後台每次
    /// 喚醒都要從零重建，重建在後台失敗時更跌落系統長震
    /// 降級，與前台的短促 transient 完全兩種手感
    /// （Laurent 點名「在 app 內和後台的震動不一樣」）。
    private var engineStopped = false

    private init() {}

    // MARK: - 生命週期

    /// 預熱：在 App 啟動、回前台、節拍器啟動、首次 UI
    /// 回饋前呼叫（冪等）。
    /// 【返修批8】引擎已存在時也嘗試 start 一次：系統中斷
    /// 後 CHHapticEngine 可能停在「對象仍在、已停止」態，
    /// ensureEngine 的 nil 守衛不會重建——start 對運行中
    /// 引擎為冪等成功，對已停止引擎即恢復。
    /// 【返修批10】加預建 player 池＋時間基重檢：批9 實機
    /// 「震動一開始沒有」——冷啟動後首次 warmUp 與第一拍
    /// 同擠串行佇列，引擎建立＋首批 player 逐個現建的成
    /// 本超過節拍器 0.12 s 前瞻，最初一兩拍的目標時刻在
    /// player 就緒前已流逝而被吞。改為 App 啟動即預熱
    /// （ContentView.onAppear），並在此把常用圖案的
    /// player 先建好，第一拍只剩 start 一步。
    func warmUp() {
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureEngine()
            if let engine = self.engine {
                try? engine.start()
                self.engineStopped = false
                let drift = abs(engine.currentTime
                                - ProcessInfo.processInfo.systemUptime)
                self.absoluteSchedulingOK = drift <= 0.25
                self.primePlayers(engine: engine)
            }
        }
    }

    /// 預建常用圖案的 player（節拍三級／細分／detent／
    /// 鎖定棘輪／常用 UI 輕震）：池已存在該鍵則跳過。
    private func primePlayers(engine: CHHapticEngine) {
        for level in 1...3 {
            let p = HapticPatternTable.beat(level: level)
            prime(key: "beat\(level)", engine: engine, specs: [
                TransientSpec(relativeTime: 0, intensity: p.intensity,
                              sharpness: p.sharpness)])
        }
        let sub = HapticPatternTable.subdivision
        prime(key: "sub", engine: engine, specs: [
            TransientSpec(relativeTime: 0, intensity: sub.intensity,
                          sharpness: sub.sharpness)])
        let det = HapticPatternTable.detent
        prime(key: "detent", engine: engine, specs: [
            TransientSpec(relativeTime: 0, intensity: det.intensity,
                          sharpness: det.sharpness)])
        prime(key: "lock", engine: engine,
              specs: HapticPatternTable.lockRatchet.map { entry in
                  TransientSpec(relativeTime: entry.offset,
                                intensity: entry.transient.intensity,
                                sharpness: entry.transient.sharpness)
              })
        for ms in [4.0, 6, 8, 10, 12, 14, 20] {
            let intensity = Float(min(1, max(0.25, ms / 45)))
            prime(key: "tap\(Int((intensity * 10).rounded()))",
                  engine: engine, specs: [
                    TransientSpec(relativeTime: 0, intensity: intensity,
                                  sharpness: 0.55)])
        }
    }

    private func prime(key: String, engine: CHHapticEngine,
                       specs: [TransientSpec]) {
        guard players[key] == nil else { return }
        _ = try? nextPlayer(key: key, events: Self.events(for: specs),
                            engine: engine)
    }

    /// TransientSpec 陣列 → CHHapticEvent 陣列（prime 與
    /// playSpecs 共用，圖案參數單一真源）。
    private static func events(for specs: [TransientSpec]) -> [CHHapticEvent] {
        specs.map { spec in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity,
                                           value: spec.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness,
                                           value: spec.sharpness),
                ],
                relativeTime: spec.relativeTime)
        }
    }

    private func ensureEngine() {
        guard supportsHaptics else { return }
        if engine != nil {
            // 【返修批10】引擎對象在（可能被系統停機）：
            // 先原地重啟——成功即沿用既有 player 池，不
            // 成功才整組作廢、落到下方從零重建。
            if engineStopped {
                do {
                    try engine?.start()
                    engineStopped = false
                } catch {
                    // 【返修批13】啟動失敗不作廢引擎與 player
                    // 池：App 在後台時系統停機且拒絕啟動（節
                    // 拍器後台逐拍呼叫都會走到這裡），舊制每
                    // 拍把整套狀態丟棄、下拍從零重建，既白
                    // 付成本、回前台首拍又要現建 player。保
                    // 留對象與池、維持 engineStopped 標記，
                    // 下一拍直接再試啟動；引擎真損壞由
                    // playSpecs 播放失敗路徑作廢處理。
                    return
                }
            }
            if engine != nil { return }
        }
        do {
            let created = try CHHapticEngine()
            created.stoppedHandler = { [weak self] _ in
                // 【返修批10】只標記不停機（見 engineStopped
                // 註）：引擎與池保留待重啟，前後台手感一致。
                self?.queue.async { self?.engineStopped = true }
            }
            created.resetHandler = { [weak self] in
                self?.queue.async { [weak self] in
                    guard let self, let eng = self.engine else { return }
                    try? eng.start()
                    self.engineStopped = false
                }
            }
            try created.start()
            engine = created
            let drift = abs(created.currentTime - ProcessInfo.processInfo.systemUptime)
            absoluteSchedulingOK = drift <= 0.25
        } catch {
            engine = nil
            absoluteSchedulingOK = false
        }
    }

    // MARK: - 節拍（圖樣數值全數出自 HapticPatternTable，階段 6
    // 數值化：強拍 1.0／0.25、次強 0.6／0.75、弱 0.35／0.75、
    // 細分 0.18——《架構演進方案》§05 採納值）

    /// 在音訊拍點的同一 host 時刻觸發。level 0（靜音拍）不震
    /// （母本 hapticBeat(0) = vibrate(0)）。
    func beat(level: Int, atHostTimeSeconds target: Double) {
        guard isEnabled, level > 0 else { return }
        let pattern = HapticPatternTable.beat(level: level)
        playTransient(intensity: pattern.intensity, sharpness: pattern.sharpness,
                      key: "beat\(level)", atHostTimeSeconds: target)
    }

    /// 細分拍微觸感（架構方案採納項；母本與階段 3 無細分拍
    /// 震動，此為原生增強）：與拍點音訊同一 host 時刻觸發。
    func subdivision(atHostTimeSeconds target: Double) {
        guard isEnabled else { return }
        let pattern = HapticPatternTable.subdivision
        playTransient(intensity: pattern.intensity, sharpness: pattern.sharpness,
                      key: "sub", atHostTimeSeconds: target)
    }

    /// 準音鎖定棘輪（HapticPatternTable.lockRatchet：雙記
    /// transient 的機械咬合感，形制沿母本 [8, 35, 16]）。
    func inTuneLock() {
        guard isEnabled else { return }
        let specs = HapticPatternTable.lockRatchet.map { entry in
            TransientSpec(relativeTime: entry.offset,
                          intensity: entry.transient.intensity,
                          sharpness: entry.transient.sharpness)
        }
        playSpecs(specs, key: "lock", atHostTimeSeconds: nil)
    }

    // MARK: - UI 回饋（母本 navigator.vibrate(ms) 的各呼叫點）

    /// 單次輕震：毫秒數映射為 intensity（母本 iOS 網頁端 vibrate
    /// 本為 no-op，此映射是原生增強；相對強弱次序與母本一致）。
    func tap(milliseconds ms: Double) {
        guard isEnabled else { return }
        let intensity = Float(min(1, max(0.25, ms / 45)))
        playTransient(intensity: intensity, sharpness: 0.55,
                      key: "tap\(Int((intensity * 10).rounded()))",
                      atHostTimeSeconds: nil)
    }

    /// 步進定位觸感（Laurent 架構意見採納項：A4／BPM 步進鈕的
    /// detent 回饋）：短促高銳度 transient，與 tap 的映射分開，
    /// 每次步進一記（長按連調時逐記跟隨）。數值見
    /// HapticPatternTable.detent。
    func detent() {
        guard isEnabled else { return }
        let pattern = HapticPatternTable.detent
        playTransient(intensity: pattern.intensity, sharpness: pattern.sharpness,
                      key: "detent", atHostTimeSeconds: nil)
    }

    /// 震動圖案：母本 vibrate([震, 停, 震, …]) 毫秒陣列
    /// （調音鎖定 [8,35,16]、重音重置 [8,30,12] 等）。
    func pattern(_ segmentsMs: [Double]) {
        guard isEnabled, !segmentsMs.isEmpty else { return }
        var specs: [TransientSpec] = []
        var t = 0.0
        for (index, seg) in segmentsMs.enumerated() {
            if index % 2 == 0 {
                let intensity = Float(min(1, max(0.3, seg / 30)))
                specs.append(TransientSpec(relativeTime: t, intensity: intensity,
                                           sharpness: 0.6))
            }
            t += seg / 1000
        }
        let key = "pat" + segmentsMs.map { String(Int($0)) }.joined(separator: "-")
        playSpecs(specs, key: key, atHostTimeSeconds: nil)
    }

    // MARK: - 播放（player 池）
    //
    // CHHapticEvent 非 Sendable：跨佇列只傳 Sendable 的 TransientSpec，
    // 事件本體一律在觸感佇列內建立。

    /// 一個 transient 的可送遞規格。
    private struct TransientSpec: Sendable {
        var relativeTime: Double
        var intensity: Float
        var sharpness: Float
    }

    private func playTransient(intensity: Float, sharpness: Float,
                               key: String, atHostTimeSeconds target: Double?) {
        playSpecs([TransientSpec(relativeTime: 0, intensity: intensity,
                                 sharpness: sharpness)],
                  key: key, atHostTimeSeconds: target)
    }

    private func playSpecs(_ specs: [TransientSpec], key: String,
                           atHostTimeSeconds target: Double?) {
        queue.async { [weak self] in
            guard let self, self.isEnabled else { return }
            guard self.supportsHaptics else {
                self.fallbackFire(atHostTimeSeconds: target)
                return
            }
            self.ensureEngine()
            guard let engine = self.engine else {
                // 【返修批10】硬件支持 Core Haptics 卻暫時
                // 無引擎（後台建立失敗等）：寧可這一記不
                // 出，也不用系統長震冒充——前台短促
                // transient 與後台長嗡嗡完全兩種手感正是
                // 「前後台震動不一樣」的來源。不支持
                // Core Haptics 的硬件才走 fallbackFire
                // （上方 supportsHaptics 分支）。
                return
            }
            // 絕對排程：目標時刻仍在未來且時間基可信時預排；
            // 否則立即播放（目標已過或即時回饋類呼叫）。
            var startTime = CHHapticTimeImmediate
            if let target {
                let now = engine.currentTime
                if self.absoluteSchedulingOK && target > now + 0.002 {
                    startTime = target
                } else if target > ProcessInfo.processInfo.systemUptime + 0.002
                            && !self.absoluteSchedulingOK {
                    // 時間基不可信：改以 uptime 派發到點播放。
                    self.dispatchAt(uptimeSeconds: target) { [weak self] in
                        self?.playSpecs(specs, key: key, atHostTimeSeconds: nil)
                    }
                    return
                }
            }
            let events = Self.events(for: specs)
            do {
                let player = try self.nextPlayer(key: key, events: events, engine: engine)
                try player.start(atTime: startTime)
            } catch {
                // 【返修批8】舊版只重建 player 再試一次：若失
                // 敗原因是引擎本體已停止（中斷後 resetHandler
                // 的 start 未成功），player 建得出也 start 不
                // 了，且 ensureEngine 的 nil 守衛永不重建——
                // 震動就此整場死亡（實機「震動有時候沒反
                // 應」）。改為：先重啟引擎、重建 player 再試；
                // 仍失敗則整引擎作廢，下一個呼叫由
                // ensureEngine 從零重建，不留半死狀態。
                try? engine.start()
                self.players[key] = nil
                do {
                    let player = try self.nextPlayer(key: key, events: events, engine: engine)
                    try player.start(atTime: startTime)
                } catch {
                    // 【返修批13】引擎處於系統停機態（後台）
                    // 時的播放失敗不作廢狀態：保留引擎與池
                    // 待下一拍重試啟動（見 ensureEngine 批
                    // 13 註）。非停機態的失敗維持批 8 裁決：
                    // 整引擎作廢、下一個呼叫從零重建。
                    if self.engineStopped { return }
                    self.engine = nil
                    self.players = [:]
                }
            }
        }
    }

    private func nextPlayer(key: String, events: [CHHapticEvent],
                            engine: CHHapticEngine) throws -> CHHapticPatternPlayer {
        var pool = players[key] ?? []
        if pool.count < 3 {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            pool.append(player)
            players[key] = pool
            poolCursor[key] = pool.count - 1
            return player
        }
        let idx = ((poolCursor[key] ?? 0) + 1) % pool.count
        poolCursor[key] = idx
        return pool[idx]
    }

    // MARK: - 降級（無 Core Haptics）

    /// 系統震動無法預排程：以 uptime 派發到點觸發。
    private func fallbackFire(atHostTimeSeconds target: Double?) {
        let fire: @Sendable () -> Void = {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        if let target {
            dispatchAt(uptimeSeconds: target, block: fire)
        } else {
            fire()
        }
    }

    private func dispatchAt(uptimeSeconds target: Double, block: @escaping @Sendable () -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(0, target - now)
        if delay < 0.002 {
            block()
        } else {
            let ns = UInt64(delay * 1_000_000_000)
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: DispatchTime(uptimeNanoseconds: UInt64(now * 1_000_000_000) + ns),
                execute: block)
        }
    }
}
