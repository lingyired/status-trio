# 系统监控高占用应用 Top 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 CPU、GPU、内存、网络详情页显示按应用合并后的高占用前 5 名，网络同时显示实时下载和上传速度。

**Architecture:** 沿用 Stats 的 ps / top / nettop / IOKit 采集来源，通过共享归属器先合并应用再排名。新增独立榜单服务和叶子 observable，复用现有受控命令执行器，由真实详情页可见性驱动；命令不进入硬件采样队列。

**Tech Stack:** Swift、Foundation Process、IOKit、Darwin/libproc（仅身份元数据）、AppKit 应用目录、Combine、SwiftUI、XCTest。

**Spec:** [已确认设计](../specs/2026-11-18-system-monitor-top-apps-design.md)。执行前必须同时阅读。

## Global Constraints

- macOS 13+；保持 arm64 + x86_64 构建；第一版 GPU 榜单仅在实际暴露客户端字段的 Apple Silicon 上启用，Intel 显示不可用。
- 四页统一按应用合并后排序，最多 5 行；不增加持久化设置、特权 Helper、权限弹窗或常驻榜单采样。
- CPU 为 ps `%CPU`；内存为 top MEM；GPU 为累计执行时间差；网络为累计字节差 / 实际单调时间差；不替换为其他指标。
- 默认 1 秒采样、单个在途任务；命令超时 5 秒；stdout / stderr 各沿用执行器的计数限制，榜单调用上限设为 8_388_608 字节，超限失败而不截断排行。
- 网络排序按 max(下载, 上传) 降序、min(下载, 上传) 降序、稳定身份升序；其余按占用降序、稳定身份升序。
- GPU/网络首次读取只建基线；长间隔 > 3 秒重建基线；GPU 间隔 < 250_000_000 ns 不生成值。应用 CPU/GPU 不截断到 100%。
- 只采当前可见详情页；关闭、切页、隐藏模块、睡眠、停止时清理；旧会话结果不能发布；不改变图标和现有整机指标。
- 复用 BoundedProcessInvocation，保持 250 ms kill grace / 500 ms stream grace；不为榜单另写底层 Process 状态机。
- 普通测试禁止呈现真实窗口/状态栏项；人工或 live UI 验收与单测分开记录；最终功能交付走 full 本地配置，验收前不合并推送。

## Review Focus

1. 两个安装路径不同的同名应用与嵌套 Helper：应分别归属，名称相同不能合并（Task 1）。
2. 应用启动/退出和 PID 复用发生在命令读取期间：允许跳过消失项，不可继承旧进程累计计数（Task 3、4）。
3. nettop 进程名包含点、空格、逗号及输出缺字段：保留合法名字，不误认 PID/列，结构损坏明确失败（Task 3）。
4. 快速切页且旧命令忽略取消、GPU 同步读取尚未结束：旧任务收尾前不并发再读，迟到值不回填（Task 5、6）。
5. 阿拉伯语 RTL、长应用名、CPU 240.5% 和极大内存/网速：数值与方向可读，第 5 行可滚动到达（Task 7）。

## 接手边界与文件地图

本计划只有文档，用户要求**换模型后再开始实现**。目标 worktree 为 `/Users/lingsmbp/Documents/aiwork/status-trio-detail-pages`，分支为 `feat/system-monitor-detail-pages`；设计提交 `69aa7304`，功能基线 `00b2f94d`。执行前重新核对 git status、HEAD 与本文件，不能覆盖其他会话改动。现有分支应复用，不自动另开 worktree、不切到 main。

新文件均放在 `Sources/StatusTrioCore/Monitoring/`：`TopAppModels.swift`（值与状态）、`ProcessAppResolver.swift`（归属）、`TopAppAggregator.swift`（合并排序）、`TopAppCommandReaders.swift`（CPU/内存）、`TopAppNetworkReader.swift`（网络基线）、`TopAppGPUReader.swift`（GPU 基线）、`TopAppsSampler.swift`（单一采样入口）、`TopAppsService.swift`（生命周期及 observable）。UI 新文件为 `Sources/StatusTrioCore/UI/TopAppsListView.swift`。文件可按职责进一步拆小，但跨任务签名须同步更新。

主要既有接入点：

- [BoundedProcessRunner](../../../Sources/StatusTrioCore/Monitoring/BoundedProcessRunner.swift:77)：命令执行器 init / run / runSync。
- [SystemStatusStore](../../../Sources/StatusTrioCore/Store/SystemStatusStore.swift:153)：服务所有权；init 注入在约 352 行，wake / sleep 在约 469 / 501 行，stop 在约 666 行。
- [StatusPanelViewModel](../../../Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift:997)：updateHardwareMetricsDemand 的真实可见性、activeDetailKind、panel.stop。
- [StatusPopoverView](../../../Sources/StatusTrioCore/UI/StatusPopoverView.swift:130)和 [HardwareDetailView](../../../Sources/StatusTrioCore/UI/HardwareDetailView.swift:34)：向独立列表传 observable，不订阅全局快照。
- [PanelStoreFixture](../../../Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift:1042)：测试服务注入；[ApplicationEnergyReader](../../../Sources/StatusTrioCore/Monitoring/ApplicationEnergyReader.swift:54)已有外层 app 路径归属思路，只参考或复用纯函数，不改变电池能耗监控。

## Task 1：应用身份、合并与稳定排行

**Files:** 新建 TopAppModels.swift、ProcessAppResolver.swift、TopAppAggregator.swift；新建 `Tests/StatusTrioCoreTests/TopAppAggregationTests.swift`。

**Interfaces:**

- 定义 `TopAppMetric: String, Sendable`（cpu/gpu/memory/network）；`ProcessIdentity: Hashable, Sendable`（pid: Int32, startedAt: UInt64?），startedAt 用进程启动时间，不能用本次读取时间。
- 定义 `ProcessMetadata: Sendable`（identity、name、executablePath: String?、responsiblePID: Int32?），`ProcessApplication: Sendable`（pid: Int32、path、bundleID: String?、name），均不携带 NSImage。
- 定义 `TopAppIdentity: Hashable, Sendable`（application(path: String) / process(ProcessIdentity)）、`TopAppRow: Equatable, Identifiable, Sendable`（id、name、applicationPath: String?、value: Double、upload: Double?）。网络 value 为下载 B/s，其余为百分比或内存字节。
- 定义 `ProcessUsageSample: Sendable`（metadata、value、upload）；`ProcessAppResolver.resolve(_ process: ProcessMetadata, applications: [ProcessApplication]) -> TopAppIdentity`；`TopAppAggregator.rows(metric: TopAppMetric, samples: [ProcessUsageSample], applications: [ProcessApplication], limit: Int = 5) -> [TopAppRow]`。
- 定义 `TopAppsReadResult: Sendable`（collecting / measured([TopAppRow]) / unsupported / failed），空 measured 与失败分开；observable 的状态另有 idle。

- [ ] 写 `testMergeBeforeTakingFive`：6 个单进程 app 各 9，另一个 app 的 3 个 Helper 各 4；合并榜单断言 `XCTAssertEqual(rows.first?.value, 12)`、`XCTAssertEqual(rows.count, 5)`。
- [ ] 写 `testNestedHelpersAndSameNameDifferentPaths`、`testInvalidOwnerFallsBackToPathThenProcess`：同名不同路径行数为 2、Helper 归主 app、owner 为 -1/0 时不形成公共错误分组。
- [ ] 写 `testNetworkSortUsesBusiestDirection`：下载80上传0的 app 排在下载50上传50之前；补全零、无效/负数、并列稳定排序、CLI 独立行用例。
- [ ] 运行 `bash scripts/test.sh TopAppAggregationTests`，确认新行为失败；实现上述模型和纯归属/合并函数，再运行同命令应 PASS。
- [ ] 提交这一独立单元，建议 `feat(monitor): add shared top-app aggregation`。

## Task 2：复用命令执行器并接入 CPU / 内存

**Files:** 修改 [BoundedProcessRunner](../../../Sources/StatusTrioCore/Monitoring/BoundedProcessRunner.swift)；新建 TopAppCommandReaders.swift；新建 `TopAppCommandReaderTests.swift`（测试目录同 Task 1）；按需扩充现有 BoundedProcessInvocationTests。

**Interfaces:**

- 在 BoundedProcessInvocation 的 init / run / runSync 增加 `environment: [String: String]? = nil`，默认保留旧语义，设置到 child.environment，不修改既有调用点行为。
- 定义 `TopAppCommandReading: Sendable`，`func read(_ metric: TopAppMetric) async -> Result<[ProcessUsageSample], TopAppReadError>`；仅接受 cpu/memory，其他返回明确错误。`TopAppReadError` 为 launchOrExit / malformedOutput / timedOut / cancelled / outputTooLarge / unsupported；采样入口把 unsupported 映射为 TopAppsReadResult.unsupported，其余读取错误映射为 failed，取消结果由会话门控丢弃。
- 采集用 `BoundedProcessInvocation.run(... timeout: .seconds(5), outputLimit: 8_388_608, environment: ...)`；固定 `LC_ALL=C`、`LANG=C`，合并必要的继承环境，不使用 shell。
- CPU argv 用 `["-Aceo", "pid,pcpu,comm", "-r"]`；内存用 `["-l", "1", "-o", "mem", "-stats", "pid,command,mem"]`，禁止 `-n 5`。

- [ ] 写 `testCPUParsesAllRowsAndKeeps240Point5Percent`：断言第 6+ 个 PID 仍在输入样本中，`XCTAssertEqual(sample.value, 240.5)`。
- [ ] 写 `testTopMemoryUnitsNamesAndMarkers`：`1.5G` → 1_610_612_736 字节，`512M+` → 536_870_912，覆盖 K/M/G/T、无单位、尾部减号及名字空格；不能通过失败值默认为 0。
- [ ] 写 `testInvocationReceivesFixedLocaleAndExactArguments`、`testMalformedOutputIsNotSuccessfulEmptyList`。CPU/内存解析从纯函数进入测试，不真实跑系统 top 来构造预期。
- [ ] 运行 `bash scripts/test.sh 'TopAppCommandReaderTests|BoundedProcessInvocationTests'` 确认新断言失败；实现 reader、身份元数据读取和执行器可选环境，再运行应 PASS。元数据只读取 pid/start/path/owner，不读取进程内容。
- [ ] 保留并运行 `bash scripts/test.sh 'BoundedProcessDrainTests|BoundedProcessDualStreamTests'`，确保 stdout/stderr 排空、取消、非零退出、输出超限和忽略 SIGTERM 的原有边界不回归；补一个 8 MiB 榜单限制映射断言。
- [ ] 提交，建议 `feat(monitor): read CPU and memory app usage with Stats commands`。

## Task 3：网络累计计数、真实速率与合并

**Files:** 新建 TopAppNetworkReader.swift；新建 `TopAppNetworkReaderTests.swift`。

**Interfaces:**

- `NetworkProcessCounter: Sendable`（metadata: ProcessMetadata、received: UInt64、sent: UInt64）；`NetworkAppUsageTracker` 持有 PID 身份基线，`mutating func sample(_ counters: [NetworkProcessCounter], at uptimeNanoseconds: UInt64) -> [ProcessUsageSample]?`；`mutating func reset()`。nil 表示尚无有效差值。
- `TopAppNetworkReader.read() async -> Result<[NetworkProcessCounter], TopAppReadError>`，复用 Task 2 命令执行和元数据边界；实际 argv 参考已固定 SHA 的 Stats nettop 列选择，不采用宽松的任意列位置猜测。

- [ ] 写 `testFirstSampleOnlyPrimesBaseline` 与 `testRatesUseActualTwoSecondInterval`：同一身份 2 秒内接收增加 4096、发送增加 1024，断言下载 2048、上传 512 B/s。
- [ ] 写 `testRestartCounterResetAndLongGapReprime`：PID 相同但启动时间不同、计数器回退、间隔 >3 秒、身份启动时间不可读，均不复用旧差值；新 PID 从下一有效样本计速。
- [ ] 写 `testNamesWithDotsSpacesAndQuotedCommas`、`testMissingHeaderOrCounterFails`：PID 从名字最后的 `.PID` 后缀解析，按 CSV 规则处理引号/逗号，不能用无条件 split 丢空列；只在明确识别到有效空表时返回空成功。
- [ ] 运行 `bash scripts/test.sh TopAppNetworkReaderTests` 确认失败；实现 parser/tracker，再运行应 PASS。最后将两进程网络样本交给 Task 1，断言同 app 两个方向都求和，且合并后才取 5。
- [ ] 提交，建议 `feat(monitor): calculate per-app live network rates`。

## Task 4：新版 Stats GPU 客户端时间差

**Files:** 新建 TopAppGPUReader.swift；新建 `TopAppGPUReaderTests.swift`；如复制上游代码，按仓库已有方式更新第三方声明。

**Interfaces:**

- `GPUClientCounter: Sendable`（entryID: UInt64、metadata: ProcessMetadata、gpuTime: UInt64、queueCount: Int）；`GPUAppUsageTracker.sample(_ clients: [GPUClientCounter], at uptimeNanoseconds: UInt64) -> [ProcessUsageSample]?` 与 `reset()`。
- `TopAppGPUReader.read() -> Result<[GPUClientCounter], TopAppReadError>`；硬件能力作为独立可注入值，非 arm64 返回 unsupported，不用空客户端伪装不支持。IOKit 遍历在专属 utility worker 上，不能阻塞 MainActor 或 HardwareSampler 队列。

- [ ] 固定并读取 Stats GPU 参考源码 SHA `7de898dda04945031073b22f061f5e926d96a358`，核对许可证、字段及单位；本地旧 Stats checkout 不能作为 GPU 实现来源，不修改它。
- [ ] 写 `testGpuTimeDeltaIsPercentage`：1 秒内累计时间增加 500_000_000 ns，断言 value 为 50；同 PID 多客户端先汇总，再按应用汇总。
- [ ] 写 `testGPUClientOrQueueChangeReprimes`：entryID 新增、PID/启动时间/队列数变化或 counter 回退不跨旧基线；`testTooShortOrLongSampleDoesNotSpike` 覆盖 249_999_999 ns 与 >3 秒。
- [ ] 写 `testMissingAppUsageAndUnsupportedArchitecture`，区分不支持字段、读取失败与已确认支持后的空活跃列表；检查所有 io_object 和 CF 对象释放路径。
- [ ] 运行 `bash scripts/test.sh TopAppGPUReaderTests` 确认新行为失败；实现 collector/parser/tracker，再运行应 PASS。不要夹到 100%，不要改已有 GPUReader 的整卡选择策略。
- [ ] 提交，建议 `feat(monitor): add GPU app usage from accelerator clients`。

## Task 5：独立采样入口与生命周期服务

**Files:** 新建 TopAppsSampler.swift、TopAppsService.swift；新建 `TopAppsServiceTests.swift`。

**Interfaces:**

- `TopAppsSampling: Sendable`：`func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult`、`func reset() async`。生产 `TopAppsSampler` 持有 Task 2–4 readers 与两种 tracker，串行拥有其状态；接受单调时钟、身份查询和命令执行的测试依赖。
- `@MainActor final class TopAppsObservable: ObservableObject`：`@Published private(set) var state: TopAppsState`；状态 idle / collecting(metric) / measured(metric, rows) / unsupported(metric) / failed(metric)。
- `@MainActor final class TopAppsService`：`let observable`、`setDemand(_ metric: TopAppMetric?)`、`sleep()`、`wake()`、`stop()`；init 注入 TopAppsSampling、应用目录提供器、时钟/调度器及 `automaticScheduling`。应用目录在 MainActor 读取成 Sendable 值，NSImage 不跨 actor。

- [ ] 写 `testNoDemandDoesNotRead`、`testOneSecondCadenceNeverOverlaps`：使用手动时钟/调度器和阻塞假采样器；无需求调用数为 0；在途数最大 1。
- [ ] 写 `testSwitchCancelsOldSessionAndDropsLateResult`：CPU 读悬停 → 切网络 → CPU 返回；CPU 不发布，旧物理读取完成并 reset 后才开始新读。切走立刻清空旧列表。
- [ ] 写 `testSleepReopenAndStopClearBaselines`、`testFailureDoesNotKeepNumbersAsLive`：恢复后 collecting；超时/超限/失败与 measured([]) 明确区分。
- [ ] 运行 `bash scripts/test.sh TopAppsServiceTests` 确认失败；实现需求会话、调度、任务取消和 reset 屏障，再运行应 PASS。任务取消不等于同步 IOKit 已结束，必须等待物理读取完成。
- [ ] 检查停止路径无强引用保活；使用现有 DeinitProbe 测释放，不使用 isolated deinit 或弱 let。提交 `feat(monitor): own top-app sampling by visible detail session`。

## Task 6：接入 Store、面板可见性与系统睡眠

**Files:** 修改 [SystemStatusStore](../../../Sources/StatusTrioCore/Store/SystemStatusStore.swift)、[StatusPanelViewModel](../../../Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift)、[PanelStoreFixture](../../../Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift:1042)；新建 `TopAppsPanelDemandTests.swift`。

**Interfaces:** Store 新增 `let topApps: TopAppsService` 与 init 默认注入；panel 暴露 `var topApps: TopAppsObservable { store.topApps.observable }`。在 updateHardwareMetricsDemand 用现有 detailVisible + activeDetailKind 映射 setDemand；磁盘/概览/nil → nil。panel.stop、store.stop、睡眠/唤醒调用对应服务接口。

- [ ] 写 `testOnlyVisibleHardwareDetailDemandsTopApps`：覆盖 CPU/GPU/内存/网络、磁盘、概览、关面板、隐藏硬件模块、panel.stop，断言 metric 或 nil；测试夹具必须注入假采样器，不能默认启动真实 ps/nettop。
- [ ] 写 `testBackgroundHardwareRefreshDoesNotEnableTopApps`、`testStoreSleepWakeAndStopReachService`：后台间隔设置不产生榜单读取；睡眠期间计数不增长；唤醒只恢复当前有效需求。
- [ ] 运行 `bash scripts/test.sh 'TopAppsPanelDemandTests|HardwareMonitorPanelDemandTests'` 确认新增断言失败；接入最小所有权与可见性，再运行应 PASS；补全原有 fixture 默认实例不采真实系统的边界。
- [ ] 提交 `feat(monitor): wire top-app demand to panel and system lifecycle`。不要把排行加入 StatusSnapshot、IconSourceSnapshot、HardwareMetricsSnapshot。

## Task 7：列表卡片、格式化与全语言文案

**Files:** 新建 TopAppsListView.swift；修改 [HardwareDetailView](../../../Sources/StatusTrioCore/UI/HardwareDetailView.swift)、[StatusPopoverView](../../../Sources/StatusTrioCore/UI/StatusPopoverView.swift)、[LocalizationKey](../../../Sources/StatusTrioCore/Localization/LocalizationKey.swift)以及 Resources 下现有 12 个语言目录的 Localizable.strings；新建 `TopAppsPresentationTests.swift`。

**Interfaces:** `TopAppsListView(metric: TopAppMetric, observable: TopAppsObservable)` 仅列表订阅；HardwareDetailView 新增可选 `topApps: TopAppsObservable? = nil`，保留既有离屏预览入口，nil 不采集。格式化 `TopAppFormat.percent(_ value: Double) -> String` 保留一位小数、不限 100%；内存/网速复用现有 bytes/rate 口径。图标主线程加载，按会话/应用身份限制缓存。

- [ ] 写 `testApplicationPercentIsNotClamped`：断言 240.5 → `240.5%`；`testNetworkColumnsAndStates` 断言 value 映射下载、upload 映射上传，idle/collecting/empty/unsupported/failed 文案各自正确。
- [ ] 写 `testLongNamesRTLAndLargeValuesKeepFiveRowsReachable`，用项目既有离屏布局机制验证名称截断、数值不重叠与列表高度；涉及实际窗口的测试必须用现有 VisibleUITestCase 边界，普通测试不创建窗口。
- [ ] 运行 `bash scripts/test.sh TopAppsPresentationTests` 确认新行为失败；在现有四页末尾追加卡片、接入独立 observable，实现英文/简中文案（“高占用应用”“采集中…”“暂无活跃应用”“暂不支持”“读取失败”）并翻译全部现有语言，再运行应 PASS。方向复用现有下载/上传本地化，不添加未要求的操作按钮。
- [ ] 运行 `bash scripts/test.sh 'HardwareDetailTests|HardwareDetailSnapshotTests|LocalizationTests|LocalizationParityTests'`，保留既有预览/整机显示。列表不新增嵌套滚动容器，使用面板现有滚动。
- [ ] 提交 `feat(monitor): show five high-usage apps on detail pages`。

## Task 8：集成验收与交付

**Files:** 按需修正以上任务；新建 `docs/system-monitor-top-apps-verification.md` 记录证据，不预写 PASS。

- [ ] 执行任务级集成过滤器 `bash scripts/test.sh 'TopApp|TopApps|HardwareMetricsServiceTests|HardwareSamplerTests|HardwareMonitorPanelDemandTests'`，要求 0 failures。新增回归不能依赖真实用户进程名。
- [ ] Fetch 并比较最新 origin/main，记录共同祖先和共享文件冲突；如需集成必须先保留当前工作并按项目规则处理，不覆盖其他人改动。
- [ ] 最终集成树执行一次 `bash scripts/verify-local.sh full`，保存 SHA、工具链、变更范围及退出码；不把它当 runtime / Universal / release 通过。
- [ ] 按项目 background-ui-testing 技能及真实可用工具验证四页、少于 5 个应用、快速切页、长名称、滚动至第 5 行、关闭后停止采集；无法后台安全执行的步骤记录 BLOCKED 或 NOT RUN，保留人工验收。
- [ ] 用已有性能脚本对比关面板、概览、四个详情页各自的 CPU/内存和持有子进程数，记录设备/时长/基线；测试多进程浏览器、下载/上传、GPU 负载和 VPN/代理。确认退出后没有榜单子进程。
- [ ] 单独列出 macOS 13 / 当前 macOS、Apple Silicon / Intel 的实际覆盖与缺口；资源开销不合格则修复或向用户提出周期调整，不默默更换采集方案。
- [ ] 完成整分支代码审阅，交用户验收；验收前保留分支与 worktree，不自动合并、推送或关闭 issue。

## 更换模型后的执行交接

当前没有任何任务开始实现，所有复选框保持未勾选。用户换模型后，新执行者先读设计、本计划和项目 AGENTS.md，核对工作区，然后再按用户的开始指令执行。推荐在新模型的当前会话逐任务执行并在末尾独立审阅；若用户另选子代理方式，则遵循其选择。

可直接发送给新模型：

```text
请在 /Users/lingsmbp/Documents/aiwork/status-trio-detail-pages 的 feat/system-monitor-detail-pages 分支，阅读 docs/superpowers/specs/2026-11-18-system-monitor-top-apps-design.md 和 docs/superpowers/plans/2026-11-18-system-monitor-top-apps.md。设计已确认，沿用 Stats 采集方案，四类指标按应用合并后取前 5。请先核对当前工作区，再按实施计划逐任务实现并记录验证；不要自动合并或推送。
```
