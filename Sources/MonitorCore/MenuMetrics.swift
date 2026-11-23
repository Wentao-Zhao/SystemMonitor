import Foundation

public enum MetricPresentation: String, Codable, CaseIterable, Sendable {
    case instant, history
    public var title: String { self == .instant ? "实时点列" : "60 秒历史点阵" }
}

public enum MetricSignal: String, Sendable { case unknown, normal, elevated, critical }

/// Stable reading identity and scale survive a sensor temporarily disappearing.
public struct MenuMetric: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let module: ModuleID
    public let title: String
    public let unit: String
    public init(id: String, module: ModuleID, title: String, unit: String) {
        self.id = id; self.module = module; self.title = title; self.unit = unit
    }
    public var defaultPresentation: MetricPresentation { module == .cpu || module == .gpu ? .history : .instant }
    public var referenceID: String? {
        if module == .memory && unit == "bytes" && id != "memory.swap" { return "memory.total" }
        if module == .disk && unit == "bytes" { return "disk.total" }
        return nil
    }
    public var defaultScale: Double {
        switch unit {
        case "%", "°C": return 100
        case "level": return 4
        case "RPM": return 6000
        case "W": return id == "system.power" ? 100 : 30
        case "B/s": return (module == .disk ? 100 : 10) * 1_048_576
        case "bytes": return (id == "memory.swap" ? 4 : 1) * 1_073_741_824
        default: return 100
        }
    }
    public var hasAdjustableScale: Bool { unit != "%" && unit != "level" && referenceID == nil }
    public var scaleInputUnit: String { unit == "B/s" ? "MiB/s" : unit == "bytes" ? "GiB" : unit }
    public var scaleInputMultiplier: Double { unit == "B/s" ? 1_048_576 : unit == "bytes" ? 1_073_741_824 : 1 }
    public func fullScale(in snapshot: MonitorSnapshot, override: Double? = nil) -> Double? {
        let scale: Double?
        if let override { scale = override }
        else if let referenceID { scale = snapshot.reading(referenceID)?.value }
        else { scale = defaultScale }
        return scale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    public func fraction(in snapshot: MonitorSnapshot, override: Double? = nil) -> Double? {
        guard let value = snapshot.reading(id)?.value, value.isFinite,
              let scale = fullScale(in: snapshot, override: override) else { return nil }
        return min(1, max(0, value / scale))
    }
    public func signal(in snapshot: MonitorSnapshot, fraction: Double?, previous: MetricSignal = .unknown) -> MetricSignal {
        guard let fraction, fraction.isFinite else { return .unknown }
        if module == .memory {
            guard let pressure = snapshot.reading("memory.pressure")?.value, pressure.isFinite else { return .unknown }
            return pressure >= 4 ? .critical : pressure >= 2 ? .elevated : .normal
        }
        var load = fraction
        if id == "disk.total" {
            guard let occupancy = snapshot.reading("disk.percent")?.value, occupancy.isFinite else { return .unknown }
            load = occupancy / 100
        }
        if id == "disk.available" || id == "disk.free" { load = 1 - load }
        let warning = unit == "°C" ? 0.7 : 0.6
        let critical = unit == "°C" ? 0.9 : 0.85
        if load >= critical || (previous == .critical && load >= critical - 0.05) { return .critical }
        if load >= warning || (previous == .elevated && load >= warning - 0.05) { return .elevated }
        return .normal
    }
}

public struct MenuMetricSelection: Identifiable, Codable, Equatable, Sendable {
    public var id: String { metric.id }
    public let metric: MenuMetric
    public var presentation: MetricPresentation
    public var scale: Double?
    public init(metric: MenuMetric, presentation: MetricPresentation? = nil, scale: Double? = nil) {
        self.metric = metric; self.presentation = presentation ?? metric.defaultPresentation; self.scale = scale
    }
}

public enum MenuMetricCatalog {
    public static func metrics(in snapshot: MonitorSnapshot) -> [MenuMetric] {
        let fixed: [(ModuleID, [(String, String, String)])] = [
            (.cpu, [("cpu.total", "CPU 总负载", "%")]),
            (.gpu, [("gpu.total", "GPU 负载", "%")]),
            (.memory, [("memory.percent", "内存占用", "%"), ("memory.used", "已用内存", "bytes"), ("memory.available", "可用内存", "bytes"), ("memory.total", "物理内存", "bytes"), ("memory.compressed", "压缩内存", "bytes"), ("memory.cached", "可回收缓存", "bytes"), ("memory.swap", "交换空间", "bytes"), ("memory.pressure", "内存压力", "level")]),
            (.disk, [("disk.percent", "磁盘占用", "%"), ("disk.available", "磁盘可用空间", "bytes"), ("disk.total", "卷容量", "bytes"), ("disk.used", "磁盘已用空间", "bytes"), ("disk.free", "当前空闲空间", "bytes"), ("disk.read", "磁盘读取", "B/s"), ("disk.write", "磁盘写入", "B/s")]),
            (.network, [("network.in", "网络下载", "B/s"), ("network.out", "网络上传", "B/s"), ("network.received", "会话接收", "bytes"), ("network.sent", "会话发送", "bytes")]),
            (.sensors, [("cpu.temperature", "CPU 温度", "°C"), ("gpu.temperature", "GPU 温度", "°C")]),
            (.power, [("system.power", "整机功耗", "W"), ("cpu.power", "CPU 功耗", "W"), ("gpu.power", "GPU 功耗", "W")])
        ]
        var result: [MenuMetric] = []
        for (module, readings) in fixed {
            result += readings.map { MenuMetric(id: $0.0, module: module, title: $0.1, unit: $0.2) }
            let known = Set(result.map(\.id))
            result += (snapshot.readings[module] ?? []).filter { !known.contains($0.id) }.map {
                MenuMetric(id: $0.id, module: module, title: $0.title, unit: $0.unit)
            }
        }
        return result
    }

    public static func migrate(modules: [ModuleID], presentation: ModePresentation) -> [MenuMetricSelection] {
        let catalog = metrics(in: MonitorSnapshot())
        return modules.flatMap { module -> [MenuMetricSelection] in
            let ids: [String]
            switch module {
            case .cpu: ids = ["cpu.total"]
            case .gpu: ids = ["gpu.total"]
            case .memory: ids = [presentation.memoryAsBytes ? "memory.used" : "memory.percent"]
            case .disk: ids = presentation.diskAsCapacity ? ["disk.available"] : ["disk.read", "disk.write"]
            case .network: ids = ["network.in", "network.out"]
            case .sensors: ids = [presentation.sensorID]
            case .power: ids = [presentation.powerID]
            }
            return ids.map { id in
                let metric = catalog.first { $0.id == id } ?? MenuMetric(id: id, module: module, title: id, unit: module == .power ? "W" : id.hasPrefix("fan.") ? "RPM" : "°C")
                let style: MetricPresentation
                switch presentation.styles[module.rawValue] {
                case .graph: style = .history
                case .value: style = .instant
                case nil: style = metric.defaultPresentation
                }
                return MenuMetricSelection(metric: metric, presentation: style)
            }
        }
    }
}

/// Time-weighted four-second buckets. Samples may be held briefly until the next
/// sample, but explicit nil samples and long gaps never become zero load.
public enum DotMatrixSeries {
    public static func bins(points: [HistoryPoint], now: Double, fullScale: Double, maxHold: Double = 8) -> [Double?] {
        var result = [Double?](repeating: nil, count: 15)
        guard now.isFinite, fullScale.isFinite, fullScale > 0, maxHold.isFinite, maxHold > 0 else { return result }
        let start = now - 60
        var sums = [Double](repeating: 0, count: 15), durations = sums
        for (index, point) in points.enumerated() {
            guard point.time.isFinite, let value = point.value, value.isFinite else { continue }
            let end = min(now, point.time + maxHold, index + 1 < points.count ? points[index + 1].time : now)
            guard end > point.time else { continue }
            for bin in 0..<15 {
                let a = max(start + Double(bin) * 4, point.time)
                let b = min(start + Double(bin + 1) * 4, end)
                if b > a { sums[bin] += (b - a) * max(0, value); durations[bin] += b - a }
            }
        }
        for bin in 0..<15 where durations[bin] > 0 { result[bin] = min(1, max(0, sums[bin] / durations[bin] / fullScale)) }
        return result
    }
}
