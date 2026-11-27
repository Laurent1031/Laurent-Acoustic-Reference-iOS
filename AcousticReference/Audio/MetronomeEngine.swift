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
    /// 本拍所在小節是否為 Gap Click 靜音小節（補強段）：靜音
    /// 小節照常派發視覺事件（拍點顯示不中斷），只是無聲無震。
    let isSilentBar: Bool
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
    // Gap Click（lock 保護）：gapCyclePosition = 本循環已完成的
    // 常規小節數（預備拍小節不計）；currentBarSilent 在每小節
    // 邊界由 barCompleted 依循環位置重算（小節內鎖定，設定變更
    // 下一小節生效——前瞻僅 0.12 s，邊界誤差至多一拍內的部分
    // tick 已排程，屬可忽略的排程粒度，報告註明）。
    private var gapCyclePosition = 0
    private var currentBarSilent = false
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
        // Gap 循環自第一個常規小節重新起算，第一段恆為發聲段。
        gapCyclePosition = 0
        currentBarSilent = false
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

    /// 中斷開始：凍結調度（返修批7・D6）。定時器取消；playing
    /// 與拍序／漸速狀態保留，已排進 player 的 ≤0.12 s 前瞻照常
    /// 播完，其後不再新排點音／震動／視覺。
    func pauseScheduling() {
        lock.lock()
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    /// 中斷恢復：重建調度定時器（未在播放或定時器已存在時
    /// 不動作）；拍點錨定由 resyncAfterInterruption 的
    /// needsInitTick 在下一 tick 完成。
    func resumeScheduling() {
        lock.lock()
        guard playing, timer == nil else {
            lock.unlock()
            return
        }
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

        // —— 點音（母本 triggerMetroSound；accentLevel==0 不發聲；
        // Gap 靜音小節整節不發聲，含細分拍）——
        // 預備拍期間母本把覆蓋等級（首拍 3、其餘 2）一併傳給細分拍，
        // 不讀拍柱重音；正式小節細分拍才讀 beatAccents。
        let keyLevel = isSub
            ? (countInActive ? (beatIndex == 0 ? 3 : 2) : s.beatAccents[pillarIdx])
            : lvl
        if keyLevel > 0, !currentBarSilent,
           let buffer = buffers[ClickKey(timbre: s.timbre, level: keyLevel, isSub: isSub)] {
            let when = AVAudioTime(sampleTime: AVAudioFramePosition(nextTickSamples),
                                   atRate: sampleRate)
            player.scheduleBuffer(buffer, at: when, options: [])
        }

        // —— 細分拍震動（階段 6，架構方案採納項）：0.18 微觸感
        // 與點音同一 host 時刻；母本無此項（母本細分拍僅有聲），
        // Gap 靜音小節同步靜默（與點音同規則）。統計與視覺仍
        // 僅主拍（母本同）。——
        let tickHostSeconds = hostBaseSeconds
            + (nextTickSamples - hostBaseSamples) / sampleRate
        if isSub, !currentBarSilent, keyLevel > 0 {
            HapticsEngine.shared.subdivision(
                atHostTimeSeconds: tickHostSeconds + Double(s.bluetoothCompMs) / 1000)
        }

        // —— 主拍：統計、震動、視覺 ——
        if !isSub {
            let hostSeconds = tickHostSeconds
            if let last = lastMainBeatSamples {
                let intervalMs = (nextTickSamples - last) / sampleRate * 1000
                // 主拍間隔恆為 60000/bpm：每 tick 間隔 (60/bpm)/subs、
                // 主拍每 subs tick 一次，subs 抵消；附點只改 subs 與
                // beatsInBar，不改主拍名義間隔（舊式多乘 ×3 已撤）。
                let nominalMs = 60000.0 / Double(s.bpm)
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
            // Gap 靜音小節：觸感同步靜默；視覺事件照常派發。
            if !currentBarSilent {
                HapticsEngine.shared.beat(level: lvl, atHostTimeSeconds: hostSeconds + bt)
            }
            let event = BeatVisualEvent(pillarIndex: pillarIdx, beatIndex: beatIndex,
                                        beatsInBar: beatsInBar, level: lvl,
                                        barCount: barCount, isCountIn: countInActive,
                                        bpm: s.bpm, isSilentBar: currentBarSilent)
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
    /// 補強段 Gap Click：常規小節（含靜音小節）推進循環並重算
    /// 下一小節的靜音旗標；預備拍小節不計入循環（恆發聲）。
    /// 漸速計步同樣包含靜音小節（速度是時間軸的連續量，練習者
    /// 在靜音段落仍跟拍前進，漸速應照常推進——此為本段的交互
    /// 定義，母本無 Gap Click 可對照）。
    private func barCompleted() {
        if countInActive {
            countInActive = false
            barCount = 1
            return
        }
        barCount += 1
        advanceGapCycle()
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

    /// Gap 循環推進一格（呼叫時持有 lock，常規小節邊界）：
    /// 位置在 [0, 響+靜) 內循環，位置 ≥ 響數 → 下一小節靜音。
    /// gap 關閉時位置歸零、旗標恆 false（行為與母本一致）。
    private func advanceGapCycle() {
        // 【返修批2】Gap Click 靜音小節經 Laurent 指示整項
        // 取消：循環恆不推進、靜音旗標恆 false。模型欄位
        // 保留供舊存檔解碼相容，不再被讀取。
        gapCyclePosition = 0
        currentBarSilent = false
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
    /// measurement 組成態的播放增益補償級（階段 6）：player →
    /// EQ → mainMixer；globalGain 由協調器型態觀察驅動。
    private var gainEQ: AVAudioUnitEQ?
    private var compensationDB: Float = 0
    private var sessionAcquired = false
    private var notificationTokens: [NSObjectProtocol] = []
    /// 配置變更觀察代幣（返修批7・D2）：觀察對象是當下的
    /// AVAudioEngine 實例，引擎圖重建後須換綁新實例，故獨立
    /// 於 notificationTokens 管理（start 註冊、stop 移除、
    /// 重建完成時換綁）。
    private var configurationChangeToken: NSObjectProtocol?
    /// 最近一次引擎啟動的 uptime（配置變更自愈去抖，同
    /// AudioEngine 形制：重建自身觸發的變更 0.75 s 內忽略）。
    private var lastEngineStartUptime: TimeInterval = 0

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
        // 型態觀察（階段 6）：組成態進／出 measurement 時同步
        // 增益補償（常數見 PlaybackGainCompensation）。
        AudioSessionCoordinator.shared.addProfileObserver { [weak self] profile in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.compensationDB = PlaybackGainCompensation.gainDB(
                    profile: profile, pathValue: PlaybackGainCompensation.metronomeDB)
                self.gainEQ?.globalGain = self.compensationDB
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
        Self.scheduleAuditionTeardown(on: playerNode, buffer: buffer,
                                      engineID: engineID,
                                      ownsSession: ownsSession, engine: self)
    }

    /// 【裝機返修・同 AudioEngine .ips 教訓】播放完成回調由
    /// AVFoundation 在背景佇列呼叫，閉包必須 nonisolated
    /// 形成，否則同觸 swift_task_checkIsolatedSwift 斷言。
    /// 只拆自己這一次的試聽引擎（快速連切音色時，舊回調
    /// 不得誤停新一次試聽）：以 ObjectIdentifier 比對身分。
    nonisolated private static func scheduleAuditionTeardown(
        on playerNode: AVAudioPlayerNode, buffer: AVAudioPCMBuffer,
        engineID: ObjectIdentifier, ownsSession: Bool,
        engine: MetronomeEngine
    ) {
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak engine] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let engine,
                          engine.auditionEngine.map({ ObjectIdentifier($0) }) == engineID
                    else { return }
                    engine.auditionEngine?.stop()
                    engine.auditionEngine = nil
                    engine.auditionPlayer = nil
                    if ownsSession {
                        // 【返修批7・D3】拆卸當下重查協調器
                        // 佔用：試聽開始後其他引擎（調音／節
                        // 拍器／Drone）可能已接手 session，仍有
                        // 使用者時不得 setActive(false) 誤殺對方。
                        let coordinatorBusy =
                            AudioSessionCoordinator.shared.isActive(.tuner)
                            || AudioSessionCoordinator.shared.isActive(.metronome)
                            || AudioSessionCoordinator.shared.isActive(.drone)
                        if !coordinatorBusy {
                            try? AVAudioSession.sharedInstance().setActive(false)
                        }
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
            // 動態 Mode（補強段）：category/mode 由協調器依目前
            // 使用者組成統一裁決——調音在場走錄音型（playAndRecord
            // +measurement），僅播放時走播放型（.playback，恢復
            // 外放電平）；組成未變時 applyProfile 不重設。
            AudioSessionCoordinator.shared.applyProfile()
            try session.setActive(true)
        } catch {
            lastError = "音频工作阶段启动失败：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.globalGain = compensationDB
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        let outputRate = playerNode.outputFormat(forBus: 0).sampleRate
        let clickBuffers = buffers(for: outputRate)
        core.configure(player: playerNode, sampleRate: outputRate, buffers: clickBuffers)
        do {
            try engine.start()
        } catch {
            lastError = "节拍器引擎启动失败：\(error.localizedDescription)"
            releaseSessionIfUnused()
            return
        }
        playerNode.play()
        avEngine = engine
        player = playerNode
        gainEQ = eq
        HapticsEngine.shared.warmUp()
        core.startScheduling()
        isPlaying = true
        lastEngineStartUptime = ProcessInfo.processInfo.systemUptime
        registerNotifications()
    }

    func stop() {
        guard isPlaying else { return }
        core.stopScheduling()
        player?.stop()
        avEngine?.stop()
        avEngine = nil
        player = nil
        gainEQ = nil
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
        } else {
            // 尚有其他使用者：組成改變可能觸發型態切換（如
            // 調音已退、只剩 Drone → 播放型），由協調器裁決。
            AudioSessionCoordinator.shared.applyProfile()
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
                switch type {
                case .began:
                    // 中斷開始：渲染時鐘先凍結（session 已被
                    // 系統停用，player 繼續跑只會空轉排程）；
                    // 拍序不重置，恢復時 resync 重新錨定。
                    self.player?.pause()
                    // 【返修批7・D6】調度器一併凍結：舊版只
                    // pause player，25 ms 定時器續跑，0.12 s
                    // 前瞻耗盡後仍逐拍派發震動／視覺（聲音已
                    // 停、震動先行）。恢復走 resumeScheduling。
                    self.core.pauseScheduling()
                case .ended:
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.resumeAfterInterruption()
                    } else {
                        // 系統不建議自動恢復：明確停機並給可見
                        // 提示（View 層以 toast 呈現 lastError），
                        // 不留「畫面在跑、聲音已死」的靜默狀態。
                        self.stop()
                        self.lastError = "节拍器因中断停止，点按开始可继续"
                    }
                @unknown default:
                    break
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                // 耳機／外接裝置被拔：自動暫停防外放突響
                // （藍圖 Pass 標準「拔插藍牙耳機」項）。以完整
                // stop 落地（調度、Live Activity、session 會計
                // 一致收尾），提示經 lastError → toast 可見。
                self.stop()
                self.lastError = "耳机已拔出，节拍器已自动暂停"
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
        registerConfigurationChangeObserver()
    }

    private func unregisterNotifications() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens = []
        unregisterConfigurationChangeObserver()
    }

    /// 配置變更觀察（返修批7・D2）：綁當下引擎實例；自愈
    /// 重建後由 rebuild 路徑重新呼叫本函數換綁新實例（先移
    /// 除舊代幣，不重複註冊）。重建自身觸發的變更以 0.75 s
    /// 去抖忽略（同 AudioEngine 形制）。
    private func registerConfigurationChangeObserver() {
        unregisterConfigurationChangeObserver()
        guard let engine = avEngine else { return }
        configurationChangeToken = NotificationCenter.default.addObserver(
            forName: AVAudioEngine.configurationChangeNotification,
            object: engine, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying,
                      ProcessInfo.processInfo.systemUptime - self.lastEngineStartUptime >= 0.75
                else { return }
                self.rebuildEngineAfterConfigurationChange()
            }
        }
    }

    private func unregisterConfigurationChangeObserver() {
        if let token = configurationChangeToken {
            NotificationCenter.default.removeObserver(token)
            configurationChangeToken = nil
        }
    }

    private func resumeAfterInterruption() {
        guard let avEngine, let player else {
            // 引擎引用遺失卻仍標記播放中：不靜默——停機並
            // 報錯，讓 UI 狀態與聲音現實重新一致。
            stop()
            lastError = "中断后恢复失败：引擎状态遗失，已停止"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try avEngine.start()
            player.play()
            core.resyncAfterInterruption()
            core.resumeScheduling()
        } catch {
            // 【返修批7・D1】舊版只寫 lastError 不停機：引擎已
            // 死、isPlaying 恆 true，UI 顯示播放中卻無聲，須手
            // 動按停才收斂。比照本函數 guard 分支與 .ended 不
            // 恢復分支——完整 stop 落地（調度／session 會計／
            // 觀察者一併收尾），再寫錯誤供 toast 呈現。
            stop()
            lastError = "中断后恢复失败：\(error.localizedDescription)"
        }
    }

    /// 配置變更自愈（返修批7・D2）：播放中裝置切換致輸出
    /// 格式（取樣率）改變時，舊 player 的連接格式與按舊速率
    /// 渲染的點音緩衝可能失效——按 start() 的建圖配方原地
    /// 重建引擎圖。調度狀態不動（拍序／漸速保留），resync
    /// 重新錨定樣本時間格。與 routeChange 的分工：裝置被拔
    /// （.oldDeviceUnavailable）走 stop 防外放突響；仍有裝置
    /// 而格式改變走本路徑。重建失敗比照 D1：完整 stop＋
    /// lastError 可見，不留假播放狀態。
    private func rebuildEngineAfterConfigurationChange() {
        guard isPlaying, let oldEngine = avEngine else { return }
        oldEngine.stop()
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.globalGain = compensationDB
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        let outputRate = playerNode.outputFormat(forBus: 0).sampleRate
        core.configure(player: playerNode, sampleRate: outputRate,
                       buffers: buffers(for: outputRate))
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            stop()
            lastError = "音频配置变更后重建失败：\(error.localizedDescription)"
            return
        }
        playerNode.play()
        avEngine = engine
        player = playerNode
        gainEQ = eq
        lastEngineStartUptime = ProcessInfo.processInfo.systemUptime
        core.resyncAfterInterruption()
        registerConfigurationChangeObserver()
    }
}
