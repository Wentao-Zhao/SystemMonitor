import Foundation
import Darwin

/// Continuous monotonic time includes sleep, unlike ProcessInfo.systemUptime.
public enum SampleClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    public static var now: Double { Double(mach_continuous_time()) * secondsPerTick }
}

public struct CounterRate {
    private var previous: (total: UInt64, time: Double)?
    public init() {}
    public mutating func sample(total: UInt64, time: Double) -> Double? {
        defer { previous = time.isFinite ? (total, time) : nil }
        guard let previous, time > previous.time, total >= previous.total else { return nil }
        return Double(total - previous.total) / (time - previous.time)
    }
    public mutating func reset() { previous = nil }
}

public struct NetworkSession {
    public private(set) var currentInterface: String?
    private var start: (received: UInt64, sent: UInt64)?
    private var previous: (received: UInt64, sent: UInt64)?
    public init() {}
    public mutating func select(interface: String) {
        let id = interface.isEmpty ? nil : interface
        if currentInterface != id { currentInterface = id; start = nil; previous = nil }
    }
    public mutating func sample(interface: String, received: UInt64, sent: UInt64) -> (received: UInt64, sent: UInt64, didReset: Bool) {
        let changed = currentInterface != interface || start == nil || received < (previous?.received ?? 0) || sent < (previous?.sent ?? 0)
        if changed { start = (received, sent); currentInterface = interface }
        previous = (received, sent)
        return (received - (start?.received ?? received), sent - (start?.sent ?? sent), changed)
    }
    public mutating func reset() { currentInterface = nil; start = nil; previous = nil }
}

public struct HistoryPoint: Identifiable, Sendable {
    public var id: Double { time }
    public let time: Double
    public let value: Double?
    public let minimum: Double?
    public let maximum: Double?
    public init(time: Double, value: Double?, minimum: Double? = nil, maximum: Double? = nil) {
        self.time = time; self.value = value; self.minimum = minimum; self.maximum = maximum
    }
}

public func chartSegments(_ points: [HistoryPoint], maxGap: Double = 12) -> [[HistoryPoint]] {
    var result: [[HistoryPoint]] = []
    var segment: [HistoryPoint] = []
    for point in points {
        guard let value = point.value, value.isFinite else {
            if !segment.isEmpty { result.append(segment); segment = [] }
            continue
        }
        if let previous = segment.last, point.time - previous.time > maxGap {
            result.append(segment); segment = []
        }
        segment.append(point)
    }
    if !segment.isEmpty { result.append(segment) }
    return result
}

/// Recent samples stay exact; older ten-second buckets retain mean and range.
public struct MetricHistory {
    private struct Frame {
        var time: Double
        var values: [String: Double]
        var minimum: [String: Double] = [:]
        var maximum: [String: Double] = [:]
    }
    private struct Bucket {
        var index: Double
        var time: Double
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var minimum: [String: Double] = [:]
        var maximum: [String: Double] = [:]
        var invalid = Set<String>()
        var samples = 0
        mutating func add(time: Double, values: [String: Double], known: Set<String>) {
            self.time = time
            invalid.formUnion(known.subtracting(values.keys))
            if samples > 0 { invalid.formUnion(Set(values.keys).subtracting(counts.keys)) }
            for (id, value) in values {
                sums[id, default: 0] += value; counts[id, default: 0] += 1
                minimum[id] = min(minimum[id] ?? value, value)
                maximum[id] = max(maximum[id] ?? value, value)
            }
            samples += 1
        }
        var frame: Frame {
            let means = sums.filter { !invalid.contains($0.key) }.compactMapValues { $0.isFinite ? $0 : nil }
            var values: [String: Double] = [:]
            for (id, sum) in means { values[id] = sum / Double(counts[id] ?? 1) }
            return Frame(time: time, values: values, minimum: minimum, maximum: maximum)
        }
    }
    private var recent: [Frame] = []
    private var archived: [Frame] = []
    private var bucket: Bucket?
    private var known = Set<String>()
    private var lastTime: Double?
    private let retention: Double
    public init(retention: Double = 86_400) { self.retention = retention.isFinite ? max(1, retention) : 86_400 }

    public mutating func append(time: Double, values: [String: Double]) {
        guard time.isFinite, lastTime.map({ time > $0 }) ?? true else { return }
        lastTime = time
        let values = values.filter { $0.value.isFinite }
        known.formUnion(values.keys)
        recent.append(Frame(time: time, values: values))
        let rawRetention = min(120, retention)
        recent.removeAll { $0.time < time - rawRetention }
        if recent.count > 1201 { recent.removeFirst(recent.count - 1201) }
        guard retention > 120 else { return }
        let index = floor(time / 10)
        if bucket?.index != index { flushBucket() }
        if values.isEmpty {
            flushBucket()
            if archived.last?.values.isEmpty != true { archived.append(Frame(time: time, values: [:])) }
        } else {
            if bucket == nil { bucket = Bucket(index: index, time: time) }
            bucket?.add(time: time, values: values, known: known)
        }
        if archived.first.map({ $0.time < time - retention }) == true {
            archived.removeAll { $0.time < time - retention }
        }
        // Bound unusual callers with extremely frequent pause/missing markers too.
        let limit = Int(min(retention / 10, 86_400)) * 3 + 16
        if archived.count > limit { archived.removeFirst(archived.count - limit) }
    }
    private mutating func flushBucket() {
        if let bucket { archived.append(bucket.frame) }
        bucket = nil
    }
    public func points(for id: String, since: Double) -> [HistoryPoint] {
        let boundary = recent.first?.time ?? .infinity
        var frames: [Frame] = []
        if since < boundary { frames = archived.filter { $0.time >= since && $0.time < boundary } }
        frames += recent.filter { $0.time >= since }
        guard frames.contains(where: { $0.values[id] != nil }) else { return [] }
        return frames.map {
            HistoryPoint(time: $0.time, value: $0.values[id], minimum: $0.minimum[id], maximum: $0.maximum[id])
        }
    }
    public mutating func removeSeries(prefix: String) {
        func remove(_ frame: inout Frame) {
            frame.values = frame.values.filter { !$0.key.hasPrefix(prefix) }
            frame.minimum = frame.minimum.filter { !$0.key.hasPrefix(prefix) }
            frame.maximum = frame.maximum.filter { !$0.key.hasPrefix(prefix) }
        }
        for index in recent.indices { remove(&recent[index]) }
        for index in archived.indices { remove(&archived[index]) }
        known = known.filter { !$0.hasPrefix(prefix) }
        if var pending = bucket {
            pending.sums = pending.sums.filter { !$0.key.hasPrefix(prefix) }
            pending.counts = pending.counts.filter { !$0.key.hasPrefix(prefix) }
            pending.minimum = pending.minimum.filter { !$0.key.hasPrefix(prefix) }
            pending.maximum = pending.maximum.filter { !$0.key.hasPrefix(prefix) }
            pending.invalid = pending.invalid.filter { !$0.hasPrefix(prefix) }
            bucket = pending
        }
    }
}

/// Reduce drawing work after separating gaps, preserving extrema and chronology.
public func plotSegments(_ points: [HistoryPoint], targetPoints: Int = 600) -> [[HistoryPoint]] {
    let segments = chartSegments(points)
    let total = segments.reduce(0) { $0 + $1.count }
    guard total > max(4, targetPoints) else { return segments }
    let chunk = max(1, Int(ceil(Double(total) / Double(max(1, targetPoints / 4)))))
    return segments.map { segment in
        var result: [HistoryPoint] = []
        for start in stride(from: 0, to: segment.count, by: chunk) {
            let end = min(segment.count, start + chunk)
            let range = start..<end
            let low = range.min { (segment[$0].minimum ?? segment[$0].value ?? 0) < (segment[$1].minimum ?? segment[$1].value ?? 0) }!
            let high = range.max { (segment[$0].maximum ?? segment[$0].value ?? 0) < (segment[$1].maximum ?? segment[$1].value ?? 0) }!
            result += Set([start, end - 1, low, high]).sorted().map { segment[$0] }
        }
        return result
    }
}
