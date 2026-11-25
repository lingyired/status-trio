# 硬件监控按指标可调刷新间隔 — 设计提案

状态：提案（待确认）
关联：Issue #392

## 背景

- 现在只有一个「硬件数据刷新间隔」（`hardwarePanelRefreshSeconds`，1–8 秒），
  只驱动面板采样与后台历史；高占用应用列表、菜单栏/Dock 图标各有自己的固定节奏。
- #392 反馈：把间隔调慢后，详情页底部的「高占用应用」列表仍按 1–2 秒刷新，观感矛盾。
- 用户希望：整个硬件监控按指标分开，各自可调刷新频率。

## 目标

把单一的「硬件数据刷新间隔」拆成按指标分组的独立可调间隔，覆盖：

| 分组 | 包含指标 | 默认（最快） | 可调范围 |
| --- | --- | --- | --- |
| CPU 占用 | `cpuUsage` | 2 s | 2–8 s |
| GPU 占用 | `gpuUsage` | 2 s | 2–8 s |
| 内存占用 | `memoryUsage`, `memoryPressure` | 2 s | 2–8 s |
| 网络速度 | `networkDownload`, `networkUpload` | 1 s | 1–8 s |
| 温度 | `cpuTemperature`, `gpuTemperature`, `batteryTemperature`, `fanRPM` | 4 s | 4–8 s |
| 磁盘读写 | `diskRead`, `diskWrite` | 1 s | 1–8 s |

`volume` / `wifiSignal` / `batteryLevel` 不经过硬件采样器，不纳入。

## 采样与共享（关键设计）

每个指标仍然**只物理采样一次**，由所有使用者共享，避免重复读取：

- 采样器按「所有活跃消费者里最快的需求」决定该指标的实际采样间隔（沿用现有
  `HardwareMetricsService.interval(for:)` 的 min 合并逻辑）。
- **面板侧**（摘要卡片、详情页、后台历史）按各分组设置作为该指标的面板节奏上限，
  只会比最快需求更慢，不会更快。
- **高占用应用列表**是独立服务（`top` 读取，较贵），按各分组设置作为其采样节奏，
  这是真正能省 CPU 的地方。
- **菜单栏 / Dock 图标**保持现有最快节奏，不随这些设置变慢。

### 已知行为（需明示）

一个指标只采样一份。如果菜单栏/Dock 图标正好也在用该指标，采样会被图标的较快节奏
拉着，面板在该指标上也会按图标节奏更新——即「物理只读一次、共享给所有面」的代价。
只有当面板是该指标唯一消费者（或对应图标模块关闭）时，较慢的设置才真正降低读取频率。
若要做到「图标保持快、面板严格按慢节奏（即使共用数据）」，需要额外一套面板显示抽稀
管线（不重复采样，仅按节奏过滤展示），成本更高，本提案暂不做。

## 数据与设置

- 新增 6 个 `@Published var Int`（如 `hardwareCPUUsageRefreshSeconds` …），持久化、
  按各自范围校验、写入 UserDefaults。
- 加进 `SettingsPreferenceCatalog`（默认值 / 读取 / 校验 / 写入），导出导入可往返，
  并补 `SettingsPreferenceCatalogTests`。
- 升级迁移：读旧的 `hardwarePanelRefreshSeconds`，若其值大于某组默认值，用它初始化
  该组（老用户不改则维持原值），随后该键只作迁移来源，不再有 UI。

## UI

「设置 → 监控 → 采样」组内，把单个「硬件数据刷新间隔」选择器替换为 6 行选择器
（CPU 占用 / GPU 占用 / 内存 / 网络 / 温度 / 磁盘），沿用现有行样式与 `SettingsGroup`。

## 服务改动

- `HardwareMetricsService`：`panelIntervalSeconds: TimeInterval` → 按指标/分组的
  `panelIntervals`（同样给 `backgroundIntervalSeconds` 一份分组值），`interval(for:)`
  里 `.panel` / `.background` 取对应分组值。
- `TopAppsService`：`minimumIntervalSeconds` → 按 `TopAppMetric`（cpu/gpu/network/memory）
  的映射，循环里取 `max(每指标默认, 分组设置)`。
- `StatusPanelViewModel` / `HardwareBackgroundDemandController`：把设置映射成
  按指标的字典注入服务。

## 测试

- 设置默认 / 校验 / 迁移 / catalog 往返。
- `HardwareMetricsService` 面板与后台按分组生效、图标不被拖慢。
- `TopAppsService` 各指标按分组节奏（调慢、不加速）。
- 面板需求注入：设置改动即时生效。

## 明确不做

- 不做「面板独立第二套采样」。物理采样继续一份共享。
- 不改菜单栏/Dock 图标的默认节奏。
