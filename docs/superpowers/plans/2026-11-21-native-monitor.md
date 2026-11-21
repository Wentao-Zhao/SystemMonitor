# 原生系统监控实现计划

> 按 subagent-driven-development 执行硬件采集子任务，并由主代理集成；先核对规格，再进行代码质量审查。使用现有新建仓库的 feature/native-monitor 分支，避免改动其他 Mac 工具。用户已批准设计并授权继续实现，不重复请求实现许可。

**目标：** 在当前 M1 Pro 上交付可运行的原生菜单栏监控应用和 DMG，默认合并，支持独立模式与全部约定指标。

**架构：** MonitorCore 维护状态、差分与偏好；SystemCollectors 采集数据；HardwareBridge 封装必要的 IOKit/IOReport 调用；SwiftUI 和 AppKit 呈现同一快照。硬件实现独立编写，不复制第三方实现。

**技术栈：** Swift 6 工具链、Swift 5 语言模式、SwiftUI、AppKit、Mach、IOKit、CoreFoundation、ServiceManagement、Swift Package Manager。

## 文件职责

- `Sources/MonitorCore/Models.swift`：模块、指标、快照、硬件传感器 DTO。
- `Sources/MonitorCore/Sampling.swift`：计数差分、15 分钟历史、断点、唤醒重置。
- `Sources/MonitorCore/Preferences.swift`：两种模式偏好、显隐、排序、刷新间隔。
- `Sources/HardwareBridge/include/HardwareBridge.h`、`Sources/HardwareBridge/HardwareBridge.c`：只读 SMC 与动态 IOReport 桥接。
- `Sources/SystemCollectors/HardwareCollector.swift`：GPU、传感器、功耗及实际失败状态。
- `Sources/SystemCollectors/BasicCollector.swift`：CPU、内存、磁盘、网卡。
- `Sources/SystemMonitor/MonitoringStore.swift`：后台采集、历史、休眠和暂停。
- `Sources/SystemMonitor/MenuBarController.swift`：合并/独立状态项与弹窗。
- `Sources/SystemMonitor/MonitorViews.swift`：概览、模块详情和曲线。
- `Sources/SystemMonitor/SettingsView.swift`：设置、持久化、开机启动。
- `Sources/SystemMonitor/SystemMonitorApp.swift`：应用入口与生命周期。
- `Sources/MonitorProbe/main.swift`：真实数据与资源占用诊断 CLI，复用正式采集器。
- `Tests/MonitorCoreTests/main.swift`：纯逻辑回归测试执行器。
- `Resources/Info.plist`、`scripts/package-app.sh`、`scripts/package-dmg.sh`：原生应用及 DMG。
- `README.md`：安装、指标口径、实际支持情况和构建。

## 任务 1：基础模型与回归测试

- [x] 先写 `Tests/MonitorCoreTests/main.swift`，针对首次采样、速率、回退、唤醒重置、历史缺口与偏好不为空编写断言。
- [x] 用最小占位实现运行 `swift run --disable-sandbox MonitorCoreTests`，观察断言失败。
- [x] 实现模型、差分、历史及配置归一化，再运行同一命令，要求所有断言通过。

关键接口：

```swift
public struct CounterRate {
    public mutating func sample(total: UInt64, time: Double) -> Double?
    public mutating func reset()
}
public struct HardwareSensor { public let id: String; public let title: String; public let value: Double; public let unit: String }
public struct HardwareSample { public var gpu: Double?; public var gpuName: String; public var sensors: [HardwareSensor]; public var powers: [HardwareSensor]; public var errors: [String] }
```

## 任务 2：硬件采集与实机探测

- [x] 独立子任务实现 HardwareBridge 和 HardwareCollector。`HardwareCollector.sample() -> HardwareSample`，`reset()` 重建功耗基线。探测过程不改变风扇，不使用特权助手，不调用 sudo。
- [x] CPU/GPU 温度通过发现到的 SMC 热区读取；风扇 RPM 用 SMC；功耗用 IOReport 能量差分或有实际功耗单位的 SMC 数据，不能制造整机值。
- [x] GPU 设备忙碌率从 IOAccelerator PerformanceStatistics 读取，使用驱动 model 字段作为名称。
- [x] 运行 MonitorProbe，至少两个采样，确认温度、RPM、CPU/GPU 功耗及 GPU 使用率是否实际可用；记录缺口。缺口不阻止基础模块继续开发，但不能宣称完成全部替代。

## 任务 3：基础采集

- [x] Mach 读取逐核 ticks、VM 页统计；sysctl 读取物理内存和交换空间。CPU 用差分，已用内存明确口径。
- [x] getifaddrs 与接口计数差分获得网速，以路由信息选默认网卡；单接口会话累计，切换重置。
- [x] 挂载卷容量与 IOMedia/块设备统计分别读取，容量每 30 秒刷新，不重复累加 APFS 卷。
- [x] MonitorProbe 验证两个采样间能形成有效 CPU、网速与 I/O。

## 任务 4：状态存储与 UI

- [x] MonitoringStore 唯一持有采集器；后台串行采集，主线程发布。以 generation 排除暂停和设备切换前的过期回调。
- [x] 默认 2 秒，支持 1/2/5 秒；硬件不快于 2 秒。休眠停止，唤醒重建基线，历史按实际时间留空。
- [x] AppKit 负责单个/多个状态项；偏好切换不重启采集器。SwiftUI 绘制概览、模块详情、1/5/15 分钟曲线和清楚的不可用状态。
- [x] 设置包含模块显隐/排序/样式/网卡/磁盘/刷新/开机启动。偏好用 UserDefaults 编码保存；所有模块关闭时保留入口。
- [x] 构建后用桌面工具验证默认合并、展开、模块详情、设置、独立模式和重启恢复。

## 任务 5：验收、审查与打包

- [x] 运行 `swift run --disable-sandbox MonitorCoreTests` 和 release 构建；修复所有失败。
- [ ] 完成与 iStat Menus 同步的统计口径对照及关闭面板下长期资源基准。已完成十分钟 301 次采集、短时资源观察；详情见 `docs/2026-11-21-validation.md`。
- [x] 规格审查后进行代码质量审查，修复影响正确性的问题。
- [x] `zsh scripts/package-app.sh` 产出 app；`zsh scripts/package-dmg.sh` 产出 DMG，验证 codesign、DMG 可读性和 SHA-256。
- [x] README 准确记录支持范围、安装、构建、指标口径及已知限制。交付时区分已验证的行为与未完成的验收。

## 当前交付状态

0.1.0 开发预览已实现、审查并打包。CPU 分项功耗受当前系统冻结计数限制，完整替代验收仍有缺口。已知边界、真实 UI 检查范围及未完成验收在 `docs/2026-11-21-validation.md` 中明确记录。
