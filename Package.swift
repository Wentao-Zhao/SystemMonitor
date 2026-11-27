// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SystemMonitor", targets: ["SystemMonitor"])],
    targets: [
    .binaryTarget(
      name: "Sparkle",
      url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
    ),
        .target(name: "MonitorCore"),
        .target(name: "HardwareBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "SystemCollectors", dependencies: ["MonitorCore", "HardwareBridge"]),
        .executableTarget(name: "SystemMonitor", dependencies: ["MonitorCore", "SystemCollectors", "Sparkle"],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "MonitorProbe", dependencies: ["SystemCollectors", "MonitorCore"]),
        .executableTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
