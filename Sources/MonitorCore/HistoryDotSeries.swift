import Foundation

public struct HistoryDotColumn: Equatable, Sendable {
    public let fraction: Double
    public let peak: Double
}

/// Fixed time slots for panel dot charts. Gaps remain empty; a faint peak dot can
/// retain a brief spike without confusing it with sustained average load.
public enum HistoryDotSeries {
    public static func columns(points: [HistoryPoint], now: Double, window: Double,
                               fullScale: Double, count: Int, maxHold: Double = 12) -> [HistoryDotColumn?] {
        guard count > 0, count <= 1024 else { return [] }
        var result = [HistoryDotColumn?](repeating: nil, count: count)
        guard now.isFinite, window.isFinite, window > 0, (now - window).isFinite,
              fullScale.isFinite, fullScale > 0, maxHold.isFinite, maxHold > 0 else { return result }
        let start = now - window, step = window / Double(count)
        guard step.isFinite, step > 0 else { return result }
        var sums = [Double](repeating: 0, count: count), durations = sums, peaks = sums
        var invalid = [Bool](repeating: false, count: count)
        func visit(_ a: Double, _ b: Double, body: (Int, Double) -> Void) {
            let left = max(start, a), right = min(now, b)
            guard right > left else { return }
            let first = max(0, min(count - 1, Int(floor((left - start) / step))))
            let last = max(0, min(count - 1, Int(ceil((right - start) / step)) - 1))
            for column in first...last {
                let overlap = min(right, start + Double(column + 1) * step) - max(left, start + Double(column) * step)
                if overlap > 0 { body(column, overlap) }
            }
        }
        for (index, point) in points.enumerated() {
            guard point.time.isFinite, point.time < now else { continue }
            let next = index + 1 < points.count ? points[index + 1].time : now
            guard next.isFinite, next > point.time else { continue }
            let end = min(now, next)
            guard let value = point.value, value.isFinite else {
                visit(point.time, end) { column, _ in invalid[column] = true }
                continue
            }
            let heldUntil = min(end, point.time + maxHold)
            let normalized = min(1, max(0, value / fullScale))
            let peak = point.maximum.flatMap { $0.isFinite ? $0 : nil } ?? value
            visit(point.time, heldUntil) { column, duration in
                sums[column] += normalized * duration
                durations[column] += duration
                peaks[column] = max(peaks[column], min(1, max(0, peak / fullScale)), normalized)
            }
            if end > heldUntil { visit(heldUntil, end) { column, _ in invalid[column] = true } }
        }
        for column in 0..<count where durations[column] > 0 && !invalid[column] {
            result[column] = HistoryDotColumn(fraction: sums[column] / durations[column], peak: peaks[column])
        }
        return result
    }
}
