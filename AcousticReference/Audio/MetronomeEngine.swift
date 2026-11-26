import AVFoundation
import Foundation

/// 一次主拍的視覺事件（調度時產生、在拍點時刻 +藍牙補償後送達）。
struct BeatVisualEvent: Sendable {
    /// 拍柱序號（附點計拍時一拍跨三柱，此為該拍的首柱）。
    let pillarIndex: Int
    /// 計拍序號（0 起；提示列「第 N 拍」用）。
    let beatIndex: Int
    /// 本小節計拍總數。
    let beatsInBar: Int
    /// 重音等級 0–3（預備拍期間為母本覆蓋值：首拍 3、其餘 2）。
    let level: Int
    /// 小節計數（預備拍期間為 0）。
    let barCount: Int
    let isCountIn: Bool
    let bpm: Int
}

/// 節拍器調度診斷（階段 1 DetectionLog 的節拍器對應物）：
/// 由排程樣本時間計算——拍距 = 相鄰主拍的排程樣本差，偏差 =
/// 實際拍距 − 名義拍距（60/BPM×附點倍率）。樣本時間格以 Double
/// 累積，無整數取整漂移；此統計即「漂移可量測」的證據面。
struct MetronomeDiagnostics: Sendable, Equatable {
    var beatsScheduled = 0
    var lastIntervalMs = 0.0
    var meanAbsDeviationMs = 0.0
    var maxAbsDeviationMs = 0.0
    /// 調度器每次醒來時，下一拍距「現在」的最小餘量（ms）；
    /// 若曾 ≤0 代表前瞻不足、該拍可能遲到。
    var minHeadroomMs = 0.0
}

/// 節拍器調度核心：執行緒紀律比照階段 1 的 EngineCore——
/// 全部可變狀態由 NSLock 保護；25 ms 定時器在專屬佇列醒來，
/// 以 0.12 s 前瞻把點音緩衝按「樣本時間」排進 AVAudioPlayerNode
/// （母本 metroScheduler 的原生等價，行 11375–11442）。
/// 視覺與震動不在調度當下觸發，而是按拍點 host 時刻 +藍牙補償
/// 另行派發（母本以 setTimeout 對齊 nextTickTime 的原生等價）。
final class MetronomeCore: @unchecked Sendable {
    // 回調在 init 後、start 前各設一次（比照 EngineCore.onReading）。
    var onVisualEvent: ((BeatVisualEvent) -> Void)?
    var onStats: ((MetronomeDiagnostics) -> Void)?
    var onRampFinished: (() -> Void)?
    var onRampChanged: ((RampState) -> Void)?
    var onBpmChanged: ((Int) -> Void)?

    private let lock = NSLock()
    private var settings: MetronomeSettings
    private var ramp = RampState()
    private var buffers: [ClickKey: AVAudioPCMBuffer] = [:]
    private var player: AVAudioPlayerNode?
    private var sampleRate: Double = 48000

    private let schedQueue = DispatchQueue(label: "com.laurent.acousticreference.metro-scheduler",
                                           qos: .userInteractive)
    private let visualQueue = DispatchQueue(label: "com.laurent.acousticreference.metro-visual",
                                            qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    // 調度狀態（lock 保護）。
    private var playing = false
    private var nextTickSamples: Double = 0
    private var needsInitTick = true
    private var beatIndex = 0
    private var subIndex = 0
    private var barCount = 1
    private var countInActive = false
    private var lastMainBeatSamples: Double?
    private var stats = MetronomeDiagnostics()
    private var intervalCount = 0
    private var sumAbsDeviation = 0.0

    init(settings: MetronomeSettings) {
        self.settings = settings
    }

    // MARK: - 配置（由 facade 在主線程呼叫）

    func configure(player: AVAudioPlayerNode, sampleRate: Double,
                   buffers: [ClickKey: AVAudioPCMBuffer]) {
        lock.lock()
        self.player = player
        self.sampleRate = sampleRate
        self.buffers = buffers
        lock.unlock()
    }

    func updateSettings(_ newSettings: MetronomeSettings) {
        lock.lock()
        settings = newSettings
        lock.unlock()
    }

    func resetBeatIndex() {
        lock.lock()
        beatIndex = 0
        lock.unlock()
    }

    /// 提示列點按：小節計數歸 1（母本行 10519）。
    func resetBarCount() {
        lock.lock()
        barCount = 1
        lock.unlock()
    }

    func rampSnapshot() -> RampState {
        lock.lock()
        defer { lock.unlock() }
        return ramp
    }

    // MARK: - 漸速（母本 startRamp/cancelRamp，行 11011/10994）

    func startRamp(from: Int, to: Int, step: Int, barsPerStep: Int) {
        lock.lock()
        ramp = RampState(active: true, from: from, to: to, step: step,
                         barsPerStep: barsPerStep, barsDone: 0)
        settings.bpm = settings.clampedBpm(from)
        let bpm = settings.bpm
        let snapshot = ramp
        lock.unlock()
        onBpmChanged?(bpm)
        onRampChanged?(snapshot)
    }

    func cancelRamp() {
        lock.lock()
        let wasActive = ramp.active
        ramp.active = false
        let snapshot = ramp
        lock.unlock()
        if wasActive { onRampChanged?(snapshot) }
    }

    // MARK: - 啟停

    func startScheduling() {
        lock.lock()
        playing = true
        beatIndex = 0
        subIndex = 0
        countInActive = settings.countIn
        barCount = countInActive ? 0 : 1
        needsInitTick = true
        lastMainBeatSamples = nil
        stats = MetronomeDiagnostics()
        stats.minHeadroomMs = .greatestFiniteMagnitude
        intervalCount = 0
        sumAbsDeviation = 0
        lock.unlock()

        let source = DispatchSource.makeTimerSource(queue: schedQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(25),
                        leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in self?.schedulerTick() }
        source.resume()
        lock.lock()
        timer = source
        lock.unlock()
    }

    func stopScheduling() {
        lock.lock()
        playing = false
        let wasRampActive = ramp.active
        ramp.active = false
        let snapshot = ramp
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
        if wasRampActive { onRampChanged?(snapshot) }
    }

    /// 中斷恢復後：樣本時間格重新錨定（拍序不重置）。
    func resyncAfterInterruption() {
        lock.lock()
        needsInitTick = true
        lastMainBeatSamples = nil
        lock.unlock()
    }

    // MARK: - 調度（schedQueue）

    private func schedulerTick() {
        lock.lock()
        defer { lock.unlock() }
        guard playing, let player,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }
        let nowSamples = Double(playerTime.sampleTime)
        let hostBase = AVAudioTime.seconds(forHostTime: playerTime.hostTime)

        if needsInitTick {
            // 母本：nextTickTime = ctx.currentTime + 0.04。
            nextTickSamples = nowSamples + 0.04 * sampleRate
            needsInitTick = false
        }
        let headroomMs = (nextTickSamples - nowSamples) / sampleRate * 1000
        if headroomMs < stats.minHeadroomMs {
            stats.minHeadroomMs = headroomMs
        }
        let horizon = nowSamples + 0.12 * sampleRate
        while nextTickSamples < horizon {
            scheduleOne(player: player, hostBaseSeconds: hostBase,
                        hostBaseSamples: nowSamples)
        }
    }

    /// 排一個 tick（主拍或細分拍）。呼叫時持有 lock。
    private func scheduleOne(player: AVAudioPlayerNode,
                             hostBaseSeconds: Double, hostBaseSamples: Double) {
        let s = settings
        let dotted = s.isDottedBeat
        let subs = s.effectiveSubs
        let beatsInBar = s.beatsInBar
        if beatIndex >= beatsInBar { beatIndex = 0 }
        let isSub = subIndex > 0
        let rawPillar = dotted ? beatIndex * 3 : beatIndex
        let pillarIdx = min(rawPillar, max(0, s.beatAccents.count - 1))
        // 母本 lvl：預備拍覆蓋（首拍 3、其餘 2），否則讀拍柱重音。
        let lvl = isSub ? 0
            : (countInActive ? (beatIndex == 0 ? 3 : 2) : s.beatAccents[pillarIdx])

        // —— 點音（母本 triggerMetroSound；accentLevel==0 不發聲）——
        let keyLevel = isSub ? s.beatAccents[pillarIdx] : lvl
        if keyLevel > 0,
           let buffer = buffers[ClickKey(timbre: s.timbre, level: keyLevel, isSub: isSub)] {
            let when = AVAudioTime(sampleTime: AVAudioFramePosition(nextTickSamples),
                                   atRate: sampleRate)
            player.scheduleBuffer(buffer, at: when, options: [])
        }

        // —— 主拍：統計、震動、視覺（細分拍三者皆無，母本同）——
        if !isSub {
            let hostSeconds = hostBaseSeconds
                + (nextTickSamples - hostBaseSamples) / sampleRate
            if let last = lastMainBeatSamples {
                let intervalMs = (nextTickSamples - last) / sampleRate * 1000
                let nominalMs = 60000.0 / Double(s.bpm) * (dotted ? 3.0 : 1.0)
                let deviation = abs(intervalMs - nominalMs)
                intervalCount += 1
                sumAbsDeviation += deviation
                stats.lastIntervalMs = intervalMs
                stats.meanAbsDeviationMs = sumAbsDeviation / Double(intervalCount)
                stats.maxAbsDeviationMs = max(stats.maxAbsDeviationMs, deviation)
            }
            lastMainBeatSamples = nextTickSamples
            stats.beatsScheduled += 1
            onStats?(stats)

            let bt = Double(s.bluetoothCompMs) / 1000
            HapticsEngine.shared.beat(level: lvl, atHostTimeSeconds: hostSeconds + bt)
            let event = BeatVisualEvent(pillarIndex: pillarIdx, beatIndex: beatIndex,
                                        beatsInBar: beatsInBar, level: lvl,
                                        barCount: barCount, isCountIn: countInActive,
                                        bpm: s.bpm)
            let targetSeconds = hostSeconds + bt
            let deadline = DispatchTime(uptimeNanoseconds: UInt64(max(0, targetSeconds) * 1_000_000_000))
            visualQueue.asyncAfter(deadline: deadline) { [weak self] in
                self?.onVisualEvent?(event)
            }
        }

        // —— 推進（母本行 11387–11401）：間隔在此刻讀現行 BPM，
        // 已排定的 tick 不受之後改速影響 ——
        let intervalSec: Double
        if s.subdivision == 5 {
            intervalSec = (60.0 / Double(s.bpm)) * (subIndex % 2 == 0 ? 2.0 / 3.0 : 1.0 / 3.0)
        } else {
            intervalSec = (60.0 / Double(s.bpm)) / Double(subs)
        }
        nextTickSamples += intervalSec * sampleRate
        subIndex += 1
        if subIndex >= subs {
            subIndex = 0
            beatIndex += 1
            if beatIndex >= beatsInBar {
                beatIndex = 0
                barCompleted()
            }
        }
    }

    /// 一小節走完（呼叫時持有 lock）。母本行 11404–11414：
    /// 預備拍小節結束只切換旗標、不觸發漸速計步。
    private func barCompleted() {
        if countInActive {
            countInActive = false
            barCount = 1
            return
        }
        barCount += 1
        guard ramp.active else { return }
        ramp.barsDone += 1
        if ramp.barsDone % ramp.barsPerStep == 0 {
            if settings.bpm == ramp.to {
                finishRamp()
                return
            }
            var next = settings.bpm + (ramp.to > settings.bpm ? ramp.step : -ramp.step)
            if (ramp.to > ramp.from && next > ramp.to)
                || (ramp.to < ramp.from && next < ramp.to) {
                next = ramp.to
            }
            settings.bpm = next
            onBpmChanged?(next)
            if next == ramp.to {
                finishRamp()
                return
            }
        }
        onRampChanged?(ramp)
    }

    private func finishRamp() {
        settings.bpm = ramp.to
        ramp.active = false
        let snapshot = ramp
        onRampChanged?(snapshot)
        onRampFinished?()
    }
}

/// 節拍器引擎 facade（主線程）：AVAudioEngine 生命週期、session
/// 協調、中斷恢復；調度數學全在 MetronomeCore。
@MainActor
final class MetronomeEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var diagnostics = MetronomeDiagnostics()
    @Published var lastError: String?

    /// 由 MetronomeViewModel 設置一次。
    var onBeatVisual: ((BeatVisualEvent) -> Void)?
    var onRampFinished: (() -> Void)?
    var onRampChanged: ((RampState) -> Void)?
    var onBpmChanged: ((Int) -> Void)?

    private let core: MetronomeCore
    private var avEngine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var sessionAcquired = false
    private var notificationTokens: [NSObjectProtocol] = []

    init(settings: MetronomeSettings) {
        core = MetronomeCore(settings: settings)
        core.onStats = { [weak self] value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.diagnostics = value }
            }
        }
        core.onVisualEvent = { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onBeatVisual?(event) }
            }
        }
        core.onRampFinished = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onRampFinished?() }
            }
        }
        core.onRampChanged = { [weak self] state in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onRampChanged?(state) }
            }
        }
        core.onBpmChanged = { [weak self] bpm in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onBpmChanged?(bpm) }
            }
        }
    }

    // MARK: - 轉發

    func updateSettings(_ settings: MetronomeSettings) { core.updateSettings(settings) }
    func startRamp(from: Int, to: Int, step: Int, barsPerStep: Int) {
        core.startRamp(from: from, to: to, step: step, barsPerStep: barsPerStep)
    }
    func cancelRamp() { core.cancelRamp() }
    func rampSnapshot() -> RampState { core.rampSnapshot() }
    func resetBeatIndex() { core.resetBeatIndex() }
    func resetBarCount() { core.resetBarCount() }

    // MARK: - 音色試聽（母本：未播放時切換音色即試聽首柱點音）

    private var auditionEngine: AVAudioEngine?
    private var auditionPlayer: AVAudioPlayerNode?
    private var bufferCache: [Double: [ClickKey: AVAudioPCMBuffer]] = [:]

    private func buffers(for sampleRate: Double) -> [ClickKey: AVAudioPCMBuffer] {
        if let cached = bufferCache[sampleRate] { return cached }
        let rendered = ClickSynth.renderAll(sampleRate: sampleRate)
        bufferCache[sampleRate] = rendered
        return rendered
    }

    func audition(timbre: MetronomeTimbre, level: Int) {
        let key = ClickKey(timbre: timbre, level: max(1, level), isSub: false)
        let session = AVAudioSession.sharedInstance()
        let coordinatorBusy = AudioSessionCoordinator.shared.isActive(.tuner)
            || AudioSessionCoordinator.shared.isActive(.metronome)
        let ownsSession = !coordinatorBusy && !isPlaying
        if ownsSession {
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true)
        }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        let rate = playerNode.outputFormat(forBus: 0).sampleRate
        guard let buffer = buffers(for: rate)[key] else {
            if ownsSession { try? session.setActive(false) }
            return
        }
        do {
            try engine.start()
        } catch {
            if ownsSession { try? session.setActive(false) }
            return
        }
        auditionEngine = engine
        auditionPlayer = playerNode
        playerNode.play()
        let engineID = ObjectIdentifier(engine)
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // 只拆自己這一次的試聽引擎（快速連切音色時，
                    // 舊回調不得誤停新一次試聽）。以 ObjectIdentifier
                    // 比對身分，避免把 non-Sendable 的 engine 送進閉包。
                    guard let self,
                          self.auditionEngine.map({ ObjectIdentifier($0) }) == engineID
                    else { return }
                    self.auditionEngine?.stop()
                    self.auditionEngine = nil
                    self.auditionPlayer = nil
                    if ownsSession {
                        try? AVAudioSession.sharedInstance().setActive(false)
                    }
                }
            }
        }
    }

    // MARK: - 啟停

    func start() {
        guard !isPlaying else { return }
        lastError = nil
        let session = AVAudioSession.sharedInstance()
        if !sessionAcquired {
            AudioSessionCoordinator.shared.acquire(.metronome)
            sessionAcquired = true
        }
        do {
            // 與調音共用 playAndRecord：調音已啟動時類別相同、
            // 不重設（避免打斷錄音）；僅在類別不同才設定。
            if session.category != .playAndRecord {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [])
            }
            try session.setActive(true)
        } catch {
            lastError = "音訊工作階段啟動失敗：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        let outputRate = playerNode.outputFormat(forBus: 0).sampleRate
        let clickBuffers = buffers(for: outputRate)
        core.configure(player: playerNode, sampleRate: outputRate, buffers: clickBuffers)
        do {
            try engine.start()
        } catch {
            lastError = "節拍器引擎啟動失敗：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }
        playerNode.play()
        avEngine = engine
        player = playerNode
        HapticsEngine.shared.warmUp()
        core.startScheduling()
        isPlaying = true
        registerNotifications()
    }

    func stop() {
        guard isPlaying else { return }
        core.stopScheduling()
        player?.stop()
        avEngine?.stop()
        avEngine = nil
        player = nil
        unregisterNotifications()
        releaseSessionIfUnused()
        isPlaying = false
    }

    private func releaseSessionIfUnused() {
        guard sessionAcquired else { return }
        sessionAcquired = false
        if AudioSessionCoordinator.shared.release(.metronome) {
            try? AVAudioSession.sharedInstance().setActive(false,
                                                           options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - 中斷與媒體服務重置（比照 AudioEngine 的處理）

    private func registerNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                if type == .ended {
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.resumeAfterInterruption()
                    }
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.stop()
                self.start()
            }
        })
    }

    private func unregisterNotifications() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens = []
    }

    private func resumeAfterInterruption() {
        guard let avEngine, let player else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try avEngine.start()
            player.play()
            core.resyncAfterInterruption()
        } catch {
            lastError = "中斷後恢復失敗：\(error.localizedDescription)"
        }
    }
}
