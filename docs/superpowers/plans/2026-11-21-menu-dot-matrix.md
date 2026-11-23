# 菜单栏点阵与指标配置实现计划

**目标：** 将已选 B 方案接入原生状态栏，瞬时值竖向六格、历史值横向十五列；用户逐项添加、移除、排序和选择显示类型。

**架构：** MonitorCore 承担指标目录、模式独立的选项持久化、旧配置迁移、固定时间分箱和状态判定。AppKit 渲染器只绘制点阵；SwiftUI 设置按具体读数管理选项。所有指标都可移除，空配置保留一个无数据的应用入口。

**技术栈：** Swift、AppKit、SwiftUI，现有本地采集器；无需新增依赖。

## 文件与职责
- `Sources/MonitorCore/MenuMetrics.swift`：稳定指标身份、可选目录、满格参考值、历史分箱、语义状态。
- `Sources/MonitorCore/Preferences.swift`：合并 / 独立模式分别保存指标列表，迁移旧模块选择。
- `Sources/SystemMonitor/MenuBarRenderer.swift`：与 B 样例一致的六格点阵、间距、深浅颜色和不可用状态。
- `Sources/SystemMonitor/MenuBarController.swift`：按指标创建入口，更新图片、悬停详情和右键菜单。
- `Sources/SystemMonitor/SettingsView.swift`：单项添加、移除、排序，选择瞬时 / 历史，调整无自然上限指标的满格参考。
- `Tests/MonitorCoreTests/main.swift`、`scripts/test.sh`：迁移、空选择、模式隔离、分箱与缺口、压力 / 容量颜色测试。
- `scripts/render-menu-preview.swift`：使用真实渲染器生成深浅外观验收图。

## 执行步骤
- [x] 先添加失败断言：指标可单独删除并持久化，旧网络模块拆成上下行，历史固定 0–100% 且缺测为空。
- [x] `./scripts/test.sh` 确认新 API 缺失；实现指标目录、迁移、分箱和状态，重跑全部核心检查。
- [x] 实现点阵渲染与控制器，移除状态栏数字与折线。CPU / GPU 默认历史，其他默认瞬时；默认不增加 GPU 和温度。
- [x] 设置改为已选列表和按模块分组的添加菜单，每个读数可单独操作。提供预览和满格说明。
- [x] 用生产渲染器生成并查看深浅外观、空配置、不可用和多指标样例。
- [x] 构建签名应用、运行核心与 C 检查、审查 diff，实际启动验证设置操作和模式切换。

## 验收约定
- 历史窗口 60 秒，15 列 × 6 格，固定参考上限；缺测 / 暂停 / 睡眠留空，不制造零值或跨缺口连线。
- 点阵填充表示比例，整块颜色表示状态。内存依据系统压力；其他指标依据各自参考，颜色带滞回以抑制抖动。
- 网速统一为点列，可分别删减下载与上传；不是链路利用率，设置和悬停明确显示可调的满格参考值。
- 两种模式单独记住顺序与呈现方式，隐藏菜单栏指标不停止详情采集。

## 最终验证记录

- `zsh scripts/test.sh`：55 项核心检查通过，C decoder 0 failures。
- `zsh scripts/test-menu-app.sh --build-only` 后在正常桌面上下文执行 `.build/checks/MonitorMenuChecks`：16 项原生 AppKit 集成检查通过。用独立 UserDefaults suite，未改用户指标选择。
- `zsh scripts/render-menu-preview.sh`：生产渲染器生成深浅外观验收图，已目视检查。
- Release 构建及本机签名验证通过。
- 独立代码审查发现的旧数值样式迁移、状态无障碍文本问题均已修复并复核。
- 当前 CUA 服务无法识别此次构建的窗口（cgWindowNotFound）。应用内日志确认窗口创建且可见，主线程正常；完整桌面点击与独立项物理排序的目视验收尚未完成。NSView 的 cacheDisplay 不完整捕获 SwiftUI 合成内容，因此不将该截图作为外观通过证据。
