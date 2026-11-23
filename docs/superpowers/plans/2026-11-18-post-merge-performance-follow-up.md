# Status Trio 性能合并后修改计划

> 执行时使用 superpowers:executing-plans 或 superpowers:subagent-driven-development，逐项勾选并验证。

**目标**　保留已验证的性能收益，补齐合盖恢复与监控采样边界，并让详情页性能可以复测。

**方案**　复用上一轮分支中经过测试的合盖和采样提交。独立处理内存榜文案、后台测试入口与性能验收。

**技术栈**　Swift 6.4、SwiftUI、AppKit、XCTest / Swift Testing、Bash。部署下限 macOS 13。

**需求依据**　本轮对 `main` 从 `ea99cbcb` 到 `65d6c7a8` 的审查，以及[上一轮稳定性计划](<../../../.agents/worktrees/fix/pre-release-stability/docs/superpowers/plans/2026-11-18-pre-upgrade-review.md>)第 1、2 项。实测命令 CPU 时间中位数由 1.094 秒降至 0.045 秒，证据范围为采集子进程。

## 执行边界

- 从执行当天最新的 `main` 建独立分支与 worktree，记录起点 SHA。当前审查快照为 `65d6c7a89ecd98de444c537d25378e2258607a64`。先用 `git cherry main fix/pre-release-stability` 确认待接入的补丁，逐个提交保留可回退性。各任务按行为分开提交，新增回归先确认能在对应修复前捕获问题。
- 任务 1、2 先复用原提交和回归。任务 3、4 可独立推进。任务 5 在前四项集成后执行。SSD 概览容量刷新排入后续。
- 保留 macOS 13 兼容、Developer ID / Helper 边界、正常启动与设置默认值。后台 UI 用项目启动器和独立 Debug 身份。用户验收后再合并或推送。

## 验收要盯的场景

- Helper 已写入，客户端同时丢失写回复和回读。持久归属仍可恢复。
- 开启合盖期间拔电、低电量或退出，以及旧重试与新会话交错。过期动作不能影响当前会话。
- 并排切页时指标需求集合不变，且旧读延迟返回。当前页不能被旧样本污染。
- 内存榜遇到带空格名称和异常数值。单位正确，坏行不能导致崩溃。
- 全新或关闭监控的测试配置、复用错页、页面未实际呈现。结果必须分清启动参数与真实路由。

## 任务 1 · 合盖恢复（发版前）

文件：[SleepControlController.swift](../../../Sources/StatusTrioCore/Monitoring/SleepControlController.swift)、[SleepControlSafetyTests.swift](../../../Tests/StatusTrioCoreTests/SleepControlSafetyTests.swift)。接口沿用 `performEnableLidSleep() async -> LidWriteOutcome`、`recoverResidualIfOwned() async` 和既有归属存储。

- [ ] 在隔离分支复用 `81360825`，再复用 `0e607a60`。先核对前置提交是否等效存在，再逐个接入。冲突按新主线调用关系处理。
- [ ] 用假 Helper 和可控等待覆盖已丢失回复、初始读中拔电、readiness 抖动、停止后重试失效。补低电量与退出中断用例。断言禁用写入前确有待恢复归属，无归属或主动维持的会话不会被清理。
- [ ] 复核残留恢复跨回读返回后再检查归属和当前意图。一次延迟恢复绑定当前会话，2 秒后的尝试进入已有有界清理流程。重试仍未确认时保留标记，退出或下次启动继续处理。
- [ ] 运行 `bash scripts/test.sh 'SleepControlSafetyTests|SleepControlControllerTests|PrivilegedHelperManagerTests'`。记录失败与跳过项，再用签名开发包验收真实 XPC、拔电、关闭、退出和重启恢复。

## 任务 2 · 详情采样和慢读调度（发版前）

文件：[HardwareMetricsService.swift](../../../Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift)、[HardwareSampler.swift](../../../Sources/StatusTrioCore/Monitoring/HardwareSampler.swift)、[HardwareMetricsServiceTests.swift](../../../Tests/StatusTrioCoreTests/HardwareMetricsServiceTests.swift)、[HardwareSamplerTests.swift](../../../Tests/StatusTrioCoreTests/HardwareSamplerTests.swift)。接口沿用 `setDetailDemand(_ kind: HardwareDetailKind?)`、`detailKindsToBuild(_:ids:)`。

- [ ] 复用 `dff08aea`，保留本轮已合并的环形动画与榜单设置改动。
- [ ] 核对 `testSwitchingDetailDropsLatePayloadFromPreviousPage`、`testSlowReadParksTheLoopInsteadOfPollingEvery50ms`、`testDetailPayloadsOnlyBuildForThisTicksDueFamilies`。再覆盖详情关闭但概览需求仍在、慢读完成后重新调度。断言非 GPU 到期不读 GPU，非磁盘到期保留原速率，旧详情不回流，下一轮能按到期时间继续采样。
- [ ] 运行 `bash scripts/test.sh 'HardwareMetricsServiceTests|HardwareSamplerTests|HardwareMonitorPanelDemandTests|TopAppsPanelDemandTests'`。断言关榜单释放排行采样，同时保留当前详情的硬件指标需求。

## 任务 3 · 保留轻量内存榜并说明 RSS（发版前）

文件：[TopAppCommandReaders.swift](../../../Sources/StatusTrioCore/Monitoring/TopAppCommandReaders.swift)、[TopAppsListView.swift](../../../Sources/StatusTrioCore/UI/TopAppsListView.swift)、[LocalizationKey.swift](../../../Sources/StatusTrioCore/Localization/LocalizationKey.swift)、[本地化资源](../../../Sources/StatusTrioCore/Resources)、[TopAppCommandReaderTests.swift](../../../Tests/StatusTrioCoreTests/TopAppCommandReaderTests.swift)、[性能记录](../../verification/2026-11-18-system-monitor-sampling.md)。沿用 `TopAppPSMemoryParser.parse(_:)` 和现有聚合、排序路径。

- [ ] 增加 `testMemoryReaderConvertsRSSAndPreservesProcessName`。向假执行器输入 `PID RSS COMM` 表头与 `7 1024 Example App` 数据行，断言输出 1,048,576 bytes、显示名保留空格。加入非法行和换算溢出行，断言有效行仍被返回，对应坏行跳过且无溢出。
- [ ] 保留 `/bin/ps -Aceo pid,rss,comm`，使用有溢出检查的 KiB 到 bytes 换算。生产榜单继续按应用聚合，移除测试文件第 89 行的尾随空白。
- [ ] 仅内存榜使用新标题键 `hardware.detail.topApps.memoryTitle`。简中用「内存占用排行（RSS）」，英文用 “Top apps by memory (RSS)”。同步 12 种语言。文档记录旧 `top MEM` 为 footprint，新榜单是 RSS，并按采集子进程记录降耗数据。
- [ ] 运行 `bash scripts/test.sh 'TopAppCommandReaderTests|TopAppAggregationTests|LocalizationParityTests'`。用现场 `ps` 输出验收解析非空，并核对 CPU、GPU、网络榜标题与开关行为。

## 任务 4 · 补齐后台详情页启动（性能验收前）

文件：[launch-computer-use.sh](../../../scripts/launch-computer-use.sh)、[computer-use-instance.swift](../../../scripts/computer-use-instance.swift)、[BackgroundUITestingConfiguration.swift](../../../Sources/StatusTrioCore/App/BackgroundUITestingConfiguration.swift)、[AppEnvironment.swift](../../../Sources/StatusTrioCore/App/AppEnvironment.swift)、[SettingsStore.swift](../../../Sources/StatusTrioCore/Settings/SettingsStore.swift)、[启动器测试](../../../scripts/test-launch-computer-use.sh)、[Debug 配置测试](../../../Tests/StatusTrioCoreTests/BackgroundUITestingTests.swift)、[设置测试](../../../Tests/StatusTrioCoreTests/SettingsStoreTests.swift)。

- [ ] 增加启动器用例。`--panel --test-open-hardware-detail=memory` 接受，传给 helper 和进程。缺 `--panel`、裸 flag、未知值、重复参数拒绝，且不构建或启动。带详情的 `--reuse` 只接受运行参数中的同一页，错页不重开。原 summary 和 Settings 路径继续通过。
- [ ] 支持五个现有值 `cpu|gpu|memory|network|disk`。helper 报告 `requestedHardwareDetail` 并检查实际进程参数。Debug App 对保留参数使用完整的非法值检查，Release 继续忽略。
- [ ] 在 `AppEnvironment.live(backgroundUITesting:)` 仅对有效详情测试配置启用进程内覆盖。将 `SettingsStore.init` 新增默认 `false` 的 `backgroundUITestingForcesHardwareMonitor: Bool`，生效范围为 `visiblePopupSections`。加设置测试，覆盖无保存值和保存关闭的两种输入，断言测试会话可见监控、持久化偏好没有写入或改动、普通会话不受影响。走既有 `showHardwareDetail(_:)` 路由。
- [ ] 运行 `bash scripts/test-launch-computer-use.sh`、`bash scripts/test-background-ui-configuration.sh` 和 `bash scripts/test.sh 'BackgroundUITestingTests|SettingsStoreTests|HardwareMonitorPanelDemandTests'`。实际性能采样前用可安全读取的窗口事实确认目标详情已呈现。无法确认时，该场景记录未验收。启动参数和 PID 用于身份核对。

## 任务 5 · 集成与性能验收

文件：[性能记录](../../verification/2026-11-18-system-monitor-sampling.md)。

- [ ] 先过聚焦测试，再对同一最终 SHA 跑 `git diff --check <基线 SHA> HEAD` 和 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=0 bash scripts/verify-local.sh full`。分别记录 SHA、退出码、失败和可见 UI 跳过数。
- [ ] 使用同一台 Mac、相同构建类型、同一刷新档位和设置、同类负载。合并后主线 `65d6c7a8` 用于比较本轮修改的影响。若要复验最初的动画收益，再对照 `ea99cbcb`。旧版本需要相同测量入口时单独记录仅含测试入口的基线 SHA。Debug 和 Release 数据各自报告。
- [ ] 预热 30 秒后每个场景至少采样 60 秒、重复 3 次。覆盖关窗且后台历史关/开、概览 1 秒和 2 秒档、五个详情页 2 秒档，以及 CPU 和内存详情的排行关/开。使用项目的 [RSS 采样脚本](../../../scripts/measure-memory.py) 和本机进程计数记录 CPU 时间、唤醒、RSS。内存页同时统计 `ps` / `top` 子进程次数和 CPU 时间。记录硬件、macOS、构建 SHA、PID、采样窗口和运行范围。
- [ ] 验收确认关榜时无该榜新的周期读取，图表继续更新。切页后没有旧数据回流。候选与基线相比，稳定场景重复出现占用上升时先定位来源。UI 与真实 Helper 分开记录通过、失败或未验收。提交结果供用户验收。

## 后续 · SSD 概览容量

- [ ] 单独安排低频刷新。仅 SSD 卡可见时查询，隐藏、切页和关闭时停止。保留最近一次有效容量，手测面板保持打开时释放磁盘空间，容量在刷新窗口内更新。源码入口见[容量读取](../../../Sources/StatusTrioCore/UI/MenuBarIconPreviewGrid.swift#L60)。
