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
        MainActor.assumeIsolated {
            owner?.displayTick(now: link.timestamp)
        }
    }
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

    /// 音分文字（母本 paintCentsTexts 格式：正數帶 +、一位小數、" ¢"）。
    var centsDisplayText: String {
        let body = String(format: "%.1f", displayCents)
        return (displayCents > 0 ? "+" + body : body) + " ¢"
    }

    /// 目前樂器顯示名。階段 4 樂器庫落地後改由目錄數據提供，
    /// 現階段只有內建預設樂器（母本 INSTRUMENTS[0]）。
    var instrumentDisplayName: String {
        switch engine.range.id {
        case "alto_sax": return "中音薩克斯 · Alto Sax"
        default: return engine.range.id
        }
    }

    // MARK: - 內部狀態

    let engine: AudioEngine
    private var cancellables: Set<AnyCancellable> = []

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

    init(engine: AudioEngine) {
        self.engine = engine
        linkProxy.owner = self

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

        if reading.hasPitch, let targetMidi = reading.targetMidi {
            hadValidPitch = true
            lastStableCents = reading.cents

            // 音名（實音為主顯示；母本 pitchMode 預設實音，記譜走數據卡）。
            let pc = ((targetMidi % 12) + 12) % 12
            noteText = PitchMath.noteNames[pc]
            octaveText = String(Int(floor(Double(targetMidi) / 12.0)) - 1)
            hasNote = true
            concertText = PitchMath.noteName(midi: targetMidi)

            // 記譜音 = 實音 − trans（母本行 9606）；唱名取記譜 pitch class。
            let writtenMidi = targetMidi - engine.range.transposition
            writtenText = PitchMath.noteName(midi: writtenMidi)
            let writtenPc = ((writtenMidi % 12) + 12) % 12
            solfegeText = "本調 " + Self.solfegeMap[writtenPc]

            frequencyText = String(format: "%.1f Hz", reading.smoothedFrequency)
            centsRoll.update(target: reading.cents, now: now)

            // 準音鎖定（母本行 9650）：連續入容差 ≥ 650 ms。
            isInTune = reading.isInTune
            if reading.isInTune {
                if let since = inTuneSince {
                    if now - since >= 0.650 { noteLocked = true }
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
