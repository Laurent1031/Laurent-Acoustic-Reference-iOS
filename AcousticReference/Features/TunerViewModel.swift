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
@MainActor
final class TunerViewModel: ObservableObject {
    // MARK: - 發佈狀態（錶盤）

    @Published private(set) var needleCents: Double = 0
    @Published private(set) var trail1Cents: Double = 0
    @Published private(set) var trail2Cents: Double = 0
    @Published private(set) var ghostCents: Double?
    @Published private(set) var ghostOpacity: Double = 0
    @Published private(set) var isInTune = false

    // MARK: - 發佈狀態（頻閃主顯示）

    /// 頻閃相位錨點：StrobeView 以 strobeRate 自 strobeAnchorDate
    /// 外推至顯示時刻。錨點隨每幀 reading 更新（≈94 Hz），與
    /// 針值同源同幀，兩種顯示模式的判讀永遠一致。
    @Published private(set) var strobePhase: Double = 0
    @Published private(set) var strobeRate: Double = 0
    @Published private(set) var strobeConfidence: Double = 0
    @Published private(set) var strobeAnchorDate: Date = Date()

    // MARK: - 發佈狀態（讀數）

    @Published private(set) var noteText = "--"
    @Published private(set) var octaveText = ""
    @Published private(set) var hasNote = false
    @Published private(set) var noteLocked = false
    @Published private(set) var solfegeText = "本調 --"
    @Published private(set) var writtenText = "--"
    @Published private(set) var concertText = "--"
    @Published private(set) var frequencyText = "0.0 Hz"
    @Published private(set) var displayCents: Double = 0
    @Published private(set) var stabilityBadgeText = "輕點定格"
    @Published private(set) var stabilityFrozen = false

    // MARK: - 發佈狀態（削波警示，補強段）

    /// 削波警示旗標：輸入峰值達 −1 dBFS 即亮，峰值回落至
    /// −6 dBFS 以下持續 1.5 s 後滅（遲滯＋保持，防邊界閃爍）。
    /// 門檻為本段自訂（母本無削波警示）：−1 dBFS 是「已非常
    /// 接近數位滿格、波形頂部大概率已被削平」的實務警戒線，
    /// 真削波（0 dBFS）才亮會漏掉臨界過載；−6 dBFS 釋放線與
    /// 1.5 s 保持則確保警示可讀、不隨每幀峰值跳動。
    @Published private(set) var clipWarning = false
    private var clipLastAboveRelease: TimeInterval = -.infinity
    private static let clipEnterPeak = 0.8913   // −1 dBFS
    private static let clipReleasePeak = 0.5012 // −6 dBFS
    private static let clipHoldSeconds = 1.5

    /// 音分文字（母本 paintCentsTexts 格式：正數帶 +、一位小數、" ¢"）。
    var centsDisplayText: String {
        let body = String(format: "%.1f", displayCents)
        return (displayCents > 0 ? "+" + body : body) + " ¢"
    }

    // MARK: - 鎖定目標音（母本 state.lockedTargetNote，僅執行期）

    /// 鎖定目標音的音名字串；nil = 自動識別。變更同步進引擎核心
    /// （音分判準）與 Drone 目標音（母本目標晶片處理，行 8562）。
    @Published private(set) var lockedTargetNote: String?

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
    private var hadValidPitch = false
    private var lastStableCents: Double = 0
    private var ghostUntil: TimeInterval = 0
    private var inTuneSince: TimeInterval?
    private var centsRoll = CentsDisplayRoll()
    private var stability = StabilityTracker()

    private let linkProxy = DisplayLinkProxy()
    private var displayLink: CADisplayLink?

    /// 母本 SOLFEGE_MAP（行 6187），索引為記譜音 pitch class。
    private static let solfegeMap = [
        "1 Do", "♯1 Di", "2 Re", "♭3 Me", "3 Mi", "4 Fa",
        "♯4 Fi", "5 Sol", "♭6 Le", "6 La", "♭7 Te", "7 Ti",
    ]

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
                    if self.drone.isPlaying {
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

        engine.$latestReading
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
                        self.ensureDisplayLink()
                    } else {
                        self.resetReadout()
                        self.pauseDisplayLink()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Reading 入口

    private func ingest(_ reading: PitchReading) {
        lastReading = reading
        needleCents = reading.cents
        trail1Cents = reading.trail1Cents
        trail2Cents = reading.trail2Cents
        let now = ProcessInfo.processInfo.systemUptime

        // 削波警示狀態機（與音高有效性無關：過載幀常被檢測
        // 回絕，峰值仍須計入——detector 在回絕前已算峰值）。
        if reading.peak >= Self.clipReleasePeak {
            clipLastAboveRelease = now
        }
        if reading.peak >= Self.clipEnterPeak {
            clipWarning = true
        } else if clipWarning, now - clipLastAboveRelease > Self.clipHoldSeconds {
            clipWarning = false
        }

        // 頻閃錨點（兩種模式都更新，切換即時生效）：分析時刻
        // （uptime）換算為牆鐘錨點，供 StrobeView 的 TimelineView
        // 以 context.date 外推。
        let strobe = reading.strobe
        strobePhase = strobe.phase
        strobeRate = strobe.angularRate
        strobeConfidence = strobe.confidence
        strobeAnchorDate = Date().addingTimeInterval(-(now - strobe.time))

        if reading.hasPitch, let targetMidi = reading.targetMidi {
            hadValidPitch = true
            lastStableCents = reading.cents

            updateNoteDisplay(targetMidi: targetMidi)

            frequencyText = String(format: "%.1f Hz", reading.smoothedFrequency)
            centsRoll.update(target: reading.cents, now: now)

            // #12 音高跟隨（母本行 9614）：droneFollow 開時，偵測音
            // （平滑頻率的最近音，與鎖定狀態無關）恆定 ≥ 1000 ms
            // 且 ≠ 目前目標（無鎖定以 69 計）→ 鎖定改為該音、
            // Drone 播放中即改頻、計時重置。
            let detectedMidi = Int(PitchMath.exactMidi(
                frequency: reading.smoothedFrequency,
                a4: engine.settings.a4).rounded())
            let currentTarget = lockedTargetMidi ?? 69
            if store.droneFollow, detectedMidi != currentTarget {
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
            let wasInTune = isInTune
            isInTune = reading.isInTune
            if reading.isInTune {
                if !wasInTune {
                    HapticsEngine.shared.tap(milliseconds: 14)
                }
                if let since = inTuneSince {
                    if now - since >= 0.650, !noteLocked {
                        noteLocked = true
                        HapticsEngine.shared.pattern([8, 35, 16])
                        // 母本 uiSound("lock")（行 9655，同呼叫點）。
                        UISoundEngine.shared.play(.lock)
                    }
                } else {
                    inTuneSince = now
                }
            } else {
                inTuneSince = nil
                noteLocked = false
            }

            stability.push(t: now, cents: reading.cents)
        } else {
            isInTune = false
            inTuneSince = nil
            noteLocked = false

            // #13：氣息停止 → 定格針凍結最後穩定值 1.5 s（母本行 9706）。
            if hadValidPitch {
                ghostCents = lastStableCents
                ghostUntil = now + 1.5
                hadValidPitch = false
            }
            stability.push(t: now, cents: nil)
        }

        refreshBadgeText()
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
        writtenText = PitchMath.noteName(midi: writtenMidi)
        concertText = PitchMath.noteName(midi: targetMidi)
        let writtenPc = ((writtenMidi % 12) + 12) % 12
        solfegeText = "本調 " + Self.solfegeMap[writtenPc]

        let displayed = store.pitchMode == .written ? writtenMidi : targetMidi
        let pc = ((displayed % 12) + 12) % 12
        noteText = PitchMath.noteNames[pc]
        octaveText = String(Int(floor(Double(displayed) / 12.0)) - 1)
        hasNote = true
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
            TargetChipItem(label: "標準 A4", note: "A4", isGreen: false),
            TargetChipItem(label: "管樂 B♭4", note: "B♭4", isGreen: false),
            TargetChipItem(label: "中央 C4", note: "C4", isGreen: false),
            TargetChipItem(label: "F4", note: "F4", isGreen: false),
            TargetChipItem(label: "G4", note: "G4", isGreen: false),
        ]
    }

    // MARK: - Drone 控制（母本 droneCapsule，行 10217）

    /// Drone 目標音：鎖定音 ?? A4(69)（母本 droneTargetFreq）。
    var droneTargetMidi: Int { lockedTargetMidi ?? 69 }

    /// 主鈕文案（母本 droneBtnText）：停止 (X)／基準音 X。
    var droneButtonText: String {
        let note = lockedTargetNote ?? "A4"
        return drone.isPlaying ? "停止 (\(note))" : "基準音 \(note)"
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
        if abs(needleCents) > 0.02 { return true }
        if ghostCents != nil { return true }
        if centsRoll.active { return true }
        return false
    }

    func displayTick(now: TimeInterval) {
        centsRoll.tick(now: now)
        displayCents = centsRoll.value

        if ghostCents != nil {
            if now < ghostUntil {
                let remain = ghostUntil - now
                let fade = remain < 0.4 ? remain / 0.4 : 1
                ghostOpacity = 0.35 * fade
            } else {
                ghostCents = nil
                ghostOpacity = 0
            }
        }

        if !needsMotion {
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
        displayLink?.isPaused = false
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
        stabilityFrozen = stability.frozen
        refreshBadgeText()
        // 母本行 9268：定格 uiSound("switch")、解凍 uiSound("tick")。
        UISoundEngine.shared.play(stabilityFrozen ? .switch : .tick)
    }

    /// 母本 updateTraceBadge（行 9243）四態文字。
    private func refreshBadgeText() {
        let stats = stability.stats
        if stability.frozen {
            if let stats {
                let mean = stats.mean
                let meanText = (mean >= 0 ? "+" : "") + String(format: "%.1f", mean)
                stabilityBadgeText = "⏸ 已定格 · 穩定度 \(stats.stability)% (\(meanText)¢)"
            } else {
                stabilityBadgeText = "⏸ 已定格 · 輕點繼續"
            }
        } else if engine.isRunning, let stats {
            stabilityBadgeText = "穩定度 \(stats.stability)% · 輕點定格"
        } else {
            stabilityBadgeText = "輕點定格"
        }
    }

    // MARK: - 重置（母本 resetTunerReadout）

    private func resetReadout() {
        noteText = "--"
        octaveText = ""
        hasNote = false
        noteLocked = false
        isInTune = false
        solfegeText = "本調 --"
        writtenText = "--"
        concertText = "--"
        frequencyText = "0.0 Hz"
        centsRoll.reset()
        displayCents = 0
        // 頻閃：引擎停止 → 角速度與可信度歸零（相位保留凍結，
        // StrobeView 在 micActive=false 時恆暫停）。
        strobeRate = 0
        strobeConfidence = 0
        // 削波警示隨停止熄滅（無輸入即無過載可言）。
        clipWarning = false
        clipLastAboveRelease = -.infinity
        inTuneSince = nil
        hadValidPitch = false
        // 母本 reset 不清 ghost（靠 1.5 s 自然到期）；原生版停止時一併
        // 清除，避免 link 已停而淡出停在半途（視覺等價，註明差異）。
        ghostCents = nil
        ghostOpacity = 0
        stability.reset()
        refreshBadgeText()
    }
}
