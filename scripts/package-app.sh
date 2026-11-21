#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
build_args=(--disable-sandbox --cache-path .build/swift-cache --config-path .build/swift-config --security-path .build/swift-security -c release -debug-info-format none)
swift build "${build_args[@]}" --product SystemMonitor
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app_dir="$project_dir/dist/SystemMonitor.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/.build/AppIcon.iconset"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/generate-icon.swift "$project_dir/.build/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns"
install -m 755 "$binary_dir/SystemMonitor" "$app_dir/Contents/MacOS/SystemMonitor"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier local.wentao.SystemMonitor "$app_dir"
codesign --verify --strict "$app_dir"
touch "$app_dir"
printf '%s\n' "$app_dir"
