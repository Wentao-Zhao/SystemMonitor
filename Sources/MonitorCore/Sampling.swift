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
    public init(time: Double, value: Double?) { self.time = time; self.value = value }
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

public struct MetricHistory {
    private var frames: [(time: Double, values: [String: Double])] = []
    private let retention: Double
    public init(retention: Double = 900) { self.retention = max(1, retention) }
    public mutating func append(time: Double, values: [String: Double]) {
        guard time.isFinite, frames.last.map({ time > $0.time }) ?? true else { return }
        frames.append((time, values.filter { $0.value.isFinite }))
        frames.removeAll { $0.time < time - retention }
        // Also bound memory if a caller unexpectedly supplies a very fast cadence.
        if frames.count > 1801 { frames.removeFirst(frames.count - 1801) }
    }
    public func points(for id: String, since: Double) -> [HistoryPoint] {
        guard frames.contains(where: { $0.values[id] != nil }) else { return [] }
        return frames.filter { $0.time >= since }.map { HistoryPoint(time: $0.time, value: $0.values[id]) }
    }
    public mutating func removeSeries(prefix: String) {
        for index in frames.indices { frames[index].values = frames[index].values.filter { !$0.key.hasPrefix(prefix) } }
    }
}
