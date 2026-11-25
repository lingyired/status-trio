# 实施计划：硬件监控按指标可调刷新间隔 + 面板到点取最新样本

依据：`docs/superpowers/specs/2026-11-25-hardware-per-metric-refresh-design.md`（已批准）
Issue：#392

## 目标回顾

- 六个指标分组各自可调刷新间隔（CPU 占用 / GPU 占用 / 内存 / 网络 / 温度 / 磁盘）。
- 高占用应用列表一个单独间隔（默认 4s，范围 1–30s），与面板解耦；内存列表受自身 6s 下限。
- 面板按各组节奏「到点取最近样本」（新增投影对象），图标保持快节奏，物理采样仍一份共享。
- 移除旧的单一「硬件数据刷新间隔」，升级时迁移。

## 文件结构

新增
- `Sources/StatusTrioCore/Settings/HardwareRefreshGroup.swift` — 分组枚举、指标映射、默认/范围、标题 key。
- `Sources/StatusTrioCore/Presentation/Panel/PanelHardwareDisplay.swift` — 面板侧节流投影。
- 测试：`Tests/StatusTrioCoreTests/HardwareRefreshGroupTests.swift`、`PanelHardwareDisplayTests.swift`、`SettingsStoreHardwareRefreshTests.swift`。

修改
- `Sources/StatusTrioCore/Settings/SettingsStore.swift` — 7 个新设置、默认/校验、迁移、映射 helper；移除 `hardwarePanelRefreshSeconds` 使用。
- `Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift` — 移除旧项，加 7 项。
- `Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift` — 面板/后台 cadence 改为按指标的 provider。
- `Sources/StatusTrioCore/Monitoring/HardwareBackgroundDemandController.swift` — 注入后台 provider、监听新设置。
- `Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift` — 注入 provider、把 top apps 指向 `hardwareTopAppsRefreshSeconds`、持有并暴露投影。
- `Sources/StatusTrioCore/UI/StatusPopoverView.swift`、`HardwareMonitorSummaryView.swift`、`HardwareMonitorCardView.swift`、`HardwareDetailView.swift`、`HardwareDetailHistoryStore.swift` — 面板数据源换投影。
- `Sources/StatusTrioCore/UI/Settings/HardwareMonitorSectionView.swift` — 7 行选择器 + footnote。
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift` — 新 key。
- `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` — 12 种语言文案。
- 测试：`HardwareMetricsServiceTests.swift`、`SettingsPreferenceCatalogTests.swift`、`TopAppsPanelDemandTests.swift`。

## 任务

### 任务 1：HardwareRefreshGroup 枚举
Files: `Sources/StatusTrioCore/Settings/HardwareRefreshGroup.swift`（新）, `Tests/.../HardwareRefreshGroupTests.swift`（新）

- 定义 `enum HardwareRefreshGroup: String, CaseIterable, Sendable { case cpuUsage, gpuUsage, memory, network, temperature, disk }`。
- `static func group(for id: HardwareMetricID) -> HardwareRefreshGroup?`：
  cpuUsage→cpuUsage；gpuUsage→gpuUsage；memoryUsage/memoryPressure→memory；
  networkDownload/networkUpload→network；cpuTemperature/gpuTemperature/batteryTemperature/fanRPM→temperature；
  diskRead/diskWrite→disk；volume/wifiSignal/batteryLevel→nil。
- `var defaultSeconds: Int`：cpuUsage/gpuUsage/memory 2，network 1，temperature 4，disk 1。
- `var options: [Int] { Array(defaultSeconds...8) }`。
- `var titleKey: LocalizationKey`（见任务 9 定义的 key）。
- 测试：映射每个 id 到预期组；`group(for: .volume) == nil`；默认与范围。

### 任务 2：SettingsStore 六+一设置 + 迁移 + 映射
Files: `SettingsStore.swift`, `Tests/.../SettingsStoreHardwareRefreshTests.swift`（新）

- 为 6 组各加 `@Published var hardware<Group>RefreshSeconds: Int`，默认 `HardwareRefreshGroup.<case>.defaultSeconds`，didSet 校验 `options.contains`，否则回落默认，持久化；`defaultsKey` 常量成对新增（如 `hardwareCPUUsageRefreshSeconds`）。命名：`hardwareCPUUsageRefreshSeconds`、`hardwareGPUUsageRefreshSeconds`、`hardwareMemoryRefreshSeconds`、`hardwareNetworkRefreshSeconds`、`hardwareTemperatureRefreshSeconds`、`hardwareDiskRefreshSeconds`。
- 加 `@Published var hardwareTopAppsRefreshSeconds: Int`，默认 4，options `Array(1...30)`。
- `func hardwareRefreshSeconds(for group: HardwareRefreshGroup) -> Int` 返回对应属性。
- `func hardwarePanelCadence(for id: HardwareMetricID) -> TimeInterval?`：`group(for:)` 命中则返回 `TimeInterval(hardwareRefreshSeconds(for:))`，否则 nil。
- `init` 里加载各键；迁移：读旧 `hardwarePanelRefreshSecondsDefaultsKey`，若存在且大于某组默认，则用 `min(oldValue, 8)` 初始化该组（≤默认则用默认）。移除旧 `@Published var hardwarePanelRefreshSeconds` 及 `hardwarePanelRefreshOptions`/default 常量（或保留常量仅作迁移读取）。
- 测试：默认值；越界回落；迁移（旧值=6 → 各组=6，温度=max(4,6)=6；旧值=1 → 各组=默认）；映射 helper。

### 任务 3：设置导出目录
Files: `SettingsPreferenceCatalog.swift`, `SettingsPreferenceCatalogTests.swift`

- `panelPreferences`：删除 `integer("hardwarePanelRefreshSeconds", …)`，新增 7 个 `integer(...)`（key 用属性名，range 用各组 `options` 的首末；topApps 1...30）。
- 更新 `SettingsPreferenceCatalogTests` 里期望的 key 集合（第 52 行附近大列表）与往返/越界用例：去掉 `hardwarePanelRefreshSeconds`，加 7 个新 key 的默认/往返/非法回落断言。

### 任务 4：HardwareMetricsService 按指标面板/后台 cadence
Files: `HardwareMetricsService.swift`, `HardwareMetricsServiceTests.swift`

- 用 provider 替换单值：`var panelCadenceProvider: @MainActor (HardwareMetricID) -> TimeInterval = { _ in 0 }`；`var backgroundCadenceProvider: @MainActor (HardwareMetricID) -> TimeInterval = { _ in 0 }`。删除 `panelIntervalSeconds` / `backgroundIntervalSeconds`。
- `interval(for:)`：`.panel` → `panelCadenceProvider(id)`，`.background` → `backgroundCadenceProvider(id)`；`candidate = cadence > 0 ? max(base, cadence) : base` 不变（min 合并保持）。
- 更新测试：`testPanelDemandUsesConfiguredCadence`、`testBackgroundDemandUsesConfiguredCadence`、`testSharedCPUAndIndependentPanelDeadlines` 用 provider 设定（如 `service.panelCadenceProvider = { _ in 5 }`，对 network 单值；组合测试用按 id 返回）。
- 断言保留：面板 5s + 图标引用同指标 → tick 取 1s（快者）；面板独占磁盘 → 5s。

### 任务 5：注入 provider（面板 + 后台）
Files: `StatusPanelViewModel.swift`, `HardwareBackgroundDemandController.swift`

- `StatusPanelViewModel`：在初始化/`start` 设置
  `store.hardwareMetrics.panelCadenceProvider = { [settings] id in settings.hardwarePanelCadence(for: id) ?? 0 }`；
  删除 `panelIntervalSeconds = …` 与 `panelRefresh` 相关赋值。
- 其 `settings.$hardwarePanelRefreshSeconds` 订阅改为订阅 6 个新设置（`merge`/各自 sink）触发 `updateHardwareMetricsDemand()`；`panelSeconds:` 参数移除。
- `HardwareBackgroundDemandController`：`backgroundCadenceProvider = { [settings] id in settings.hardwarePanelCadence(for: id) ?? 0 }`；删除 `backgroundIntervalSeconds = …`；`triggers` 增加 6 个新设置 publisher。
- 测试：`HardwareMonitorPanelDemandTests` 里若有对旧属性引用则改；新增断言“改设置后 provider 生效”。

### 任务 6：面板投影 PanelHardwareDisplay
Files: `Presentation/Panel/PanelHardwareDisplay.swift`（新）, `Tests/.../PanelHardwareDisplayTests.swift`（新）

- `@MainActor final class PanelHardwareDisplay: ObservableObject`
  - 输入：`live: HardwareMonitorObservable`、`cadence: () -> [HardwareRefreshGroup: TimeInterval]`（或读取 SettingsStore）、`now: () -> Date`。
  - `@Published private(set) var snapshot: HardwareMetricsSnapshot`（= `displayed`）。
  - 订阅 `live.snapshotPublisher`；每事件对每个 `HardwareRefreshGroup` 判断 `now() - lastEmit[group] >= cadence[group]`（首帧立即），到点把该组所有指标的最新值从 live 快照并入 `displayed`，再发 `objectWillChange`。
  - 派生：`summarySnapshot`/`summarySnapshot(at:)` 由 `displayed` 计算（复用提成纯函数的逻辑）；`historyRowsForDetail` 直接透传 `live.historyRowsForDetail`（历史不抽稀）。
  - `func start()` / `func stop()`；`stop()` 取消订阅。仅面板会话期订阅。
- 测试：可控时钟喂快照序列，断言各组独立节奏、首帧立即、慢组不被快组带跑、`stop()` 后不再变化、历史透传。

### 任务 7：面板视图换投影
Files: `StatusPopoverView.swift`、`HardwareMonitorSummaryView.swift`、`HardwareMonitorCardView.swift`、`HardwareDetailView.swift`、`HardwareDetailHistoryStore.swift`、`StatusPanelViewModel.swift`

- `StatusPanelViewModel` 持有 `let hardwareDisplay: PanelHardwareDisplay`（依赖 `store.hardwareMetrics.observable` 与 settings cadence），`start()` 里 `hardwareDisplay.start()`，`stop()` 里 `stop()`。
- 把 `panel.hardwareMonitor`（实时 observable）在面板路径换成 `panel.hardwareDisplay`；上述视图的 `@ObservedObject var …: HardwareMonitorObservable` 改为 `PanelHardwareDisplay`（保持同名属性 `snapshot`/`summarySnapshot`/`historyRowsForDetail`）。
- `HardwareDetailHistoryStore.start(observable:)` 接受投影（内部用其 `historyRowsForDetail` 与实时源）。
- 预览网格 `MenuBarIconPreviewGrid` 继续用实时 `HardwareMonitorObservable`（不动）。
- 测试：现有面板/详情相关测试保持通过；补一个“投影接入面板”的行为测试（可用现有 PanelStoreFixture 注入 fake observable）。

### 任务 8：设置界面
Files: `HardwareMonitorSectionView.swift`

- `samplingGroup`：把单个「硬件数据刷新间隔」`SettingsRow` 换成 6 个分组选择器（标题用各组 `titleKey`），选择 binding 写对应 `store.hardware<Group>RefreshSeconds`，选项 `HardwareRefreshGroup.<case>.options`。
- 新增「高占用应用刷新间隔」行，binding 写 `store.hardwareTopAppsRefreshSeconds`，选项 `1...30`；该行下方 footnote：内存列表受自身 6 秒下限，实际不会更快（用新 LocalizationKey）。
- 复用现有 `SettingsRow`/`Picker`/`settingsMenuPickerWidth()` 样式。

### 任务 9：本地化
Files: `LocalizationKey.swift`, `Resources/*.lproj/Localizable.strings`（12 语言）

- 新 key：6 个分组标题（如 `hardware.monitor.settings.refresh.cpuUsage` 等）+ 1 个「高占用应用刷新间隔」标题 + 1 条 footnote 说明。
- `HardwareRefreshGroup.titleKey` 指向对应 key。
- 12 种语言全部补齐（至少 en / zh-Hans 手写，其余翻译）。删掉旧 `hardware.monitor.settings.panelRefresh(.description)` 若无引用（或保留不引用）。
- 跑 docs 档本地化回归过滤。

### 任务 10：高占用应用指向独立设置
Files: `StatusPanelViewModel.swift`

- 删除 `store.topApps.minimumIntervalSeconds = TimeInterval(panelRefresh)`；改为 `store.topApps.minimumIntervalSeconds = TimeInterval(settings.hardwareTopAppsRefreshSeconds)`（此属性来自上一提交的 `minimumIntervalSeconds`，语义不变：`max(每指标默认, 该值)`）。
- 订阅 `settings.$hardwareTopAppsRefreshSeconds` 触发更新。
- 更新 `TopAppsPanelDemandTests`：改为断言 top apps 间隔来自新设置而非 `hardwarePanelRefreshSeconds`。

### 任务 11：验证与交付
- `bash scripts/verify-local.sh full`（全量 Swift + Release + 原生/离线发布检查）。
- `bash scripts/build-worktree.sh release` 起开发版人工自测；告知 CFBundleName / STDevelopmentCodename。
- 通过后打 `status: needs-verification`（已加）；用户验收后合并推送并转 `status: pending-release`。

## 备注
- 频繁小提交，按任务提交。
- 默认值下行为与现状一致（不改设置听感不变）。
- 不为面板重复采样；被图标引用的指标物理读取次数不变。
