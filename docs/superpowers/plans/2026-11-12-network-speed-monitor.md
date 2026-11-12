# 系统监控 · 网速（上传/下载）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** 在「系统监控」里新增下载/上传网速两个指标（MB/s，自动 KB/s），支持自定义下载/上传上限（Mbps，默认 1000/100）驱动圆弧进度。

**Architecture:** 新采样器并入 `HardwareSampler → HardwareMetricsService → HardwareMonitorMetric` 按需管线；`sysctl NET_RT_IFLIST2` 读 64 位累计收发字节，差分算 B/s。卡片与外环复用现有渲染/格式化。

**Tech Stack:** Swift / Darwin (`sysctl`, `if_indextoname`)、SwiftUI 设置组件。

**Spec:** `docs/superpowers/specs/2026-11-12-network-speed-monitor-design.md`

## Global Constraints
- 采样只在指标被请求时进行（Demand 驱动，低功耗）；网速间隔 1s，其它不变。
- 只累加物理 `en*` 且 UP、非回环接口；排除 VPN/awdl；无 en* 时回退非回环。
- 显示：卡片 `KB/s`（<1MB/s，取整）/`MB/s`（1 位小数）；外环顶部紧凑 `456K`/`12.3M`。
- 上限：下载 1000、上传 100 Mbps，范围 1…100000，持久化。
- 网速不套用警告/严重阈值。
- macOS 13+；不改 Battery/AirPods；本地化 12 语言齐全。

## Review Focus
- 差分在首次/长间隔/计数器回绕时必须返回 collecting 或重设基线，不产出假的巨大速率。
- 关掉系统监控/卡片后必须停止采样（需求释放）。
- 网速上限 ≤0 时只显示数值、进度为空，不显示 0%。
- 卡片 8 tile 布局不破；外环双环左下载右上传正确。

---

### Task 1: 模型与采样
**Files:** `Monitoring/HardwareMetricsModels.swift`, `Monitoring/HardwareSampler.swift`, `Monitoring/HardwareMetricsService.swift`, `Monitoring/MetricProgressMapper.swift`, new `Monitoring/NetworkThroughputReader.swift`
- [ ] 1a. `HardwareMetricID` 加 `.networkDownload/.networkUpload`；`HardwareMetricUnit` 加 `.bytesPerSecond`；`HardwareMetricFamily` 加 `.network`；`unit(for:)`/`requested(from:)` 补分支；`HardwareMetricsSnapshot` 加 `networkDownload/networkUpload` 访问器。
- [ ] 1b. 新增 `NetworkThroughputReader`：`read(at:) -> NetworkReading?`；纯函数 `rates(previous:current:interval:)`；`InterfaceByteTotals` 解析 `NET_RT_IFLIST2`（en* UP 非回环，`if_indextoname` 取名）；首次/间隔≤0或>15s 或计数回退→重设基线返回 nil。
- [ ] 1c. `HardwareSampler` 加 `networkReader` 与 `networkProvider`；`collect` 计算 network；`map` 填 `networkDownload/networkUpload`（unit `.bytesPerSecond`，source 新 `.network`）。
- [ ] 1d. `HardwareMetricsService.interval(for: .networkDownload/.networkUpload) = 1`；`defaultMetricIDs` 不含网速（由需求传入）。
- [ ] 1e. `MetricProgressMapper.speed(_ sample:capMbps:) -> Double?`：`value(B/s)*8/1e6/cap`，cap<=0 → nil。
- [ ] Test: `NetworkThroughputReaderTests`（rates 差分/回绕/超时）、`MetricProgressMapperTests` 加 speed。Commit。

### Task 2: 设置与指标枚举
**Files:** `Models/HardwareMonitorMetric.swift`, `Settings/SettingsStore.swift`
- [ ] 2a. `HardwareMonitorMetric` 加 `.downloadSpeed/.uploadSpeed`（titleKey、systemImage `arrow.down`/`arrow.up`、metricID）。
- [ ] 2b. `SettingsStore` 加 `hardwareDownloadCapMbps`(1000)/`hardwareUploadCapMbps`(100)，范围 1…100000，持久化 + clamp + 载入默认。
- [ ] Test: 默认值/clamp/持久化。Commit。

### Task 3: 卡片
**Files:** `UI/HardwareMonitorCardView.swift`, `Monitoring/MetricProgressMapper.swift`(已在 1e)
- [ ] 3a. `HardwareMonitorTile` 加 `.download/.upload`（symbol arrow.down/up、labelKey）。
- [ ] 3b. `tiles(...)` 映射新 metric；`make` 支持 `.bytesPerSecond` 文案（KB/s↔MB/s 自动）；进度用 cap（新增 `caps` 入参，默认读 1000/100）。
- [ ] 3c. `StatusPopoverView`/`StatusPanelViewModel` 把 caps 传进卡片。
- [ ] Test: tile 文案 KB/s 与 MB/s、进度随 cap。Commit。

### Task 4: 外环映射
**Files:** `Presentation/Icon/Behavior/HardwareRingMapper.swift`, `Resolution/IconSourceSnapshot.swift`, `App/AppEnvironment.swift`, `Preview/IconPreviewInputBuilder.swift`
- [ ] 4a. `IconSourceSnapshot` 加 `hardwareSpeedCapsMbps: [HardwareMonitorMetric: Double]`。
- [ ] 4b. mapper `progress` 支持 speed（cap）；`formattedValue` 支持 `.bytesPerSecond`（紧凑 K/M）。
- [ ] 4c. `AppEnvironment.resolveInputs` 注入 caps；预览 builder 注入默认 caps。
- [ ] Test: 外环选 download/upload 的进度与顶部数值格式；双环左右。Commit。

### Task 5: 设置 UI
**Files:** `UI/Settings/AppIconRingView.swift`
- [ ] 5a. 「高级设置」中，当引用了 `.downloadSpeed` 显示「下载上限 (Mbps)」Stepper（1000 默认），`.uploadSpeed` 显示「上传上限 (Mbps)」；不显示警告/严重阈值行。
- [ ] 5b. 网速 metric 的行样式与现有 Stepper 一致。
- [ ] （「监控」tab 的开关/排序因 `allCases` 自动包含，无需改。）
- [ ] Test/编译。Commit。

### Task 6: 本地化
- [ ] 6a. 新 key：指标名 `hardwareMonitorDownload/Upload`、上限标签与说明、卡片 KB/s、MB/s、无障碍；12 语言补齐，通过 parity 测试。Commit。

### Task 7: 验证
- [ ] 7a. `bash scripts/verify-local.sh full`。
- [ ] 7b. `bash scripts/build-worktree.sh debug open` 手动：系统监控双环左下载右上传，下载时 KB/s→MB/s，圆弧随上限变化。
- [ ] 7c. 报告 + commit。

## Self-Review
- Spec coverage: 采样/模型(T1)、设置(T2)、卡片(T3)、外环(T4)、UI(T5)、本地化(T6)、验证(T7)。
- 风险点（Review Focus）均在 T1/T4 覆盖。
- 类型一致：`HardwareMonitorMetric` 新增两 case 需全 switch 补分支（compiler 会提示）。
