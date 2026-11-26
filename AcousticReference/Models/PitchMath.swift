import Foundation

/// 音高數學：頻率／MIDI／音名／音分換算。
///
/// 全部常數與公式逐項對照母本 `~/workspace/tuner-metronome/index.html`（基準版
/// 12,582 行、md5 1c13f1482b4d158d5834711921cbf1e4），行號註記指該檔行號。
enum PitchMath {

    /// 母本 NOTE_NAMES（行 6186）。拼寫與母本一致（升降號混用為母本既定拼法，
    /// 不是平均律標準拼法，不要自行「修正」）。
    static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    /// 五極限純律相對十二平均律的音分偏移（母本 JUST_CENTS，行 8880）。
    /// 索引為 pitch class（C = 0）。
    static let justIntonationCents: [Double] = [
        0, 11.7, 3.9, 15.6, -13.7, -2.0, -9.8, 2.0, 13.7, -15.6, 17.6, -11.7,
    ]

    /// 母本 exactMidi（行 9598）：69 + 12·log2(f / A4)。
    static func exactMidi(frequency: Double, a4: Double) -> Double {
        69.0 + 12.0 * log2(frequency / a4)
    }

    /// 母本 freqOf（行 6136）：以當前 A4 為基準的 MIDI→頻率。
    static func frequency(midi: Double, a4: Double) -> Double {
        a4 * pow(2.0, (midi - 69.0) / 12.0)
    }

    /// 自訂樂器音域換算專用（母本行 7856）：固定以 440 為基準，不用當前 A4。
    static func frequency440(midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    /// 母本音名拼法（行 9610 起）：NOTE_NAMES[midi mod 12] + 八度，
    /// 八度 = floor(midi / 12) − 1。
    static func noteName(midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = Int(floor(Double(midi) / 12.0)) - 1
        return noteNames[pc] + String(octave)
    }

    /// 母本 noteStringToMidi（行 8867）：音名字串 → MIDI；
    /// 格式 ^([A-G])([♯♭#b]?)(-?\d+)$，不合格式回 69（母本原式）。
    static func midi(noteString: String) -> Int {
        let chars = Array(noteString)
        guard chars.count >= 2, let base = baseSemitones[chars[0]] else { return 69 }
        var semitone = base
        var idx = 1
        if idx < chars.count {
            switch chars[idx] {
            case "♯", "#": semitone += 1; idx += 1
            case "♭", "b": semitone -= 1; idx += 1
            default: break
            }
        }
        let octaveText = String(chars[idx...])
        guard !octaveText.isEmpty, let octave = Int(octaveText) else { return 69 }
        return (octave + 1) * 12 + semitone
    }

    private static let baseSemitones: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
    ]

    /// 母本 temperamentOffsetCents（行 8882）：僅純律（just）時非零；
    /// pc 以主音（justTonicPc）為原點。
    static func temperamentOffsetCents(targetMidi: Int, temperament: Temperament, justTonicPc: Int) -> Double {
        guard temperament == .just else { return 0 }
        let pc = (((targetMidi - justTonicPc) % 12) + 12) % 12
        return justIntonationCents[pc]
    }

    /// 母本音分公式（行 9598）：(exactMidi − targetMidi)·100 − 純律偏移，
    /// 結果鉗制在 [−50, +50]。
    static func cents(exactMidi: Double, targetMidi: Int, temperament: Temperament, justTonicPc: Int) -> Double {
        let raw = (exactMidi - Double(targetMidi)) * 100.0
            - temperamentOffsetCents(targetMidi: targetMidi, temperament: temperament, justTonicPc: justTonicPc)
        return min(50.0, max(-50.0, raw))
    }
}

/// 律制（母本 profile.temperament，預設 "equal"，行 6225）。
enum Temperament: String, CaseIterable, Codable, Sendable {
    case equal
    case just
}
