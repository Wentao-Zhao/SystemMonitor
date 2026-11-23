# 磁盘容量口径修复

## 复现证据

用户截图的 macOS 储存空间为总量 994.66 GB、可用 339.54 GB。旧实现仅使用 `volumeAvailableCapacity`，遗漏系统可回收空间，并将磁盘字节以二进制方式显示，导致数值与系统界面不一致。

正常应用上下文的只读探针测得：

- 总容量：994662584320 字节。
- 当前空闲：约 265 GB。
- `volumeAvailableCapacityForImportantUsage`：约 339 GB。
- 启动卷与 Data 路径查询容量相同，没有重复累加 APFS 卷。
- 命令沙盒下 Important 接口会返回 0；不能以该结果证明真实可用空间为 0。

## 修复

- `DiskCapacity` 统一计算容量：有效的当前空闲与系统可用估计取较大值，并限制在总容量以内；异常、缺失或不支持的估计回退到可读的空闲容量。
- 单独查询 Important 接口，避免不支持时丢弃整个磁盘卷。
- 已用空间 = 总容量 − 可用空间；占用比例也使用这一口径。
- 磁盘容量使用十进制 GB/TB，内存继续保留原来的二进制换算。
- 详情分别展示“可用空间”和“当前空闲空间”，说明前者包含 macOS 预计可回收空间；不执行清理或删除操作。

## 验证与交付

- 先复现磁盘格式的两个回归失败，添加 APFS、缺测、沙盒零估计、无效数值等容量测试后，70 项核心检查和 C decoder 检查通过。
- 正式 `MonitorProbe` 真实采集结果可用 338.555 GB、总量 994.663 GB、已用 656.107 GB，数值相互一致。
- 更新 `/Applications/SystemMonitor.app` 并重启后，实际界面显示总量 994.66 GB、可用 339.06 GB、已用 655.6 GB、当前空闲 265.33 GB；空间随系统活动变化。
- 原应用备份位于 `.build/backups/SystemMonitor-before-disk-capacity-fix.app`，用户指标配置保留。
- 独立只读审查未发现重要阻塞，已补正缺少 free 来源时的说明文字。

参考：[Apple 容量查询说明](https://developer.apple.com/documentation/foundation/checking-volume-storage-capacity)、[Apple 磁盘可用空间说明](https://support.apple.com/en-asia/guide/disk-utility/dskutl1005/mac)。
