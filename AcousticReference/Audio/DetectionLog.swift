import Foundation

/// 一筆檢測記錄（規格書 §3.2 診斷模式：檢測記錄可導出，供離線逐音核對）。
struct DetectionRecord: Sendable {
    /// 單調時鐘秒數（相對引擎首次分析）。
    var time: TimeInterval
    var hasPitch: Bool
    var rawFrequency: Double?
    var clarity: Double
    var rms: Double
    var smoothedFrequency: Double
    var cents: Double
}

/// 檢測記錄環形緩衝（上限 1200 筆，約涵蓋最近 ~13 秒 @512 hop/48k）。
/// 線程安全：分析佇列寫入、主線程導出。
/// 【返修批7・F9】名實相符的真環形：舊實作以 Array＋removeFirst
/// 淘汰（O(n) 搬移，滿載後每筆 append 都搬 1200 筆）；改 head
/// 索引覆寫最舊筆，append 恆 O(1)。對外行為（容量、順序、
/// 導出格式）與舊版逐項一致。
final class DetectionLog: @unchecked Sendable {
    private let lock = NSLock()
    /// 環形儲存：未滿載時依序 append；滿載後 ring[head] 為最舊
    /// 一筆、新筆覆寫之並推進 head。
    private var ring: [DetectionRecord] = []
    private var head = 0
    private var startTime: TimeInterval?
    private let capacity = 1200

    func append(reading: PitchReading, now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if startTime == nil { startTime = now }
        let record = DetectionRecord(
            time: now - (startTime ?? now),
            hasPitch: reading.hasPitch,
            rawFrequency: reading.rawFrequency,
            clarity: reading.clarity,
            rms: reading.rms,
            smoothedFrequency: reading.smoothedFrequency,
            cents: reading.cents
        )
        if ring.count < capacity {
            ring.append(record)
        } else {
            ring[head] = record
            head = (head + 1) % capacity
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        ring.removeAll()
        head = 0
        startTime = nil
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return ring.count
    }

    /// 依時間序（舊→新）展開環形儲存；呼叫方須持 lock。
    private var orderedRecords: [DetectionRecord] {
        guard ring.count == capacity, head > 0 else { return ring }
        return Array(ring[head...]) + Array(ring[..<head])
    }

    /// 導出為 CSV 文字（time_s,has_pitch,raw_hz,clarity,rms,smoothed_hz,cents）。
    func exportText() -> String {
        lock.lock()
        let snapshot = orderedRecords
        lock.unlock()
        var lines = ["time_s,has_pitch,raw_hz,clarity,rms,smoothed_hz,cents"]
        lines.reserveCapacity(snapshot.count + 1)
        for r in snapshot {
            let raw = r.rawFrequency.map { String(format: "%.2f", $0) } ?? ""
            lines.append(
                String(format: "%.3f,%ld,%@,%.4f,%.5f,%.2f,%.1f",
                       r.time, r.hasPitch ? 1 : 0, raw, r.clarity, r.rms,
                       r.smoothedFrequency, r.cents)
            )
        }
        return lines.joined(separator: "\n")
    }
}
