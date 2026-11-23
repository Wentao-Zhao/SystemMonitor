import AppKit
import MonitorCore

@MainActor
final class MenuCheckDelegate: NSObject, NSApplicationDelegate {
    private let suite = "local.SystemMonitor.menu-checks.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var store: MonitoringStore!
    private var controller: MenuBarController!
    private var checks = 0
    private var failures = 0
    private var originalWidth: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaults = UserDefaults(suiteName: suite)!
        var preferences = MonitorPreferences(); preferences.normalize()
        defaults.set(try! JSONEncoder().encode(preferences), forKey: "monitor.preferences.v1")
        store = MonitoringStore(defaults: defaults, resolvePublicIP: false)
        controller = MenuBarController(store: store)
        controller.showSettings()
        later(2.5) { self.initialState() }
    }
    private func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(name)") }
    }
    private func later(_ seconds: Double = 0.2, _ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
    private var buttons: [NSStatusBarButton] {
        func find(_ view: NSView) -> [NSStatusBarButton] {
            (view as? NSStatusBarButton).map { [$0] } ?? view.subviews.flatMap(find)
        }
        return NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(find)
    }
    private func initialState() {
        expect(buttons.count == 1, "combined configuration creates one native status button")
        expect(buttons.first?.image?.isTemplate == false, "native status image preserves semantic colors")
        expect(buttons.allSatisfy { $0.toolTip == nil }, "native status buttons do not display hover tooltips")
        expect((buttons.first?.accessibilityLabel()?.contains("内存压力") == true || buttons.first?.accessibilityLabel()?.contains("压力未知") == true), "memory pressure is present in accessible status text")
        expect(NSApp.windows.contains { $0.title == "SystemMonitor 设置" && $0.isVisible }, "native settings window is visible")
        expect(store.snapshot.bootTime.map { $0 <= Date() && Date().timeIntervalSince($0) > 0 } == true, "collector provides the system boot timestamp")
        expect(store.publicIPLocation == nil && !store.publicIPLookupEnabled, "isolated app checks never issue an online location query")
        originalWidth = buttons.first?.image?.size.width ?? 0
        store.updatePreferences { $0.menuMetrics.removeAll { $0.id == "network.out" } }
        later { self.removedDirection() }
    }
    private func removedDirection() {
        expect(buttons.count == 1 && (buttons.first?.image?.size.width ?? 0) < originalWidth, "removing upload shrinks the actual combined image")
        expect(buttons.first?.accessibilityLabel()?.contains("网络下载") == true && buttons.first?.accessibilityLabel()?.contains("网络上传") == false, "removing upload preserves download only")
        let temp = MenuMetricCatalog.metrics(in: store.snapshot).first { $0.id == "cpu.temperature" }!
        store.updatePreferences { $0.menuMetrics.append(MenuMetricSelection(metric: temp)) }
        later {
            self.expect(self.buttons.first?.accessibilityLabel()?.contains("CPU 温度") == true, "a separately selected sensor reaches the native accessibility label")
            self.store.updatePreferences { $0.mode = .independent }
            self.later { self.independentState() }
        }
    }
    private func independentState() {
        expect(buttons.count == 4, "independent configuration creates a button for each selected reading")
        expect(buttons.filter { $0.accessibilityLabel()?.contains("网络下载") == true }.count == 1, "download has its own independently accessible button")
        expect(buttons.filter { $0.accessibilityLabel()?.contains("网络上传") == true }.count == 1, "upload has its own independently accessible button")
        store.updatePreferences { $0.menuMetrics = [] }
        later {
            self.expect(self.buttons.count == 1 && self.buttons.first?.accessibilityLabel()?.contains("未选择") == true, "removing every metric retains a native launcher")
            self.store.updatePreferences { $0.mode = .combined }
            self.later { self.restoredState() }
        }
    }
    private func restoredState() {
        expect(buttons.count == 1 && buttons.first?.accessibilityLabel()?.contains("CPU 温度") == true, "switching back restores the other mode's selected sensor")
        expect(buttons.first?.accessibilityLabel()?.contains("网络上传") == false, "switching modes preserves a removed upload indicator")
        let before = buttons.first?.image?.size.width ?? 0
        store.updatePreferences { $0.menuMetrics[0].presentation = .instant }
        later {
            self.expect((self.buttons.first?.image?.size.width ?? 0) < before, "switching CPU to instantaneous changes the actual dot geometry")
            self.store.togglePaused()
            self.later { self.pausedState() }
        }
    }
    private func pausedState() {
        expect(buttons.first?.accessibilityLabel()?.contains("采集已暂停") == true, "paused state remains accessible")
        expect(buttons.allSatisfy { $0.toolTip == nil }, "pausing does not restore hover tooltips")
        store.togglePaused()
        store.updatePreferences { $0.menuMetrics[0].presentation = .history }
        later(0.5) { self.captureSettings() }
    }
    private func captureSettings() {
        if let view = NSApp.windows.first(where: { $0.title == "SystemMonitor 设置" })?.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: bitmap)
            }
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/checks/menu-settings.png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            print("Settings capture: \(url.path)")
            expect(bitmap.pixelsWide >= 620 && bitmap.pixelsHigh >= 690, "settings capture has the expected native dimensions")
        } else { expect(false, "settings can be rendered for inspection") }
        defaults.removePersistentDomain(forName: suite)
        print("\(checks) native app checks, \(failures) failures")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}

@main
enum MenuChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = MenuCheckDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
