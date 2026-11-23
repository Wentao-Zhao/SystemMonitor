#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
swift build --disable-sandbox --cache-path .build/swift-cache --config-path .build/swift-config --security-path .build/swift-security --product SystemMonitor
mkdir -p .build/checks
app_sources=(Sources/SystemMonitor/*.swift)
app_sources=(${app_sources:#Sources/SystemMonitor/SystemMonitorApp.swift})
swiftc -parse-as-library -swift-version 5 -module-cache-path .build/clang-cache -I .build/debug -I Sources/HardwareBridge/include -Xcc -fmodule-map-file=.build/out/Intermediates.noindex/GeneratedModuleMaps/HardwareBridge.modulemap \
    "${app_sources[@]}" Tests/MonitorAppTests/main.swift \
    .build/debug/MonitorCore.o .build/debug/SystemCollectors.o .build/debug/HardwareBridge.o \
    -framework IOKit -framework CoreFoundation -framework SystemConfiguration -o .build/checks/MonitorMenuChecks
if [[ "${1:-}" != "--build-only" ]]; then .build/checks/MonitorMenuChecks; fi
