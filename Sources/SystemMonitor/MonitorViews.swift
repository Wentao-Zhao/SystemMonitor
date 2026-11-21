import SwiftUI
import MonitorCore

// Select the property-wrapper type explicitly on SDKs that also define a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension ModuleID {
    var tint: Color {
        switch self {
        case .cpu: return .blue
        case .gpu: return .purple
        case .memory: return .teal
        case .disk: return .orange
        case .network: return .cyan
        case .sensors: return .red
        case .power: return .yellow
        }
    }
    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .disk: return "磁盘"
        case .network: return "网络"
        case .sensors: return "温度 / 风扇"
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
    @ObservedObject var store: MonitoringStore
    let openSettings: () -> Void
    @ViewState private var selection: ModuleID?
    @ViewState private var window: Double = 300
    init(store: MonitoringStore, module: ModuleID? = nil, openSettings: @escaping () -> Void) {
        self.store = store; self.openSettings = openSettings
        _selection = ViewState(initialValue: module)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let module = selection { detail(module) }
            else { overview }
            Divider()
            footer
        }
        .frame(width: 580, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: selection?.symbol ?? "waveform.path.ecg")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(selection?.tint ?? .blue)
                .frame(width: 42, height: 42)
                .background((selection?.tint ?? .blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(selection?.title ?? "系统监控").font(.system(size: 19, weight: .semibold))
                Text(selection == nil ? "每一个变化，尽在掌握" : "实时指标与近期趋势")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(store.paused ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(store.paused ? "已暂停" : "实时 · \(Int(store.preferences.refreshInterval))s")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
            if selection != nil {
                Button { selection = nil } label: { Image(systemName: "square.grid.2x2").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless).help("返回概览")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("系统概览").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let updated = store.lastUpdated {
                        Text("更新于 \(updated.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ModuleID.allCases) { module in
                        Button { selection = module } label: { card(module) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看\(module.title)详情")
                    }
                }
            }
            .padding(18)
        }
        .opacity(store.paused ? 0.65 : 1)
        .overlay(alignment: .bottom) {
            if store.paused { Text("采集已暂停 · 下方保留最后一次数据").font(.caption).padding(8).background(.regularMaterial, in: Capsule()).padding(10) }
        }
    }

    private func card(_ module: ModuleID) -> some View {
        let id = module.primaryID(store.preferences)
        let reading = store.snapshot.reading(id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: module.symbol).foregroundStyle(module.tint)
                Text(module.shortTitle).fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.font(.system(size: 11))
            HStack(alignment: .firstTextBaseline) {
                Text(reading?.formatted ?? "—").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                if module == .network {
                    Text("↑ \(store.snapshot.reading("network.out")?.formatted ?? "—")")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Sparkline(points: store.history.points(for: id, since: SampleClock.now - 60), now: SampleClock.now, window: 60, color: module.tint, ceiling: reading?.unit == "%" ? 100 : nil)
                .frame(height: 30)
            Text(cardSubtitle(module))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.055)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cardSubtitle(_ module: ModuleID) -> String {
        switch module {
        case .cpu: return "\(ProcessInfo.processInfo.processorCount) 核心 · 整机负载"
        case .gpu: return store.snapshot.reading("gpu.total")?.title ?? "等待设备数据"
        case .memory: return "共 \(store.snapshot.reading("memory.total")?.formatted ?? "—") · 压力\(store.snapshot.reading("memory.pressure")?.formatted ?? "不可用")"
        case .disk: return "剩余 \(store.snapshot.reading("disk.available")?.formatted ?? "—")"
        case .network: return "\(store.snapshot.selectedInterface.isEmpty ? "等待网卡" : store.snapshot.selectedInterface) · 实时上下行"
        case .sensors: return "GPU \(store.snapshot.reading("gpu.temperature")?.formatted ?? "—") · \(store.snapshot.readings[.sensors]?.filter { $0.unit == "RPM" }.count ?? 0) 个风扇"
        case .power: return "整机 \(store.snapshot.reading("system.power")?.formatted ?? "—")"
        }
    }

    private func detail(_ module: ModuleID) -> some View {
        let readings = store.snapshot.readings[module] ?? []
        let primary = module.primaryID(store.preferences)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.snapshot.reading(primary)?.title ?? module.title).font(.caption).foregroundStyle(.secondary)
                            Text(store.snapshot.reading(primary)?.formatted ?? "—")
                                .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        Spacer()
                        Picker("时间范围", selection: $window) {
                            Text("1 分钟").tag(60.0)
                            Text("5 分钟").tag(300.0)
                            Text("15 分钟").tag(900.0)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 206).help("曲线时间范围")
                    }
                    Sparkline(points: store.history.points(for: primary, since: SampleClock.now - window), now: SampleClock.now, window: window, color: module.tint, ceiling: store.snapshot.reading(primary)?.unit == "%" ? 100 : nil)
                        .frame(height: 130)
                    HStack {
                        Text("\(Int(window / 60)) 分钟前")
                        Spacer()
                        Text(store.paused ? "已暂停" : "现在")
                    }.font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 0) {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reading.title).font(.system(size: 12))
                                if !reading.note.isEmpty { Text(reading.note).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                if reading.value == nil, let previous = reading.previousValue, let date = reading.previousDate {
                                    Text("上次 \(MetricReading(reading.id, reading.title, previous, reading.unit).formatted) · \(date.formatted(date: .omitted, time: .standard))（已过期）")
                                        .font(.system(size: 10)).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 10)
                            Text(reading.formatted).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                                .foregroundStyle(reading.value == nil ? Color.secondary : Color.primary)
                        }.padding(.vertical, 11).padding(.horizontal, 14)
                        if index != readings.count - 1 { Divider().padding(.horizontal, 14) }
                    }
                }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                if let note = store.snapshot.notes[module], !note.isEmpty {
                    Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if store.paused { Label("已暂停，显示最后一次采样结果", systemImage: "pause.circle").font(.caption).foregroundStyle(.orange) }
            }.padding(18)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) { Label("设置", systemImage: "slider.horizontal.3") }.buttonStyle(.borderless)
            Spacer()
            Text("SystemMonitor").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            Spacer()
            Button { store.togglePaused() } label: { Label(store.paused ? "继续采集" : "暂停", systemImage: store.paused ? "play" : "pause") }
                .buttonStyle(.borderless)
        }.font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 12)
    }
}

struct Sparkline: View {
    let points: [HistoryPoint]
    let now: Double
    let window: Double
    let color: Color
    var ceiling: Double?
    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(ceiling ?? ((points.compactMap(\.value).max() ?? 1) * 1.15), 0.001)
            ZStack {
                Path { path in
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = geometry.size.height * fraction
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                Path { path in
                    for segment in chartSegments(points) {
                        for (index, point) in segment.enumerated() {
                            guard let value = point.value else { continue }
                            let x = geometry.size.width * min(1, max(0, (point.time - (now - window)) / window))
                            let y = geometry.size.height * (1 - min(1, max(0, value / maxValue)))
                            let position = CGPoint(x: x, y: y)
                            if index > 0 { path.addLine(to: position) } else { path.move(to: position) }
                        }
                    }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                if points.compactMap(\.value).isEmpty {
                    Text("等待有效采样").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }.accessibilityLabel("近期趋势，缺失采样保留空白")
    }
}
