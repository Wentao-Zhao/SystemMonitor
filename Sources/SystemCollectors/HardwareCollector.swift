import Foundation
import HardwareBridge
import MonitorCore

/// Serializes the read-only native bridge. No subprocesses, fan writes or helpers.
public final class HardwareCollector {
    private let lock = NSLock()
    private var context: OpaquePointer?

    public init() {}

    deinit {
        if let context { HBDestroy(context) }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        // Wake or resume can replace registry services, sensor keys and access
        // permissions. Discard all cached discovery, not only energy deltas.
        if let context { HBDestroy(context) }
        context = nil
    }

    public func sample() -> HardwareSample {
        lock.lock()
        defer { lock.unlock() }
        // Discovery happens once, on the caller's sampling queue, not the UI thread.
        if context == nil { context = HBCreate() }
        var native = HBSnapshot()
        HBSample(context, &native)
        var sensors: [HardwareSensor] = []
        var powers: [HardwareSensor] = []
        func append(_ value: Double, id: String, title: String, unit: String, to values: inout [HardwareSensor]) {
            guard value.isFinite else { return }
            values.append(HardwareSensor(id: id, title: title, value: value, unit: unit))
        }
        append(native.cpuTemperature, id: "cpu.temperature", title: "CPU 热区最高温", unit: "°C", to: &sensors)
        append(native.gpuTemperature, id: "gpu.temperature", title: "GPU 热区最高温", unit: "°C", to: &sensors)
        withUnsafeBytes(of: native.fanRPM) { bytes in
            let fans = bytes.bindMemory(to: Double.self)
            for index in 0..<min(max(Int(native.fanCount), 0), fans.count) {
                append(fans[index], id: "fan.\(index)", title: "风扇 \(index + 1)", unit: "RPM", to: &sensors)
            }
        }
        withUnsafeBytes(of: native.thermalZones) { bytes in
            let zones = bytes.bindMemory(to: HBThermalZone.self)
            for index in 0..<min(max(Int(native.thermalZoneCount), 0), zones.count) {
                let zone = zones[index]
                let key = withUnsafeBytes(of: zone.key) { keyBytes in
                    String(cString: keyBytes.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                guard key.count == 4, zone.category == 1 || zone.category == 2 else { continue }
                let family = zone.category == 1 ? "CPU" : "GPU"
                append(zone.value, id: "sensor.\(key)", title: "\(family) 热区 \(key)", unit: "°C", to: &sensors)
            }
        }
        append(native.cpuWatts, id: "cpu.power", title: "CPU 功耗（IOReport）", unit: "W", to: &powers)
        append(native.gpuWatts, id: "gpu.power", title: "GPU 功耗（IOReport）", unit: "W", to: &powers)
        append(native.systemWatts, id: "system.power", title: "整机功耗（SMC PSTR）", unit: "W", to: &powers)
        let gpuName = withUnsafeBytes(of: native.gpuName) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let errors = withUnsafeBytes(of: native.errors) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
                .split(separator: "\n").map(String.init)
        }
        return HardwareSample(gpu: native.gpuPercent.isFinite ? native.gpuPercent : nil,
                              gpuName: gpuName.isEmpty ? "GPU" : gpuName,
                              sensors: sensors, powers: powers, errors: errors)
    }
}
