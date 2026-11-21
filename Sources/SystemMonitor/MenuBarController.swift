import AppKit
import SwiftUI
import Combine
import MonitorCore

@MainActor
final class MenuBarController: NSObject {
    private let store: MonitoringStore
    private var items: [(item: NSStatusItem, module: ModuleID?)] = []
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
        for (title, action, key) in [("系统概览", #selector(showOverview), "1"), ("设置…", #selector(showSettings), ","), ("退出 SystemMonitor", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; applicationMenu.addItem(item)
        }
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
        let layout = preferences.mode.rawValue + preferences.visibleModules.map(\.rawValue).joined(separator: ",")
        if layout != lastLayout {
            popover.close()
            for entry in items { NSStatusBar.system.removeStatusItem(entry.item) }
            items = []
            let modules: [ModuleID?] = preferences.mode == .combined ? [nil] : preferences.visibleModules.map(Optional.some)
            for module in modules {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "SystemMonitor.\(module?.rawValue ?? "combined")"
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                items.append((item, module))
            }
            lastLayout = layout
        }
        for entry in items {
            guard let button = entry.item.button else { continue }
            if store.paused {
                button.image = nil; button.title = entry.module.map { "\($0.shortTitle) ⏸" } ?? "监控 ⏸"
                button.toolTip = "SystemMonitor · 采集已暂停"
            } else {
                button.title = ""
                let modules = entry.module.map { [$0] } ?? preferences.visibleModules
                button.image = summaryImage(modules)
                button.imagePosition = .imageOnly
                button.toolTip = modules.map { "\($0.title)：\(store.snapshot.reading($0.primaryID(preferences))?.formatted ?? "等待采样")" }.joined(separator: "\n")
                button.setAccessibilityLabel(button.toolTip)
            }
        }
    }

    private func summaryImage(_ modules: [ModuleID]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let segments: [(String, ModuleID, Bool)] = modules.map { module in
            let reading = store.snapshot.reading(module.primaryID(store.preferences))
            let value = reading?.formatted ?? "—"
            let text: String
            switch module {
            case .cpu: text = "CPU \(value)"
            case .gpu: text = "GPU \(value)"
            case .memory: text = "MEM \(value)"
            case .disk: text = store.preferences.diskAsCapacity ? "SSD \(value)" : "R \(value) W \(store.snapshot.reading("disk.write")?.formatted ?? "—")"
            case .network: text = "↓\(value) ↑\(store.snapshot.reading("network.out")?.formatted ?? "—")"
            case .sensors: text = value
            case .power: text = value
            }
            return (text, module, store.preferences.styles[module.rawValue] == .graph)
        }
        let widths = segments.map { $0.2 ? CGFloat(58) : ceil(($0.0 as NSString).size(withAttributes: attributes).width) }
        let total = widths.reduce(0, +) + CGFloat(max(0, segments.count - 1)) * 12 + 4
        let image = NSImage(size: NSSize(width: total, height: 22), flipped: false) { rect in
            var x: CGFloat = 2
            for (index, segment) in segments.enumerated() {
                if segment.2 {
                    let points = self.store.history.points(for: segment.1.primaryID(self.store.preferences), since: self.store.snapshot.uptime - 60)
                    self.drawGraph(points, in: NSRect(x: x, y: 4, width: widths[index], height: 14), now: self.store.snapshot.uptime)
                } else {
                    let size = (segment.0 as NSString).size(withAttributes: attributes)
                    (segment.0 as NSString).draw(at: NSPoint(x: x, y: (rect.height - size.height) / 2), withAttributes: attributes)
                }
                x += widths[index] + 12
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawGraph(_ points: [HistoryPoint], in rect: NSRect, now: Double) {
        let maxValue = max(points.compactMap(\.value).max() ?? 1, 1)
        NSColor.labelColor.setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.25
        for segment in chartSegments(points) {
            for (index, point) in segment.enumerated() {
                guard let value = point.value else { continue }
                let p = NSPoint(x: rect.minX + rect.width * min(1, max(0, (point.time - now + 60) / 60)), y: rect.minY + rect.height * min(1, max(0, value / maxValue)))
                if index > 0 { path.line(to: p) } else { path.move(to: p) }
            }
        }
        path.stroke()
        if points.compactMap(\.value).isEmpty {
            let dash = NSBezierPath(); dash.move(to: NSPoint(x: rect.midX - 4, y: rect.midY)); dash.line(to: NSPoint(x: rect.midX + 4, y: rect.midY)); dash.stroke()
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let entry = items.first(where: { $0.item.button === sender }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.close()
            let menu = NSMenu()
            for (title, action) in [("设置…", #selector(showSettings)), (store.paused ? "继续采集" : "暂停采集", #selector(togglePause)), ("退出 SystemMonitor", #selector(quit))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
            return
        }
        if popover.isShown { popover.close(); return }
        popover.contentViewController = NSHostingController(rootView: MonitorPanel(store: store, module: entry.module) { [weak self] in self?.showSettings() })
        popover.contentSize = NSSize(width: 580, height: 660)
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
            window.setContentSize(NSSize(width: 580, height: 660)); window.center()
            overview = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        overview?.showWindow(nil); overview?.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func togglePause() { store.togglePaused() }
    @objc private func quit() { NSApp.terminate(nil) }
}
