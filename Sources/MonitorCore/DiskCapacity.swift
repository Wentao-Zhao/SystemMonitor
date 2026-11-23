import Foundation

/// Storage capacity, with system-reclaimable availability kept separate from free bytes.
public struct DiskCapacity: Equatable, Sendable {
    public let totalBytes: Double
    public let freeBytes: Double?
    public let availableBytes: Double
    public var usedBytes: Double { totalBytes - availableBytes }
    public var usedPercent: Double { usedBytes / totalBytes * 100 }
    public var includesReclaimableSpace: Bool { freeBytes.map { availableBytes > $0 } ?? false }

    public init?(totalBytes: Double, freeBytes: Double?, availableForImportantUsage: Double?) {
        guard totalBytes.isFinite, totalBytes > 0 else { return nil }
        func valid(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 >= 0 ? min(totalBytes, $0) : nil }
        }
        let free = valid(freeBytes)
        let estimate = valid(availableForImportantUsage)
        guard let available = [free, estimate].compactMap({ $0 }).max() else { return nil }
        self.totalBytes = totalBytes; self.freeBytes = free; self.availableBytes = available
    }
}
