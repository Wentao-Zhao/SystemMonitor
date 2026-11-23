# 菜单栏图标未显示：运行目录与 MenuBarFold

## 复现与定位

- SystemMonitor 从工程的 `dist/SystemMonitor.app` 运行，采集和设置预览正常，但系统菜单栏没有入口。
- 系统设置中允许 SystemMonitor 在菜单栏显示；MenuBarFold 中也未勾选收起 SystemMonitor。
- 暂停 MenuBarFold 后，系统菜单栏宿主立即出现 SystemMonitor 按钮及各项读数，确认并非点阵绘制失败。
- 当前 MenuBarFold 的收纳白名单机制不能正常放行 `/Applications` 之外运行的应用；其工程 `FoldController.swift` 和 `MenuBarLocation.swift` 也明确记录了该限制。

## 处理与验证

1. 移除临时状态栏诊断代码；正式渲染器和用户指标配置未变。
2. 退出开发目录中的进程，将正式构建安装到 `/Applications/SystemMonitor.app`，验证签名并启动。
3. 恢复 MenuBarFold 原来的收纳状态。
4. 通过系统菜单栏宿主 AX 树及截图确认 SystemMonitor 点阵入口仍然显示，读数持续更新。

后续试用从 `/Applications/SystemMonitor.app` 启动；开发目录的 App 继续作为构建产物保留。
