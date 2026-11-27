import Combine
import Foundation
import QuartzCore

/// 音高軌跡統計（母本 computeTraceStats，行 9231）：保留最近
/// TRACE_SPAN_MS(8000)＋200 ms 寬限內的樣本（tracePush 的裁切式）；
/// 有效樣本（非空音分）≥ 6 才出統計；穩定度 =
/// clamp(round(100 − std × 5.2), 0, 100)，std 為母體標準差，
/// round 用 JS Math.round 語義（floor(x + 0.5)）。
struct StabilityTracker {
    private(set) var samples: [(t: TimeInterval, cents: Double?)] = []
    var frozen = false

    mutating func push(t: TimeInterval, cents: Double?) {
        if frozen { return }
        samples.append((t, cents))
        let cut = t - 8.2
        while let first = samples.first, first.t < cut {
            samples.removeFirst()
        }
    }

    mutating func reset() {
        samples.removeAll()
    }

    var stats: (stability: Int, mean: Double)? {
        let valid = samples.compactMap { $0.cents }.filter { $0.isFinite }
        guard valid.count >= 6 else { return nil }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let variance = valid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(valid.count)
        let std = sqrt(variance)
        let stability = max(0, min(100, Int(floor(100 - std * 5.2 + 0.5))))
        return (stability, mean)
    }
}

/// 音分讀數滾動（母本 updateCentsDisplay／tickCentsDisplay，行 9453）：
/// 讀數跟隨 spring 值；目標跳變 > 15¢ 時改以 180 ms 三次 ease-out
/// 滾過去；滾動中目標再變 > 2¢ 則自當前值重新滾。
private struct CentsDisplayRoll {
    private(set) var value: Double = 0
    private var from: Double = 0
    private var to: Double = 0
    private var t0: TimeInterval = 0
    private(set) var active = false

    mutating func update(target: Double, now: TimeInterval) {
        if active {
            if abs(target - to) > 2 {
                from = value
                to = target
                t0 = now
            }
            return
        }
        if abs(target - value) > 15 {
            from = value
            to = target
            t0 = now
            active = true
            return
        }
        value = target
    }

    mutating func tick(now: TimeInterval) {
        guard active else { return }
        let k = min(1, (now - t0) / 0.180)
        let e = 1 - pow(1 - k, 3)
        value = from + (to - from) * e
        if k >= 1 {
            value = to
            active = false
        }
    }

    mutating func reset() {
        value = 0
        from = 0
        to = 0
        active = false
    }
}

/// CADisplayLink 的轉發代理：link 強引用代理、代理弱引用 ViewModel，
/// 無循環；回調在主 runloop 觸發，以 MainActor.assumeIsolated 跳回
/// （與階段 1 AudioEngine 的既定模式一致）。
private final class DisplayLinkProxy: NSObject {
    weak var owner: TunerViewModel?

    @objc func onTick(_ link: CADisplayLink) {
        // 先在閉包外取值：assumeIsolated 的 @Sendable 閉包若直接捕獲
        // non-Sendable 的 self（代理）與 link（CADisplayLink），Swift 6
        // 會報 sending data race。timestamp 是 Double、owner 是
        // @MainActor 隔離類別，兩者捕獲皆安全（與 AudioEngine 捕獲
        // @MainActor self 的既定模式一致）。assumeIsolated 同步執行，
        // timestamp 取的仍是回調當刻的 link.timestamp，語義不變。
        let timestamp = link.timestamp
        let owner = self.owner
        MainActor.assumeIsolated {
            owner?.displayTick(now: timestamp)
        }
    }
}

/// 目標音晶片一筆（母本 renderTargetStrip 的 items，行 8515）。
struct TargetChipItem: Identifiable, Equatable {
    var label: String
    var note: String
    var isGreen: Bool
    var id: String { label + "|" + note }
}

/// 調音主畫面的顯示狀態機：把 AudioEngine 的 PitchReading 流轉成
/// 錶盤／讀數的發佈狀態。逐項對照母本 pitchLoop 的 UI 行為：
/// - 針值直接取 PitchSmoother 的 spring 輸出與兩層尾跡（每幀 reading 攜帶）；
/// - 音名／頻率只在有效音高幀更新，無聲時保留（母本同）；
/// - 準音鎖定：連續入容差 ≥ 650 ms → locked（母本行 9650）；
/// - #13 定格針：氣息停止後把最後穩定音分凍結 1.5 s，
///   最後 400 ms 線性淡出（母本 paintGauge 的 ghost 行為）；
/// - 音分文字走滾動機（見 CentsDisplayRoll）；
/// - 穩定度徽章文字四態與母本 updateTraceBadge 相同；
/// - 引擎停止 → resetReadout（對照母本 resetTunerReadout，行 9183）。
///
/// 刷新節奏：CADisplayLink 目標 120 Hz（CAFrameRateRange 80–120），
/// 只驅動與時間相關的量（音分滾動、定格針淡出）；針值本身隨 reading
/// 到達率（分析 hop ≈ 94 Hz）更新。省電：引擎未運行、或（無音高且
/// 針已回正 |cents| ≤ 0.02 且無定格針且未在滾動）時暫停 link，
/// 新 reading 達條件時自動喚醒；畫面離開時 invalidate。
/// 高頻渲染狀態（返修批4・效能隔離）：音高分析每幀（≈94 Hz）
/// 與顯示時鐘（120 Hz）寫入的全部顯示值集中於此獨立
/// ObservableObject。調音頁的靜態外殼（樂器卡、晶片列、
/// Drone 膠囊）只觀察 AppStore／DroneEngine／ViewModel
/// （皆低頻），高速顯示區（錶盤／頻閃／音名／數據卡／
/// 軌跡）才觀察本對象——舊架構下 ViewModel 的每一次
/// @Published 寫入都讓整頁幾十個玻璃面跟著重算（每秒
/// 近 200 次），是指針卡頓、頻閃不絲滑與手機發燙的共
/// 同根因。隔離後整頁重算只剩顯示區本身（Canvas＋文
/// 字），與 MetronomeView 的 DialRenderState 同法。
@MainActor
final class TunerRenderState: ObservableObject {
    // 錶盤（顯示值：由顯示時鐘以 120 Hz 向目標插值，見
    // TunerViewModel.displayTick；分析幀只寫目標）。
    @Published var needleCents: Double = 0
    @Published var trail1Cents: Double = 0
    @Published var trail2Cents: Double = 0
    @Published var ghostCents: Double?
    @Published var ghostOpacity: Double = 0
    @Published var isInTune = false
    // 頻閃主顯示（相位錨點＋角速度，StrobeView 顯示幀外推）。
    @Published var strobePhase: Double = 0
    @Published var strobeRate: Double = 0
    @Published var strobeConfidence: Double = 0
    @Published var strobeAnchorDate: Date = Date()
    // 讀數。
    @Published var noteText = "--"
    @Published var octaveText = ""
    @Published var hasNote = false
    @Published var noteLocked = false
    @Published var solfegeText = "本调 --"
    @Published var writtenText = "--"
    @Published var concertText = "--"
    @Published var frequencyText = "0.0 Hz"
    @Published var displayCents: Double = 0
    @Published var stabilityBadgeText = "轻点定格"
    @Published var stabilityFrozen = false
    // 削波警示。
    @Published var clipWarning = false

    /// 音分文字（母本 paintCentsTexts 格式：正數帶 +、一位小數、" ¢"）。
    var centsDisplayText: String {
        let body = String(format: "%.1f", displayCents)
        return (displayCents > 0 ? "+" + body : body) + " ¢"
    }
}

@MainActor
final class TunerViewModel: ObservableObject {
    /// 高頻渲染狀態（返修批4）：見 TunerRenderState 類註解。
    /// 本類只保留低頻狀態（lockedTargetNote 等）；每幀寫
    /// 入一律走 render，視圖層的高速顯示區直接觀察 render。
    let render = TunerRenderState()


    // MARK: - 鎖定目標音（母本 state.lockedTargetNote，僅執行期）

    /// 鎖定目標音的音名字串；nil = 自動識別。變更同步進引擎核心
    /// （音分判準）與 Drone 目標音（母本目標晶片處理，行 8562）。
    @Published private(set) var lockedTargetNote: String?

    /// 無訊號自報（專屬規範 S-1）：開麥後 1.5 s 內無任一
    /// 幀 rms 達噪聲門 → true（輸入增益殘值/通道異常的典
    /// 型症狀，批8「調音無讀數」遺留）；見過訊號即清、
    /// 本會話不再觸發。置於 VM（低頻對象）而非 render，
    /// 提示槽與數據卡經 TunerView 重繪讀取，不破壞返修
    /// 批4 的高頻隔離。
    @Published var noSignal = false
    private var micStartedAt: TimeInterval?
    private var sawSignal = false

    var lockedTargetMidi: Int? {
        lockedTargetNote.map { PitchMath.midi(noteString: $0) }
    }

    /// 滑奏中（目標列拖動）：點按的「再點取消鎖定」不生效、Drone
    /// 改頻走滑音常數（母本 droneGlide，行 8576）。
    private(set) var isGliding = false

    // MARK: - 內部狀態

    let engine: AudioEngine
    let store: AppStore
    let drone: DroneEngine
    private var cancellables: Set<AnyCancellable> = []

    /// #12 音高跟隨的候選音與起始時刻（母本 droneFollowTimer）。
    private var followCandidate: Int?
    private var followSince: TimeInterval?

    private var lastReading: PitchReading?
    /// 針／尾跡的分析幀目標（返修批4）：ingest 只寫目標，
    /// 顯示值（render.needleCents 等）由 displayTick 以顯示
    /// 幀率指數趨近（τ 針 22 ms／尾跡 50／85 ms）——分析
    /// 幀率 ≈94 Hz 且到達間隔不勻，直接驅動針值就是「一段
    /// 段跳」；顯示幀插值後針在 120 Hz 連續滑動。
    private var needleTarget = 0.0
    private var trail1Target = 0.0
    private var trail2Target = 0.0
    private var lastTickTime: TimeInterval?
    /// 靜默幀連續標誌（返修批4・省電早退）。
    private var lastWasQuiescent = false
    /// 徽章統計上次重算時刻（返修批7・F7 節流，見 ingest）。
    private var lastBadgeRefreshTime: TimeInterval = -.infinity
    private var hadValidPitch = false
    private var lastStableCents: Double = 0
    private var ghostUntil: TimeInterval = 0
    private var inTuneSince: TimeInterval?
    /// 上次峰值高於釋放閾值的時刻（單調時鐘）；初始 −∞ 表示從未高於。
    private var clipLastAboveRelease: TimeInterval = -.infinity
    private var centsRoll = CentsDisplayRoll()
    private var stability = StabilityTracker()

    /// 音高軌跡圖的樣本來源（返修批3 補回母本 .trace-wrap）：
    /// 與穩定度統計同一緩衝（最近 8.2 s、含空值間隙）；定格
    /// 時 push 停擺、樣本自然凍結，圖面與徽章同義。
    var traceSamples: [(t: TimeInterval, cents: Double?)] {
        stability.samples
    }

    private let linkProxy = DisplayLinkProxy()
    private var displayLink: CADisplayLink?
    /// 頁面可見性（返修批7・F11 門控，見 setPageVisible）。
    private var pageVisible = true

    /// 削波警示閾值（階段 7 驗收清單：−1 dBFS 入／−6 dBFS 釋放／保持 1.5 s；
    /// peak 為線性 0–1，dBFS = 20·log10(peak)）。
    private static let clipEnterPeak = pow(10.0, -1.0 / 20.0)    // ≈ 0.8913
    private static let clipReleasePeak = pow(10.0, -6.0 / 20.0)  // ≈ 0.5012
    private static let clipHoldSeconds: TimeInterval = 1.5

    /// 母本 SOLFEGE_MAP（行 6187），索引為記譜音 pitch class。
    private static let solfegeMap = [
        "1 Do", "♯1 Di", "2 Re", "♭3 Me", "3 Mi", "4 Fa",
        "♯4 Fi", "5 Sol", "♭6 Le", "6 La", "♭7 Te", "7 Ti",
    ]

    /// 副作用總開關（階段 7 同屏補齊）：ContentView 的 ZStack
    /// 常駐調音頁與同屏頁兩個 TunerViewModel 實例；同屏實例
    /// 須設 false 純顯示——不發觸感／音效、不改 Drone 頻率與
    /// 引擎鎖定狀態（由調音頁正規實例單一發出，防雙實例在
    /// 鎖定／跟隨時重複觸發）。預設 true，調音頁行為不變。
    var drivesSideEffects = true

    init(engine: AudioEngine, store: AppStore, drone: DroneEngine) {
        self.engine = engine
        self.store = store
        self.drone = drone
        linkProxy.owner = self

        // 選樂器（母本 selectInstrument，行 8485）：清鎖定目標、
        // 清音高軌跡統計；Drone 播放中因鎖定清除改頻回 A4
        // （母本行 8504 的 updateDroneFrequency）。訂閱 selectionPulse
        // 而非 selectedInstrumentId：同名重選母本同樣清鎖定。
        store.$selectionPulse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lockedTargetNote = nil
                    self.engine.setLockedTarget(midi: nil)
                    self.stability.reset()
                    self.followCandidate = nil
                    self.followSince = nil
                    self.refreshBadgeText()
                    if self.drivesSideEffects, self.drone.isPlaying {
                        self.drone.retarget(midi: 69, glide: false)
                    }
                }
            }
            .store(in: &cancellables)

        // 記譜/實音切換：以最後一幀有效讀數即時重算主顯示音名
        // （母本 pitchLoop 每幀重繪，效果相同）。
        store.$pitchMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,
                          let reading = self.lastReading,
                          reading.hasPitch,
                          let targetMidi = reading.targetMidi
                    else { return }
                    self.updateNoteDisplay(targetMidi: targetMidi)
                }
            }
            .store(in: &cancellables)

        // 語言切換：儲存型文字（穩定度徽章）以新語言片段重組；
        // 唱名／Drone 鈕為顯示端查表，不在此處理。
        store.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshBadgeText()
                }
            }
            .store(in: &cancellables)

        // 【返修批7・F2】讀數訂閱改走 engine.readingBox
        // （latestReading 已自 engine 本體拆出，見 ReadingBox）。
        engine.readingBox.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                MainActor.assumeIsolated {
                    guard let reading else { return }
                    self?.ingest(reading)
                }
            }
            .store(in: &cancellables)

        engine.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if running {
                        self.micStartedAt = ProcessInfo.processInfo.systemUptime
                        self.sawSignal = false
                        self.noSignal = false
                        self.ensureDisplayLink()
                    } else {
                        self.micStartedAt = nil
                        self.noSignal = false
                        self.resetReadout()
                        self.pauseDisplayLink()
                    }
                }
            }
            .store(in: &cancellables)

        // 徽章初值以目前語言組裝（@Published 初值為源串佔位）。
        refreshBadgeText()
    }

    // MARK: - Reading 入口

    private func ingest(_ reading: PitchReading) {
        lastReading = reading
        let now = ProcessInfo.processInfo.systemUptime
        // 【專屬規範 S-1】無訊號自報（置於靜默早退之前：
        // 靜默幀正是要判定的對象）：開麥後持續無幀達噪
        // 聲門逾 1.5 s → noSignal；任一幀達門即 sawSignal
        // （本會話不再觸發，安靜環境不誤報）。
        // 【全邏輯複查・低】錨點補強：isRunning sink 經
        // receive(on: main) 送達有幀級延遲，sink 前到達
        // 的幀原被跳過（不計 sawSignal）；改以首幀到達
        // 時刻補錨，判定窗貼近引擎實際啟動。
        if engine.isRunning, micStartedAt == nil {
            micStartedAt = now
        }
        if let started = micStartedAt, !sawSignal {
            if reading.rms >= engine.settings.noiseGate.rmsThreshold {
                sawSignal = true
                if noSignal { noSignal = false }
            } else if now - started > 1.5, !noSignal {
                noSignal = true
            }
        }
        // 【返修批4・靜默幀早退】麥克風開著、無音高、無定格
        // 針、頻閃可信度已落底、針已回正、無削波警示時，本幀
        // 與上一幀都沒有任何可顯示的變化：跳過全部寫入（否則
        // 分析管線在靜默中仍以 ≈94 Hz 空轉發布，持續產熱）。
        // 第一幀靜默仍走完整路徑（把針目標歸零、讓針滑回中
        // 央）；其後連續靜默才早退。代價：靜默期間音高軌跡
        // 停止推進（樣本不新增），有意為之的省電取捨。
        let quiescent = !reading.hasPitch && !hadValidPitch
            && render.ghostCents == nil
            && reading.strobe.confidence == 0
            && render.strobeConfidence == 0
            && abs(render.needleCents) < 0.02
            && !render.clipWarning
        if quiescent, lastWasQuiescent {
            return
        }
        lastWasQuiescent = quiescent
        needleTarget = reading.cents
        trail1Target = reading.trail1Cents
        trail2Target = reading.trail2Cents

        // 削波警示狀態機（與音高有效性無關：過載幀常被檢測
        // 回絕，峰值仍須計入——detector 在回絕前已算峰值）。
        if reading.peak >= Self.clipReleasePeak {
            clipLastAboveRelease = now
        }
        if reading.peak >= Self.clipEnterPeak {
            render.clipWarning = true
        } else if render.clipWarning, now - clipLastAboveRelease > Self.clipHoldSeconds {
            render.clipWarning = false
        }

        // 頻閃錨點（兩種模式都更新，切換即時生效）：分析時刻
        // （uptime）換算為牆鐘錨點，供 StrobeView 的 TimelineView
        // 以 context.date 外推。
        let strobe = reading.strobe
        render.strobePhase = strobe.phase
        render.strobeRate = strobe.angularRate
        render.strobeConfidence = strobe.confidence
        render.strobeAnchorDate = Date().addingTimeInterval(-(now - strobe.time))

        if reading.hasPitch, let targetMidi = reading.targetMidi {
            hadValidPitch = true
            lastStableCents = reading.cents
            // 【全邏輯複查・低】新音高到達即清定格針：舊
            // 版 ghost 只能靠 ghostUntil（1.5 s）自然到
            // 期，新音的活針與前音定格針最長共存 1.5 s。
            // 定格針的職責是停頓期標記前音位置，新音既
            // 至即由活針接管，清之無資訊損失。
            if render.ghostCents != nil {
                render.ghostCents = nil
                render.ghostOpacity = 0
            }

            updateNoteDisplay(targetMidi: targetMidi)

            render.frequencyText = String(format: "%.1f Hz", reading.smoothedFrequency)
            centsRoll.update(target: reading.cents, now: now)

            // #12 音高跟隨（母本行 9614）：droneFollow 開時，偵測音
            // （平滑頻率的最近音，與鎖定狀態無關）恆定 ≥ 1000 ms
            // 且 ≠ 目前目標（無鎖定以 69 計）→ 鎖定改為該音、
            // Drone 播放中即改頻、計時重置。
            let detectedMidi = Int(PitchMath.exactMidi(
                frequency: reading.smoothedFrequency,
                a4: engine.settings.a4).rounded())
            let currentTarget = lockedTargetMidi ?? 69
            if drivesSideEffects, store.droneFollow, detectedMidi != currentTarget {
                if followCandidate == detectedMidi, let since = followSince {
                    if now - since >= 1.0 {
                        applyLock(note: PitchMath.noteName(midi: detectedMidi),
                                  midi: detectedMidi)
                        followCandidate = nil
                        followSince = nil
                    }
                } else {
                    followCandidate = detectedMidi
                    followSince = now
                }
            } else {
                followCandidate = nil
                followSince = nil
            }

            // 準音鎖定（母本行 9650）：連續入容差 ≥ 650 ms。
            // 觸感（規格書 §3.6，階段 3 補階段 2 欠筆）：入容差
            // 上升沿輕震（母本 haptic(14)）、鎖定上升沿震動圖案
            // [8,35,16]（母本 lock 的 vibrate 呼叫點）；總開關在
            // HapticsEngine 內部門控（settings.hapticsOn 同步）。
            let wasInTune = render.isInTune
            render.isInTune = reading.isInTune
            if reading.isInTune {
                if drivesSideEffects, !wasInTune {
                    HapticsEngine.shared.tap(milliseconds: 14)
                }
                if let since = inTuneSince {
                    if now - since >= 0.650, !render.noteLocked {
                        render.noteLocked = true
                        if drivesSideEffects {
                            // 階段 6：鎖定棘輪專屬圖樣（形制沿母本
                            // [8, 35, 16]，數值見 HapticPatternTable）。
                            HapticsEngine.shared.inTuneLock()
                            // 母本 uiSound("lock")（行 9655，同呼叫點）。
                            UISoundEngine.shared.play(.lock)
                        }
                    }
                } else {
                    inTuneSince = now
                }
            } else {
                inTuneSince = nil
                render.noteLocked = false
            }

            stability.push(t: now, cents: reading.cents)
        } else {
            render.isInTune = false
            inTuneSince = nil
            render.noteLocked = false

            // #13：氣息停止 → 定格針凍結最後穩定值 1.5 s（母本行 9706）。
            if hadValidPitch {
                render.ghostCents = lastStableCents
                ghostUntil = now + 1.5
                hadValidPitch = false
            }
            stability.push(t: now, cents: nil)
        }

        // 【返修批7・F7】徽章統計節流：refreshBadgeText 每
        // 次都全量掃描 stability 樣本（~770 筆）＋3 次 L10n
        // 查表，舊版隨 ingest 以 ≈94 Hz 空轉（寫入守衛只省
        // 發布、不省建構）。徽章是文字標籤、統計窗長 8.2 s，
        // 改節流 ≈120 ms 才重算，視覺無差異；其餘呼叫點
        // （定格切換／語言／選樂器／重置／init）仍即時刷新、
        // 不經此節流。
        if now - lastBadgeRefreshTime >= 0.12 {
            lastBadgeRefreshTime = now
            refreshBadgeText()
        }
        if needsMotion {
            ensureDisplayLink()
        }
    }

    // MARK: - 音名顯示（母本 pitchLoop 行 9598–9612）

    /// 主顯示音名依 pitchMode：written → 記譜音、concert → 實音
    /// （母本 displayMidi 選擇）；數據卡恆雙列記譜／實音；唱名恆
    /// 取記譜 pitch class（母本行 9610）。
    private func updateNoteDisplay(targetMidi: Int) {
        let writtenMidi = targetMidi - engine.range.transposition
        render.writtenText = PitchMath.noteName(midi: writtenMidi)
        render.concertText = PitchMath.noteName(midi: targetMidi)
        let writtenPc = ((writtenMidi % 12) + 12) % 12
        render.solfegeText = "本调 " + Self.solfegeMap[writtenPc]

        let displayed = store.pitchMode == .written ? writtenMidi : targetMidi
        let pc = ((displayed % 12) + 12) % 12
        render.noteText = PitchMath.noteNames[pc]
        render.octaveText = String(Int(floor(Double(displayed) / 12.0)) - 1)
        render.hasNote = true
    }

    // MARK: - 鎖定目標音（母本 renderTargetStrip 晶片處理，行 8557）

    private func applyLock(note: String, midi: Int) {
        lockedTargetNote = note
        engine.setLockedTarget(midi: midi)
        if drone.isPlaying {
            drone.retarget(midi: midi, glide: isGliding)
        }
    }

    private func clearLock() {
        lockedTargetNote = nil
        engine.setLockedTarget(midi: nil)
        if drone.isPlaying {
            drone.retarget(midi: 69, glide: isGliding)
        }
    }

    /// 晶片點按：自動識別晶片（note = nil）清除鎖定；同一音再點
    /// 取消鎖定（滑奏中除外）；其餘設為鎖定。母本 haptic(5)＋
    /// uiSound("tick")（行 8562）。
    func tapTargetChip(note: String?) {
        HapticsEngine.shared.tap(milliseconds: 5)
        UISoundEngine.shared.play(.tick)
        guard let note else {
            clearLock()
            return
        }
        if lockedTargetNote == note, !isGliding {
            clearLock()
        } else {
            applyLock(note: note, midi: PitchMath.midi(noteString: note))
        }
    }

    /// 目標列拖動滑奏：經過的晶片直接接管鎖定（不切換取消）。
    func glideToTarget(note: String) {
        if lockedTargetNote != note {
            applyLock(note: note, midi: PitchMath.midi(noteString: note))
        }
    }

    func setGliding(_ gliding: Bool) {
        isGliding = gliding
        if !gliding, drone.isPlaying {
            // 滑奏結束：改頻常數回一般值（母本 droneGlide=false 後
            // 下一次 updateDroneFrequency 回 0.045；此處以目前目標
            // 重發一次使常數即時復位，頻率不變）。
            drone.retarget(midi: lockedTargetMidi ?? 69, glide: false)
        }
    }

    /// 目標晶片清單（母本 renderTargetStrip，行 8515）：古箏 →
    /// 目前調號 21 弦（弦號 21→1、綠弦 3/8/13/18）；有 strings →
    /// 弦晶片；其餘 → refTargets，無則母本預設五晶片。
    var targetChipItems: [TargetChipItem] {
        let inst = store.selectedInstrument
        if inst.isGuzheng {
            let notes = InstrumentCatalog.guzhengTuning(key: store.guzhengKey)
            return notes.enumerated().map { idx, note in
                let stringNumber = 21 - idx
                return TargetChipItem(
                    label: "\(stringNumber)弦 \(note)", note: note,
                    isGreen: [3, 8, 13, 18].contains(stringNumber))
            }
        }
        if let strings = inst.stringNotes {
            return strings.enumerated().map { idx, note in
                TargetChipItem(label: "\(idx + 1)弦·\(note)", note: note, isGreen: false)
            }
        }
        if let refs = inst.refTargets {
            return refs.map {
                TargetChipItem(label: $0.label, note: $0.note, isGreen: false)
            }
        }
        return [
            TargetChipItem(label: "标准 A4", note: "A4", isGreen: false),
            TargetChipItem(label: "管乐 B♭4", note: "B♭4", isGreen: false),
            TargetChipItem(label: "中央 C4", note: "C4", isGreen: false),
            TargetChipItem(label: "F4", note: "F4", isGreen: false),
            TargetChipItem(label: "G4", note: "G4", isGreen: false),
        ]
    }

    // MARK: - Drone 控制（母本 droneCapsule，行 10217）

    /// Drone 目標音：鎖定音 ?? A4(69)（母本 droneTargetFreq）。
    var droneTargetMidi: Int { lockedTargetMidi ?? 69 }

    /// 主鈕文案（母本 droneBtnText）：停止 (X)／基准音 X。
    /// 回 zh-CN 源串組裝，顯示端（TunerView）以 L10n.t 查表
    /// （「停止 (」「基准音 」皆為字典前綴鍵，與母本 tStr 組法一致）。
    var droneButtonText: String {
        let note = lockedTargetNote ?? "A4"
        return drone.isPlaying ? "停止 (\(note))" : "基准音 \(note)"
    }

    /// 開關 Drone（母本 toggleDrone）：開 haptic(12)、關 haptic(8)
    /// ＋uiSound("close")（行 10182，母本停止 Drone 的呼叫點）。
    func toggleDrone() {
        if drone.isPlaying {
            drone.stop()
            HapticsEngine.shared.tap(milliseconds: 8)
            UISoundEngine.shared.play(.close)
        } else {
            drone.start(targetMidi: droneTargetMidi, timbre: store.droneTimbre)
            HapticsEngine.shared.tap(milliseconds: 12)
        }
    }

    /// 音高跟隨開關（母本 followBtn）：切換 haptic(7)＋
    /// uiSound("tick")（行 10213）；關閉時清跟隨候選
    /// （母本 droneFollowTimer 隨之失效）。
    func toggleDroneFollow() {
        store.droneFollow.toggle()
        if !store.droneFollow {
            followCandidate = nil
            followSince = nil
        }
        HapticsEngine.shared.tap(milliseconds: 7)
        UISoundEngine.shared.play(.tick)
    }

    // MARK: - 純律主音（母本 #24 justTonicPill／Strip，行 7031）

    /// 純律主音快選：寫入設定（ContentView 同步進引擎與 Drone
    /// 改頻），母本 haptic(8)＋uiSound("tick")（行 7058）。
    func setJustTonic(_ pc: Int) {
        store.tunerSettings.justTonicPc = pc
        HapticsEngine.shared.tap(milliseconds: 8)
        UISoundEngine.shared.play(.tick)
    }

    // MARK: - 顯示時鐘

    /// 是否仍有與時間相關的動畫未 settled（決定 link 去留）。
    private var needsMotion: Bool {
        guard engine.isRunning else { return false }
        if lastReading?.hasPitch == true { return true }
        if abs(render.needleCents) > 0.02 { return true }
        if abs(needleTarget - render.needleCents) > 0.02 { return true }
        if abs(trail1Target - render.trail1Cents) > 0.02 { return true }
        if abs(trail2Target - render.trail2Cents) > 0.02 { return true }
        if render.ghostCents != nil { return true }
        if centsRoll.active { return true }
        return false
    }

    func displayTick(now: TimeInterval) {
        // 針／尾跡顯示幀插值（返修批4）：向分析幀目標指數
        // 趨近，dt 以 link 時間戳計（夾 1–50 ms）；|Δ| <
        // 0.01 直接貼合，避免無窮小抖動反覆發布。
        let dt: TimeInterval
        if let last = lastTickTime {
            dt = min(0.05, max(0.001, now - last))
        } else {
            dt = 1.0 / 120.0
        }
        lastTickTime = now
        Self.approach(&render.needleCents, to: needleTarget, tau: 0.022, dt: dt)
        Self.approach(&render.trail1Cents, to: trail1Target, tau: 0.05, dt: dt)
        Self.approach(&render.trail2Cents, to: trail2Target, tau: 0.085, dt: dt)

        centsRoll.tick(now: now)
        // 【返修批4】值不變不寫入（同 approach 註解）：穩態下
        // 音分滾動不活動，displayCents 恆定，不應每顯示幀發布。
        if render.displayCents != centsRoll.value {
            render.displayCents = centsRoll.value
        }

        if render.ghostCents != nil {
            if now < ghostUntil {
                let remain = ghostUntil - now
                let fade = remain < 0.4 ? remain / 0.4 : 1
                let opacity = 0.35 * fade
                if render.ghostOpacity != opacity {
                    render.ghostOpacity = opacity
                }
            } else {
                render.ghostCents = nil
                render.ghostOpacity = 0
            }
        }

        if !needsMotion {
            pauseDisplayLink()
        }
    }

    /// 一階指數趨近（顯示幀插值用）：x += (to − x)·(1 − e^(−dt/τ))。
    private static func approach(_ x: inout Double, to target: Double,
                                 tau: Double, dt: TimeInterval) {
        // 【返修批4】已貼合即不寫入：@Published 每寫一次即發布
        // 一次，穩態下每顯示幀的重寫會讓顯示區白白重算 120 次／秒。
        guard x != target else { return }
        let k = 1 - exp(-dt / tau)
        x += (target - x) * k
        if abs(target - x) < 0.01 { x = target }
    }

    /// 頁面可見性門控（返修批7・F11）：ContentView 雙頁
    /// 保活（ZStack 疊放、僅切透明度），不可見頁的顯示
    /// 時鐘不應續跑——舊版最壞 3 條 120 Hz driver 並存
    /// （含不可見頁）。不可見時暫停 link（ingest 照常，
    /// 切回時狀態已同步、針值由 tick 續推）；重見且仍需
    /// 動態時恢復。接線在 ContentView（onAppear＋appMode
    /// onChange）。
    func setPageVisible(_ visible: Bool) {
        pageVisible = visible
        if visible {
            if needsMotion { ensureDisplayLink() }
        } else {
            pauseDisplayLink()
        }
    }

    private func ensureDisplayLink() {
        if displayLink == nil {
            let link = CADisplayLink(
                target: linkProxy,
                selector: #selector(DisplayLinkProxy.onTick(_:))
            )
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 80, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        // 【F11】不可見頁不解暫停（setPageVisible 統一門控）。
        displayLink?.isPaused = !pageVisible
    }

    private func pauseDisplayLink() {
        displayLink?.isPaused = true
    }

    /// 畫面離開時拆 link（避免 runloop 殘留引用）。
    func viewDidDisappear() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - 穩定度徽章

    func toggleFreeze() {
        stability.frozen.toggle()
        render.stabilityFrozen = stability.frozen
        refreshBadgeText()
        // 母本行 9268：定格 uiSound("switch")、解凍 uiSound("tick")。
        UISoundEngine.shared.play(render.stabilityFrozen ? .switch : .tick)
    }

    /// 母本 updateTraceBadge（行 9243）四態文字。以 L10n 片段
    /// 組裝（整串非字典鍵）：已定格／稳定度／轻点定格為母本
    /// 字典片段鍵、轻点继续為 supplement；語言切換經 init 的
    /// store.$language 訂閱即時重組（徽章為儲存型文字，不經
    /// 顯示端查表）。
    private func refreshBadgeText() {
        let stats = stability.stats
        let text: String
        if stability.frozen {
            if let stats {
                let mean = stats.mean
                let meanText = (mean >= 0 ? "+" : "") + String(format: "%.1f", mean)
                text = "⏸ " + L10n.t("已定格") + " · " + L10n.t("稳定度")
                    + " \(stats.stability)% (\(meanText)¢)"
            } else {
                text = "⏸ " + L10n.t("已定格") + " · " + L10n.t("轻点继续")
            }
        } else if engine.isRunning, let stats {
            text = L10n.t("稳定度") + " \(stats.stability)% · " + L10n.t("轻点定格")
        } else {
            text = L10n.t("轻点定格")
        }
        // 【返修批4】值不變不寫入：@Published 每寫一次即發布
        // 一次，舊版每分析幀都重寫同一串徽章文字。
        if render.stabilityBadgeText != text {
            render.stabilityBadgeText = text
        }
    }

    // MARK: - 重置（母本 resetTunerReadout）

    private func resetReadout() {
        needleTarget = render.needleCents
        trail1Target = render.trail1Cents
        trail2Target = render.trail2Cents
        lastWasQuiescent = false
        render.noteText = "--"
        render.octaveText = ""
        render.hasNote = false
        render.noteLocked = false
        render.isInTune = false
        render.solfegeText = "本调 --"
        render.writtenText = "--"
        render.concertText = "--"
        render.frequencyText = "0.0 Hz"
        centsRoll.reset()
        render.displayCents = 0
        // 頻閃：引擎停止 → 角速度與可信度歸零（相位保留凍結，
        // StrobeView 在 micActive=false 時恆暫停）。
        render.strobeRate = 0
        render.strobeConfidence = 0
        // 削波警示隨停止熄滅（無輸入即無過載可言）。
        render.clipWarning = false
        clipLastAboveRelease = -.infinity
        inTuneSince = nil
        hadValidPitch = false
        // 母本 reset 不清 ghost（靠 1.5 s 自然到期）；原生版停止時一併
        // 清除，避免 link 已停而淡出停在半途（視覺等價，註明差異）。
        render.ghostCents = nil
        render.ghostOpacity = 0
        stability.reset()
        refreshBadgeText()
    }
}
