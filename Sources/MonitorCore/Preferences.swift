import Foundation

public enum DisplayMode: String, Codable, CaseIterable, Sendable { case combined, independent }
public enum SummaryStyle: String, Codable, CaseIterable, Sendable { case value, graph }

public struct ModePresentation: Codable, Equatable, Sendable {
    public var styles: [String: SummaryStyle] = [:]
    public var sensorID = "cpu.temperature"
    public var powerID = "system.power"
    public var memoryAsBytes = false
    public var diskAsCapacity = false
    public init() {}
}

public struct MonitorPreferences: Codable, Equatable, Sendable {
    public var mode: DisplayMode = .combined
    public var combinedModules: [ModuleID] = [.cpu, .memory, .network]
    public var independentModules: [ModuleID] = [.cpu, .memory, .network]
    // nil means an older module-level preference that has not yet been migrated.
    public var combinedMetrics: [MenuMetricSelection]?
    public var independentMetrics: [MenuMetricSelection]?
    public var menuMetrics: [MenuMetricSelection] {
        get {
            if mode == .combined { return combinedMetrics ?? MenuMetricCatalog.migrate(modules: combinedModules, presentation: combinedPresentation) }
            return independentMetrics ?? MenuMetricCatalog.migrate(modules: independentModules, presentation: independentPresentation)
        }
        set { if mode == .combined { combinedMetrics = newValue } else { independentMetrics = newValue } }
    }
    public var refreshInterval: Double = 2
    public var combinedPresentation = ModePresentation()
    public var independentPresentation = ModePresentation()
    public var interfaceID: String = ""
    public var diskID: String = ""
    // Optional for compatibility with saved preferences predating online country lookup.
    public var publicIPProvider: PublicIPProvider?
    private var presentation: ModePresentation {
        get { mode == .combined ? combinedPresentation : independentPresentation }
        set { if mode == .combined { combinedPresentation = newValue } else { independentPresentation = newValue } }
    }
    public var styles: [String: SummaryStyle] { get { presentation.styles } set { presentation.styles = newValue } }
    public var sensorID: String { get { presentation.sensorID } set { presentation.sensorID = newValue } }
    public var powerID: String { get { presentation.powerID } set { presentation.powerID = newValue } }
    public var memoryAsBytes: Bool { get { presentation.memoryAsBytes } set { presentation.memoryAsBytes = newValue } }
    public var diskAsCapacity: Bool { get { presentation.diskAsCapacity } set { presentation.diskAsCapacity = newValue } }
    public init() {}
    public var visibleModules: [ModuleID] { mode == .combined ? combinedModules : independentModules }
    public mutating func normalize() {
        func unique(_ modules: [ModuleID]) -> [ModuleID] {
            var result: [ModuleID] = []
            for module in modules where !result.contains(module) { result.append(module) }
            return result.isEmpty ? [.cpu] : result
        }
        func uniqueMetrics(_ metrics: [MenuMetricSelection]) -> [MenuMetricSelection] {
            var seen = Set<String>()
            return metrics.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.map { selection in
                var value = selection
                if let scale = value.scale, !scale.isFinite || scale <= 0 { value.scale = nil }
                return value
            }
        }
        combinedMetrics = uniqueMetrics(combinedMetrics ?? MenuMetricCatalog.migrate(modules: combinedModules, presentation: combinedPresentation))
        independentMetrics = uniqueMetrics(independentMetrics ?? MenuMetricCatalog.migrate(modules: independentModules, presentation: independentPresentation))
        combinedModules = unique(combinedModules)
        independentModules = unique(independentModules)
        if ![1.0, 2.0, 5.0].contains(refreshInterval) { refreshInterval = 2 }
    }
}
