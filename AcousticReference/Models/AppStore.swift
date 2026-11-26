import Foundation

/// App 模式（母本 state.mode 的 tuner/metro 子集）。階段 3 時以
/// ContentView 的 UserDefaults 佔位鍵保存，階段 4 起歸 AppStore
/// 統一落盤（遷移見 AppStore.migratedSnapshot）。
enum AppMode: String, Codable, Sendable {
    case tuner
    case metronome
}

/// 主顯示音名模式（母本 profile.pitchMode，行 6223）：written 記譜／
/// concert 實音；母本預設 "written"。
enum PitchMode: String, Codable, Sendable {
    case written
    case concert
}

/// 調音主顯示模式（頻閃主模式段，Laurent 2026-11-26 定版）：
/// strobe 頻閃為預設主模式、needle 錶盤指針為輔助；母本無此
/// 概念（母本只有錶盤），屬原生版新增的顯示層偏好，不影響
/// 檢測與判準。state-v1 缺此欄時預設 strobe。
enum TunerDisplayMode: String, Codable, Sendable {
    case strobe
    case needle
}

/// 收藏切換結果（母本 toggleFavoriteInstrument，行 6769）：
/// 加入／移除／因「至少保留 1 個」被拒。
enum FavoriteToggleOutcome: Sendable {
    case added
    case removed
    case rejectedMinimum
}

/// 落盤快照（state-v1.json 的形狀）。逐欄 decodeIfPresent＋預設值：
/// 任一欄缺失或型別漂移只退回該欄預設，不整份丟棄。
private struct AppStateFile: Codable {
    var version: Int = 1
    var tunerSettings: TunerSettings = TunerSettings()
    var pitchMode: PitchMode = .written
    var selectedInstrumentId: String = "alto_sax"
    var favoriteInstrumentIds: [String] = ["alto_sax", "piano", "violin"]
    var customInstruments: [Instrument] = []
    var droneTimbre: DroneTimbre = .oboe
    var droneFollow: Bool = false
    var metronomeSettings: MetronomeSettings = MetronomeSettings()
    var metronomeUserPresets: [MetronomePreset] = []
    var appMode: String = AppMode.tuner.rawValue
    var guzhengFavMigrationDone: Bool = false
    var tunerDisplayMode: TunerDisplayMode = .strobe

    private enum CodingKeys: String, CodingKey {
        case version, tunerSettings, pitchMode, selectedInstrumentId
        case favoriteInstrumentIds, customInstruments, droneTimbre
        case droneFollow, metronomeSettings, metronomeUserPresets
        case appMode, guzhengFavMigrationDone, tunerDisplayMode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tunerSettings = try c.decodeIfPresent(TunerSettings.self, forKey: .tunerSettings) ?? TunerSettings()
        pitchMode = try c.decodeIfPresent(PitchMode.self, forKey: .pitchMode) ?? .written
        selectedInstrumentId = try c.decodeIfPresent(String.self, forKey: .selectedInstrumentId) ?? "alto_sax"
        favoriteInstrumentIds = try c.decodeIfPresent([String].self, forKey: .favoriteInstrumentIds)
            ?? ["alto_sax", "piano", "violin"]
        customInstruments = try c.decodeIfPresent([Instrument].self, forKey: .customInstruments) ?? []
        droneTimbre = try c.decodeIfPresent(DroneTimbre.self, forKey: .droneTimbre) ?? .oboe
        droneFollow = try c.decodeIfPresent(Bool.self, forKey: .droneFollow) ?? false
        metronomeSettings = try c.decodeIfPresent(MetronomeSettings.self, forKey: .metronomeSettings)
            ?? MetronomeSettings()
        metronomeUserPresets = try c.decodeIfPresent([MetronomePreset].self, forKey: .metronomeUserPresets) ?? []
        appMode = try c.decodeIfPresent(String.self, forKey: .appMode) ?? AppMode.tuner.rawValue
        guzhengFavMigrationDone = try c.decodeIfPresent(Bool.self, forKey: .guzhengFavMigrationDone) ?? false
        tunerDisplayMode = try c.decodeIfPresent(TunerDisplayMode.self, forKey: .tunerDisplayMode) ?? .strobe
    }
}

/// 單一持久化數據層（規格書階段 4）：設定、收藏、自訂樂器、Drone
/// 偏好、節拍器設定與自訂預置、App 模式，統一由此管理與落盤，
/// 取代階段 3 的 MetronomeStore 佔位與 ContentView 的 mode 佔位鍵。
///
/// 落盤格式：Application Support/AcousticReference/state-v1.json，
/// 單一 JSON 文件（AppStateFile，version 1），變更即存（原子寫入
/// .atomic），啟動同步載入。寫入頻率與母本 localStorage 同步存檔
/// 同級（每次狀態變更一次小檔寫入）。
///
/// 隔離設計：@MainActor 單例式 store，所有 @Published 變更只在主
/// 線程發生；落盤為同步小檔 I/O（數 KB），不引入背景佇列與跨域
/// 傳遞。引擎側（AudioEngine／MetronomeEngine／DroneEngine）不直接
/// 持有 store，由 ContentView 以 onChange 單向同步（store 為唯一
/// 真源），避免循環依賴與雙寫。
@MainActor
final class AppStore: ObservableObject {
    // MARK: - 落盤狀態（didSet 即存）

    @Published var tunerSettings = TunerSettings() { didSet { persist() } }
    @Published var pitchMode: PitchMode = .written { didSet { persist() } }
    @Published var selectedInstrumentId = "alto_sax" { didSet { persist() } }
    @Published var favoriteInstrumentIds: [String] = [] { didSet { persist() } }
    @Published var customInstruments: [Instrument] = [] { didSet { persist() } }
    @Published var droneTimbre: DroneTimbre = .oboe { didSet { persist() } }
    @Published var droneFollow = false { didSet { persist() } }
    @Published var metronomeSettings = MetronomeSettings() { didSet { persist() } }
    @Published var metronomeUserPresets: [MetronomePreset] = [] { didSet { persist() } }
    @Published var appMode: AppMode = .tuner { didSet { persist() } }
    /// 調音主顯示模式（頻閃／指針）：純顯示偏好，引擎不感知。
    @Published var tunerDisplayMode: TunerDisplayMode = .strobe { didSet { persist() } }

    /// 選樂器脈衝：每次 selectInstrument 呼叫 +1（含同名重選——
    /// 母本 selectInstrument 連重選也清鎖定與軌跡，行 8485）。
    /// TunerViewModel 訂閱此脈衝執行選樂器副作用；不落盤。
    @Published private(set) var selectionPulse = 0

    /// 選樂器入口（母本 selectInstrument）：設定選中 id 並發脈衝。
    func selectInstrument(id: String) {
        selectedInstrumentId = id
        selectionPulse += 1
    }

    // MARK: - 僅執行期狀態（母本 state 層，不落盤）

    /// 古箏調號（母本 state.guzhengKey，預設 "D"；母本不入 profile，
    /// 重開即回 D，原生版同）。
    @Published var guzhengKey = "D"

    private var guzhengFavMigrationDone = false
    private var loading = true

    // MARK: - 檔案位置

    static var stateFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AcousticReference/state-v1.json")
    }

    // MARK: - 載入與遷移

    init() {
        let snapshot: AppStateFile
        if let loaded = Self.loadStateFile() {
            snapshot = loaded
        } else {
            snapshot = Self.migratedSnapshot()
        }
        tunerSettings = snapshot.tunerSettings
        pitchMode = snapshot.pitchMode
        customInstruments = snapshot.customInstruments
        droneTimbre = snapshot.droneTimbre
        droneFollow = snapshot.droneFollow
        metronomeSettings = snapshot.metronomeSettings
        metronomeUserPresets = snapshot.metronomeUserPresets
        appMode = AppMode(rawValue: snapshot.appMode) ?? .tuner
        tunerDisplayMode = snapshot.tunerDisplayMode
        guzhengFavMigrationDone = snapshot.guzhengFavMigrationDone

        // 收藏／選中樂器健全化：剔除無法解析的 id；收藏為空時回母本
        // 預設 [INSTRUMENTS[0], piano, violin]（createDefaultProfile）。
        var favorites = snapshot.favoriteInstrumentIds.filter { instrument(id: $0) != nil }
        if favorites.isEmpty {
            favorites = ["alto_sax", "piano", "violin"].filter { instrument(id: $0) != nil }
        }
        favoriteInstrumentIds = favorites
        selectedInstrumentId = instrument(id: snapshot.selectedInstrumentId) != nil
            ? snapshot.selectedInstrumentId
            : InstrumentCatalog.builtins[0].id

        // 古箏收藏遷移（母本行 6550，旗標 laurent_fav_guzheng_removed_v1）：
        // 未遷移過且收藏 >1 且含古箏 → 移除一次；其後手動加回保留。
        if !guzhengFavMigrationDone {
            if favoriteInstrumentIds.count > 1,
               favoriteInstrumentIds.contains("guzheng") {
                favoriteInstrumentIds.removeAll { $0 == "guzheng" }
            }
            guzhengFavMigrationDone = true
        }

        loading = false
        persist()
    }

    private static func loadStateFile() -> AppStateFile? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let decoded = try? JSONDecoder().decode(AppStateFile.self, from: data)
        else { return nil }
        return decoded
    }

    /// 階段 3 佔位鍵遷移：MetronomeStore 的兩個 UserDefaults 鍵與
    /// ContentView 的 mode 鍵。遷移後刪除舊鍵，僅執行一次（state
    /// 文件存在後不再走此路徑）。節拍器設定／自訂預置以原 Codable
    /// 形狀直讀，內容零轉換、零遺失。
    private static func migratedSnapshot() -> AppStateFile {
        var snapshot = AppStateFile()
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "laurent.metro.settings.v1"),
           let settings = try? decoder.decode(MetronomeSettings.self, from: data) {
            snapshot.metronomeSettings = settings
        }
        if let data = defaults.data(forKey: "laurent.metro.userPresets.v1"),
           let presets = try? decoder.decode([MetronomePreset].self, from: data) {
            snapshot.metronomeUserPresets = presets
        }
        if let mode = defaults.string(forKey: "laurent.app.mode") {
            snapshot.appMode = mode
        }
        defaults.removeObject(forKey: "laurent.metro.settings.v1")
        defaults.removeObject(forKey: "laurent.metro.userPresets.v1")
        defaults.removeObject(forKey: "laurent.app.mode")
        return snapshot
    }

    private func persist() {
        guard !loading else { return }
        var snapshot = AppStateFile()
        snapshot.tunerSettings = tunerSettings
        snapshot.pitchMode = pitchMode
        snapshot.selectedInstrumentId = selectedInstrumentId
        snapshot.favoriteInstrumentIds = favoriteInstrumentIds
        snapshot.customInstruments = customInstruments
        snapshot.droneTimbre = droneTimbre
        snapshot.droneFollow = droneFollow
        snapshot.metronomeSettings = metronomeSettings
        snapshot.metronomeUserPresets = metronomeUserPresets
        snapshot.appMode = appMode.rawValue
        snapshot.guzhengFavMigrationDone = guzhengFavMigrationDone
        snapshot.tunerDisplayMode = tunerDisplayMode
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = Self.stateFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - 目錄解析

    /// 母本 allInstruments()：內建（目錄序）＋自訂（新增序）。
    var allInstruments: [Instrument] {
        InstrumentCatalog.builtins + customInstruments
    }

    func instrument(id: String) -> Instrument? {
        customInstruments.first { $0.id == id } ?? InstrumentCatalog.builtin(id: id)
    }

    var selectedInstrument: Instrument {
        instrument(id: selectedInstrumentId) ?? InstrumentCatalog.builtins[0]
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteInstrumentIds.contains(id)
    }

    /// 有效移調：古箏隨目前調號（母本行 8615，選調即改寫
    /// currentInst.trans = GUZHENG_KEY_SEMITONES[key]）。
    func effectiveTransposition(of inst: Instrument) -> Int {
        if inst.isGuzheng {
            return InstrumentCatalog.guzhengKeySemitones[guzhengKey] ?? inst.transposition
        }
        return inst.transposition
    }

    /// 選中樂器的有效檢測音域（供 AudioEngine.range）。
    var effectiveRange: InstrumentRange {
        let inst = selectedInstrument
        return InstrumentRange(
            id: inst.id,
            transposition: effectiveTransposition(of: inst),
            minFrequency: inst.minFrequency,
            maxFrequency: inst.maxFrequency)
    }

    /// 頂行調號標籤（母本行 8498）：古箏顯示目前調號，其餘 keyName。
    func keyLabel(of inst: Instrument) -> String {
        inst.isGuzheng ? "1 = \(guzhengKey)" : inst.keyName
    }

    // MARK: - 收藏（母本 toggleFavoriteInstrument，行 6769）

    @discardableResult
    func toggleFavorite(id: String) -> FavoriteToggleOutcome {
        if favoriteInstrumentIds.contains(id) {
            guard favoriteInstrumentIds.count > 1 else { return .rejectedMinimum }
            favoriteInstrumentIds.removeAll { $0 == id }
            return .removed
        }
        favoriteInstrumentIds.append(id)
        return .added
    }

    // MARK: - 自訂樂器（母本保存處理，行 7836）

    /// 新增或更新一筆自訂樂器，回傳保存後的樂器。換算逐項對照
    /// 母本：en 空 → "Custom"；keyName 空 → `1 = ${NOTE_NAMES[trans 的 pc]}`；
    /// minF = max(20, freqOf440(low)×0.85)、maxF = freqOf440(high)×1.15；
    /// catLabel 恆 "CUSTOM · 自訂樂器"；新 id = `custom_${毫秒時間戳}`。
    @discardableResult
    func saveCustomInstrument(
        editingId: String?, name: String, englishName: String, keyName: String,
        transposition: Int, category: InstrumentCategory,
        lowMidi: Int, highMidi: Int
    ) -> Instrument {
        let trimmedEn = englishName.trimmingCharacters(in: .whitespaces)
        let trimmedKey = keyName.trimmingCharacters(in: .whitespaces)
        let pc = ((transposition % 12) + 12) % 12
        let inst = Instrument(
            id: editingId ?? "custom_\(Int(Date().timeIntervalSince1970 * 1000))",
            category: category,
            categoryLabel: "CUSTOM · 自訂樂器",
            name: name,
            englishName: trimmedEn.isEmpty ? "Custom" : trimmedEn,
            keyName: trimmedKey.isEmpty ? "1 = \(PitchMath.noteNames[pc])" : trimmedKey,
            transposition: transposition,
            minFrequency: max(20, PitchMath.frequency440(midi: Double(lowMidi)) * 0.85),
            maxFrequency: PitchMath.frequency440(midi: Double(highMidi)) * 1.15,
            refTargets: nil, stringNotes: nil,
            isGuzheng: false, isCustom: true)
        if let editingId, let idx = customInstruments.firstIndex(where: { $0.id == editingId }) {
            customInstruments[idx] = inst
        } else {
            customInstruments.append(inst)
        }
        return inst
    }

    /// 刪除自訂樂器（母本 deleteCustomInstrument，行 7693）：連帶移出
    /// 收藏；若為目前選中樂器，選回 INSTRUMENTS[0]。
    func deleteCustomInstrument(id: String) {
        customInstruments.removeAll { $0.id == id }
        favoriteInstrumentIds.removeAll { $0 == id }
        if selectedInstrumentId == id {
            selectInstrument(id: InstrumentCatalog.builtins[0].id)
        }
    }
}
