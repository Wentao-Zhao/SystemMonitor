import AppKit
import Combine
import OSLog
import MonitorCore
import SystemCollectors

@MainActor
final class MonitoringStore: ObservableObject {
    @Published private(set) var snapshot = MonitorSnapshot()
    @Published private(set) var preferences: MonitorPreferences
    @Published private(set) var history = MetricHistory()
    @Published private(set) var publicIPLocation: PublicIPLocation?
    @Published private(set) var paused = false
    @Published private(set) var sleeping = false
    @Published private(set) var lastUpdated: Date?
    private let queue = DispatchQueue(label: "local.SystemMonitor.collectors", qos: .utility)
    private var timer: Timer?
    private var generation = 0
    private var inFlight = false
    private let defaults: UserDefaults
    private let resolvePublicIP: Bool
    private lazy var publicIPService = PublicIPLocationService { [weak self] in self?.publicIPLocation = $0 }
    private let collector = CollectorSession()
    private var readingCache = ReadingCache()
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, resolvePublicIP: Bool = true) {
        self.defaults = defaults
        self.resolvePublicIP = resolvePublicIP
        var saved = defaults.data(forKey: "monitor.preferences.v1").flatMap { try? JSONDecoder().decode(MonitorPreferences.self, from: $0) } ?? MonitorPreferences()
        saved.normalize(); preferences = saved
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        })
        restartTimer()
    }

    func updatePreferences(_ update: (inout MonitorPreferences) -> Void) {
        let old = preferences
        var value = preferences
        update(&value); value.normalize()
        guard old != value else { return }
        preferences = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "monitor.preferences.v1") }
        let selectionChanged = old.interfaceID != value.interfaceID || old.diskID != value.diskID
        if selectionChanged {
            if old.interfaceID != value.interfaceID { history.removeSeries(prefix: "network."); readingCache.remove(prefix: "network.") }
            if old.diskID != value.diskID { history.removeSeries(prefix: "disk."); readingCache.remove(prefix: "disk.") }
            generation += 1
            queue.async { [collector] in collector.reset() }
        }
        if resolvePublicIP, old.publicIPProvider != value.publicIPProvider {
            publicIPService.refresh(interface: snapshot.selectedInterface, provider: value.publicIPProvider, force: true)
            publicIPService.suspend(value.publicIPProvider == nil || paused || sleeping)
            if value.publicIPProvider == nil { publicIPLocation = nil }
        }
        if old.refreshInterval != value.refreshInterval { restartTimer() }
        else if selectionChanged { sample() }
    }

    var publicIPLookupEnabled: Bool { resolvePublicIP && preferences.publicIPProvider != nil }

    func refreshPublicIP() {
        if publicIPLookupEnabled { publicIPService.refresh(interface: snapshot.selectedInterface, provider: preferences.publicIPProvider, force: true) }
    }

    func togglePaused() {
        paused.toggle(); generation += 1
        if publicIPLookupEnabled { publicIPService.suspend(paused || sleeping) }
        history.append(time: SampleClock.now, values: [:])
        queue.async { [collector] in collector.reset() }
        restartTimer()
    }

    private func willSleep() {
        sleeping = true; generation += 1
        if publicIPLookupEnabled { publicIPService.suspend(true) }
        history.append(time: SampleClock.now, values: [:])
        timer?.invalidate(); timer = nil
    }

    private func didWake() {
        sleeping = false; generation += 1
        if publicIPLookupEnabled { publicIPService.suspend(paused) }
        history.append(time: SampleClock.now, values: [:])
        queue.async { [collector] in collector.reset() }
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        guard !paused, !sleeping else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: preferences.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func sample() {
        guard !paused, !sleeping, !inFlight else { return }
        inFlight = true
        let currentGeneration = generation
        let options = preferences
        queue.async { [collector, weak self] in
            let result = autoreleasepool { collector.sample(preferences: options) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                guard currentGeneration == self.generation, !self.paused, !self.sleeping else { return }
                if self.snapshot.selectedInterface != result.selectedInterface { self.history.removeSeries(prefix: "network."); self.readingCache.remove(prefix: "network.") }
                if self.snapshot.selectedDisk != result.selectedDisk { self.history.removeSeries(prefix: "disk."); self.readingCache.remove(prefix: "disk.") }
                self.snapshot = self.readingCache.annotate(result)
                if self.publicIPLookupEnabled { self.publicIPService.refresh(interface: result.selectedInterface, provider: self.preferences.publicIPProvider) }
                self.history.append(time: result.uptime, values: result.values)
                self.lastUpdated = result.date
            }
        }
    }
}

/// All mutable collector state stays on the sampling queue.
private final class CollectorSession: @unchecked Sendable {
    private var basic: BasicCollector?
    private let hardware = HardwareCollector()
    private let hardwareQueue = DispatchQueue(label: "local.SystemMonitor.hardware", qos: .utility)
    private let hardwareLock = NSLock()
    private var hardwareSample = HardwareSample()
    private var lastHardwareTime: Double = -.infinity
    private var lastCompletedTime: Double = -.infinity
    private var hardwareInFlight = false
    private var hardwareGeneration = 0
    private var lastErrors: [String] = []
    private let logger = Logger(subsystem: "local.wentao.SystemMonitor", category: "Hardware")

    func reset() {
        basic?.reset()
        hardwareLock.lock()
        hardwareGeneration += 1; lastHardwareTime = -.infinity; lastCompletedTime = -.infinity
        hardwareSample = HardwareSample()
        hardwareLock.unlock()
        hardwareQueue.async { [hardware] in hardware.reset() }
    }

    func sample(preferences: MonitorPreferences) -> MonitorSnapshot {
        if basic == nil { basic = BasicCollector() }
        let hardwareSample = currentHardware()
        var snapshot = basic!.sample(interfaceID: preferences.interfaceID, diskID: preferences.diskID)
        snapshot.readings[.gpu] = [MetricReading("gpu.total", hardwareSample.gpuName, hardwareSample.gpu, "%", note: "驱动统计的设备忙碌率")]
        snapshot.readings[.sensors] = hardwareSample.sensors.map { MetricReading($0.id, $0.title, $0.value, $0.unit) }
        snapshot.readings[.power] = hardwareSample.powers.map { MetricReading($0.id, $0.id == "cpu.power" ? "CPU 功耗" : $0.id == "gpu.power" ? "GPU 功耗" : "整机功耗", $0.value, $0.unit) }
        for (id, title) in [("cpu.temperature", "CPU 热区温度"), ("gpu.temperature", "GPU 热区温度")] {
            if snapshot.readings[.sensors]?.contains(where: { $0.id == id }) != true {
                snapshot.readings[.sensors, default: []].insert(MetricReading(id, title, nil, "°C", note: "当前不可用"), at: 0)
            }
        }
        for (id, title) in [("cpu.power", "CPU 功耗"), ("gpu.power", "GPU 功耗")] {
            if snapshot.readings[.power]?.contains(where: { $0.id == id }) != true {
                snapshot.readings[.power, default: []].append(MetricReading(id, title, nil, "W", note: "当前不可用"))
            }
        }
        snapshot.notes[.gpu] = statusNote(hardwareSample.errors, module: .gpu) ?? "使用率表示 GPU 忙碌时间的比例"
        snapshot.notes[.sensors] = statusNote(hardwareSample.errors, module: .sensors) ?? "温度对应芯片热区，非逐核心温度"
        snapshot.notes[.power] = statusNote(hardwareSample.errors, module: .power) ?? "分项功耗不等于整机功耗"
        return snapshot
    }
    private func statusNote(_ errors: [String], module: ModuleID) -> String? {
        let relevant = errors.filter { error in
            if error.contains("Hardware") { return true }
            switch module {
            case .gpu: return error.contains("GPU registry") || error.contains("GPU Device")
            case .sensors: return error.contains("SMC") || error.contains("fan")
            case .power: return error.contains("IOReport") || error.contains("power")
            default: return false
            }
        }.joined(separator: " ")
        guard !relevant.isEmpty else { return nil }
        if relevant.contains("denied") || relevant.contains("0xe00002e2") { return "读取权限不足 · 当前进程无法访问该硬件指标" }
        if relevant.contains("baseline") || relevant.contains("pending") { return "等待采样 · 正在建立硬件数据基线" }
        if relevant.contains("did not advance") { return "CPU 功耗不可用 · 系统能量计数未更新，其余功耗按实际数据展示" }
        if relevant.contains("ABI unavailable") || relevant.contains("library unavailable") || relevant.contains("not published") || relevant.contains("unsupported") {
            return "指标不支持 · 当前系统或驱动未提供相应数据"
        }
        return "暂时读取失败 · 保留上次有效数据和时间，暂停后恢复可重新检测"
    }
    private func currentHardware() -> HardwareSample {
        let now = SampleClock.now
        hardwareLock.lock()
        if !hardwareInFlight, now - lastHardwareTime >= 1.9 {
            hardwareInFlight = true; lastHardwareTime = now
            let token = hardwareGeneration
            hardwareQueue.async { [self] in
                let result = autoreleasepool { hardware.sample() }
                hardwareLock.lock()
                if token == hardwareGeneration {
                    hardwareSample = result; lastCompletedTime = SampleClock.now
                    if result.errors != lastErrors {
                        lastErrors = result.errors
                        if !result.errors.isEmpty { logger.error("\(result.errors.joined(separator: "; "), privacy: .public)") }
                    }
                }
                hardwareInFlight = false
                hardwareLock.unlock()
            }
        }
        let result = now - lastCompletedTime <= 8 ? hardwareSample : HardwareSample(errors: [now - lastHardwareTime < 8 && lastCompletedTime == -.infinity ? "Hardware sample pending." : "Hardware sample timed out."])
        hardwareLock.unlock()
        return result
    }

}
