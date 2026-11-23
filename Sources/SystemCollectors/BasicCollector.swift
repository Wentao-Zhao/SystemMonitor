import Foundation
import Darwin
import IOKit
import SystemConfiguration
import MonitorCore

/// Used only on the store's serial sampling queue. No subprocesses or UI calls.
public final class BasicCollector {
    private var cpuTicks: [UInt32]?
    private var cpuKinds: [Int: String] = [:]
    private var networkRates: [String: CounterRate] = [:]
    private var networkSession = NetworkSession()
    private var diskRates: [String: CounterRate] = [:]
    private var cachedVolumes: [Volume] = []
    private var lastVolumeUpdate: Double = -.infinity
    private let host = mach_host_self()
    private let bootTime: Date? = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }()
    private struct Volume { var id: String; var name: String; var capacity: DiskCapacity; var bsd: String }

    public init() { loadCPUTopology() }
    deinit { mach_port_deallocate(mach_task_self_, host) }

    public func reset() {
        cpuTicks = nil; networkRates.removeAll(); diskRates.removeAll()
        lastVolumeUpdate = -.infinity
    }

    public func sample(interfaceID: String = "", diskID: String = "") -> MonitorSnapshot {
        var snapshot = MonitorSnapshot()
        snapshot.uptime = SampleClock.now
        snapshot.bootTime = bootTime
        snapshot.readings[.cpu] = cpu()
        snapshot.readings[.memory] = memory()
        network(into: &snapshot, preferred: interfaceID)
        disks(into: &snapshot, preferred: diskID)
        return snapshot
    }

    private func number<T: FixedWidthInteger>(_ name: String, _ initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private func loadCPUTopology() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let id = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                  let raw = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
            let kind = (raw as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? (raw as? String ?? "")
            if kind.hasPrefix("P") { cpuKinds[id.intValue] = "性能核" }
            if kind.hasPrefix("E") { cpuKinds[id.intValue] = "能效核" }
        }
    }

    private func cpu() -> [MetricReading] {
        var count: natural_t = 0
        var pointer: processor_info_array_t?
        var size: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &pointer, &size) == KERN_SUCCESS, let pointer else {
            cpuTicks = nil
            return [MetricReading("cpu.total", "整机使用率", nil, "%", note: "无法读取 CPU 统计")]
        }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: pointer)), vm_size_t(Int(size) * MemoryLayout<integer_t>.size)) }
        let ticks = (0..<Int(size)).map { UInt32(bitPattern: pointer[$0]) }
        defer { cpuTicks = ticks }
        guard let previous = cpuTicks, previous.count == ticks.count else {
            return [MetricReading("cpu.total", "整机使用率", nil, "%", note: "等待第二次采样")]
        }
        var coreValues: [(Int, Double)] = []
        for core in 0..<Int(count) {
            let offset = core * Int(CPU_STATE_MAX)
            let deltas = (0..<Int(CPU_STATE_MAX)).map { UInt64(ticks[offset + $0] &- previous[offset + $0]) }
            let total = deltas.reduce(0, +)
            guard total > 0 else { continue }
            coreValues.append((core, 100 * Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total)))
        }
        let total = coreValues.isEmpty ? nil : coreValues.map(\.1).reduce(0, +) / Double(coreValues.count)
        var result = [MetricReading("cpu.total", "整机使用率", total, "%")]
        for (kind, id) in [("性能核", "performance"), ("能效核", "efficiency")] {
            let values = coreValues.filter { cpuKinds[$0.0] == kind }.map(\.1)
            if !values.isEmpty { result.append(MetricReading("cpu.\(id)", "\(kind)平均负载", values.reduce(0, +) / Double(values.count), "%")) }
        }
        result += coreValues.map { MetricReading("cpu.core.\($0.0)", "\(cpuKinds[$0.0] ?? "核心") \($0.0 + 1)", $0.1, "%") }
        return result
    }

    private func memory() -> [MetricReading] {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS, let physical = number("hw.memsize", UInt64(0)) else {
            return [MetricReading("memory.percent", "内存使用率", nil, "%", note: "无法读取内存统计")]
        }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, physical > 0 else { return [] }
        let page = Double(pageSize)
        let allocatedPages = Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        let reclaimablePages = Double(stats.purgeable_count) + Double(stats.external_page_count)
        let used = min(Double(physical), max(0, allocatedPages - reclaimablePages) * page)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        let pressure = number("kern.memorystatus_vm_pressure_level", Int32(0)).map(Double.init)
        return [
            MetricReading("memory.percent", "内存使用率", used / Double(physical) * 100, "%"),
            MetricReading("memory.used", "已用内存", used, "bytes", note: "活动、非活动、联动与压缩页，扣除文件缓存及可清理页"),
            MetricReading("memory.available", "可用内存", Double(physical) - used, "bytes"),
            MetricReading("memory.total", "物理内存", Double(physical), "bytes"),
            MetricReading("memory.compressed", "压缩内存", Double(stats.compressor_page_count) * page, "bytes"),
            MetricReading("memory.cached", "可回收缓存", reclaimablePages * page, "bytes"),
            MetricReading("memory.swap", "交换空间", swapOK ? Double(swap.xsu_used) : nil, "bytes"),
            MetricReading("memory.pressure", "系统内存压力", pressure, "level", note: pressure == nil ? "系统未提供压力信号" : "系统压力等级")
        ]
    }

    private struct Interface { var name: String; var input: UInt64; var output: UInt64; var up: Bool }
    private func interfaces() -> [Interface] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &length, nil, 0) == 0 else { return [] }
        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            var result: [Interface] = []
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if header.ifm_type == RTM_IFINFO2, messageLength >= MemoryLayout<if_msghdr2>.size {
                    let item = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(item.ifm_index), &name) != nil {
                        let string = String(cString: name)
                        if !string.hasPrefix("lo"), !string.hasPrefix("awdl"), !string.hasPrefix("llw"), !string.hasPrefix("anpi") {
                            let link = SCDynamicStoreCopyValue(nil, "State:/Network/Interface/\(string)/Link" as CFString) as? [String: Any]
                            let active = link?["Active"] as? Bool ?? (item.ifm_flags & IFF_RUNNING != 0)
                            result.append(Interface(name: string, input: item.ifm_data.ifi_ibytes, output: item.ifm_data.ifi_obytes, up: item.ifm_flags & IFF_UP != 0 && active))
                        }
                    }
                }
                offset += messageLength
            }
            return result.sorted { $0.name < $1.name }
        }
    }

    private func network(into snapshot: inout MonitorSnapshot, preferred: String) {
        let list = interfaces()
        let primary = (["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"].compactMap {
            (SCDynamicStoreCopyValue(nil, $0 as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        }).first
        let selected = preferred.isEmpty ? (primary ?? networkSession.currentInterface ?? list.first(where: { $0.up && $0.name.hasPrefix("en") })?.name ?? list.first(where: \.up)?.name ?? "") : preferred
        snapshot.interfaces = list.map { DeviceChoice(id: $0.name, title: "\($0.name)\($0.up ? "" : " · 未连接")") }
        snapshot.selectedInterface = selected
        networkSession.select(interface: selected)
        guard let item = list.first(where: { $0.name == selected }), item.up else {
            networkRates.removeAll()
            snapshot.readings[.network] = [MetricReading("network.in", "下载", nil, "B/s"), MetricReading("network.out", "上传", nil, "B/s")]
            snapshot.notes[.network] = "所选网卡未连接或无法读取"
            return
        }
        let session = networkSession.sample(interface: selected, received: item.input, sent: item.output)
        if session.didReset { networkRates.removeAll() }
        let input = networkRates["in", default: CounterRate()].sample(total: item.input, time: snapshot.uptime)
        let output = networkRates["out", default: CounterRate()].sample(total: item.output, time: snapshot.uptime)
        snapshot.readings[.network] = [
            MetricReading("network.in", "下载", input, "B/s"), MetricReading("network.out", "上传", output, "B/s"),
            MetricReading("network.received", "本次会话接收", Double(session.received), "bytes"),
            MetricReading("network.sent", "本次会话发送", Double(session.sent), "bytes")
        ]
        snapshot.notes[.network] = "\(selected) · 单接口统计 · 会话流量重启后归零"
    }

    private func volumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) ?? [URL(fileURLWithPath: "/")]
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]), values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            // This estimate includes space macOS can reclaim. Query separately so an
            // unsupported estimate does not discard an otherwise readable volume.
            let important = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = DiskCapacity(totalBytes: Double(total),
                                              freeBytes: values.volumeAvailableCapacity.map(Double.init),
                                              availableForImportantUsage: important?.volumeAvailableCapacityForImportantUsage.map(Double.init)) else { return nil }
            var fs = statfs()
            guard statfs(url.path, &fs) == 0 else { return nil }
            let device = withUnsafePointer(to: &fs.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) } }
            guard device.hasPrefix("/dev/disk") else { return nil }
            return Volume(id: url.path, name: values.volumeName ?? url.lastPathComponent, capacity: capacity, bsd: String(device.dropFirst(5)))
        }.sorted { $0.id == "/" || ($1.id != "/" && $0.name < $1.name) }
    }

    private func disks(into snapshot: inout MonitorSnapshot, preferred: String) {
        if snapshot.uptime - lastVolumeUpdate >= 30 || !cachedVolumes.contains(where: { $0.id == preferred }) && !preferred.isEmpty {
            cachedVolumes = volumes(); lastVolumeUpdate = snapshot.uptime
        }
        snapshot.disks = cachedVolumes.map { DeviceChoice(id: $0.id, title: $0.name) }
        let selected = preferred.isEmpty ? (cachedVolumes.first?.id ?? "") : preferred
        snapshot.selectedDisk = selected
        guard let volume = cachedVolumes.first(where: { $0.id == selected }), FileManager.default.fileExists(atPath: volume.id) else {
            diskRates.removeAll()
            snapshot.readings[.disk] = [MetricReading("disk.available", "可用空间", nil, "bytes")]
            snapshot.notes[.disk] = "所选本地卷不可用"
            return
        }
        var read: Double?, write: Double?
        let device = diskStatistics(bsd: volume.bsd)
        if let device {
            read = diskRates["\(selected).\(device.id).read", default: CounterRate()].sample(total: device.read, time: snapshot.uptime)
            write = diskRates["\(selected).\(device.id).write", default: CounterRate()].sample(total: device.write, time: snapshot.uptime)
        }
        let capacity = volume.capacity
        let availabilityNote: String
        if capacity.freeBytes == nil { availabilityNote = "系统可用空间估计；当前空闲空间未知" }
        else if capacity.includesReclaimableSpace { availabilityNote = "包含 macOS 预计可回收的空间" }
        else { availabilityNote = "当前空闲空间；未获得更高的系统可用空间估计" }
        snapshot.readings[.disk] = [
            MetricReading("disk.available", "可用空间", capacity.availableBytes, "bytes", note: availabilityNote),
            MetricReading("disk.total", "卷容量", capacity.totalBytes, "bytes"),
            MetricReading("disk.used", "已用空间", capacity.usedBytes, "bytes", note: "总容量减可用空间"),
            MetricReading("disk.percent", "空间占用", capacity.usedPercent, "%"),
            MetricReading("disk.free", "当前空闲空间", capacity.freeBytes, "bytes", note: "不含系统预计可回收的空间"),
            MetricReading("disk.read", "设备读取", read, "B/s", note: "对应物理设备 I/O"),
            MetricReading("disk.write", "设备写入", write, "B/s", note: "对应物理设备 I/O")
        ]
        snapshot.notes[.disk] = "\(volume.name) · \(volume.bsd)\(device == nil ? " · 设备 I/O 不可用" : " · I/O 为物理设备统计")"
    }

    private func diskStatistics(bsd: String) -> (id: UInt64, read: UInt64, write: UInt64)? {
        // Snapshot BSD nodes may not exist in IOKit; retry their enclosing APFS volume.
        var name = bsd
        var media = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name))
        if media == 0, name.filter({ $0 == "s" }).count >= 2, let last = name.lastIndex(of: "s") {
            name = String(name[..<last])
            media = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name))
        }
        guard media != 0 else { return nil }
        var current = media
        var visited = 0
        while current != 0 {
            if let stats = IORegistryEntryCreateCFProperty(current, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let read = stats["Bytes (Read)"] as? NSNumber, let write = stats["Bytes (Write)"] as? NSNumber {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(current, &id)
                IOObjectRelease(current)
                return (id, read.uint64Value, write.uint64Value)
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            visited += 1
            guard status == KERN_SUCCESS, visited < 64 else { if parent != 0 { IOObjectRelease(parent) }; return nil }
            current = parent
        }
        return nil
    }
}
