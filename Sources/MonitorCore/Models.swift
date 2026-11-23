import Foundation

public enum ModuleID: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, network, sensors, power
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: return "处理器"
        case .gpu: return "图形处理器"
        case .memory: return "内存"
        case .disk: return "磁盘"
        case .network: return "网络"
        case .sensors: return "温度与风扇"
        case .power: return "功耗"
        }
    }
    public var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .sensors: return "thermometer.medium"
        case .power: return "bolt"
        }
    }
}

public struct HardwareSensor: Codable, Sendable {
    public let id: String
    public let title: String
    public let value: Double
    public let unit: String
    public init(id: String, title: String, value: Double, unit: String) {
        self.id = id; self.title = title; self.value = value; self.unit = unit
    }
}

public struct HardwareSample: Codable, Sendable {
    public var gpu: Double?
    public var gpuName: String
    public var sensors: [HardwareSensor]
    public var powers: [HardwareSensor]
    public var errors: [String]
    public init(gpu: Double? = nil, gpuName: String = "GPU", sensors: [HardwareSensor] = [], powers: [HardwareSensor] = [], errors: [String] = []) {
        self.gpu = gpu; self.gpuName = gpuName; self.sensors = sensors; self.powers = powers; self.errors = errors
    }
}

public struct MetricReading: Identifiable, Sendable {
    public let id: String
    public let title: String
    public var value: Double?
    public let unit: String
    public var note: String
    public var previousValue: Double?
    public var previousDate: Date?
    public init(_ id: String, _ title: String, _ value: Double?, _ unit: String, note: String = "") {
        self.id = id; self.title = title; self.value = value; self.unit = unit; self.note = note
    }
    public var formatted: String {
        guard let value, value.isFinite else { return "—" }
        switch unit {
        case "bytes": return ByteCountFormatter.string(fromByteCount: Int64(max(0, min(value, Double(Int64.max) / 2))), countStyle: id.hasPrefix("disk.") ? .decimal : .binary)
        case "B/s":
            if value < 1024 { return String(format: "%.0f B/s", value) }
            if value < 1048576 { return String(format: "%.1f KB/s", value / 1024) }
            return String(format: "%.1f MB/s", value / 1048576)
        case "%": return String(format: "%.0f%%", value)
        case "°C": return String(format: "%.1f °C", value)
        case "RPM": return String(format: "%.0f RPM", value)
        case "W": return String(format: "%.2f W", value)
        case "level": return value >= 4 ? "紧张" : value >= 2 ? "偏高" : "正常"
        default: return String(format: "%.1f %@", value, unit)
        }
    }
}

public struct ReadingCache {
    private var previous: [String: (module: ModuleID, reading: MetricReading, date: Date)] = [:]
    public init() {}
    public mutating func annotate(_ snapshot: MonitorSnapshot) -> MonitorSnapshot {
        var result = snapshot
        for module in ModuleID.allCases {
            var readings = snapshot.readings[module] ?? []
            let incomingIDs = Set(readings.map(\.id))
            for cached in previous.values.filter({ $0.module == module && !incomingIDs.contains($0.reading.id) }).sorted(by: { $0.reading.id < $1.reading.id }) {
                readings.append(MetricReading(cached.reading.id, cached.reading.title, nil, cached.reading.unit, note: "当前不可用"))
            }
            result.readings[module] = readings.map { reading in
                var value = reading
                if let number = reading.value, number.isFinite { previous[reading.id] = (module, reading, snapshot.date) }
                else if let last = previous[reading.id] { value.previousValue = last.reading.value; value.previousDate = last.date }
                return value
            }
        }
        return result
    }
    public mutating func remove(prefix: String) { previous = previous.filter { !$0.key.hasPrefix(prefix) } }
}

public struct DeviceChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct MonitorSnapshot: Sendable {
    public var date: Date = Date()
    public var uptime: Double = 0
    public var bootTime: Date?
    public var readings: [ModuleID: [MetricReading]] = [:]
    public var notes: [ModuleID: String] = [:]
    public var interfaces: [DeviceChoice] = []
    public var disks: [DeviceChoice] = []
    public var selectedInterface: String = ""
    public var selectedDisk: String = ""
    public init() {}
    public func reading(_ id: String) -> MetricReading? { readings.values.joined().first { $0.id == id } }
    public var values: [String: Double] {
        Dictionary(readings.values.joined().compactMap { reading in
            reading.value.flatMap { $0.isFinite ? (reading.id, $0) : nil }
        }, uniquingKeysWith: { _, latest in latest })
    }
}
