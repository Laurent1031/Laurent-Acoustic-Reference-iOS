import AVFoundation
import Foundation
import os

/// 音訊會話診斷值（規格書 §3.1：IO buffer 壓低並實測延遲）。
/// 這裡是系統回報的採集側延遲組成；真正的端到端實測在階段 7 驗收做。
struct EngineDiagnostics: Sendable {
    var sampleRate: Double
    /// 實際生效的 IO buffer 時長（秒）——請求值會被系統鉗制，以此為準。
    var ioBufferDuration: TimeInterval
    /// 系統回報的輸入延遲（秒）。
    var inputLatency: TimeInterval
    /// 採集延遲估算 = inputLatency + ioBufferDuration。
    var captureLatency: TimeInterval { inputLatency + ioBufferDuration }
}

/// 引擎核心：tap 線程收樣本 → 環形緩衝 → 分析佇列跑檢測與平滑。
/// 與母本 AudioWorklet 路徑（`index.html` 行 8691）等價：
/// ring 16384、每 ≥512 新樣本分析一次最新 win 個樣本。
///
/// 線程模型：ring／設定快照以 NSLock 保護；PitchDetector 與 PitchSmoother
/// 只在串行分析佇列上存取；onReading 在分析佇列呼叫（由 AudioEngine 負責
/// 跳回 MainActor）。標記 @unchecked Sendable 基於上述紀律。
final class EngineCore: @unchecked Sendable {
    static let ringCapacity = 16384
    static let analysisHop = 512

    private let lock = NSLock()
    private var settings: TunerSettings
    private var range: InstrumentRange
    /// 鎖定目標音（母本 state.lockedTargetNote 的 MIDI 形）：非 nil
    /// 時音分判準對此音而非最近音（PitchSmoother 的 lockedTargetMidi）。
    private var lockedTargetMidi: Int?
    private var sampleRate: Double = 48000

    private var ring = [Float](repeating: 0, count: EngineCore.ringCapacity)
    private var head = 0
    private var filled = 0
    private var sinceAnalysis = 0
    private var analysisPending = false

    private let detector = PitchDetector()
    private var smoother: PitchSmoother
    /// 頻閃相位追蹤（頻閃主模式段）：只在分析佇列存取（與
    /// detector／smoother 同紀律），結果寫入 PitchReading.strobe。
    private let strobeTracker = StrobePhaseTracker()
    let log = DetectionLog()

    /// 分析結果回調。須在引擎啟動前設定一次，之後不變更；
    /// 在分析佇列上呼叫，接收方自行跳回主線程。
    var onReading: ((PitchReading) -> Void)?

    private let analysisQueue = DispatchQueue(
        label: "com.laurent.acousticreference.pitch-analysis", qos: .userInteractive)

    // 格式轉換器只在 tap 線程存取。
    private var converter: AVAudioConverter?

    init(settings: TunerSettings, range: InstrumentRange) {
        self.settings = settings
        self.range = range
        self.smoother = PitchSmoother(settings: settings)
    }

    func update(settings: TunerSettings, range: InstrumentRange) {
        lock.lock()
        self.settings = settings
        self.range = range
        lock.unlock()
    }

    func setLockedTarget(midi: Int?) {
        lock.lock()
        lockedTargetMidi = midi
        lock.unlock()
    }

    func setSampleRate(_ sampleRate: Double) {
        lock.lock()
        self.sampleRate = sampleRate
        lock.unlock()
    }

    /// 重新啟動時清空 ring（母本 worklet 每次重建亦為空 ring）；
    /// 平滑狀態比照母本跨開關保留，不重置。
    func resetRing() {
        lock.lock()
        head = 0
        filled = 0
        sinceAnalysis = 0
        lock.unlock()
    }

    // MARK: - Tap 入口（音訊線程）

    func handleTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let samples = extractSamples(from: buffer) else { return }
        guard let (window, hop) = ingest(samples) else { return }
        analysisQueue.async { [self] in
            analyze(window: window, hopSamples: hop)
        }
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        if let channelData = buffer.floatChannelData {
            let count = Int(buffer.frameLength)
            guard count > 0 else { return nil }
            return Array(UnsafeBufferPointer(start: channelData[0], count: count))
        }
        // 非 Float32 輸入格式（如藍牙 HFP 的 Int16）→ 轉換兜底。
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        if converter == nil || converter!.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter,
              let out = AVAudioPCMBuffer(
                pcmFormat: target, frameCapacity: buffer.frameLength + 1024)
        else { return nil }
        var error: NSError?
        // 輸入回調是 @Sendable 閉包，捕獲並修改 var 會觸發並發警告；
        // 改以 Sendable 的 OSAllocatedUnfairLock<Bool> 承載一次性旗標。
        // 回調由 convert 同步串行呼叫，旗標語義與原 var 完全相同。
        let consumed = OSAllocatedUnfairLock(initialState: false)
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            let isFirstCall = consumed.withLock { flag -> Bool in
                let wasConsumed = flag
                flag = true
                return !wasConsumed
            }
            guard isFirstCall else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channelData = out.floatChannelData else { return nil }
        let count = Int(out.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// 寫入 ring；達分析條件時回傳最新 win 個樣本的快照與本窗
    /// 距上窗的實際 hop（新樣本數，頻閃相位差分的時間基準），
    /// 否則 nil。
    /// 分析未跟上時丟棄新快照（母本 worklet 為阻塞式背壓，原生版以
    /// 丟幀換取不積壓，檢測結果節律不變）。
    private func ingest(_ samples: [Float]) -> (window: [Float], hop: Int)? {
        lock.lock()
        defer { lock.unlock() }
        let cap = ring.count
        for sample in samples {
            ring[head] = sample
            head = (head + 1) % cap
        }
        filled = min(cap, filled + samples.count)
        sinceAnalysis += samples.count

        let win = range.analysisWindowSize
        guard sinceAnalysis >= EngineCore.analysisHop, filled >= win else { return nil }
        // 分析未跟上時不重置 sinceAnalysis：hop 須涵蓋被丟棄的
        // 跨度，頻閃相位差分的時間基準才準（檢測本身不受影響，
        // 觸發條件恆成立、下一個 buffer 立即重試取窗）。
        guard !analysisPending else { return nil }
        let hop = sinceAnalysis
        sinceAnalysis = 0
        analysisPending = true

        var window = [Float](repeating: 0, count: win)
        var idx = (head - win) % cap
        if idx < 0 { idx += cap }
        for i in 0..<win {
            window[i] = ring[idx]
            idx = (idx + 1) % cap
        }
        return (window, hop)
    }

    // MARK: - 分析（串行分析佇列）

    private func analyze(window: [Float], hopSamples: Int) {
        lock.lock()
        let settingsSnapshot = settings
        let rangeSnapshot = range
        let lockedSnapshot = lockedTargetMidi
        let sr = sampleRate
        lock.unlock()

        smoother.settings = settingsSnapshot
        let bounds = rangeSnapshot.detectionBounds
        let detection = detector.detect(
            samples: window,
            sampleRate: sr,
            minFreq: bounds.minFrequency,
            maxFreq: bounds.maxFrequency,
            rmsGate: settingsSnapshot.noiseGate.rmsThreshold
        )
        let now = ProcessInfo.processInfo.systemUptime
        var reading = smoother.process(
            detection: detection, now: now, lockedTargetMidi: lockedSnapshot)
        // 頻閃相位追蹤：與檢測共用同一分析窗與設定快照；目標音
        // 取 smoother 的判準結果（鎖定／自動），與錶盤 cents 同源。
        reading.strobe = strobeTracker.process(
            window: window,
            hopSamples: hopSamples,
            detection: detection,
            targetMidi: reading.targetMidi,
            settings: settingsSnapshot,
            sampleRate: sr,
            now: now)
        log.append(reading: reading, now: now)
        onReading?(reading)

        lock.lock()
        analysisPending = false
        lock.unlock()
    }
}

/// 通知觀察者代幣的保管袋。
///
/// AudioEngine 是 @MainActor 隔離類別，其 deinit 為 nonisolated，
/// 不得存取隔離的 stored property（否則 Swift 6 編譯錯誤）。故把
/// 代幣陣列移出 AudioEngine、收進這個非隔離的專責類別：AudioEngine
/// 釋放時連帶釋放本袋，deinit 在此移除全部觀察者——時機與原本在
/// AudioEngine.deinit 內移除等價。代幣僅在 MainActor 上註冊，
/// deinit 只讀自身陣列並呼叫 thread-safe 的 removeObserver，
/// 無跨隔離域的並發存取。
private final class SessionObserverBag {
    private var tokens: [NSObjectProtocol] = []

    var isEmpty: Bool { tokens.isEmpty }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// 音訊引擎門面：AVAudioSession 測量模式＋AVAudioEngine 麥克風管線。
///
/// 母本對應：getUserMedia {echoCancellation:false, autoGainControl:false,
/// noiseSuppression:false}（行 9045）→ 原生等價為 AVAudioSession
/// `.measurement` 模式（關閉語音處理）。母本的 Android 專屬門檻適應
/// （IS_ANDROID 分支）為平台特例，原生版不移植。
@MainActor
final class AudioEngine: ObservableObject {
    @Published private(set) var latestReading: PitchReading?
    @Published private(set) var isRunning = false
    @Published private(set) var diagnostics: EngineDiagnostics?
    @Published private(set) var permissionDenied = false
    @Published private(set) var lastError: String?

    /// 設定變更即時同步進引擎核心（分析佇列下一個 hop 生效）。
    @Published var settings = TunerSettings() {
        didSet { core.update(settings: settings, range: range) }
    }
    /// 檢測音域（階段 1 固定預設樂器；樂器庫在階段 4 接入）。
    @Published var range: InstrumentRange = .altoSax {
        didSet { core.update(settings: settings, range: range) }
    }

    private let core: EngineCore
    private var engine: AVAudioEngine?
    /// 最近一次 startEngine 的 uptime（配置變更自愈的去抖基準）。
    private var lastEngineStartUptime: TimeInterval = 0
    /// 是否已向 AudioSessionCoordinator 登記（與節拍器共用 session
    /// 時，setActive(false) 由協調器裁決，避免誤殺對方播放）。
    private var sessionAcquired = false
    /// 觀察者代幣由專責保管袋持有，本類釋放時代幣隨袋釋放並自動
    /// 移除觀察者（見 SessionObserverBag）；deinit 不再碰隔離狀態。
    private let observerBag = SessionObserverBag()

    init() {
        core = EngineCore(settings: TunerSettings(), range: .altoSax)
    }

    // MARK: - 啟停

    func start() async {
        guard !isRunning else { return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        lastError = nil
        do {
            try startEngine()
            isRunning = true
            if !sessionAcquired {
                AudioSessionCoordinator.shared.acquire(.tuner)
                sessionAcquired = true
            }
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        // 僅在協調器確認無其他使用者（節拍器運行中）時才停用
        // session；未登記者（未成功 start 過）不碰 session。
        // 尚有播放型使用者時（補強段動態 Mode）：調音退出使組成
        // 轉為僅播放，交協調器切至播放型（.playback）恢復其
        // 外放電平——切換在邊界發生，播放引擎不因此停機。
        if sessionAcquired {
            sessionAcquired = false
            if AudioSessionCoordinator.shared.release(.tuner) {
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: [.notifyOthersOnDeactivation])
            } else {
                AudioSessionCoordinator.shared.applyProfile()
            }
        }
        isRunning = false
    }

    /// 鎖定目標音接線（階段 4）：TunerViewModel 的鎖定狀態變更時
    /// 呼叫；nil = 自動識別（最近音）。
    func setLockedTarget(midi: Int?) {
        core.setLockedTarget(midi: midi)
    }

    func exportDetectionLog() -> String {
        core.log.exportText()
    }

    func clearDetectionLog() {
        core.log.clear()
    }

    // MARK: - 內部

    /// 引擎啟動錯誤（可恢復形）：呈現於調音頁 lastError，
    /// 取代進程級中止（見 startEngine 的防禦註記）。
    enum EngineStartError: LocalizedError {
        case invalidInputFormat(sampleRate: Double, channels: Int)
        var errorDescription: String? {
            switch self {
            case .invalidInputFormat(let sampleRate, let channels):
                return "麥克風輸入格式未就緒（\(Int(sampleRate)) Hz／\(channels) ch），請重試"
            }
        }
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try configureSessionAndStart(session, mode: .measurement)
        } catch {
            // 【裝機返修・防禦】實機首裝一點麥克風即退出：
            // .ips 未到手前先做雙層防禦——(1) 下方格式守衛攔
            // installTap 的 NSException 路徑；(2) 可抛錯的
            // setCategory／start 若在 .measurement 下失敗，
            // 退 .default 重試一次（犧牲 AGC 關閉，換不閃退；
            // 檢測路徑與判準不變）。兩次皆敗才交回 UI 顯示。
            try configureSessionAndStart(session, mode: .default)
        }
    }

    private func configureSessionAndStart(_ session: AVAudioSession,
                                          mode: AVAudioSession.Mode) throws {
        try session.setCategory(.playAndRecord, mode: mode, options: [])
        // IO buffer 壓向硬體下限（規格書 §3.1）：先請求 3 ms，
        // 失敗退 5 ms；實際生效值以 session.ioBufferDuration 為準（診斷顯示）。
        if (try? session.setPreferredIOBufferDuration(0.003)) == nil {
            try? session.setPreferredIOBufferDuration(0.005)
        }
        try session.setActive(true)

        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 格式未就緒（取樣率／聲道為 0）時 installTap 會以
        // NSException 直接中止進程、Swift 層攔不到：先守衛，
        // 改以可恢復錯誤呈現（同上 EngineStartError）。
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EngineStartError.invalidInputFormat(
                sampleRate: format.sampleRate,
                channels: Int(format.channelCount))
        }
        core.setSampleRate(format.sampleRate)
        core.resetRing()
        core.onReading = { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.latestReading = reading
                }
            }
        }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [core] buffer, _ in
            core.handleTapBuffer(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        engine = audioEngine
        lastEngineStartUptime = ProcessInfo.processInfo.systemUptime

        diagnostics = EngineDiagnostics(
            sampleRate: session.sampleRate,
            ioBufferDuration: session.ioBufferDuration,
            inputLatency: session.inputLatency
        )
        registerSessionObservers()
    }

    private func registerSessionObservers() {
        guard observerBag.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observerBag.add(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: nil
        ) { [weak self] note in
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                switch type {
                case .began:
                    self.engine?.pause()
                case .ended:
                    // 中斷自愈（階段 6，藍圖 Pass 標準）：調音
                    // 是用戶主動開啟的監測而非媒體播放，中斷
                    // 結束即嘗試恢復，不以 shouldResume 為門
                    // （該旗標是給播放類的建議）；恢復失敗不
                    // 靜默——寫 lastError（調音頁可見）並落回
                    // 未運行狀態，UI 與現實一致。
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        try self.engine?.start()
                    } catch {
                        self.lastError = "中斷後恢復失敗：\(error.localizedDescription)"
                        self.engine = nil
                        self.isRunning = false
                    }
                @unknown default:
                    break
                }
            }
        })

        // 路由／格式變更自愈（階段 6）：耳機／外接麥克風插拔
        // 觸發 AVAudioEngineConfigurationChange——舊 tap 格式
        // 可能已失效，整引擎重建（isRunning 與 session 登記
        // 不動）。重建自身的配置變更以 0.75 s 去抖忽略，防
        // 重建→變更→重建的回環。
        observerBag.add(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, self.engine != nil,
                      ProcessInfo.processInfo.systemUptime - self.lastEngineStartUptime >= 0.75
                else { return }
                self.engine?.stop()
                self.engine = nil
                do {
                    try self.startEngine()
                } catch {
                    self.lastError = "音訊路由變更後重建失敗：\(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        })

        observerBag.add(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.stop()
                await self.start()
            }
        })
    }
}
