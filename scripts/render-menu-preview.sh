#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p .build/menu-preview
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name MonitorCore \
    Sources/MonitorCore/*.swift -o .build/menu-preview/libMonitorCore.dylib \
    -emit-module-path .build/menu-preview/MonitorCore.swiftmodule
swiftc -module-cache-path .build/clang-cache -I .build/menu-preview -L .build/menu-preview -lMonitorCore \
    Sources/SystemMonitor/MenuBarRenderer.swift scripts/render-menu-preview.swift -o .build/menu-preview/render
DYLD_LIBRARY_PATH="$project_dir/.build/menu-preview" .build/menu-preview/render "${1:-design/menu-bar-layouts/menu-bar-implemented.png}"
