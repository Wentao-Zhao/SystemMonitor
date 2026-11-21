import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: MonitoringStore?
    private var menu: MenuBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = MonitoringStore()
        self.store = store
        menu = MenuBarController(store: store)
        if !UserDefaults.standard.bool(forKey: "monitor.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "monitor.hasLaunched")
            menu?.showSettings()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menu?.showSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
enum SystemMonitorMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
