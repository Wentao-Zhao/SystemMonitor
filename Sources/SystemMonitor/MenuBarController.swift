import AppKit
import SwiftUI
import Combine
import MonitorCore

@MainActor
final class MenuBarController: NSObject {
    private let store: MonitoringStore
    private var items: [(item: NSStatusItem, metricID: String?)] = []
    private var appearanceObservers: [NSKeyValueObservation] = []
    private var signals: [String: MetricSignal] = [:]
    private let popover = NSPopover()
    private var settings: NSWindowController?
    private var overview: NSWindowController?
    private var subscriptions: Set<AnyCancellable> = []
    private var lastLayout = ""

    init(store: MonitoringStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = false
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "SystemMonitor")
        for (title, action, key) in [("系统概览", #selector(showOverview), "1"), ("设置…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; applicationMenu.addItem(item)
        }
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(AppUpdater.shared.makeMenuItem())
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 SystemMonitor", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        mainMenu.addItem(applicationItem); mainMenu.setSubmenu(applicationMenu, for: applicationItem)
        NSApp.mainMenu = mainMenu
        store.objectWillChange.sink { [weak self] in
            // Published properties notify before mutation; render on the next turn.
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        render()
    }

    private func render() {
        let preferences = store.preferences
        let selections = preferences.menuMetrics
        let layout = preferences.mode.rawValue + selections.map(\.id).joined(separator: ",")
        if layout != lastLayout {
            popover.close()
            appearanceObservers.removeAll()
            for entry in items { NSStatusBar.system.removeStatusItem(entry.item) }
            items = []
            let ids: [String?] = preferences.mode == .combined || selections.isEmpty ? [nil] : selections.map { Optional($0.id) }
            // Status items are inserted from right to left. Reverse creation keeps the
            // settings order left to right; per-item autosaving would override it.
            for id in ids.reversed() {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if id == nil { item.autosaveName = "SystemMonitor.combined" }
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                if let button = item.button {
                    appearanceObservers.append(button.observe(\.effectiveAppearance) { [weak self] _, _ in
                        DispatchQueue.main.async { self?.render() }
                    })
                }
                items.append((item, id))
            }
            lastLayout = layout
        }
        let frames = MenuBarRenderer.frames(for: selections, snapshot: store.snapshot, history: store.history,
                                            now: store.snapshot.uptime, refreshInterval: preferences.refreshInterval, previous: signals)
        signals = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.signal) })
        for entry in items {
            guard let button = entry.item.button else { continue }
            let selected = entry.metricID.map { id in selections.filter { $0.id == id } } ?? selections
            let displayedFrames = entry.metricID.map { id in frames.filter { $0.id == id } } ?? frames
            let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            button.title = ""
            button.image = MenuBarRenderer.image(frames: displayedFrames, dark: dark, paused: store.paused)
            button.imagePosition = .imageOnly
            button.toolTip = nil
            button.setAccessibilityLabel(statusAccessibilityLabel(for: selected, frames: displayedFrames))
        }
    }

    private func statusAccessibilityLabel(for selections: [MenuMetricSelection], frames: [DotMatrixFrame]) -> String {
        var lines = [store.paused ? "SystemMonitor · 采集已暂停" : "SystemMonitor"]
        if selections.isEmpty { lines.append("未选择菜单栏指标 · 右键打开设置以添加") }
        for selection in selections {
            let metric = selection.metric
            let reading = store.snapshot.reading(metric.id)
            var line = "\(metric.title)：\(reading?.formatted ?? "—") · \(selection.presentation.title)"
            if reading?.value == nil { line += " · 当前不可用" }
            if let state = frames.first(where: { $0.id == selection.id })?.signal {
                let name: String
                switch state {
                case .normal: name = "正常"
                case .elevated: name = "偏高"
                case .critical: name = "紧张"
                case .unknown: name = "状态未知"
                }
                line += " · \(name)"
            }
            if metric.module == .memory, let pressure = store.snapshot.reading("memory.pressure"), pressure.value != nil {
                line += " · 内存压力\(pressure.formatted)"
            }
            if metric.hasAdjustableScale, let scale = metric.fullScale(in: store.snapshot, override: selection.scale) {
                line += " · 满格 \(MetricReading("reference", "", scale, metric.unit).formatted)"
            }
            if metric.module == .memory, store.snapshot.reading("memory.pressure")?.value == nil { line += " · 压力未知" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let entry = items.first(where: { $0.item.button === sender }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.close()
            let menu = NSMenu()
            for (title, action) in [("设置…", #selector(showSettings)), (store.paused ? "继续采集" : "暂停采集", #selector(togglePause))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            let metrics = NSMenuItem(title: "菜单栏指标", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            let catalog = MenuMetricCatalog.metrics(in: store.snapshot)
            for module in ModuleID.allCases {
                let group = NSMenuItem(title: module.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                var available = catalog.filter { $0.module == module }
                available += store.preferences.menuMetrics.map(\.metric).filter { saved in
                    saved.module == module && !available.contains { $0.id == saved.id }
                }
                for metric in available {
                    let option = NSMenuItem(title: metric.title, action: #selector(toggleMetric(_:)), keyEquivalent: "")
                    option.target = self; option.representedObject = metric
                    option.state = store.preferences.menuMetrics.contains { $0.id == metric.id } ? .on : .off
                    submenu.addItem(option)
                }
                group.submenu = submenu; choices.addItem(group)
            }
            metrics.submenu = choices; menu.insertItem(metrics, at: 1)
            menu.addItem(.separator())
            menu.addItem(AppUpdater.shared.makeMenuItem())
            menu.addItem(.separator())
            let quitItem = NSMenuItem(title: "退出 SystemMonitor", action: #selector(quit), keyEquivalent: "")
            quitItem.target = self
            menu.addItem(quitItem)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
            return
        }
        if popover.isShown { popover.close(); return }
        popover.contentViewController = NSHostingController(rootView: MonitorPanel(store: store,
            module: entry.metricID.flatMap { id in store.preferences.menuMetrics.first { $0.id == id }?.metric.module },
            openWindow: { [weak self] in self?.showOverview() }) { [weak self] in self?.showSettings() })
        popover.contentSize = NSSize(width: MonitorPanel.width, height: MonitorPanel.height)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func showSettings() {
        popover.close()
        if settings == nil {
            let controller = NSHostingController(rootView: MonitorSettingsView(store: store) { [weak self] in self?.showOverview() })
            let window = NSWindow(contentViewController: controller)
            window.title = "SystemMonitor 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 620, height: 690)); window.center()
            window.isReleasedWhenClosed = false
            settings = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showOverview() {
        popover.close()
        settings?.window?.orderOut(nil)
        if overview == nil {
            let controller = NSHostingController(rootView: MonitorPanel(store: store) { [weak self] in self?.showSettings() })
            let window = NSWindow(contentViewController: controller)
            window.title = "SystemMonitor 系统概览"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: MonitorPanel.width, height: MonitorPanel.height)); window.center()
            overview = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        overview?.showWindow(nil); overview?.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? MenuMetric else { return }
        store.updatePreferences { preferences in
            var selections = preferences.menuMetrics
            if selections.contains(where: { $0.id == metric.id }) { selections.removeAll { $0.id == metric.id } }
            else { selections.append(MenuMetricSelection(metric: metric)) }
            preferences.menuMetrics = selections
        }
    }
    @objc private func togglePause() { store.togglePaused() }
    @objc private func quit() { NSApp.terminate(nil) }
}
