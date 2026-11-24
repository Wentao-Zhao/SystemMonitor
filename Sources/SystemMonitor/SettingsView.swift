import SwiftUI
import ServiceManagement
import MonitorCore

@MainActor
struct MonitorSettingsView: View {
    @ObservedObject var store: MonitoringStore
    @Environment(\.colorScheme) private var colorScheme
    let openMonitor: () -> Void
    @ViewState private var launchError = ""
    @ViewState private var launchEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval

    private func binding<Value>(_ key: WritableKeyPath<MonitorPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in store.updatePreferences { $0[keyPath: key] = value } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("按你的习惯，安排每个指标").font(.system(size: 21, weight: .semibold))
                    Text("监控数据留在本机，菜单栏只显示你关心的内容。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("查看监控概览", action: openMonitor).padding(.top, 8)
                }.padding(.bottom, 2)
                menuConfiguration
                GroupBox("数据与采样") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("基础刷新间隔", selection: binding(\.refreshInterval)) {
                            Text("1 秒").tag(1.0); Text("2 秒（推荐）").tag(2.0); Text("5 秒").tag(5.0)
                        }
                        Picker("网络接口", selection: binding(\.interfaceID)) {
                            Text("自动 · 当前主要网卡").tag("")
                            ForEach(store.snapshot.interfaces) { Text($0.title).tag($0.id) }
                            if !store.preferences.interfaceID.isEmpty, !store.snapshot.interfaces.contains(where: { $0.id == store.preferences.interfaceID }) {
                                Text("\(store.preferences.interfaceID) · 当前不可用").tag(store.preferences.interfaceID)
                            }
                        }
                        Picker("本地磁盘卷", selection: binding(\.diskID)) {
                            Text("自动 · 启动卷").tag("")
                            ForEach(store.snapshot.disks) { Text($0.title).tag($0.id) }
                            if !store.preferences.diskID.isEmpty, !store.snapshot.disks.contains(where: { $0.id == store.preferences.diskID }) {
                                Text("所选卷 · 当前不可用").tag(store.preferences.diskID)
                            }
                        }
                        Picker("出口国家查询", selection: binding(\.publicIPProvider)) {
                            Text("关闭").tag(Optional<PublicIPProvider>.none)
                            ForEach(PublicIPProvider.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                        Text("IPIP 会看到查询请求的公网 IP，用于返回出口国家；不发送监控指标。分流 VPN 的不同网站可能使用不同出口。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("硬件指标最快每 2 秒采样；详情保留最近 24 小时，可切换 1h / 6h / 24h；菜单栏保留短时历史。退出后清除。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox("启动") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("登录时启动 SystemMonitor", isOn: Binding(get: { launchEnabled }, set: { setLaunchEnabled($0) }))
                        if !launchError.isEmpty { Text(launchError).font(.caption).foregroundStyle(.orange) }
                        if SMAppService.mainApp.status == .requiresApproval {
                            Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                Text("SystemMonitor 0.1.1 · 原生 macOS 系统监控")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24)
        }.frame(width: 620, height: 690)
        .onAppear { refreshLaunchStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLaunchStatus() }
    }

    private var catalog: [MenuMetric] { MenuMetricCatalog.metrics(in: store.snapshot) }

    private var menuConfiguration: some View {
        GroupBox("菜单栏") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("显示方式", selection: binding(\.mode)) {
                    Text("合并显示").tag(DisplayMode.combined)
                    Text("独立显示").tag(DisplayMode.independent)
                }.pickerStyle(.segmented)
                Text(store.preferences.mode == .combined ? "所选指标合并为一个入口，按下面的顺序显示。" : "每个指标拥有独立入口，点击查看所属模块。")
                    .font(.caption).foregroundStyle(.secondary)
                preview
                HStack {
                    Text("已选指标 · \(store.preferences.menuMetrics.count)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Menu {
                        ForEach(ModuleID.allCases) { module in
                            Menu(module.title) {
                                ForEach(catalog.filter { $0.module == module }) { metric in
                                    Button(metric.title) { add(metric) }
                                        .disabled(store.preferences.menuMetrics.contains { $0.id == metric.id })
                                }
                            }
                        }
                    } label: { Label("添加指标", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                if store.preferences.menuMetrics.isEmpty {
                    Text("还没有指标。添加你关心的读数；菜单栏会保留一个设置入口。")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(store.preferences.menuMetrics) { selection in
                    metricRow(selection)
                    if selection.id != store.preferences.menuMetrics.last?.id { Divider() }
                }
                Text("实时值用竖向六格；历史用横向十五列，每列为 4 秒平均。两种显示模式分别记住选择、顺序和样式。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(10)
        }
    }

    private var preview: some View {
        let frames = MenuBarRenderer.frames(for: store.preferences.menuMetrics, snapshot: store.snapshot, history: store.history,
                                            now: store.snapshot.uptime, refreshInterval: store.preferences.refreshInterval)
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if store.preferences.mode == .independent && !frames.isEmpty {
                        ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                            Image(nsImage: MenuBarRenderer.image(frames: [frame], dark: colorScheme == .dark))
                        }
                    } else { Image(nsImage: MenuBarRenderer.image(frames: frames, dark: colorScheme == .dark)) }
                    Spacer(minLength: 0)
                }.frame(minHeight: 32).padding(.horizontal, 8)
            }.background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            Text("实时预览 · 绿 / 黄 / 红表示状态，灰色表示状态未知，斜杠表示当前不可用。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func metricRow(_ selection: MenuMetricSelection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.metric.title).font(.system(size: 12, weight: .medium))
                    Text("\(selection.metric.module.title) · \(store.snapshot.reading(selection.id)?.formatted ?? "当前不可用")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Picker("\(selection.metric.title)显示类型", selection: Binding(get: {
                    store.preferences.menuMetrics.first { $0.id == selection.id }?.presentation ?? selection.presentation
                }, set: { value in edit(selection.id) { $0.presentation = value } })) {
                    ForEach(MetricPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 150)
                Button { move(selection.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(store.preferences.menuMetrics.first?.id == selection.id).help("向前移动")
                    .accessibilityLabel("向前移动\(selection.metric.title)")
                Button { move(selection.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(store.preferences.menuMetrics.last?.id == selection.id).help("向后移动")
                    .accessibilityLabel("向后移动\(selection.metric.title)")
                Button { remove(selection.id) } label: { Image(systemName: "minus.circle") }
                    .help("移除指标").accessibilityLabel("移除\(selection.metric.title)")
            }
            if selection.metric.hasAdjustableScale {
                HStack(spacing: 5) {
                    Text("满格参考").foregroundStyle(.secondary)
                    TextField("满格参考", value: Binding(get: {
                        let value = store.preferences.menuMetrics.first { $0.id == selection.id }?.scale ?? selection.metric.defaultScale
                        return value / selection.metric.scaleInputMultiplier
                    }, set: { value in
                        guard value.isFinite, value > 0, value <= 1_000_000 else { return }
                        edit(selection.id) { $0.scale = value * selection.metric.scaleInputMultiplier }
                    }), format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(selection.metric.title)满格参考")
                    Text(selection.metric.scaleInputUnit).foregroundStyle(.secondary)
                    if selection.scale != nil { Button("还原") { edit(selection.id) { $0.scale = nil } }.buttonStyle(.link) }
                    if selection.metric.unit == "B/s" { Text("· 参考速率，非链路利用率").foregroundStyle(.secondary) }
                }.font(.system(size: 10))
            }
        }
    }

    private func add(_ metric: MenuMetric) {
        store.updatePreferences { preferences in
            guard !preferences.menuMetrics.contains(where: { $0.id == metric.id }) else { return }
            preferences.menuMetrics.append(MenuMetricSelection(metric: metric))
        }
    }
    private func remove(_ id: String) { store.updatePreferences { $0.menuMetrics.removeAll { $0.id == id } } }
    private func edit(_ id: String, update: (inout MenuMetricSelection) -> Void) {
        store.updatePreferences { preferences in
            var metrics = preferences.menuMetrics
            guard let index = metrics.firstIndex(where: { $0.id == id }) else { return }
            update(&metrics[index]); preferences.menuMetrics = metrics
        }
    }
    private func move(_ id: String, by distance: Int) {
        store.updatePreferences { preferences in
            var metrics = preferences.menuMetrics
            guard let index = metrics.firstIndex(where: { $0.id == id }), metrics.indices.contains(index + distance) else { return }
            metrics.swapAt(index, index + distance); preferences.menuMetrics = metrics
        }
    }

    private func setLaunchEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            launchError = SMAppService.mainApp.status == .requiresApproval ? "请在系统登录项中允许启动。" : ""
        } catch {
            launchEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            launchError = "无法更新登录项：\(error.localizedDescription)"
        }
    }
    private func refreshLaunchStatus() {
        let status = SMAppService.mainApp.status
        launchEnabled = status == .enabled || status == .requiresApproval
        if status == .enabled { launchError = "" }
    }
}
