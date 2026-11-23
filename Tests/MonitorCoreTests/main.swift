import Foundation
#if canImport(MonitorCore)
import MonitorCore
#endif

var failures = 0
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(name)") }
}

var rate = CounterRate()
expect(rate.sample(total: 100, time: 1) == nil, "first sample establishes baseline")
expect(rate.sample(total: 160, time: 3) == 30, "counter delta uses elapsed monotonic time")
expect(rate.sample(total: 20, time: 5) == nil, "counter rollback discards rate")
expect(rate.sample(total: 60, time: 7) == 20, "rollback establishes fresh baseline")
rate.reset()
expect(rate.sample(total: 600, time: 100) == nil, "wake reset prevents sleep spike")
expect(rate.sample(total: 620, time: 100) == nil, "zero elapsed time produces no rate")
expect(rate.sample(total: 640, time: 102) == 10, "invalid timestamp establishes baseline")

var history = MetricHistory(retention: 10)
history.append(time: 1, values: ["cpu": 10])
history.append(time: 4, values: [:])
history.append(time: 8, values: ["cpu": 40])
expect(history.points(for: "cpu", since: 0).count == 3, "missing sample remains a chart gap")
expect(history.points(for: "cpu", since: 0).dropFirst().first?.value == nil, "gap does not invent zero")
history.append(time: 12, values: ["cpu": 20])
expect(history.points(for: "cpu", since: 0).first?.time == 4, "history retention is time bounded")
expect(history.points(for: "cpu", since: 9).count == 1, "selected time window clips chart")
history.removeSeries(prefix: "cpu")
expect(history.points(for: "cpu", since: 0).isEmpty, "interface switch clears selected series")

var preferences = MonitorPreferences()
expect(preferences.mode == .combined, "first launch defaults to combined")
preferences.combinedModules = []
preferences.independentModules = []
preferences.refreshInterval = 0
preferences.normalize()
expect(!preferences.visibleModules.isEmpty, "combined mode always keeps an entry point")
expect(preferences.refreshInterval == 2, "invalid refresh uses default")
preferences.mode = .independent
expect(!preferences.visibleModules.isEmpty, "independent mode always keeps an entry point")
preferences.independentModules = [.cpu, .cpu, .network]
preferences.normalize()
expect(preferences.visibleModules == [.cpu, .network], "duplicate modules cannot create duplicate status items")
let encoded = try JSONEncoder().encode(preferences)
let restored = try JSONDecoder().decode(MonitorPreferences.self, from: encoded)
expect(restored.visibleModules == preferences.visibleModules, "preferences survive restart")

var modes = MonitorPreferences()
modes.styles["cpu"] = .graph
modes.memoryAsBytes = true
modes.sensorID = "fan.0"
modes.mode = .independent
expect(modes.styles["cpu"] != .graph && !modes.memoryAsBytes && modes.sensorID != "fan.0", "presentation choices are isolated between modes")
modes.mode = .combined
expect(modes.styles["cpu"] == .graph && modes.memoryAsBytes && modes.sensorID == "fan.0", "switching back restores combined presentation")

let segments = chartSegments([HistoryPoint(time: 1, value: 2), HistoryPoint(time: 2, value: 3), HistoryPoint(time: 30, value: 4), HistoryPoint(time: 31, value: nil), HistoryPoint(time: 32, value: 5)])
expect(segments.map(\.count) == [2, 1, 1], "menu and detail charts break at missing samples and long elapsed gaps")
var cache = ReadingCache()
var good = MonitorSnapshot()
good.date = Date(timeIntervalSince1970: 100)
good.readings[.network] = [MetricReading("network.in", "下载", 42, "B/s")]
_ = cache.annotate(good)
var bad = good
bad.date = Date(timeIntervalSince1970: 102)
bad.readings[.network] = [MetricReading("network.in", "下载", nil, "B/s")]
let stale = cache.annotate(bad).reading("network.in")
expect(stale?.value == nil && stale?.previousValue == 42 && stale?.previousDate == good.date, "failure preserves timestamped last known reading without treating it as live")
cache.remove(prefix: "network.")
expect(cache.annotate(bad).reading("network.in")?.previousValue == nil, "interface changes remove previous device values")
_ = cache.annotate(good)
bad.readings[.network] = []
let missing = cache.annotate(bad).reading("network.in")
expect(missing?.value == nil && missing?.previousValue == 42, "omitted metrics remain visible as unavailable with their last value")
var traffic = NetworkSession()
expect(traffic.sample(interface: "en0", received: 100, sent: 100).didReset, "new interface establishes session baseline")
expect(traffic.sample(interface: "en0", received: 500, sent: 300).received == 400, "session counts from startup")
let rollback = traffic.sample(interface: "en0", received: 200, sent: 200)
expect(rollback.didReset && rollback.received == 0 && rollback.sent == 0, "counter rollback above initial baseline still resets session")
expect(traffic.sample(interface: "en0", received: 250, sent: 220).received == 50, "session resumes from rollback baseline")
expect(traffic.sample(interface: "utun0", received: 700, sent: 800).didReset, "interface switch resets session")
traffic.select(interface: "en5")
traffic.select(interface: "utun0")
expect(traffic.sample(interface: "utun0", received: 900, sent: 1000).received == 0, "switch through an offline interface discards old session baseline")


// Menu selections operate on concrete readings, independently of module visibility.
let catalog = MenuMetricCatalog.metrics(in: MonitorSnapshot())
let cpuMetric = catalog.first { $0.id == "cpu.total" }!
let memoryMetric = catalog.first { $0.id == "memory.percent" }!
var dots = MonitorPreferences()
expect(dots.menuMetrics.map(\.id) == ["cpu.total", "memory.percent", "network.in", "network.out"], "default menu keeps CPU, memory and individually selectable network directions")
expect(dots.menuMetrics[0].presentation == .history && dots.menuMetrics[1].presentation == .instant, "CPU defaults to history and memory defaults to instantaneous dots")
dots.menuMetrics.removeAll { $0.id == "network.out" }
expect(dots.menuMetrics.contains { $0.id == "network.in" } && !dots.menuMetrics.contains { $0.id == "network.out" }, "upload can be removed without removing download")
dots.menuMetrics = []
dots.normalize()
expect(dots.menuMetrics.isEmpty, "removing every metric does not silently add CPU back")
dots.mode = .independent
expect(dots.menuMetrics.count == 4, "independent mode has its own metric selections")
dots.menuMetrics = [MenuMetricSelection(metric: memoryMetric)]
dots.mode = .combined
expect(dots.menuMetrics.isEmpty, "switching modes restores an explicitly empty list")
let dotData = try JSONEncoder().encode(dots)
var dotRestored = try JSONDecoder().decode(MonitorPreferences.self, from: dotData)
expect(dotRestored.menuMetrics.isEmpty, "empty metric list survives restart")
dotRestored.mode = .independent
expect(dotRestored.menuMetrics.map(\.id) == ["memory.percent"], "per-mode metric list survives restart")
var legacyJSON = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacyJSON.removeValue(forKey: "combinedMetrics")
legacyJSON.removeValue(forKey: "independentMetrics")
var legacy = try JSONDecoder().decode(MonitorPreferences.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
legacy.normalize()
expect(legacy.menuMetrics.map(\.id) == ["cpu.total", "network.in", "network.out"], "old module settings migrate to individual readings in order")
legacy.menuMetrics = [MenuMetricSelection(metric: cpuMetric), MenuMetricSelection(metric: cpuMetric)]
legacy.normalize()
expect(legacy.menuMetrics.count == 1, "duplicate metric selections cannot create duplicate items")
var explicitValue = ModePresentation()
explicitValue.styles["cpu"] = .value
expect(MenuMetricCatalog.migrate(modules: [.cpu], presentation: explicitValue).first?.presentation == .instant, "an explicit old numeric style migrates to an instantaneous column")
let bins = DotMatrixSeries.bins(points: [HistoryPoint(time: 0, value: 20), HistoryPoint(time: 4, value: 80), HistoryPoint(time: 8, value: nil), HistoryPoint(time: 12, value: 40)], now: 60, fullScale: 100, maxHold: 8)
expect(bins.count == 15 && bins[0] == 0.2 && bins[1] == 0.8, "history uses fixed four-second slots and fixed full scale")
expect(bins[2] == nil && bins[3] == 0.4 && bins[5] == nil, "missing samples and long gaps remain unlit")
let weighted = DotMatrixSeries.bins(points: [HistoryPoint(time: 56, value: 0), HistoryPoint(time: 57, value: 100)], now: 60, fullScale: 100, maxHold: 8)
expect(weighted.last! == 0.75, "historical bins average by elapsed time rather than sample count")
let clipped = DotMatrixSeries.bins(points: [HistoryPoint(time: 56, value: 200)], now: 60, fullScale: 100, maxHold: 8)
expect(clipped.last! == 1, "history clamps to reference rather than rescaling every frame")
expect(DotMatrixSeries.bins(points: [], now: 60, fullScale: 0).allSatisfy { $0 == nil }, "invalid reference yields no invented data")
var dotSnapshot = MonitorSnapshot()
dotSnapshot.readings[.memory] = [MetricReading("memory.percent", "内存", 92, "%"), MetricReading("memory.pressure", "压力", 1, "level")]
expect(memoryMetric.signal(in: dotSnapshot, fraction: 0.92) == .normal, "high memory occupancy alone does not imply memory pressure")
dotSnapshot.readings[.memory]?[1].value = 4
expect(memoryMetric.signal(in: dotSnapshot, fraction: 0.2) == .critical, "memory color follows actual system pressure")
dotSnapshot.readings[.memory]?[1].value = nil
expect(memoryMetric.signal(in: dotSnapshot, fraction: 0.2) == .unknown, "missing memory pressure is not painted healthy green")
expect(cpuMetric.signal(in: dotSnapshot, fraction: 0.83, previous: .critical) == .critical, "state hysteresis prevents rapid threshold flicker")
expect(cpuMetric.signal(in: dotSnapshot, fraction: nil) == .unknown, "unavailable metric is not displayed as zero load")
let availableMetric = catalog.first { $0.id == "disk.available" }!
expect(availableMetric.signal(in: dotSnapshot, fraction: 0.05) == .critical, "remaining disk space reverses occupancy state logic")
var diskState = MonitorSnapshot()
diskState.readings[.disk] = [MetricReading("disk.percent", "磁盘占用", 20, "%")]
let capacityMetric = catalog.first { $0.id == "disk.total" }!
expect(capacityMetric.signal(in: diskState, fraction: 1) == .normal, "a fixed disk capacity is colored by actual occupancy rather than always alarming at full scale")
var live = MonitorSnapshot()
live.readings[.memory] = [MetricReading("memory.used", "已用", 16, "bytes"), MetricReading("memory.total", "总量", 32, "bytes")]
let usedMetric = catalog.first { $0.id == "memory.used" }!
expect(usedMetric.fraction(in: live) == 0.5, "byte quantities use their actual capacity as the reference")
live.readings[.sensors] = [MetricReading("fan.3", "右侧风扇", 2300, "RPM")]
expect(MenuMetricCatalog.metrics(in: live).contains { $0.id == "fan.3" }, "each dynamically discovered sensor can be added separately")

expect(MetricReading("disk.total", "卷容量", 994_662_584_320, "bytes").formatted.contains("994.66"), "disk capacity uses decimal GB like macOS Storage")
expect(MetricReading("disk.available", "可用", 339_540_000_000, "bytes").formatted.contains("339.54"), "disk available capacity preserves the system decimal value")
expect(MetricReading("memory.total", "内存", 34_359_738_368, "bytes").formatted.contains("32"), "memory formatting retains the existing binary capacity convention")

let apfsCapacity = DiskCapacity(totalBytes: 994_662_584_320, freeBytes: 265_040_000_000, availableForImportantUsage: 339_540_000_000)!
expect(apfsCapacity.availableBytes == 339_540_000_000, "APFS available capacity includes system-reclaimable space")
expect(apfsCapacity.usedBytes == 655_122_584_320, "used capacity is consistent with total minus system available capacity")
expect(abs(apfsCapacity.usedPercent - 65.86378919644905) < 0.001, "disk occupancy uses the same available capacity as the displayed number")
expect(apfsCapacity.freeBytes == 265_040_000_000 && apfsCapacity.includesReclaimableSpace, "physical free space stays distinct from available space")
let unsupportedCapacity = DiskCapacity(totalBytes: 1000, freeBytes: 250, availableForImportantUsage: nil)!
expect(unsupportedCapacity.availableBytes == 250 && !unsupportedCapacity.includesReclaimableSpace, "unsupported capacity estimates fall back to physical free space")
expect(DiskCapacity(totalBytes: 1000, freeBytes: 250, availableForImportantUsage: 0)?.availableBytes == 250, "a blocked estimate reporting zero cannot hide known free space")
expect(DiskCapacity(totalBytes: 1000, freeBytes: 250, availableForImportantUsage: 200)?.availableBytes == 250, "an estimate below known free space does not under-report capacity")
expect(DiskCapacity(totalBytes: 1000, freeBytes: 250, availableForImportantUsage: 2000)?.availableBytes == 1000, "capacity estimate is bounded by volume size")
expect(DiskCapacity(totalBytes: 1000, freeBytes: nil, availableForImportantUsage: 400)?.freeBytes == nil, "missing physical free capacity is not invented")
expect(DiskCapacity(totalBytes: 0, freeBytes: 0, availableForImportantUsage: 0) == nil, "invalid total capacity cannot produce a disk percent")
expect(DiskCapacity(totalBytes: 1000, freeBytes: nil, availableForImportantUsage: nil) == nil, "missing capacity sources are unavailable rather than zero")
expect(DiskCapacity(totalBytes: 1000, freeBytes: 250, availableForImportantUsage: .nan)?.availableBytes == 250, "non-finite system estimates cannot pollute history")


var dayHistory = MetricHistory()
for time in stride(from: 0.0, through: 86_400.0, by: 30) { dayHistory.append(time: time, values: ["cpu": 30]) }
expect(dayHistory.points(for: "cpu", since: 0).first?.time == 0, "default history retains a complete 24 hours")
expect(dayHistory.points(for: "cpu", since: 64_800).first?.time == 64_800, "six-hour view clips against the real time window")


var denseDay = MetricHistory()
for time in 0...86_400 { denseDay.append(time: Double(time), values: ["cpu": time == 4005 ? 99 : 10, "memory": 60]) }
let archivedDay = denseDay.points(for: "cpu", since: 0)
expect(archivedDay.count < 9000 && archivedDay.count > 8000, "24-hour retention compresses older samples to a bounded ten-second history")
expect(denseDay.points(for: "cpu", since: 86_340).count == 61, "the menu bar retains full sampling resolution for its last minute")
expect(archivedDay.contains { $0.maximum == 99 }, "history aggregation preserves an old short load spike")
denseDay.removeSeries(prefix: "cpu")
expect(denseDay.points(for: "cpu", since: 0).isEmpty && !denseDay.points(for: "memory", since: 0).isEmpty, "switching a device removes only its own raw and aggregated history")
var gapHistory = MetricHistory()
for time in 0...1000 {
    gapHistory.append(time: Double(time), values: time >= 501 && time <= 505 ? ["memory": 60] : ["cpu": 20, "memory": 60])
}
expect(gapHistory.points(for: "cpu", since: 0).contains { $0.time >= 500 && $0.time <= 510 && $0.value == nil }, "aggregation retains per-metric missing intervals")
let manyPoints = (0..<6000).map { HistoryPoint(time: Double($0), value: $0 == 3025 ? 100 : 10) }
let plotted = plotSegments(manyPoints, targetPoints: 600).flatMap { $0 }
expect(plotted.count <= 600 && plotted.contains { $0.value == 100 }, "chart reduction bounds drawing work without dropping load spikes")
expect(plotSegments([HistoryPoint(time: 0, value: 10), HistoryPoint(time: 1, value: nil), HistoryPoint(time: 2, value: 20)], targetPoints: 2).count == 2, "chart reduction never connects a missing interval")
expect(HistoryRange.allCases.map(\.rawValue) == [3600, 21600, 86400], "all detail modules offer 1h, 6h and 24h")
expect(UptimeFormatter.string(seconds: 3 * 86400 + 4 * 3600 + 12 * 60) == "3天 4小时 12分", "boot uptime is formatted in days, hours and minutes")
expect(UptimeFormatter.string(seconds: 59) == "不足1分钟" && UptimeFormatter.string(seconds: nil) == "—", "uptime distinguishes a recent boot from missing data")
let location = PublicIPLocation(trace: "ip=203.0.113.42\ncolo=SJC\nloc=JP\n")
expect(location?.countryCode == "JP" && location?.flag == "🇯🇵", "country flag follows IP country rather than the serving data center")
expect(PublicIPLocation(trace: "ip=2001:db8::1\nloc=DE\n")?.flag == "🇩🇪", "public IPv6 results support country flags")
expect(PublicIPLocation(trace: "ip=203.0.113.42\nloc=XX\n")?.flag == "🌐", "unknown IP location displays a globe instead of a made-up flag")
expect(PublicIPLocation(trace: "<html>request blocked</html>") == nil && PublicIPLocation(trace: "ip=not-an-ip\nloc=US") == nil, "invalid or blocked geo responses do not become valid locations")

expect(MonitorPreferences().publicIPProvider == nil, "public IP queries stay disabled until a provider is explicitly selected")
expect(PublicIPLocation(ipipText: "当前 IP：203.0.113.2  来自于：中国 北京 北京 电信")?.flag == "🇨🇳", "domestic IPIP responses produce a China flag")
expect(PublicIPLocation(ipipText: "当前 IP：203.0.113.3  来自于：日本 东京")?.flag == "🇯🇵", "IPIP country parsing also supports foreign exits")
expect(PublicIPLocation(ipipText: "查询失败") == nil, "a domestic lookup failure does not produce an incorrect flag")

print("\(checks) checks, \(failures) failures")
if failures > 0 { exit(1) }
