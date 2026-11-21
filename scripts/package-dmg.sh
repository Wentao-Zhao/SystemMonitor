#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ ! -x dist/SystemMonitor.app/Contents/MacOS/SystemMonitor ]]; then
    zsh scripts/package-app.sh
fi
stage_dir="$project_dir/dist/dmg-stage"
mkdir -p "$stage_dir"
ditto dist/SystemMonitor.app "$stage_dir/SystemMonitor.app"
if [[ ! -L "$stage_dir/Applications" ]]; then ln -s /Applications "$stage_dir/Applications"; fi
cat > "$stage_dir/安装说明.txt" <<'TEXT'
SystemMonitor 0.1.0

将 SystemMonitor.app 拖入 Applications 后启动，应用显示在菜单栏。
左键打开监控，右键进入设置或退出。默认合并显示，可在设置改为独立显示。

此开发预览使用本机临时签名，尚未经过 Developer ID 公证。
如 macOS 阻止打开，可在系统设置 > 隐私与安全性中查看对应提示。
当前优先验证 Apple M1 Pro；CPU 分项功耗在当前系统上不可用，整机和 GPU 功耗可读。
TEXT
hdiutil create -volname SystemMonitor -srcfolder "$stage_dir" -ov -format UDZO "$project_dir/dist/SystemMonitor-0.1.0.dmg"
shasum -a 256 dist/SystemMonitor-0.1.0.dmg > dist/SystemMonitor-0.1.0.dmg.sha256
printf '%s\n' "$project_dir/dist/SystemMonitor-0.1.0.dmg"
