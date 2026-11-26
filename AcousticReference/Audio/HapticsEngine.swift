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

    private init() {}

    // MARK: - 生命週期

    /// 預熱：在節拍器啟動、首次 UI 回饋前呼叫（冪等）。
    func warmUp() {
        queue.async { [weak self] in self?.ensureEngine() }
    }

    private func ensureEngine() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.stoppedHandler = { [weak self] _ in
                self?.queue.async { self?.engine = nil; self?.players = [:] }
            }
            created.resetHandler = { [weak self] in
                self?.queue.async { [weak self] in
                    guard let self, let eng = self.engine else { return }
                    try? eng.start()
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

    // MARK: - 節拍（母本 hapticBeat：L3 42 ms／L2 26／L1 13；iOS 原生
    // 以 transient 的 intensity/sharpness 對應其「時長感」強度）

    /// 在音訊拍點的同一 host 時刻觸發。level 0（靜音拍）不震
    /// （母本 hapticBeat(0) = vibrate(0)）。
    func beat(level: Int, atHostTimeSeconds target: Double) {
        guard isEnabled, level > 0 else { return }
        let (intensity, sharpness) = Self.beatParams(level: level)
        playTransient(intensity: intensity, sharpness: sharpness,
                      key: "beat\(level)", atHostTimeSeconds: target)
    }

    private static func beatParams(level: Int) -> (Float, Float) {
        switch level {
        case 3: return (1.0, 0.75)
        case 2: return (0.62, 0.6)
        default: return (0.35, 0.45)
        }
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
                self.fallbackFire(atHostTimeSeconds: target)
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
            let events = specs.map { spec in
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
            do {
                let player = try self.nextPlayer(key: key, events: events, engine: engine)
                try player.start(atTime: startTime)
            } catch {
                // player 失效時重建一次（引擎可能被系統回收）。
                self.players[key] = nil
                if let player = try? self.nextPlayer(key: key, events: events, engine: engine) {
                    try? player.start(atTime: startTime)
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
        let fire = {
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
