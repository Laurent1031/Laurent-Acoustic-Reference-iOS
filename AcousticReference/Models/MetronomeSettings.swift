import Foundation

/// 節拍器點音色（母本 TIMBRE_OPTIONS，行 7094）：同名同性格，
/// 合成參數在 ClickSynth 逐項對照母本 triggerMetroSound。
enum MetronomeTimbre: String, CaseIterable, Codable, Sendable {
    case woodblock
    case wittner
    case digital
    case rimshot
    case marimba

    /// 母本顯示名（zh-CN 源串；zh-TW 介面經 i18n 表轉換，階段 5 接入
    /// i18n 後改走字串表，此處先用母本 zh-TW 渲染值）。
    var displayName: String {
        switch self {
        case .woodblock: return "樂團木魚"
        case .wittner: return "機械鐘擺"
        case .digital: return "DB-90 電子"
        case .rimshot: return "軍鼓邊擊"
        case .marimba: return "溫潤木琴"
        }
    }
}

/// 節拍器預置（母本 metro preset：整組節拍器狀態的命名快照）。
struct MetronomePreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var bpm: Int
    var beats: Int
    var noteUnit: Int
    var subdivision: Int
    var timbre: MetronomeTimbre
    var builtin: Bool

    /// 母本 BUILTIN_METRO_PRESETS（行 7096–7100），逐值照抄。
    static let builtins: [MetronomePreset] = [
        MetronomePreset(id: "bi_60_4_4", name: "基础长音 60", bpm: 60, beats: 4, noteUnit: 4, subdivision: 1, timbre: .woodblock, builtin: true),
        MetronomePreset(id: "bi_76_4_4", name: "室内乐行板 76", bpm: 76, beats: 4, noteUnit: 4, subdivision: 1, timbre: .wittner, builtin: true),
        MetronomePreset(id: "bi_96_3_4", name: "圆舞曲 96", bpm: 96, beats: 3, noteUnit: 4, subdivision: 1, timbre: .woodblock, builtin: true),
        MetronomePreset(id: "bi_120_2_4", name: "进行曲 120", bpm: 120, beats: 2, noteUnit: 4, subdivision: 2, timbre: .rimshot, builtin: true),
        MetronomePreset(id: "bi_88_6_8", name: "复拍律动 88", bpm: 88, beats: 6, noteUnit: 8, subdivision: 1, timbre: .marimba, builtin: true),
    ]
}

/// 漸速快捷方案（母本 RAMP_QUICK_SCHEMES，行 7102–7109）。
struct RampQuickScheme: Identifiable, Sendable {
    let id: String
    let label: String
    /// 目標 = 目前 BPM + delta；off／custom 為 nil。
    let delta: Int?
    let bars: Int
    let step: Int

    static let all: [RampQuickScheme] = [
        RampQuickScheme(id: "off", label: "关闭（常规恒速）", delta: nil, bars: 0, step: 0),
        RampQuickScheme(id: "warm_up", label: "阶梯热身：每4小节 +2 (→ +20)", delta: 20, bars: 4, step: 2),
        RampQuickScheme(id: "steady_up", label: "稳步提速：每4小节 +4 (→ +32)", delta: 32, bars: 4, step: 4),
        RampQuickScheme(id: "sprint_up", label: "密集冲刺：每2小节 +5 (→ +40)", delta: 40, bars: 2, step: 5),
        RampQuickScheme(id: "calm_down", label: "慢练巩固：每4小节 -2 (→ -16)", delta: -16, bars: 4, step: 2),
        RampQuickScheme(id: "custom", label: "自订渐速参数…", delta: nil, bars: 0, step: 0),
    ]
}

/// 漸速運行狀態（母本 metroRamp，行 10998）。
struct RampState: Equatable, Sendable {
    var active = false
    var from = 0
    var to = 0
    var step = 1
    var barsPerStep = 1
    var barsDone = 0

    /// 母本 setRampUI 的進度：已完成小節 / 總小節（START鈕填充比）。
    var progress: Double {
        guard active else { return 0 }
        let totalSteps = max(1, Int(ceil(Double(abs(to - from)) / Double(max(1, step)))))
        let totalBars = max(1, totalSteps * barsPerStep)
        return min(1, Double(barsDone) / Double(totalBars))
    }
}

/// 節拍器設定快照。預設值 = 母本 state 初始值（行 6258–6267）：
/// bpm 120、4/4、細分 1、音色 woodblock、重音 [3,1,2,1]。
/// countIn 在母本是僅記憶體的開關（行 11346，預設關、不落盤），
/// 故自訂 Codable 將它排除於持久化之外（解碼恆為 false）。
struct MetronomeSettings: Equatable, Sendable {
    var bpm: Int = 120
    var beatsPerBar: Int = 4
    var beatUnit: Int = 4
    var dottedBeat: Bool = false
    var subdivision: Int = 1
    var timbre: MetronomeTimbre = .woodblock
    var beatAccents: [Int] = [3, 1, 2, 1]
    /// 藍牙補償（母本 androidBtCompMs）：0–300 ms、步進 10，
    /// 只延遲視覺與震動、不延遲音頻（母本行 11287、12106）。
    var bluetoothCompMs: Int = 0
    /// 預備拍開關（母本 countInOn）：僅執行期狀態，不落盤。
    var countIn: Bool = false

    // MARK: - 母本常數（行 10450–10458）

    static let bpmMin = 40
    static let bpmMax = 208
    static let bpmMaxDotted = 213

    /// 母本 isDottedBeat：附點計拍只在八分音符拍號下生效。
    var isDottedBeat: Bool { dottedBeat && beatUnit == 8 }

    /// 母本 bpmMaxNow。
    var bpmMaxNow: Int { isDottedBeat ? Self.bpmMaxDotted : Self.bpmMax }

    /// 母本 setBpm 的鉗制（行 10650）：round 後鉗 [40, bpmMaxNow]。
    func clampedBpm(_ value: Int) -> Int {
        min(bpmMaxNow, max(Self.bpmMin, value))
    }

    /// 母本 effectiveSubsNow（行 10464）：每拍的細分步數。
    /// 細分 5（附點搖擺）恆為 2 步（2:1）；附點計拍下八分細分變
    /// 3 步、十六分變 6 步。
    var effectiveSubs: Int {
        if subdivision == 5 { return 2 }
        if !isDottedBeat { return subdivision }
        if subdivision == 1 { return 1 }
        if subdivision == 2 || subdivision == 3 { return 3 }
        if subdivision == 4 { return 6 }
        return subdivision
    }

    /// 一小節的計拍數（附點計拍時一拍跨三根八分拍柱）。
    var beatsInBar: Int { isDottedBeat ? beatsPerBar / 3 : beatsPerBar }

    // MARK: - 母本選項表

    /// 母本 SIG_OPTIONS（行 7092）：11 種拍號。
    static let signatures: [(beats: Int, unit: Int)] = [
        (1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4),
        (3, 8), (6, 8), (7, 8), (9, 8), (12, 8),
    ]

    /// 母本 SUB_OPTIONS（行 7093）：5 種細分（zh-TW 渲染值）。
    static let subdivisionOptions: [(value: Int, label: String)] = [
        (1, "♩ 四分"), (2, "♫ 八分"), (3, "♪♪♪ 三連"), (4, "♬ 十六"), (5, "♩. 附點"),
    ]

    /// 速度預置（母本 tempoPresetRow，行 5409–5416）：6 個。
    static let tempoPresets: [(bpm: Int, name: String)] = [
        (56, "慢板"), (66, "柔板"), (76, "行板"),
        (104, "中板"), (120, "快板"), (176, "急板"),
    ]

    /// 推子吸附點（母本行 10704，僅拖動路徑、±1.5 BPM 內吸附）。
    static let faderSnapPoints = [60, 72, 80, 96, 120, 144, 160]

    /// 重音等級標籤（母本 LEVEL_LABELS，行 10392）。
    static let levelLabels = ["靜音", "弱拍", "次強", "強拍"]

    /// 母本 defaultAccentsFor（行 6489）：按拍號給出音樂性預設重音。
    static func defaultAccents(beats: Int, unit: Int) -> [Int] {
        if unit == 8 && beats % 3 == 0 && beats >= 6 {
            return (0..<beats).map { i in i == 0 ? 3 : (i % 3 == 0 ? 2 : 1) }
        }
        if beats == 5 { return [3, 1, 1, 2, 1] }
        if beats == 7 && unit == 8 { return [3, 1, 2, 1, 2, 1, 1] }
        if beats == 4 { return [3, 1, 2, 1] }
        if beats == 3 { return [3, 1, 1] }
        if beats == 2 { return [3, 1] }
        return (0..<beats).map { $0 == 0 ? 3 : 1 }
    }

    /// 母本 getTempoTerm（行 10434）。
    static func tempoTerm(_ bpm: Int) -> String {
        if bpm < 40 { return "GRAVE" }
        if bpm < 60 { return "LARGO" }
        if bpm < 76 { return "ADAGIO" }
        if bpm < 100 { return "ANDANTE" }
        if bpm < 120 { return "MODERATO" }
        if bpm < 156 { return "ALLEGRO" }
        if bpm < 176 { return "VIVACE" }
        if bpm < 200 { return "PRESTO" }
        return "PRESTISSIMO"
    }
}

// MARK: - Codable（countIn 不落盤，母本行 11346）

extension MetronomeSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case bpm, beatsPerBar, beatUnit, dottedBeat, subdivision
        case timbre, beatAccents, bluetoothCompMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try c.decode(Int.self, forKey: .bpm)
        beatsPerBar = try c.decode(Int.self, forKey: .beatsPerBar)
        beatUnit = try c.decode(Int.self, forKey: .beatUnit)
        dottedBeat = try c.decode(Bool.self, forKey: .dottedBeat)
        subdivision = try c.decode(Int.self, forKey: .subdivision)
        timbre = try c.decode(MetronomeTimbre.self, forKey: .timbre)
        beatAccents = try c.decode([Int].self, forKey: .beatAccents)
        bluetoothCompMs = try c.decode(Int.self, forKey: .bluetoothCompMs)
        countIn = false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(beatsPerBar, forKey: .beatsPerBar)
        try c.encode(beatUnit, forKey: .beatUnit)
        try c.encode(dottedBeat, forKey: .dottedBeat)
        try c.encode(subdivision, forKey: .subdivision)
        try c.encode(timbre, forKey: .timbre)
        try c.encode(beatAccents, forKey: .beatAccents)
        try c.encode(bluetoothCompMs, forKey: .bluetoothCompMs)
    }
}

/// 節拍器設定的佔位持久化（MetronomeStore，UserDefaults）已於
/// 階段 4 由 Models/AppStore.swift 的單一數據層取代；舊鍵
/// laurent.metro.settings.v1／laurent.metro.userPresets.v1 在
/// AppStore 首次啟動時遷移並刪除（見 AppStore.migratedSnapshot）。
