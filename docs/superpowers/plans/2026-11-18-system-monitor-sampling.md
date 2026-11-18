# 系统监控共享采样与后台历史实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标**　硬件监控启用后默认在关面板时保留最近 60 秒的曲线数据，菜单栏、Dock、面板和历史共享同一次整机 CPU 采样。

**架构**　沿用 HardwareMetricsService 与串行 HardwareSampler。各使用方提出所需指标和间隔，服务按指标计算到期时间，分别交付图标、面板和历史数据。Top 5 继续使用独立的 TopAppsService。

**技术栈**　Swift、AppKit、SwiftUI、Combine、XCTest、Swift Testing。

**设计稿**　[系统监控采样、刷新与历史设计](../specs/2026-11-18-system-monitor-sampling-design.md)。后台记录默认开启，首发采用新字段。

## 全局约束

- 工作目录为 /Users/lingsmbp/Documents/aiwork/status-trio-detail-pages，分支为 feat/system-monitor-detail-pages。计划依据 41c38b0e，共同祖先为 ded7693a99e00c4bf8b17d01d4b5379cc712134f。执行前核对该分支和工作区。交付前 fetch 最新 origin/main 并记录差异。
- 支持 macOS 13 起。执行前读 [性能规则](../../../.agents/rules/performance.md)、[渲染规则](../../../.agents/rules/rendering.md)、[兼容性规则](../../../.agents/rules/macos-compatibility.md) 和 [项目规则](../../../AGENTS.md)。菜单栏和 Dock 使用同一共享场景和设置。通用状态兜底周期保持原行为。
- 「面板刷新」保留 1–8 秒，默认 1 秒。「后台记录历史」默认开启，沿用面板档位。设置目录使用新布尔字段。旧未发布秒数字段直接退役。
- 面板及后台历史的常规间隔取档位与指标基础间隔的较大值。整机占用 2 秒，速率 1 秒，温度、风扇、CPU 估算频率、Swap 和压力 4 秒。SSD 容量进页首读后每 15 秒。Top 5 的 CPU、GPU、网络为 2 秒，内存为 6 秒。
- 历史仅驻内存，窗口 60 秒。正常档位切换保持连续性，休眠、停采、读失败和基线重建留下缺口。禁用模块终止额外读取并清历史。差分首个周期只建基线。
- 任务 1–5 按顺序执行。每个任务先添加可运行的失败断言，记录预期失败原因，实现后执行同一条命令并提交该任务。最终使用任务 6 验收。常规测试采用默认的离屏行为。

## 文件职责

以下名字及路径用于实施定位。

- Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift 拥有共享读数、需求生命周期、调度和投影。新增同目录 HardwareSamplingSchedule.swift 负责间隔计算和到期时间，HardwareMetricHistory.swift 负责时间序列与缺口。
- Sources/StatusTrioCore/Monitoring/{HardwareSampler,HardwareMetricsModels,HardwareDetailReadings,MemoryReader,NetworkThroughputReader,DiskCapacityReader}.swift 负责物理读取、共享结果和详情字段。TopAppsService.swift 在相同目录独立调度应用排行。
- Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift 根据可见入口、路由和设置提交需求。UI/{StatusPopoverView,HardwareMonitorSummaryView,MenuBarIconPreviewGrid,HardwareDetailView,HardwareDetailHistoryStore,HardwareDetailHistoryChart}.swift 负责面板展示。路径以 Sources/StatusTrioCore/ 为根。
- Sources/StatusTrioCore/App/{AppEnvironment,IconSourceDemandBridge}.swift 与 Presentation/Icon/IconPresentationViewModel.swift 接共享图标投影。Store/SystemStatusStore.swift 负责休眠及退出释放。
- Sources/StatusTrioCore/Settings/{SettingsStore,SettingsPreferenceCatalog}.swift、UI/Settings/HardwareMonitorSectionView.swift、Localization/LocalizationKey.swift 和 Resources/*.lproj/Localizable.strings 负责新开关的存储和展示，路径以 Sources/StatusTrioCore/ 为根。测试位于 Tests/StatusTrioCoreTests/。

## 重点回归

1. 慢档面板与快档 CPU 图标并存时，磁盘等面板独占指标按自己的到期时间读。任务 1。
2. 睡眠或切页发生在 IOKit 读取期间时，旧详情不能回填，菜单栏和 Dock 仍可复用有效的基础读数。任务 1、2。
3. 网络详情退出后，图标仍能连续显示速率，下次进入详情重新开始会话流量统计。任务 2。
4. 面板关掉时直接进入最近一次路由，或停在 CPU 详情期间改进 GPU 详情，图表能读取已积累的历史。任务 3、4。
5. 读取失败、休眠和关停留下的缺口与正常慢档间隔可以区分，历史在长时间无新增点时仍有界。任务 3。

---

### 任务 1　按指标共享采集与独立交付

**文件**　新增 Monitoring/HardwareSamplingSchedule.swift。修改 Monitoring/HardwareMetricsService.swift、App/AppEnvironment.swift、Presentation/Icon/IconPresentationViewModel.swift。测试用 HardwareMetricsServiceTests.swift、IconPresentationViewModelTests.swift、IconSurfaceIntegrationTests.swift。

**接口**　定义 HardwareSamplingWork: Hashable, Sendable，含 .metric(HardwareMetricID)、.cpuFrequency、.memoryExtras、.diskCapacity。服务增加 replaceDemand(_ demand: Demand, intervals: [HardwareSamplingWork: Duration]) 和 replacePanelDemands(panel: [HardwareSamplingWork: Duration], background: [HardwareSamplingWork: Duration], detail: HardwareDetailKind?)。后一方法在同一个主 actor 调用原子替换面板状态。提供 `panelObservable: HardwareMonitorObservable` 与 `iconObservable: HardwareMonitorObservable`。测试在保留现有 `automaticScheduling` 和 `now` 参数的基础上注入 `monotonicNow: () -> Duration` 与 `sleepFor: @Sendable (Duration) async throws -> Void`。本任务可用转接层保持当前面板入口可运行，到任务 4 一并删除被替代的入口。

- [ ] 添加 `testSharedCPUAndIndependentPanelDeadlines`。手动推进单调时钟到 0、2、4、5、6、8、10 秒。菜单栏和 Dock 都要 CPU 2 秒，面板 CPU 和读写 5 秒。断言 CPU 物理请求点为 [0, 2, 4, 6, 8, 10]，磁盘为 [0, 5, 10]，面板在 5 秒交付 CPU 4 秒的那个样本。另测 3 秒面板档与图标网络 1 秒并存时，传感器在 4 秒到期。
- [ ] 添加 `testRateChangeReschedulesPendingWait`、`testSleepingReadCannotPublishAndDoesNotOverlap`、`testReplacingDetailKeepsSharedCPUResult`。分别验证从 8 秒改到 2 秒后重算到期，阻塞的休眠前读数归来后不发布且最大在途读取数为 1，离开的页面不接收迟到详情但仍被图标请求的 CPU 基础读数可以提交。
- [ ] 执行 `bash scripts/test.sh 'HardwareMetricsServiceTests|IconPresentationViewModelTests|IconSurfaceIntegrationTests'`，确认新增断言在旧调度下失败。先补齐测试需要的最小接口，使新增断言因行为失败而非编译失败。
- [ ] 把全局固定轮询改成到最早截止时间的一次性等待。物理读取取每项工作所有活跃请求中的最短间隔，按开始时间更新到期记录，慢读结束只补当前到期的一轮。分离投影交付时间和物理到期时间。单调时间用于到期计算，Date 用于样本时间戳。等待读数与读取任务各有取消或失效路径，用休眠和完全停机的代际拦截晚到结果，路由代际只约束详情字段。设置和需求变化后重算等待，保留仍有效的同一底层来源样本。
- [ ] 将 AppEnvironment 中的图标订阅和运行时读取都接到图标投影，保持设置预览的既有入口。按实际引用的 primary 和 fallback 指标筛选，图标放置取消时释放相应请求。图标值相同走既有场景去重与渲染缓存。添加 `testUnrelatedPanelSampleDoesNotRepublishHardwareIcon`，验证两表面同源且无关样本的发布不会触发场景更新。
- [ ] 重跑本任务过滤器，全部通过后仅提交本任务文件。

### 任务 2　拆开快慢详情字段并复用物理读取

**文件**　修改 Monitoring/{HardwareSampler,HardwareMetricsService,HardwareMetricsModels,HardwareDetailReadings,MemoryReader,NetworkThroughputReader,DiskCapacityReader}.swift。测试用 HardwareSamplerTests.swift、HardwareReaderTests.swift 和现有速率 reader 测试。

**接口**　采样器接收 read(work: Set<HardwareSamplingWork>, detail: HardwareDetailKind?, at date: Date) async -> HardwareMetricsSnapshot。给快照增加独立的 diskCapacity: DiskCapacityReading?，原有详情负载投影复用它。网络会话用 setNetworkDetailActive(_ active: Bool) 在现有串行队列更新。测试 provider 注入与生产入口走同一份到期选择逻辑。

- [ ] 添加 `testDetailExtrasDoNotRepeatSharedReaders`。断言一个 CPU 工作同时提供总量、核心和 user/system/idle，GPU 详情与温度同轮时 IOAccelerator 只读一次，单独温度到期不读 GPU 占用。内存总占用和分解共一次 VM 读取，未到期的 Swap/压力读调用数为 0。模拟仅磁盘速率到期，容量读调用数为 0。
- [ ] 添加 `testLeavingNetworkDetailKeepsThroughputBaseline`。用已知累计字节推进，关页后下一份图标速率仍按真实时间差正常计算，重新开页累计归零。设备集合变化、计数回退及休眠后的下一帧建立基线。缺失数据不写成 0。
- [ ] 运行 `bash scripts/test.sh 'HardwareSamplerTests|HardwareReaderTests|HardwareMetricsServiceTests|NetworkThroughputReader|DiskThroughputReader'`，确认失败能够定位重复读取、更新失联或重置边界。
- [ ] 按工作项调用采样器。CPU 频率、内存附加字段、SSD 容量各自带时间戳，保留各自最近的有效值。复用原有 CPU 拓扑和 GPU 结果中可顺带取得的设备名，设备或唤醒变化才重建静态缓存。SSD 容量的文件系统名随卷标识变化更新，容量本身每 15 秒更新。拆开网络会话流量与共享速率基线，详情退出只结束会话，休眠同时让共享差分基线失效。
- [ ] 重跑本任务过滤器，全部通过后仅提交本任务文件。

### 任务 3　共享 60 秒历史及缺口

**文件**　新增 Monitoring/HardwareMetricHistory.swift。修改 Monitoring/HardwareMetricsService.swift、UI/{HardwareDetailHistoryStore,HardwareDetailHistoryChart,HardwareDetailView}.swift。测试用 HardwareDetailTests.swift 与 HardwareMetricsServiceTests.swift。

**接口**　定义 HardwareMetricHistoryPoint，字段为 sampledAt: Date、value: Double、startsSegment: Bool。历史缓冲在主 actor 提供 record(_ sample: HardwareMetricSample, for id: HardwareMetricID)、markDiscontinuity(for ids: Set<HardwareMetricID>)、series(for ids: [HardwareMetricID], at now: Date) -> [[HardwareMetricHistoryPoint]] 和 clear()。服务提供 `setHistoryMetrics(_ ids: Set<HardwareMetricID>)`、`historySeries(for ids: [HardwareMetricID], at now: Date) -> [[HardwareMetricHistoryPoint]]` 和 `historyPublisher: AnyPublisher<Void, Never>`。变动写入后才发布，详情仅在可见期间订阅。

- [ ] 添加 `testFirstDetailUsesBackgroundHistoryAndIgnoresDuplicateSamples`。后台于 0、2、4 秒取得 CPU，4.5 秒进入，曲线起始包含这三个点。重复投影与过期处理不追加点。切去其他详情再回来保留原点。
- [ ] 添加 `testHistorySeparatesRealGapsFromCadenceChanges` 和 `testHistoryWindowPrunesOnReadAfterIdle`。验证慢档保持连续，网络下载失败只断受影响的序列，睡眠或停采后新点开启新段，仍在窗口内的旧点继续可见。0 秒的点在 60 秒可见，60.001 秒被过滤。
- [ ] 运行 `bash scripts/test.sh 'HardwareDetailTests|HardwareDetailSnapshotTests|HardwareMetricsServiceTests'`，确认旧页内缓冲和连线规则触发预期失败。
- [ ] 在成功合并物理读取后按指标写入历史，筛选由启用入口或当前详情拥有的曲线。关闭后台后允许现有图标对已启用入口的自然贡献。按样本时间去重，通过各序列自己的标记切断线段。详情页读取同一缓冲，保留离屏快照可注入的展示输入。读写都以当前时间裁剪窗口。在只有过期点时返回空序列。详情可见时由既有调度在样本到期或失败时触发裁剪与发布，关闭面板后无视图刷新任务。
- [ ] 重跑本任务过滤器，全部通过后仅提交本任务文件。

### 任务 4　接入后台开关与面板需求

**文件**　修改文件职责中列出的设置文件与本地化资源，以及 Presentation/Panel/StatusPanelViewModel.swift、UI/{StatusPopoverView,HardwareMonitorSummaryView,MenuBarIconPreviewGrid,HardwareDetailView}.swift、Store/SystemStatusStore.swift。测试用 HardwareMonitorPanelDemandTests.swift、HardwareMonitorSettingsTests.swift、SettingsPreferenceCatalogTests.swift、SettingsTransferTests.swift、HardwareMonitorSummaryTests.swift。

**接口**　新增 SettingsStore.hardwareBackgroundHistoryEnabled: Bool，持久化键与导出键同名，默认 true。面板用 replacePanelDemands(panel:background:detail:) 提交实时需求，用任务 3 定义的 `setHistoryMetrics(_:)` 指定允许记录的曲线。两者由同一设置与路由快照驱动。模块禁用时提供明确的清理入口。

- [ ] 编写 `testBackgroundHistoryDefaultsOnAndSharesPanelCadence`，硬件模块启用后，关面板默认请求曲线占用、网络与磁盘，无传感器、容量、排行。关闭开关后仅保留图标工作，重开面板继续记历史。改为 5 秒时后台读取随之变化。模块关闭时仍无额外需求。
- [ ] 编写 `testReachableDetailsKeepHistoryAcrossRoutes`、`testSourcesFollowBothSummarySwitchesAndSelectedItems`、`testPanelDisableAndStopReleaseDemands`。验证在 CPU、其他普通路由和关闭后恢复上次详情的情形，当前页只额外读自己的详情字段。隐藏下载、保留上传时采双向值，SSD 或磁盘 I/O 任一入口都保留磁盘双曲线，两个区都关闭且无详情时不采面板数据。关模块与停止面板释放面板及后台需求，应用退出整体释放。
- [ ] 编写 `testBackgroundHistoryPreferenceRoundTripsWithPanelCadence`。新设置默认 true，关闭后重载仍是 false，设置传输往返保留 false 和面板 5 秒。导出清单没有 hardwareBackgroundRefreshSeconds。
- [ ] 运行 `bash scripts/test.sh 'HardwareMonitorSettingsTests|HardwareMonitorPanelDemandTests|SettingsPreferenceCatalogTests|SettingsTransferTests|HardwareMonitorSummaryTests|LocalizationParityTests'`，确认旧行为触发预期失败。
- [ ] 用开关替换秒数选择器，说明文案讲清关闭面板后继续记录最近 60 秒，采集频率跟随面板。覆盖现有语言和辅助功能标签。删除旧秒数的生产字段与目录条目。复用当前路由和两组显隐设置，订阅传入 @Published 新值，确保同一次重新计算不读到旧值。归并当前可达入口和可见详情对应的历史，在概览只发布启用指标，详情路由只要求对应的实时字段。SSD 卡和详情读同一个缓存。停止主 store 时调用硬件服务停止入口。移除已被新需求入口取代的固定全套请求、整批强制刷新和旧摘要/详情接线。
- [ ] 重跑本任务过滤器，全部通过后仅提交本任务文件。

### 任务 5　降低详情排行的独立开销

**文件**　Sources/StatusTrioCore/Monitoring/TopAppsService.swift、Tests/StatusTrioCoreTests/{TopAppsServiceTests,TopAppsPanelDemandTests}.swift。

**接口**　TopAppsService.defaultInterval(for metric: TopAppMetric) -> Double 用在当前可注入的 intervalSeconds 默认值。

- [ ] 改排行测试，断言 [.cpu, .gpu, .network] 均为 2 秒、.memory 为 6 秒。首次可见立即采样，慢任务在途最多 1 个。切去概览、磁盘、关面板和休眠时停止，迟到榜单不能发布。后台历史开关不改变榜单需求。
- [ ] 执行 `bash scripts/test.sh 'TopAppsServiceTests|TopAppsPanelDemandTests'`，确认旧间隔的断言失败。
- [ ] 替换默认间隔，保留现有取消、会话代际及无重叠读取。继续按实际单调时间差计算 GPU 和网络增量。
- [ ] 重跑本任务过滤器，全部通过后仅提交本任务文件。

### 任务 6　整体验收

- [ ] 完成 `bash scripts/test.sh 'Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests'` 和 `bash scripts/verify-local.sh full`。记录 SHA、分支基点、退出状态及可见 UI 跳过项。合入前若主线变动，重新核对共享文件及受影响的验证范围。
- [ ] 按项目后台 UI 流程使用独立 Debug 实例。让后台累计一段时间后秒进 CPU，检查已有趋势。停在 CPU 后切 GPU、网络及 SSD，检查连续趋势、会话流量及容量。再验证关后台、切图标来源、改变档位和睡眠恢复。使用经核实的实际运行系统分别记录 macOS 13 与当前 macOS 测试结果。
- [ ] 用同一台机器、同一供电状态、相同采样时长比较基线 1b5acf6c 与候选构建。先稳定 15 秒，每种情形采 60 秒，记录仅基础状态图标、后台关与开、仅 CPU 图标、概览、内存详情。比较 1 秒和 5 秒面板档。已确认的测试 PID 可用 `python3 scripts/measure-memory.py --pid <PID> --seconds 60 --output <OUTPUT.json>` 记录 CPU、唤醒与内存。真实排行比较同时关注 top 等子进程的 CPU 时间。用采样调用计数验证 60 秒内 CPU 2 秒与盘速 5 秒分别约 30 和 12 次，允许首样本和窗口端点造成一次差异。
- [ ] 在 docs/verification/2026-11-18-system-monitor-sampling.md 记录机器、App 与 PID 来源、测试时长、基线对比、首帧时间、调用次数及未覆盖项。默认档后台开销偏高时，提交测量证据供用户决定档位。同机验收后再安排合并。
