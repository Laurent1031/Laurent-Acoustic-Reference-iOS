import Combine
import Foundation
import QuartzCore

/// 節拍器畫面的 CADisplayLink 轉發代理（照 TunerViewModel 的
/// DisplayLinkProxy 已修寫法：閉包外先取 timestamp 與 owner，
/// 再 assumeIsolated 跳回主 actor，避免 Swift 6 sending 競態）。
private final class MetroDisplayLinkProxy: NSObject {
    weak var owner: MetronomeViewModel?

    @objc func onTick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let owner = self.owner
        MainActor.assumeIsolated {
            owner?.displayTick(now: timestamp)
        }
    }
}

/// BPM 里程表一柱（母本 .bpm-col 的 pos/vel/targetPos）。
private struct OdometerColumn {
    var pos: Double = 0
    var vel: Double = 0
    var targetPos: Double = 0
}

/// 一次拍點脈衝（母本 strikePulse 的執行期狀態）。
private struct PulseState {
    var start: TimeInterval = 0
    var durationMs: Double = 0
    var level: Int = 0
    var isCountIn: Bool = false
    var active: Bool = false
}

/// 節拍器畫面狀態機：設定／預置／漸速的 UI 側邏輯（對照母本
/// metro 區塊），調度與聲音在 MetronomeEngine。
/// 動畫量（脈衝包絡、BPM 里程表 spring、推子填充 spring）由
/// CADisplayLink 驅動，公式逐項照母本（spring 360/37.95、
/// 子步 1/240、脈衝 attack 立方／decay 2.4 次冪）。
@MainActor
/// 錶盤渲染狀態（返修批3 隔離）：里程表柱位／推子填充比
/// 以 display-link 速率發布，若掛在 VM 本體（ObservableObject
/// 任一 @Published 變更即全體觀察者重繪），拖動與滾動期間
/// 整頁每幀重繪——實機拖推桿「中間卡頓」的主因之一。獨立
/// 成小對象、僅 BpmDialView／BpmFaderView 觀察，頁面本體
/// 不再被渲染幀牽動。
final class DialRenderState: ObservableObject {
    @Published var odoPositions: [Double] = [0, 0, 0]
    @Published var odoHundredsBlank = true
    @Published var faderRatio: Double = 0
}

/// 【返修批3 CI 修復】@MainActor 屬本類：批3 抽出 DialRenderState
/// 時把它插在本類之上，原 @MainActor 被吸到 DialRenderState，
/// 本類失隔離致 CI 4 錯（didSet 內 engine.updateSettings／
/// LiveActivity.shared.update／dial 預設值）。
@MainActor
final class MetronomeViewModel: ObservableObject {
    // MARK: - 設定與預置

    @Published var settings = MetronomeSettings() {
        didSet {
            engine.updateSettings(settings)
            schedulePersist()
            // Live Activity（階段 6）：播放中改 BPM／拍號即
            // 同步活動內容（拍位沿用目前顯示值）。
            if isPlaying {
                MetronomeLiveActivityController.shared.update(
                    state: activityState(bpm: settings.bpm,
                                         beat: displayBeat + 1,
                                         beatsInBar: displayBeatsInBar,
                                         isCountIn: displayIsCountIn))
            }
        }
    }
    @Published private(set) var userPresets: [MetronomePreset] = []
    @Published var activePresetId: String?

    var allPresets: [MetronomePreset] { MetronomePreset.builtins + userPresets }
    var activePreset: MetronomePreset? {
        allPresets.first { $0.id == activePresetId }
    }

    // MARK: - 播放與拍點顯示

    @Published private(set) var isPlaying = false
    /// 背景膠囊暫停態（母本 metroCapsulePaused）。
    @Published var capsulePaused = false
    @Published private(set) var rampState = RampState()
    @Published private(set) var currentPillar: Int?
    @Published private(set) var pulseValue: Double = 0
    @Published private(set) var pulseLevel: Int = 0
    @Published private(set) var pulseIsCountIn: Bool = false
    @Published private(set) var displayBar = 1
    @Published private(set) var displayBeat = 0
    @Published private(set) var displayBeatsInBar = 4
    @Published private(set) var displayIsCountIn = false
    /// 目前拍所在小節是否為 Gap Click 靜音小節（補強段）。
    @Published private(set) var displayIsSilentBar = false
    @Published private(set) var toast: String?

    // MARK: - 里程表／推子渲染值

    /// 渲染值改經 dial 發布（見 DialRenderState 註解）。
    let dial = DialRenderState()
    /// 轉盤／推子／數字拖動中（里程表與填充直跟、繞過 spring）。
    var bpmAdjusting = false
    /// 拖動中的連續 BPM（未取整）：返修批3 起只餵推子填充
    /// （連續量本色）；里程表與 settings 只吃取整值——
    /// Laurent 定調「定位到準確數字，其他轉換只是中途
    /// 特效」：數字落位必須是精確整數，滾動是 spring 過渡。
    private var liveAdjustValue: Double?

    var capsuleVisible: Bool { isPlaying || capsulePaused }
    /// 背景膠囊文字：以 L10n 片段組裝（節拍器運行中／已暫停
    /// 為母本字典鍵）；本屬性在 ContentView body 求值，語言
    /// 切換隨 store 重繪即時生效。
    var capsuleText: String {
        isPlaying ? "♩ \(settings.bpm) BPM · " + L10n.t("节拍器运行中")
                  : L10n.t("已暂停 · 点按继续")
    }

    /// 頂部提示列（母本 updateMetroHint，行 10505；補強段：
    /// Gap 靜音小節在拍訊後加「· 靜音」標記，拍點視覺本身
    /// 照常——靜默的是聲音與觸感，不是顯示）。
    /// 提示列文字以 L10n 格式串組裝（supplement 的
    /// 「预备拍 · 第 %d/%d 拍 (%d BPM)」「第 %d 小节 · 第
    /// %d/%d 拍」兩條格式鍵＋字典片段「静音」）；在
    /// MetronomeView body 求值，語言切換即時生效。
    var hintText: String {
        if isPlaying {
            if displayIsCountIn {
                // 分母須與引擎實際計拍一致（審計修復）：引擎預備
                // 拍按 beatsInBar（附點調整後）計，舊寫 beatsPerBar
                // 令附點 6/8 的 2 拍預備拍顯示為「第 x/6 拍」。
                return "● " + String(
                    format: L10n.t("预备拍 · 第 %d/%d 拍 (%d BPM)"),
                    displayBeat + 1, settings.beatsInBar, settings.bpm)
            }
            let suffix = settings.isDottedBeat
                ? " (♩. \(settings.bpm) BPM)" : " (\(settings.bpm) BPM)"
            let silent = displayIsSilentBar ? " · " + L10n.t("静音") : ""
            return "● " + String(
                format: L10n.t("第 %d 小节 · 第 %d/%d 拍"),
                displayBar, displayBeat + 1, displayBeatsInBar) + suffix + silent
        }
        return L10n.t("点击拍柱切换：强拍 / 次强 / 弱拍 / 静音")
    }

    // MARK: - 內部

    let engine: MetronomeEngine
    /// 持久化出口（階段 4 起由 AppStore 承接，ContentView 注入；
    /// 取代階段 3 的 MetronomeStore 佔位）。預設 no-op 供 Preview。
    var persistSettings: @MainActor (MetronomeSettings) -> Void = { _ in }
    var persistUserPresets: @MainActor ([MetronomePreset]) -> Void = { _ in }
    private var cancellables: Set<AnyCancellable> = []

    private let linkProxy = MetroDisplayLinkProxy()
    private var displayLink: CADisplayLink?
    private var lastTickTime: TimeInterval = 0

    private var pulse = PulseState()
    private var odoCols = [OdometerColumn(), OdometerColumn(), OdometerColumn()]
    private var odoValue = 120
    private var odoSettled = true
    private var fillDisp: Double = 120
    private var fillVel: Double = 0
    private var fillSettled = true

    private var tapTimes: [Double] = []
    private var persistTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(engine: MetronomeEngine,
         persisted: (settings: MetronomeSettings,
                     userPresets: [MetronomePreset])? = nil) {
        self.engine = engine
        linkProxy.owner = self

        let loaded = persisted?.settings ?? MetronomeSettings()
        settings = loaded
        userPresets = persisted?.userPresets ?? []
        engine.updateSettings(loaded)
        odoValue = loaded.bpm
        fillDisp = Double(loaded.bpm)
        setOdometerImmediate(loaded.bpm)
        publishFill()

        engine.onBeatVisual = { [weak self] event in
            self?.handleBeat(event)
        }
        engine.onRampFinished = { [weak self] in
            guard let self else { return }
            self.rampState = self.engine.rampSnapshot()
            HapticsEngine.shared.tap(milliseconds: 20)
            // 母本行 10979：漸速到達 haptic(20)＋uiSound("success")。
            UISoundEngine.shared.play(.success)
            self.showToast("已到达目标速度")
        }
        engine.onRampChanged = { [weak self] state in
            self?.rampState = state
        }
        engine.onBpmChanged = { [weak self] bpm in
            self?.applyRemoteBpm(bpm)
        }
        engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPlaying = playing
                    // Live Activity 與引擎生命週期嚴格同步
                    // （階段 6）：啟動建活動、停止即結束；
                    // 中斷／路由的引擎側停機同經此訂閱收尾。
                    if playing {
                        MetronomeLiveActivityController.shared.start(
                            state: self.activityState(
                                bpm: self.settings.bpm, beat: 1,
                                beatsInBar: self.settings.beatsInBar,
                                isCountIn: self.settings.countIn),
                            timbreName: L10n.t(self.settings.timbre.sourceName))
                    } else {
                        MetronomeLiveActivityController.shared.stop()
                        self.currentPillar = nil
                        self.pulse.active = false
                        self.pulseValue = 0
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - BPM 變更（母本 setBpm，行 10650）

    /// 用戶路徑：取消漸速、與現行預置比對後清除 activePresetId。
    func setBpm(_ value: Int) {
        engine.cancelRamp()
        rampState = engine.rampSnapshot()
        if let preset = activePreset, preset.bpm != settings.clampedBpm(value) {
            activePresetId = nil
        }
        setBpmRaw(value)
    }

    private func setBpmRaw(_ value: Int) {
        let clamped = settings.clampedBpm(value)
        let prev = settings.bpm
        guard clamped != prev else { return }
        settings.bpm = clamped
        // 母本：值變且抵達上下限 → haptic(12)。
        if clamped == MetronomeSettings.bpmMin || clamped == settings.bpmMaxNow {
            HapticsEngine.shared.tap(milliseconds: 12)
        }
        syncBpmRender()
    }

    func stepBpm(_ delta: Int) {
        setBpm(settings.bpm + delta)
    }

    /// 漸速引擎步進回報（不取消漸速、不清預置）。
    private func applyRemoteBpm(_ bpm: Int) {
        guard bpm != settings.bpm else { return }
        settings.bpm = bpm
        syncBpmRender()
    }

    /// 拖動 BPM 控件時的 detent 輕震（母本 dragTickHaptic：
    /// 每變 1、節流 45 ms、3 ms）。
    private var lastDragTickAt: TimeInterval = 0
    private var lastDragTickValue = Int.min
    func dragTickBpm(_ value: Int) {
        guard value != lastDragTickValue else { return }
        lastDragTickValue = value
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDragTickAt >= 0.045 else { return }
        lastDragTickAt = now
        HapticsEngine.shared.tap(milliseconds: 3)
    }

    /// 拖動看門狗（返修批2）：手勢被系統取消時 onEnded 不
    /// 觸發，bpmAdjusting 會永久停在 true、里程表凍結於
    /// 小數位置（實機「數字卡在中間」）。beginAdjust 起
    /// 一條巡檢：adjusting 期間若 0.35 s 無新的拖動值，
    /// 自動 endAdjust 收斂到整數 BPM。正常拖動中值持續
    /// 到達，看門狗恆不觸發。
    private var lastDragAt: TimeInterval = 0
    private var adjustWatchdog: Task<Void, Never>?

    func beginAdjust() {
        bpmAdjusting = true
        lastDragAt = ProcessInfo.processInfo.systemUptime
        adjustWatchdog?.cancel()
        adjustWatchdog = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, self.bpmAdjusting else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastDragAt > 0.35 {
                    self.endAdjust()
                    return
                }
            }
        }
    }

    func endAdjust() {
        adjustWatchdog?.cancel()
        adjustWatchdog = nil
        liveAdjustValue = nil
        bpmAdjusting = false
        syncBpmRender()
    }

    /// 拖動路徑專用：連續值只餵推子填充（連續量本色）；
    /// settings／引擎／里程表只在「取整值跨格」時更新一次
    /// ——舊版每個觸摸事件都 setBpm（取消漸速＋引擎重定時
    /// ＋落盤）是拖動卡頓的另一主因。里程表目標恆為整數
    /// （見 syncOdometerTarget 返修批3 註解）。
    func setBpmFromDrag(_ continuous: Double) {
        lastDragAt = ProcessInfo.processInfo.systemUptime
        liveAdjustValue = continuous
        let target = Int(continuous.rounded())
        if target != settings.bpm {
            setBpm(target)
        }
        // 取整值未變時 setBpm 不觸發 render；填充仍須跟指。
        if bpmAdjusting { syncFillTarget() }
    }

    // MARK: - 拍號／細分／音色／重音

    func setSignature(beats: Int, unit: Int) {
        guard beats != settings.beatsPerBar || unit != settings.beatUnit else { return }
        settings.beatsPerBar = beats
        settings.beatUnit = unit
        // 母本：切拍號重置為該拍號預設重音。補強段分組：該拍號
        // 存有選定分組時，以分組推導重音取代預設（分組記憶；
        // 未存分組的拍號行為與母本逐值一致，零回退）。
        if let groups = settings.groupingBySignature[
            MetronomeSettings.signatureKey(beats: beats, unit: unit)],
           groups.reduce(0, +) == beats {
            settings.beatAccents = MetronomeSettings.accents(forGroups: groups)
        } else {
            settings.beatAccents = MetronomeSettings.defaultAccents(beats: beats, unit: unit)
        }
        if isPlaying { engine.resetBeatIndex() }
        activePresetId = nil
        publishFill()
        HapticsEngine.shared.tap(milliseconds: 6)
        // 母本選單選項點按：uiSound("tick")（行 7262／7604）。
        UISoundEngine.shared.play(.tick)
    }

    func setSubdivision(_ value: Int) {
        guard value != settings.subdivision else { return }
        settings.subdivision = value
        activePresetId = nil
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
    }

    func setTimbre(_ timbre: MetronomeTimbre) {
        guard timbre != settings.timbre else { return }
        settings.timbre = timbre
        activePresetId = nil
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
        // 母本：未播放時試聽新音色（首柱等級，缺省 3）。
        if !isPlaying {
            engine.audition(timbre: timbre, level: settings.beatAccents.first ?? 3)
        }
    }

    // MARK: - 不規則拍分組（補強段）

    /// 目前拍號的有效分組：已存分組（合計吻合）優先，否則自
    /// 目前重音型推導（供分組面板標示「目前」）。
    var currentGrouping: [Int] {
        if let stored = settings.groupingBySignature[settings.currentSignatureKey],
           stored.reduce(0, +) == settings.beatsPerBar {
            return stored
        }
        return MetronomeSettings.groups(fromAccents: settings.beatAccents)
    }

    /// 目前重音型是否正等於 currentGrouping 的推導（否則面板
    /// 顯示「手動重音」——分組只是生成器，手動改重音後分組
    /// 不再是現行重音的完整描述）。
    var accentsMatchGrouping: Bool {
        MetronomeSettings.accents(forGroups: currentGrouping) == settings.beatAccents
    }

    /// 套用分組：存入分組記憶＋以推導重音重寫 beatAccents。
    /// 合計須等於拍數，否則不動作（面板已擋，此為防線）。
    func setGrouping(_ groups: [Int]) {
        guard groups.reduce(0, +) == settings.beatsPerBar,
              !groups.isEmpty, groups.allSatisfy({ $0 >= 1 }) else { return }
        settings.groupingBySignature[settings.currentSignatureKey] = groups
        settings.beatAccents = MetronomeSettings.accents(forGroups: groups)
        if isPlaying { engine.resetBeatIndex() }
        activePresetId = nil
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
    }

    /// 清除分組記憶並回母本預設重音（面板的「預設重音」項與
    /// 預置分組首項等效；此入口供清除自訂分組）。
    func clearGrouping() {
        settings.groupingBySignature[settings.currentSignatureKey] = nil
        settings.beatAccents = MetronomeSettings.defaultAccents(
            beats: settings.beatsPerBar, unit: settings.beatUnit)
        if isPlaying { engine.resetBeatIndex() }
        activePresetId = nil
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
    }

    func setDottedBeat(_ on: Bool) {
        guard on != settings.dottedBeat else { return }
        settings.dottedBeat = on
        if settings.bpm > settings.bpmMaxNow {
            setBpmRaw(settings.bpm)
        }
        // 與其餘 setter 一致（審計修復）：清除作用中預置標記
        // （此前唯獨此 setter 不清，預置列顯示與實際狀態不符）
        // 並補 tick 音效。
        activePresetId = nil
        publishFill()
        if isPlaying { engine.resetBeatIndex() }
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
    }

    /// 點按拍柱：等級向下循環 3→2→1→0→3（母本行 11575；
    /// uiSound("tick") 行 10416）。
    func cycleAccent(pillar: Int) {
        guard settings.beatAccents.indices.contains(pillar) else { return }
        settings.beatAccents[pillar] = (settings.beatAccents[pillar] + 3) % 4
        HapticsEngine.shared.tap(milliseconds: 10)
        UISoundEngine.shared.play(.tick)
    }

    func resetAccents() {
        settings.beatAccents = MetronomeSettings.defaultAccents(
            beats: settings.beatsPerBar, unit: settings.beatUnit)
        HapticsEngine.shared.pattern([8, 30, 12])
        // 母本行 10430：重音重置 uiSound("success")。
        UISoundEngine.shared.play(.success)
    }

    func toggleCountIn() {
        settings.countIn.toggle()
        HapticsEngine.shared.tap(milliseconds: 8)
        // 母本行 11363：預備拍開關 uiSound("tick")。
        UISoundEngine.shared.play(.tick)
    }

    // MARK: - TAP 測速（母本行 10762，逐項對照）

    func tapTempo() {
        HapticsEngine.shared.tap(milliseconds: 10)
        // 母本行 10892：TAP uiSound("tick")。
        UISoundEngine.shared.play(.tick)
        let nowMs = ProcessInfo.processInfo.systemUptime * 1000
        tapTimes.append(nowMs)
        if tapTimes.count > 5 { tapTimes.removeFirst(tapTimes.count - 5) }
        tapTimes = tapTimes.filter { nowMs - $0 <= 1800 }
        guard tapTimes.count >= 2 else { return }
        var gaps: [Double] = []
        for i in 1..<tapTimes.count { gaps.append(tapTimes[i] - tapTimes[i - 1]) }
        if gaps.count >= 2 {
            let last = gaps[gaps.count - 1]
            let prev = gaps[gaps.count - 2]
            if (prev > 0 && last / prev > 2.5) || (last > 0 && prev / last > 2.5) {
                tapTimes = [nowMs]
                return
            }
        }
        let allWeights = [0.1, 0.2, 0.3, 0.4]
        let weights = Array(allWeights.suffix(gaps.count))
        var sum = 0.0
        var weightSum = 0.0
        for i in gaps.indices {
            sum += gaps[i] * weights[i]
            weightSum += weights[i]
        }
        setBpm(Int((60000 / (sum / weightSum)).rounded()))
    }

    // MARK: - 播放控制（母本 toggleMetronome，行 11446）

    func togglePlay() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    func start() {
        capsulePaused = false
        engine.start()
        if engine.isPlaying {
            HapticsEngine.shared.tap(milliseconds: 14)
        }
    }

    func stop() {
        engine.stop()
        capsulePaused = false
        HapticsEngine.shared.tap(milliseconds: 10)
        // 母本行 11442：停止節拍器 uiSound("close")。
        UISoundEngine.shared.play(.close)
    }

    /// 背景膠囊點按（母本行 11640）：播放中 → 暫停（膠囊保留）；
    /// 暫停中 → 自第一拍重啟。
    func capsuleTapped() {
        if isPlaying {
            engine.stop()
            capsulePaused = true
        } else if capsulePaused {
            capsulePaused = false
            engine.start()
        }
    }

    /// 提示列點按：小節計數歸 1（母本行 10519；
    /// uiSound("tick") 行 11391）。
    func hintTapped() {
        guard isPlaying else { return }
        engine.resetBarCount()
        displayBar = 1
        HapticsEngine.shared.tap(milliseconds: 6)
        UISoundEngine.shared.play(.tick)
    }

    // MARK: - 預置（母本 applyMetroPreset/saveCurrentMetroPreset）

    /// store → VM 同步（審計修復）：備份匯入直接寫
    /// store.metronomeUserPresets 時，運行中的 VM 以此刷新副本
    /// ——此前同步只有 VM→store 單向，匯入後節拍器頁仍顯示舊
    /// 預置，且 VM 下次落盤會以舊副本覆寫匯入值。
    func syncUserPresetsFromStore(_ presets: [MetronomePreset]) {
        // VM 自身落盤回寫 store 時 onChange 亦會觸發，同值直退。
        guard presets != userPresets else { return }
        userPresets = presets
        if let id = activePresetId,
           !allPresets.contains(where: { $0.id == id }) {
            activePresetId = nil
        }
    }

    func applyPreset(_ preset: MetronomePreset) {
        engine.cancelRamp()
        rampState = engine.rampSnapshot()
        setBpmRaw(preset.bpm)
        settings.beatsPerBar = preset.beats
        settings.beatUnit = preset.noteUnit
        settings.subdivision = preset.subdivision
        settings.timbre = preset.timbre
        // 與 setSignature 同路徑（審計修復）：優先套用該拍號的
        // 分組記憶推導重音；此前直接寫預設重音，手動切同拍號
        // 與套預置切同拍號的重音結果不一致。播放中拍位歸零
        // 亦與 setSignature 齊平。
        if let groups = settings.groupingBySignature[
            MetronomeSettings.signatureKey(beats: preset.beats,
                                           unit: preset.noteUnit)],
           groups.reduce(0, +) == preset.beats {
            settings.beatAccents = MetronomeSettings.accents(forGroups: groups)
        } else {
            settings.beatAccents = MetronomeSettings.defaultAccents(
                beats: preset.beats, unit: preset.noteUnit)
        }
        if isPlaying { engine.resetBeatIndex() }
        activePresetId = preset.id
        HapticsEngine.shared.tap(milliseconds: 8)
        UISoundEngine.shared.play(.tick)
        showToast("已套用预设")
    }

    /// 保存目前狀態為預置；同名覆蓋（母本行 11063）。成功回 true。
    @discardableResult
    func savePreset(name rawName: String) -> Bool {
        let collapsed = rawName
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else {
            showToast("请输入预设名称")
            return false
        }
        if let idx = userPresets.firstIndex(where: { $0.name == collapsed }) {
            userPresets[idx].bpm = settings.bpm
            userPresets[idx].beats = settings.beatsPerBar
            userPresets[idx].noteUnit = settings.beatUnit
            userPresets[idx].subdivision = settings.subdivision
            userPresets[idx].timbre = settings.timbre
            activePresetId = userPresets[idx].id
        } else {
            let preset = MetronomePreset(
                id: "mp\(Int(Date().timeIntervalSince1970 * 1000))",
                name: collapsed, bpm: settings.bpm,
                beats: settings.beatsPerBar, noteUnit: settings.beatUnit,
                subdivision: settings.subdivision, timbre: settings.timbre,
                builtin: false)
            userPresets.append(preset)
            activePresetId = preset.id
        }
        persistUserPresets(userPresets)
        HapticsEngine.shared.tap(milliseconds: 10)
        // 保存完成回饋：母本同類保存點（設為默認 行 7080、自訂
        // 樂器保存 行 7686）皆 uiSound("success")，此處比照。
        UISoundEngine.shared.play(.success)
        showToast("已保存预设")
        return true
    }

    func deleteActiveUserPreset() {
        guard let id = activePresetId,
              let idx = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets.remove(at: idx)
        activePresetId = nil
        persistUserPresets(userPresets)
    }

    // MARK: - 漸速（母本 applyRampQuickScheme/startCustomRamp）

    /// 回傳 true 表示視圖應開啟自訂漸速面板。
    func applyRampQuick(_ scheme: RampQuickScheme) -> Bool {
        HapticsEngine.shared.tap(milliseconds: 12)
        switch scheme.id {
        case "off":
            engine.cancelRamp()
            rampState = engine.rampSnapshot()
            return false
        case "custom":
            return true
        default:
            guard let delta = scheme.delta else { return false }
            let from = settings.bpm
            let to = settings.clampedBpm(from + delta)
            guard to != from else {
                // 母本行 11410：漸速極限提示 uiSound("warn")。
                UISoundEngine.shared.play(.warn)
                showToast("当前已在极限速度，无法往该方向渐速")
                return false
            }
            engine.startRamp(from: from, to: to, step: scheme.step,
                             barsPerStep: scheme.bars)
            rampState = engine.rampSnapshot()
            if !isPlaying { start() }
            return false
        }
    }

    /// 自訂漸速（母本驗證：from/to ∈ [40,208]、to≠from、
    /// bars 1–32、step 1–20）。成功回 true。
    func startCustomRamp(from: Int, to: Int, bars: Int, step: Int) -> Bool {
        // 上限隨附點計拍（審計修復）：附點模式 BPM 可達 307，
        // 舊驗證寫死 300 令 301–307 的合法目標被拒。
        let maxBpm = settings.bpmMaxNow
        guard (MetronomeSettings.bpmMin...maxBpm).contains(from),
              (MetronomeSettings.bpmMin...maxBpm).contains(to),
              to != from, (1...32).contains(bars), (1...20).contains(step)
        else {
            // 母本行 11317：漸速參數無效 uiSound("warn")。
            UISoundEngine.shared.play(.warn)
            showToast("请检查渐速参数")
            return false
        }
        engine.startRamp(from: from, to: to, step: step, barsPerStep: bars)
        rampState = engine.rampSnapshot()
        if !isPlaying { start() }
        return true
    }

    func stopRamp() {
        engine.cancelRamp()
        rampState = engine.rampSnapshot()
        // 母本行 7489：取消漸速 uiSound("close")。
        UISoundEngine.shared.play(.close)
    }

    // MARK: - 拍點事件 → 脈衝（母本 strikePulse，行 11552）

    /// Live Activity 內容狀態組裝（拍號字串與 App 內顯示同源）。
    private func activityState(bpm: Int, beat: Int, beatsInBar: Int,
                               isCountIn: Bool) -> MetronomeActivityAttributes.ContentState {
        MetronomeActivityAttributes.ContentState(
            bpm: bpm,
            timeSignature: settings.currentSignatureKey,
            beat: beat,
            beatsInBar: beatsInBar,
            isCountIn: isCountIn)
    }

    private func handleBeat(_ event: BeatVisualEvent) {
        currentPillar = event.pillarIndex
        displayBar = event.barCount
        displayBeat = event.beatIndex
        displayBeatsInBar = event.beatsInBar
        displayIsCountIn = event.isCountIn
        displayIsSilentBar = event.isSilentBar
        // Live Activity 逐拍更新（控制器內以內容相等去重，
        // 並以 staleDate 防殭屍）。
        MetronomeLiveActivityController.shared.update(
            state: activityState(bpm: event.bpm,
                                 beat: event.beatIndex + 1,
                                 beatsInBar: event.beatsInBar,
                                 isCountIn: event.isCountIn))
        let beatMs = 60000.0 / Double(event.bpm) * (settings.isDottedBeat ? 3.0 : 1.0)
        pulse = PulseState(start: ProcessInfo.processInfo.systemUptime,
                           durationMs: min(950, max(180, beatMs * 0.92)),
                           level: event.level, isCountIn: event.isCountIn,
                           active: true)
        ensureDisplayLink()
    }

    // MARK: - 顯示時鐘

    private var needsMotion: Bool {
        pulse.active || !odoSettled || !fillSettled
    }

    func displayTick(now: TimeInterval) {
        let dt = min(0.05, max(0.001, now - lastTickTime))
        lastTickTime = now

        if pulse.active {
            let elapsedMs = (now - pulse.start) * 1000
            if elapsedMs >= pulse.durationMs {
                pulse.active = false
                pulseValue = 0
            } else {
                let t = elapsedMs / pulse.durationMs
                // 母本包絡：attack 段三次方入、decay 段 2.4 次冪出。
                pulseValue = t < 0.08
                    ? 1 - pow(1 - t / 0.08, 3)
                    : pow(1 - t, 2.4)
                pulseLevel = pulse.level
                pulseIsCountIn = pulse.isCountIn
            }
        }
        if !odoSettled { stepOdometer(dt: dt) }
        if !fillSettled { stepFill(dt: dt) }
        if !needsMotion { pauseDisplayLink() }
    }

    private func ensureDisplayLink() {
        if displayLink == nil {
            let link = CADisplayLink(
                target: linkProxy,
                selector: #selector(MetroDisplayLinkProxy.onTick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 80, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        lastTickTime = ProcessInfo.processInfo.systemUptime
        displayLink?.isPaused = false
    }

    private func pauseDisplayLink() {
        displayLink?.isPaused = true
    }

    func viewDidDisappear() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - 里程表（母本 renderBpmNumber/stepBpmReels）

    private func syncBpmRender() {
        syncOdometerTarget()
        syncFillTarget()
    }

    private func syncOdometerTarget() {
        let v = settings.bpm
        // 【返修批3・Laurent 定調】里程表恆以「整數 BPM」為
        // 目標行 spring 滾動——拖動中亦然：拖動跨過取整門檻
        // 即向新整數滾，滾動只是中途特效，落位必須精確是
        // 整數本身。舊版拖動把連續小數直餵柱位（setOdometer
        // Continuous），數字恆停在兩格之間（實機截圖數字
        // 互相疊壓、Laurent 點名「卡在中間」），已廢除。
        let dir = v > odoValue ? 1 : (v < odoValue ? -1 : 0)
        odoValue = v
        let digits = [v / 100, (v / 10) % 10, v % 10]
        for c in 0..<3 {
            let cur = (odoCols[c].targetPos.truncatingRemainder(dividingBy: 10) + 10)
                .truncatingRemainder(dividingBy: 10)
            var dd = (Double(digits[c]) - cur + 15)
                .truncatingRemainder(dividingBy: 10) - 5
            if dd == -5 && dir > 0 { dd = 5 }
            odoCols[c].targetPos += dd
        }
        odoSettled = false
        publishOdo()
        ensureDisplayLink()
    }

    private func setOdometerImmediate(_ v: Int) {
        let digits = [v / 100, (v / 10) % 10, v % 10]
        for c in 0..<3 {
            odoCols[c].pos = Double(digits[c])
            odoCols[c].targetPos = Double(digits[c])
            odoCols[c].vel = 0
        }
        odoValue = v
        odoSettled = true
        publishOdo()
    }

    private func stepOdometer(dt: Double) {
        var settled = true
        let steps = max(1, Int(ceil(dt / (1.0 / 240.0))))
        let h = dt / Double(steps)
        for c in 0..<3 {
            for _ in 0..<steps {
                let d = odoCols[c].targetPos - odoCols[c].pos
                let acc = d * 360 - odoCols[c].vel * 37.95
                odoCols[c].vel += acc * h
                odoCols[c].pos += odoCols[c].vel * h
            }
            let d = odoCols[c].targetPos - odoCols[c].pos
            if abs(d) > 0.002 || abs(odoCols[c].vel) > 0.02 { settled = false }
        }
        if settled {
            for c in 0..<3 {
                odoCols[c].pos = odoCols[c].targetPos
                odoCols[c].vel = 0
            }
            odoSettled = true
        }
        publishOdo()
    }

    private func publishOdo() {
        dial.odoPositions = odoCols.map {
            ($0.pos.truncatingRemainder(dividingBy: 10) + 10)
                .truncatingRemainder(dividingBy: 10)
        }
        dial.odoHundredsBlank = settings.bpm < 100
    }

    // MARK: - 推子填充 spring（母本 stepFaderFill，同組參數）

    private func syncFillTarget() {
        if bpmAdjusting {
            fillDisp = liveAdjustValue ?? Double(settings.bpm)
            fillVel = 0
            fillSettled = true
            publishFill()
        } else {
            fillSettled = false
            ensureDisplayLink()
        }
    }

    private func stepFill(dt: Double) {
        let target = Double(settings.bpm)
        let steps = max(1, Int(ceil(dt / (1.0 / 240.0))))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            let d = target - fillDisp
            let acc = d * 360 - fillVel * 37.95
            fillVel += acc * h
            fillDisp += fillVel * h
        }
        if abs(target - fillDisp) <= 0.002 && abs(fillVel) <= 0.02 {
            fillDisp = target
            fillVel = 0
            fillSettled = true
        }
        publishFill()
    }

    private func publishFill() {
        let range = Double(settings.bpmMaxNow - MetronomeSettings.bpmMin)
        dial.faderRatio = min(1, max(0, (fillDisp - Double(MetronomeSettings.bpmMin)) / range))
    }

    // MARK: - 持久化（佔位）與 toast

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistSettings(self.settings)
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
