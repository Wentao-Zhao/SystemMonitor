import SwiftUI
import MonitorCore

typealias ViewState<Value> = SwiftUI.State<Value>

extension ModuleID {
    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .disk: return "磁盘"
        case .network: return "网络"
        case .sensors: return "传感"
        case .power: return "功耗"
        }
    }
    func primaryID(_ options: MonitorPreferences) -> String {
        switch self {
        case .cpu: return "cpu.total"
        case .gpu: return "gpu.total"
        case .memory: return options.memoryAsBytes ? "memory.used" : "memory.percent"
        case .disk: return options.diskAsCapacity ? "disk.available" : "disk.read"
        case .network: return "network.in"
        case .sensors: return options.sensorID
        case .power: return options.powerID
        }
    }
}

struct MonitorPanel: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 610
    @ObservedObject var store: MonitoringStore
    let openWindow: (() -> Void)?
    let openSettings: () -> Void
    @ViewState private var selection: ModuleID?
    @ViewState private var window: Double = HistoryRange.oneHour.rawValue

    init(store: MonitoringStore, module: ModuleID? = nil, openWindow: (() -> Void)? = nil, openSettings: @escaping () -> Void) {
        self.store = store; self.openWindow = openWindow; self.openSettings = openSettings
        _selection = ViewState(initialValue: module)
    }
    private var now: Double { store.snapshot.uptime > 0 ? store.snapshot.uptime : SampleClock.now }
    private func value(_ id: String) -> String { store.snapshot.reading(id)?.formatted ?? "—" }
    private func fraction(_ id: String) -> Double? {
        guard let metric = MenuMetricCatalog.metrics(in: store.snapshot).first(where: { $0.id == id }) else { return nil }
        return metric.fraction(in: store.snapshot)
    }
    private func signal(_ id: String) -> MetricSignal {
        guard let metric = MenuMetricCatalog.metrics(in: store.snapshot).first(where: { $0.id == id }) else { return .unknown }
        return metric.signal(in: store.snapshot, fraction: metric.fraction(in: store.snapshot))
    }
    private func color(_ id: String) -> Color { MonitorTheme.color(signal(id)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            navigation
            ScrollView {
                Group {
                    if let module = selection { detail(module) }
                    else { overview }
                }.padding(16)
            }
            .id(selection?.rawValue ?? "overview")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 13)).foregroundStyle(MonitorTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("SystemMonitor").font(.system(size: 13, weight: .semibold))
                if selection == nil {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let uptime = store.snapshot.bootTime.map { timeline.date.timeIntervalSince($0) }
                        Text("开机运行 \(UptimeFormatter.string(seconds: uptime))")
                            .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(store.paused ? Color.orange : MonitorTheme.accent).frame(width: 5, height: 5)
                Text(store.paused ? "已暂停" : "实时").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.trailing, 5)
            if let openWindow { PanelIconButton(symbol: "arrow.up.right.square", title: "在独立窗口查看", action: openWindow) }
            PanelIconButton(symbol: "gearshape", title: "打开设置", action: openSettings)
        }.padding(.leading, 18).padding(.trailing, 12).frame(height: 48)
    }

    private var navigation: some View {
        HStack(spacing: 2) {
            tab("概览", module: nil)
            ForEach(ModuleID.allCases) { tab($0.shortTitle, module: $0) }
        }.padding(4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16).padding(.bottom, 1)
    }
    private func tab(_ title: String, module: ModuleID?) -> some View {
        let selected = selection == module
        return Button { selection = module } label: {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity).frame(height: 25)
                .background(selected ? Color.primary.opacity(0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(module.map { "查看\($0.title)详情" } ?? "返回系统概览")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var overview: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                cpuSummary
                memorySummary
            }
            networkSummary
            diskSummary
            HStack(spacing: 8) {
                smallSummary(.gpu, id: "gpu.total", caption: "设备负载")
                smallSummary(.sensors, id: "cpu.temperature", caption: "CPU 热区")
                smallSummary(.power, id: "system.power", caption: "整机功耗")
                fanSummary
            }
            if store.paused {
                Text("采集已暂停，保留最后一次数据").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }

    private var cpuSummary: some View {
        Button { selection = .cpu } label: {
            VStack(alignment: .leading, spacing: 9) {
                summaryTitle("CPU 负载")
                Text(value("cpu.total")).font(.system(size: 29, weight: .medium)).monospacedDigit()
                HistoryDotChart(points: store.history.points(for: "cpu.total", since: now - 3612), now: now, window: 3600,
                          color: MonitorTheme.accent, ceiling: 100, compact: true).frame(height: 38)
                HStack {
                    Text("最近 1 小时")
                    Spacer()
                    Text("0–100%")
                }.font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading).panelSurface()
        }.buttonStyle(.plain).accessibilityLabel("CPU 负载 \(value("cpu.total"))，查看处理器详情")
    }

    private var memorySummary: some View {
        Button { selection = .memory } label: {
            VStack(alignment: .leading, spacing: 9) {
                summaryTitle("内存")
                Text(value("memory.percent")).font(.system(size: 29, weight: .medium)).monospacedDigit()
                VStack(alignment: .leading, spacing: 9) {
                    SegmentedMeter(fraction: fraction("memory.percent"), color: color("memory.percent"), segments: 20).frame(height: 7)
                    Text("\(value("memory.used")) / \(value("memory.total"))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                }.frame(height: 38, alignment: .bottom)
                Text("内存压力\(value("memory.pressure") == "—" ? "未知" : value("memory.pressure"))")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(color("memory.percent"))
            }.frame(maxWidth: .infinity, alignment: .leading).panelSurface()
        }.buttonStyle(.plain).accessibilityLabel("内存 \(value("memory.percent"))，压力\(value("memory.pressure"))，查看内存详情")
    }

    private var networkSummary: some View {
        Button { selection = .network } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    summaryTitle("网络")
                    Spacer()
                    HStack(spacing: 6) {
                        Text(store.publicIPLocation?.flag ?? "🌐").font(.system(size: 13)).accessibilityHidden(true)
                        Text(store.snapshot.selectedInterface.isEmpty ? "等待连接" : store.snapshot.selectedInterface)
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 16) {
                    networkRate("下载", id: "network.in", symbol: "arrow.down")
                    Rectangle().fill(MonitorTheme.border).frame(width: 0.5, height: 29)
                    networkRate("上传", id: "network.out", symbol: "arrow.up")
                }
            }.panelSurface()
        }.buttonStyle(.plain).accessibilityLabel("网络下载 \(value("network.in"))，上传 \(value("network.out"))，出口国家\(store.publicIPLocation?.countryName ?? "未知")，查看网络详情")
    }
    private func networkRate(_ title: String, id: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value(id)).font(.system(size: 20, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diskSummary: some View {
        Button { selection = .disk } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    summaryTitle("磁盘空间")
                    Spacer()
                    Text("已用 \(value("disk.percent"))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                SegmentedMeter(fraction: fraction("disk.percent"), color: color("disk.percent"), segments: 44).frame(height: 5)
                HStack(alignment: .firstTextBaseline) {
                    Text("可用 \(value("disk.available"))").font(.system(size: 13, weight: .medium)).monospacedDigit()
                    Spacer()
                    Text("共 \(value("disk.total"))").font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                }
            }.panelSurface()
        }.buttonStyle(.plain).accessibilityLabel("磁盘可用 \(value("disk.available"))，总容量 \(value("disk.total"))，查看磁盘详情")
    }

    private func smallSummary(_ module: ModuleID, id: String, caption: String) -> some View {
        Button { selection = module } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(module == .sensors ? "温度" : module.shortTitle).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(value(id)).font(.system(size: 15, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text(caption).font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .topLeading).panelSurface(padding: 11)
        }.buttonStyle(.plain).accessibilityLabel("\(caption) \(value(id))，查看\(module.title)详情")
    }
    private var fanReadings: [MetricReading] {
        (store.snapshot.readings[.sensors] ?? []).filter { $0.unit == "RPM" }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private var fanSummary: some View {
        let fans = fanReadings
        return Button { selection = .sensors } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("风扇转速").font(.system(size: 10)).foregroundStyle(.secondary)
                if fans.isEmpty {
                    Text("—").font(.system(size: 15, weight: .medium))
                    Text("无可用读数").font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(fans.prefix(2).enumerated()), id: \.element.id) { index, reading in
                            HStack(spacing: 5) {
                                Text("\(index + 1)").font(.system(size: 8)).foregroundStyle(.tertiary)
                                Text(reading.formatted.replacingOccurrences(of: " RPM", with: ""))
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(reading.value == nil ? Color.secondary : Color.primary)
                            }
                        }
                    }
                    Text(fans.count > 2 ? "RPM · 共 \(fans.count) 个" : "RPM")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .topLeading).panelSurface(padding: 11)
        }.buttonStyle(.plain)
            .accessibilityLabel("风扇转速，" + (fans.isEmpty ? "无可用读数" : fans.map { "\($0.title) \($0.formatted)" }.joined(separator: "，")) + "，查看传感器详情")
    }

    private func summaryTitle(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold)).foregroundStyle(.quaternary)
        }
    }

    private func detail(_ module: ModuleID) -> some View {
        let readings = store.snapshot.readings[module] ?? []
        let primary = module.primaryID(store.preferences)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(module.title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("时间范围", selection: $window) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range.rawValue)
                    }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 185)
            }
            if module == .network { publicNetworkLocation }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(value(primary)).font(.system(size: 31, weight: .medium)).monospacedDigit()
                    Spacer()
                    Text(store.snapshot.reading(primary)?.title ?? "等待采样").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HistoryDotChart(points: store.history.points(for: primary, since: now - window - 12), now: now, window: window,
                          color: color(primary), ceiling: store.snapshot.reading(primary)?.unit == "%" ? 100 : nil,
                          compact: false).frame(height: 100)
                HStack {
                    Text("\(Int(window / 3600)) 小时前")
                    Spacer()
                    Text(store.paused ? "已暂停" : "现在")
                }.font(.system(size: 9)).foregroundStyle(.tertiary)
            }.panelSurface()
            VStack(spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    readingRow(reading)
                    if index < readings.count - 1 { Divider().opacity(0.55) }
                }
            }.padding(.horizontal, 14).panelSurface(padding: 0)
            if let note = store.snapshot.notes[module], !note.isEmpty {
                Text(note).font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if store.paused { Text("采集已暂停，显示最后一次数据").font(.system(size: 10)).foregroundStyle(.orange) }
        }
    }
    private var publicNetworkLocation: some View {
        HStack(spacing: 8) {
            Text(store.publicIPLocation?.flag ?? "🌐").font(.system(size: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text("公网出口 · \(store.publicIPLocation?.countryName ?? "国家未知")").font(.system(size: 10, weight: .medium))
                Text(store.publicIPLocation?.address ?? (store.publicIPLookupEnabled ? "暂未获取到出口 IP" : "可在设置中开启 IPIP 国家查询"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            PanelIconButton(symbol: "arrow.clockwise", title: "刷新出口 IP") { store.refreshPublicIP() }
                .disabled(!store.publicIPLookupEnabled)
        }.panelSurface(padding: 10)
    }

    private func readingRow(_ reading: MetricReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(reading.title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(reading.formatted).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(reading.value == nil ? Color.secondary : Color.primary)
            }
            if !reading.note.isEmpty {
                Text(reading.note).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if reading.value == nil, let previous = reading.previousValue, let date = reading.previousDate {
                Text("上次 \(MetricReading(reading.id, reading.title, previous, reading.unit).formatted) · \(date.formatted(date: .omitted, time: .standard))（已过期）")
                    .font(.system(size: 9)).foregroundStyle(.orange)
            }
        }.padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            Text(store.paused ? "暂停期间数据不再更新" : "每 \(Int(store.preferences.refreshInterval)) 秒更新")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            Spacer()
            Button { store.togglePaused() } label: {
                Label(store.paused ? "继续采集" : "暂停采集", systemImage: store.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 18).frame(height: 34)
            .overlay(alignment: .top) { Rectangle().fill(MonitorTheme.border).frame(height: 0.5) }
    }
}
