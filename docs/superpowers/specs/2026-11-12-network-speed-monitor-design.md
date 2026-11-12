# 系统监控 · 网速（上传/下载）设计

日期：2026-11-12
范围：把「上传网速 / 下载网速」作为两个硬件监控指标并入现有硬件监控管线，并支持自定义宽带上限（Mbps）。
状态：待确认

## 意图与为什么

用户在「系统监控」外环与状态面板卡片里需要看实时网速，分下载与上传两条；因为不同宽带档位差别很大，圆弧进度需要用「当前宽带上限」来换算，所以允许用户自定义下载/上传上限。显示按 MB/s，并按用量自动在 KB/s 与 MB/s 之间切换。

## 目标

- 新增两个指标：**下载网速**、**上传网速**（内部以 bytes/s 采样）。
- 纳入现有 `HardwareSampler → HardwareMetricsService → HardwareMonitorMetric` 按需采样链路；只在使用时采样（低功耗约定）。
- 卡片显示两个新 tile（下箭头/上箭头），数值自动 KB/s ↔ MB/s。
- 外环单环/双环都可选这两个指标（双环天然左下载、右上传）。
- 可配置 **下载上限 / 上传上限**（Mbps，默认 1000 / 100），用于圆弧进度 = `bytesPerSec × 8 / 1e6 ÷ capMbps`，clamp 0…1；上限 ≤0 时只显示数值、不画进度。
- macOS 13+，复用现有设置组件与渲染器。

## 非目标 / 反目标

- 不做「总流量/累计用量/历史曲线」。
- 不做按进程统计网速。
- 不为网速套用温度那种「警告/严重危险阈值」（速度没有危险值语义）。
- 不引入第三方依赖或后台常驻轮询；仍由 Demand 驱动。

## 约束与实现取值

- **采样来源**：`sysctl(NET_RT_IFLIST2)` 读 `if_msghdr2.ifm_data` 的累计 `ifi_ibytes/ifi_obytes`（64 位，避免回绕），按相邻采样差分 ÷ 时间。缺一次采样→`collecting`；接口消失→`temporarilyUnavailable`。
- **接口范围**：只累加物理接口（名字前缀 `en`）且 UP、非回环；排除 `lo0/utun/tun/ppp/awdl/llw`，避免 VPN/点对点重复计数。若某机无 `en*`，回退为「所有非回环 AF_LINK 接口」。
- **采样节奏**：网速需要及时性，`HardwareMetricFamily` 新增 `.network`，轮询间隔 **1s**（现有 usage 2s / sensors 4s；requested 取最小）。
- **单位**：内部 `bytesPerSecond`；新增 `HardwareMetricUnit.bytesPerSecond`。
  - 卡片/tooltip 文案：< 1 MB/s 显示 `KB/s`（取整），≥ 1 MB/s 显示 `MB/s`（1 位小数）。
  - 外环顶部数值空间有限：用紧凑串 `456K` / `12.3M`（不带单位后缀）。
- **上限存储**：`SettingsStore` 两个 `@Published` Double（`hardwareDownloadCapMbps`、`hardwareUploadCapMbps`，默认 1000 / 100，范围 1…100000，持久化 + 传设置导入需评估）。
- **默认启用**：两个新指标加入 `HardwareMonitorMetric.allCases` 与「监控」tab 的开关/排序（默认开启，用户可关）。卡片因此可能到 8 个 tile（4 行）——沿用现有 `height(for:)` 自适应。

## 考虑过的做法

- **A（采用）并入现有 HardwareMetricsService 管线**：复用需求/低功耗/设置，代价是改枚举、采样、卡片、外环、设置多处。
- B 独立 NetworkMonitor 旁路：隔离但重复采样/低功耗管理，割裂「系统监控是一个数据源」，不推荐。
- C 用 `getifaddrs`（32 位计数）：实现简单但会回绕、精度差，不推荐。

## 具体改动点（按现有架构）

1. `Monitoring/HardwareMetricsModels.swift`
   - `HardwareMetricID` 加 `.networkDownload` / `.networkUpload`；`HardwareMetricUnit` 加 `.bytesPerSecond`；`HardwareMetricFamily` 加 `.network`；`unit(for:)` 与 `requested(from:)` 补分支。
   - `HardwareMetricsSnapshot` 加 `networkDownload/networkUpload` 便捷访问。
2. 新增 `Monitoring/NetworkThroughputReader.swift`：维护上次计数与时间，返回 `(downloadBps, uploadBps)`；提供纯解析函数（可单测：给定两次 iflist2 计数与时间 → 速率）。
3. `Monitoring/HardwareSampler.swift`：加 `networkReader` 与 `networkProvider`，`collect`/`map` 处理这两个 id。
4. `Monitoring/HardwareMetricsService.swift`：`interval(for:)` `.network → 1`。
5. `Models/HardwareMonitorMetric.swift`：加 `.downloadSpeed/.uploadSpeed`（titleKey、systemImage=`arrow.down`/`arrow.up`、metricID）。
6. `UI/HardwareMonitorCardView.swift`：`HardwareMonitorTile` 加 `.download/.upload`；`make` 支持 bytesPerSecond 文案；进度用 Mbps/上限（上限经传入的 caps）。
7. `Monitoring/MetricProgressMapper.swift`：`speed(sample, capMbps)`。
8. `Presentation/Icon/Behavior/HardwareRingMapper.swift`：`progress` 支持 speed（用 caps）；`formattedValue` 支持 bytesPerSecond（紧凑 K/M）。
9. `IconSourceSnapshot`/`AppEnvironment` 投影：把 `hardwareDownloadCapMbps/UploadCapMbps` 传入解析（类似 hardwareMetricColors）。
10. `Settings/SettingsStore.swift`：两个上限属性 + 持久化 + clamp。
11. `UI/Settings/HardwareMonitorSectionView.swift`：8 指标开关/排序沿用现有；可选在网速行显示单位提示。
12. `UI/Settings/AppIconRingView.swift` 高级设置：当外环引用网速指标时，显示「下载上限(Mbps)」「上传上限(Mbps)」数值行（Stepper），不显示警告/严重阈值；温度等保持原样。
13. 本地化：新指标名、上限标签/说明、卡片/无障碍文案，12 语言补齐（含单位 KB/s、MB/s）。
14. 测试：解析器差分/回绕、`MetricProgressMapper.speed`、mapper 进度与紧凑格式、设置 clamp/持久化、card tile 文案、外环选 speed 的集成解析、12 语言 key 一致性。

## 验证

- 聚焦：`bash scripts/test.sh 'NetworkThroughput|HardwareMonitor|HardwareRing|SettingsStore'`。
- 交付：`bash scripts/verify-local.sh full`（涉及新采样器、状态、渲染、设置 → full）。
- 手动：`scripts/build-worktree.sh debug open`，系统监控开到双环（左下载右上传），跑一次下载观察 KB/s→MB/s 切换与圆弧随上限变化。

## 留给实现者的判断

- 接口过滤用 `en*` 前缀（排除 VPN/awdl）；如遇特殊机型无 `en*` 再回退。
- 网速默认上限 1000/100 Mbps、范围 1…100000。
- 卡片 8 tile 的默认布局沿用现有两列自适应，不额外分页。
- 采样 1s 仅在网速被请求时生效；其它指标节奏不变。
