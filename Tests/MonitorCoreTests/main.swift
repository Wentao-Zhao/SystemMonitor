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

print("\(checks) checks, \(failures) failures")
if failures > 0 { exit(1) }
