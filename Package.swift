// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SystemMonitor", targets: ["SystemMonitor"])],
    targets: [
        .target(name: "MonitorCore"),
        .target(name: "HardwareBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "SystemCollectors", dependencies: ["MonitorCore", "HardwareBridge"]),
        .executableTarget(name: "SystemMonitor", dependencies: ["MonitorCore", "SystemCollectors"]),
        .executableTarget(name: "MonitorProbe", dependencies: ["SystemCollectors", "MonitorCore"]),
        .executableTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
