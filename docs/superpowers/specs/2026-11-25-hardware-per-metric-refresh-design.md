# 硬件监控按指标可调刷新间隔 + 面板到点取最新样本 — 设计

2026-11-25 · 设计稿（待批准）
关联：Issue #392
关联既有规格：`docs/superpowers/specs/2026-11-18-system-monitor-sampling-design.md`

## 1. 背景

- 当前只有一个「硬件数据刷新间隔」（`hardwarePanelRefreshSeconds`，1–8 秒），只并进面板采样间隔，
  不能按指标分别设置。
- #392：把间隔调慢后，详情页「高占用应用」列表仍按 1–2 秒刷新；且当菜单栏/Dock 图标也在用同一
  指标时，面板会跟着图标的快节奏更新。
- **关键：这不是设计本意。** 2026-11-18 采样规格已写明：“硬件图标独立提出自己的目标间隔……按最快
  的有效需求安排下一次物理读取……**面板到点取最近样本**”“CPU 图标每 2 秒、面板设 5 秒时，面板
  到点取最近样本”。但实现只做了「面板档位并入物理间隔、按 min 合并」，漏掉了面板侧的「到点取最近
  样本」节流。因此 #392 描述的现象是实现缺口。

本设计：把单一档位拆成按指标分组可调，并补齐面板侧「到点取最近样本」的节流（Approach A）。

## 2. 目标 / 非目标

目标
- 六个指标分组各自一个可调刷新间隔：CPU 占用 / GPU 占用 / 内存 / 网络 / 温度 / 磁盘读写。
- 面板（概览卡片、详情实时数字、后台历史记录）按各分组节奏刷新；菜单栏/Dock 图标保持自己的快节奏。
- 每个指标仍只物理采样一次，所有消费者共享，绝不重复读硬件。
- 高占用应用列表用一个**单独的「高占用应用刷新间隔」**（一个值管所有列表），与面板卡片节奏解耦
  ——它是独立、较贵的 `top` 读取，是真正省 CPU 的地方。

非目标
- 不做第二套采样器 / 面板独立再读一遍硬件。
- 不改菜单栏 / Dock 图标的既有节奏。
- 不改变详情曲线的历史密度（节流只作用于「当前实时值」的展示，不抽稀历史缓冲）。

## 3. 方案（Approach A：面板侧轻量投影 + 共享采样）

1. 物理采样不变：`HardwareMetricsService` 仍按「所有活跃消费者里最快的有效需求」安排下一次读取
   （现有 min 合并），一个指标一份样本，图标/面板/历史共享。
2. 面板侧新增轻量投影对象 `PanelHardwareDisplay`（`@MainActor`, `ObservableObject`）：
   - 订阅 `store.hardwareMetrics.observable.snapshotPublisher`。
   - 内部保存一份 `displayed: HardwareMetricsSnapshot`。每来一个实时样本，**逐分组**判断是否“到点”：
     距该分组上次采纳 ≥ 该分组设置秒数，才把这一组的最新值并入 `displayed`；否则保留旧值。
   - 事件驱动，**不新增定时器/轮询**；首帧立即采纳，保证打开即有值。
   - 暴露面板需要的派生访问（`snapshot`、`summarySnapshot`、`historyRowsForDetail` 等）：
     实时值来自 `displayed`；历史曲线（`historyRowsForDetail`）直接透传实时 observable，保持稠密。
   - 生命周期归属面板会话：面板停止 / 关闭即取消订阅并释放（owner + 停止路径，符合低功耗约束）。
3. 面板视图改读投影对象；图标路径（`snapshotPublisher` + `resolveInputs` 里的 `snapshot`）继续读实时
   快照，完全不受影响。预览网格等非面板场景继续用实时 observable（或由实时源种一个投影）。
4. 当某指标只被面板消费（无图标引用）时，物理采样仍按该分组设置慢采，真省读取；被图标引用时物理
   采样维持图标节奏，面板靠上面的投影按设置节奏展示——两者兼得，且始终一份采样。

## 4. 设置与数据

分组、默认（其最快下限）、范围：

| 分组 | 指标 | 默认 | 范围 | 设置键 |
| --- | --- | --- | --- | --- |
| CPU 占用 | cpuUsage | 2 s | 2–8 | hardwareCPUUsageRefreshSeconds |
| GPU 占用 | gpuUsage | 2 s | 2–8 | hardwareGPUUsageRefreshSeconds |
| 内存 | memoryUsage, memoryPressure | 2 s | 2–8 | hardwareMemoryRefreshSeconds |
| 网络 | networkDownload, networkUpload | 1 s | 1–8 | hardwareNetworkRefreshSeconds |
| 温度 | cpuTemperature, gpuTemperature, batteryTemperature, fanRPM | 4 s | 4–8 | hardwareTemperatureRefreshSeconds |
| 磁盘 | diskRead, diskWrite | 1 s | 1–8 | hardwareDiskRefreshSeconds |
| 高占用应用列表 | （所有列表共用一个值） | 4 s | 1–30 | hardwareTopAppsRefreshSeconds |

`volume` / `wifiSignal` / `batteryLevel` 不走硬件采样器，不纳入。

「高占用应用刷新间隔」这一行下方需要一条说明文案（footnote）：内存列表受自身 6 秒下限限制，
实际不会快于 6 秒。文案要进本地化（12 种语言），与现有设置说明一致风格。

- 6 个 `@Published var Int`，持久化、按各自范围校验、写 UserDefaults。
- 加进 `SettingsPreferenceCatalog`（默认 / 读取 / 校验 / 写入），导出导入往返，补
  `SettingsPreferenceCatalogTests`。
- 迁移：读旧 `hardwarePanelRefreshSeconds`，若其值大于某组默认，用它初始化该组；旧键仅作迁移来源，
  UI 与 catalog 不再使用。
- 提供 `SettingsStore.hardwareRefreshSeconds(for group) -> Int` 与
  `hardwareRefreshIntervalsByMetricID -> [HardwareMetricID: TimeInterval]` 之类的映射给服务层。

## 5. 服务与视图改动

- `HardwareMetricsService`：`panelIntervalSeconds: TimeInterval` → 按分组的面板节奏；
  `backgroundIntervalSeconds` 同样按分组；`interval(for:)` 里 `.panel` / `.background` 取对应分组值
  （仍与图标需求 min 合并，物理采样一份）。
- `TopAppsService`：保留现有的单个 `minimumIntervalSeconds`，改由新的
  `hardwareTopAppsRefreshSeconds` 驱动；循环仍取 `max(每指标默认, 该值)`（内存不会因此快于 6 s）。
  与指标分组的面板节奏完全解耦。
- `StatusPanelViewModel` / `HardwareBackgroundDemandController`：把设置映射注入服务；面板停止/关闭取消
  投影订阅。
- 新增 `PanelHardwareDisplay`；面板概览/详情视图改读它。
- UI：「设置 → 监控 → 采样」把单个「硬件数据刷新间隔」替换为 6 行选择器，并新增「高占用应用
  刷新间隔」行；该行下方带一条 footnote 说明「内存列表受自身 6 秒下限限制，实际不会更快」。

## 6. 测试

- 设置：6 项默认值、范围校验、旧值迁移、catalog 往返。
- `PanelHardwareDisplay`：喂可控时钟的一串快照，断言各分组按自己节奏采纳、互不串台、首帧立即、停止后不再更新。
- `HardwareMetricsService`：面板/后台按分组生效；图标需求不被面板拖慢；面板独占指标按分组慢采。
- `TopAppsService`：按「高占用应用刷新间隔」调慢、不加速；与面板分组设置互不影响。
- 面板需求注入：设置改动即时生效；关闭面板停止投影。

## 7. 验收（沿用既有规格 + #392）

- 用可控时钟和计数验证：同一个 CPU 样本同时供菜单栏、Dock、面板和历史消费；CPU 图标 2 秒需求不加速
  只属于面板的磁盘 I/O；面板设 8 秒时，详情/概览按 8 秒展示，但物理读取仍只一份。
- 调高/调低各项间隔后，对应面板区块与高占用列表按新节奏；图标变化仍及时。
- 默认值下行为与现状一致（不改设置听感不变）。
- 项目 full 验证 + 相关渲染/面板测试。

## 8. 风险与权衡

- 面板视图数据源从实时 observable 换成投影对象：机械替换，注意预览网格等非面板场景仍用实时源。
- “到点取最近样本”会带来最多一个采样周期的显示延迟——这是刻意取舍，符合既有规格。
- 不为面板重复采样，因此被图标引用的指标物理读取次数不变；只有面板独占指标与高占用列表真正降读取。

## 9. 实现备注（设计侧取舍，供实现参考）

- 把 `HardwareMonitorObservable.summarySnapshot(at:)` 的派生逻辑提成纯函数，投影与实时 observable 复用。
- `PanelHardwareDisplay` 持有一个实时 `HardwareMonitorObservable` 引用用于 `historyRowsForDetail` 透传；
  曲线/历史不改稠密度。`HardwareDetailHistoryStore.start` 接受投影提供的实时历史源。
- 非面板场景（`MenuBarIconPreviewGrid` 等预览）继续用实时 observable，不换投影。
- 投影注入可注入时钟（默认 `Date()`），便于用可控时钟做单测。
- 投影仅在面板会话存在时订阅；`stop()`/关闭面板取消订阅，避免空转。

