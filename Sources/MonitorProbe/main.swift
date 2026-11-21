import Foundation
import Darwin
import MonitorCore
import SystemCollectors

let count = max(2, Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3)
let basic = BasicCollector()
let hardware = HardwareCollector()
for index in 0..<count {
    let start = ProcessInfo.processInfo.systemUptime
    let snapshot = basic.sample()
    let sample = hardware.sample()
    let report: [String: Any] = [
        "sample": index + 1,
        "time": ISO8601DateFormatter().string(from: snapshot.date),
        "basic": snapshot.readings.reduce(into: [String: Any]()) { out, module in
            out[module.key.rawValue] = module.value.map { ["id": $0.id, "value": $0.value.map { $0 as Any } ?? NSNull(), "unit": $0.unit] as [String: Any] }
        },
        "interface": snapshot.selectedInterface,
        "disk": snapshot.selectedDisk,
        "notes": snapshot.notes.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value },
        "gpu": sample.gpu.map { $0 as Any } ?? NSNull(),
        "gpuName": sample.gpuName,
        "sensors": sample.sensors.map { ["id": $0.id, "value": $0.value, "unit": $0.unit] as [String: Any] },
        "powers": sample.powers.map { ["id": $0.id, "value": $0.value, "unit": $0.unit] as [String: Any] },
        "errors": sample.errors,
        "samplingMilliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
    if index < count - 1 { Thread.sleep(forTimeInterval: 2) }
}
