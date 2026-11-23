#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p .build/checks
swiftc -module-cache-path .build/clang-cache \
    Sources/MonitorCore/*.swift \
    Tests/MonitorCoreTests/main.swift -o .build/checks/MonitorCoreTests
.build/checks/MonitorCoreTests
clang -Wall -Wextra -Werror -ISources/HardwareBridge/include \
    Sources/HardwareBridge/HardwareBridge.c Tests/HardwareBridgeTests/decoder-test.c \
    -framework IOKit -framework CoreFoundation -o .build/checks/HardwareDecoderTests
.build/checks/HardwareDecoderTests
