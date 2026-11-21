import SwiftUI
import ServiceManagement
import MonitorCore

@MainActor
struct MonitorSettingsView: View {
    @ObservedObject var store: MonitoringStore
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
                GroupBox("菜单栏") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("显示方式", selection: binding(\.mode)) {
                            Text("合并显示").tag(DisplayMode.combined)
                            Text("独立显示").tag(DisplayMode.independent)
                        }.pickerStyle(.segmented)
                        Text(store.preferences.mode == .combined ? "多个指标集中在一个入口，点击查看系统概览。" : "每个模块拥有独立入口，点击直接查看该模块。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(orderedModules) { module in
                            HStack {
                                Toggle(isOn: Binding(get: { store.preferences.visibleModules.contains(module) }, set: { enabled in
                                    store.updatePreferences { preferences in
                                        var modules = preferences.visibleModules
                                        if enabled { if !modules.contains(module) { modules.append(module) } }
                                        else { modules.removeAll { $0 == module } }
                                        if preferences.mode == .combined { preferences.combinedModules = modules }
                                        else { preferences.independentModules = modules }
                                    }
                                })) { Label(module.title, systemImage: module.symbol) }
                                Spacer()
                                Picker("\(module.title)样式", selection: Binding(get: { store.preferences.styles[module.rawValue] ?? .value }, set: { value in
                                    store.updatePreferences { $0.styles[module.rawValue] = value }
                                })) {
                                    Text("数值").tag(SummaryStyle.value)
                                    Text("曲线").tag(SummaryStyle.graph)
                                }.labelsHidden().frame(width: 85)
                                Button { move(module, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(store.preferences.visibleModules.first == module || !store.preferences.visibleModules.contains(module)).help("向前移动")
                                Button { move(module, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(store.preferences.visibleModules.last == module || !store.preferences.visibleModules.contains(module)).help("向后移动")
                            }
                        }
                        Text("两种模式分别记住指标顺序；始终保留一个菜单栏入口。隐藏摘要不会关闭详情中的监控。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(10)
                }
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
                        Toggle("内存摘要显示已用容量", isOn: binding(\.memoryAsBytes))
                        Toggle("磁盘摘要显示剩余空间", isOn: binding(\.diskAsCapacity))
                        sensorPicker("温度 / 风扇摘要", module: .sensors, key: \.sensorID)
                        sensorPicker("功耗摘要", module: .power, key: \.powerID)
                        Text("硬件指标最快每 2 秒采样；曲线保留最近 15 分钟，退出后清除。")
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
                Text("SystemMonitor 0.1.0 · 原生 macOS 系统监控")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(24)
        }.frame(width: 620, height: 690)
        .onAppear { refreshLaunchStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLaunchStatus() }
    }

    private var orderedModules: [ModuleID] {
        store.preferences.visibleModules + ModuleID.allCases.filter { !store.preferences.visibleModules.contains($0) }
    }

    private func move(_ module: ModuleID, by distance: Int) {
        store.updatePreferences { preferences in
            var modules = preferences.visibleModules
            guard let index = modules.firstIndex(of: module), modules.indices.contains(index + distance) else { return }
            modules.swapAt(index, index + distance)
            if preferences.mode == .combined { preferences.combinedModules = modules }
            else { preferences.independentModules = modules }
        }
    }

    @ViewBuilder
    private func sensorPicker(_ title: String, module: ModuleID, key: WritableKeyPath<MonitorPreferences, String>) -> some View {
        let readings = store.snapshot.readings[module] ?? []
        let value = store.preferences[keyPath: key]
        Picker(title, selection: binding(key)) {
            ForEach(readings) { Text("\($0.title) · \($0.formatted)").tag($0.id) }
            if !readings.contains(where: { $0.id == value }) { Text("当前指标 · 不可用").tag(value) }
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
