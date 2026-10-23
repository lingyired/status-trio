# Memory Lifecycle Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实施第二轮按需求启停和回收，减少不用的蓝牙工作、隐藏面板状态和闲置预览资源，并建立瞬时峰值的可复现证据。

**Architecture:** 沿用 SystemStatusStore / StatusPanelViewModel / StatusBarController，集中消费者需求与生命周期，不另造监控服务。将窗口可见性、功能开关与资源使用者统一到可测试边界；保留当前图像、活动帧、用户设置与迟到结果防护。

**Tech Stack:** Swift、Combine、AppKit/SwiftUI、CoreBluetooth、Swift Testing/XCTest、Python/Swift只读采样脚本。

**Spec:** `docs/superpowers/specs/2026-10-20-memory-lifecycle-design.md`。

**2026-10-21 main sync:** 同一工作树已快进到 `e682e4bd6f7177672aa221b0547e0201e19152d3`，未提交的优化改动已恢复。3 处冲突已解决，并完成蓝牙电源、HUAWEI 发现信号与本地优先规则的整合。最终 `full` 本地验证和独立审查通过；详见 performance 报告的 Main synchronization 章节和 plan ledger。

## Global Constraints

- 固定工作树 `/Users/lingsmbp/.codex/worktrees/memory-optimization/status-trio`，分支 `codex/memory-optimization`；已经 fast-forward 到 main `99d6fa998187ba2d5beced13377ed9ceee6ca263`，保留未跟踪dist-dev应用和第一轮测量。主工作区3个用户修改不带入。
- 用户已明确要求计划完成后立即委派实现，采用工具中可调用的 `auto/deepseek-v4.1-flash`（用户称 `group/auto-deepseek-v4-1-flash`）。不再等待计划审批；有歧义由协调者作可逆裁定并写ledger。
- 本轮不自动commit/push/merge/release；任务完成保留同一分支与工作树，不删除正在使用的应用。
- macOS13，构建SDK>=26。2026-10-21 同步 main 后按当前 AGENTS 使用风险对应的本地验证；正式发布环境为 Xcode27。原始 Xcode26.6/Swift6.3.3 记录仅说明当时验证边界。Swift隔离清理遵守AGENTS，不新增实验开关。
- 不删除持久偏好、授权选择、隐藏顺序、图标配置；不新增蓝牙连接或扩大授权。不减少分辨率、36帧/20FPS或改变菜单栏与Dock外观。
- 新行为先有回归测试：每worker使用当前plan workspace内run-swift锁串行执行SwiftPM，保留red/green日志；其他worker引入的未完成接口不算有意义的red证据，交协调者处理。所有修改必须在明确write set内。
- 不把30→59MiB的差值归因到一个模块；不承诺省下固定MB，不用像素预算替代footprint。

## Review Focus

1. 蓝牙图标/音频AirPods能力/蓝牙设置/后台刷新与面板各自持有需求：关一个不影响另一个；未授权不因启动或通用面板弹权限。归Task1/2。
2. 同一main-actor回合开关设置、快速关开、旧Task取消后迟到：使用publisher传入值/epoch；不得依赖额外Task.yield或真实sleep解决竞态。归Task1/3。
3. 隐藏分区后仍有音频区域消费者：蓝牙UI mapping可停，必要的音频设备能力继续可用；重开状态立即更新。归Task2。
4. 设置、引导、popover并存时只回收无使用者资源；不改变活动动画current frame和steady rebuildCount。归Task4。
5. 342MiB只是一项累计峰值：记录每个阶段的实际样本峰值，验证PID复用/退出和窗口状态，不把observer内存算入目标。归Task5。

## 分工与依赖

| 任务 | 主要write set | 依赖 | 实施者 |
|---|---|---|---|
| 1 蓝牙需求与数据回收 | SystemStatusStore、BluetoothDeviceController、ProfilerCache、必要蓝牙设置页面、AppEnvironment绑定 | 基线 | DeepSeek A |
| 2 面板状态按需构建 | StatusPanelViewModel、独立Tests | 与1可并行，修改文件不重叠 | DeepSeek B |
| 3 面板快速关闭/释放 | StatusBarController、PopoverLifecycleTests、StatusBarMemoryPressureTests | 2接口完成；不与4并行改同文件 | DeepSeek C |
| 4 闲置预览回收 | AppEnvironment、窗口/引导控制器、预览缓存生命周期 | 1和3评审完成 | DeepSeek D |
| 5 峰值采样工具/复现 | scripts、工具Tests、独立performance报告 | 工具与1/2并行；最终曲线依赖新build | DeepSeek E +协调者实测 |
| 6 集成、审查、构建、报告 | 文档和跨模块必要修正 | 1–5 | 协调者+DeepSeek reviewer |

每项完成后独立task review（规格+质量），共享接口的实现开始前先完成前置review；最后再做整分支review。每次fix记录证据，三次同因失败停止猜测并重新审视假设。

### Task 1：蓝牙需求统一与闲置数据释放

**Files:** Modify `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, `App/AppEnvironment.swift`, `Monitoring/BluetoothDeviceController.swift`, `Monitoring/BluetoothProfilerReportCache.swift`；如有实际调用需要，修改 `UI/Settings/BluetoothSectionView.swift`, `UI/Settings/PopoverSectionView.swift`。Create/extend `Tests/StatusTrioCoreTests/BluetoothDemandLifecycleTests.swift`、既有BluetoothPollingLifetime/PermissionTiming/BatteryController/ProfilerCacheTests。

**Interfaces:** `SystemStatusStore.bindBluetoothSettings(_ settings: SettingsStore)` 管理weak settings引用与开关订阅；同一central reconciliation计算授权与消费者，现有 `setPopoverVisible`, `requestBluetoothAuthorization` 继续可调用。同步 main 后监控接口采用 `setBluetoothDeviceMonitoringEnabled`，电源写入接口 `setBluetoothPower` 保持独立。清理使用者全部消失时的瞬态数据，不把一次设置开关当所有权布尔值。必要新增有意义的消费者token API时在该任务定义，并由现有settings页面调用。

- [ ] 列出真实所有消费者和授权条件；明确网络图标只有CoreAudio即可时不应额外启动paired profiler，图标指定配对设备时需要device controller。后台读取需原有授权和独立opt-in；设置页只有显示时持有claim。
- [ ] 写测试验证：四种用途均关+通用面板开关，fake state monitor.startCount==0/worker.readCount==0；授权未决定时普通打开不提示；显式开启仍能请求；设置/后台/图标任一个有需求时关闭面板不误停；最后一个需求消失清内存但preferences逐字不变；迟到读取不恢复已清列表。
  ```swift
  fixture.settings.setPopupSection(.bluetooth, enabled: false)
  fixture.settings.replacesNetworkIconWithBluetoothAudio = false
  fixture.store.bindBluetoothSettings(fixture.settings)
  fixture.store.setPopoverVisible(true)
  XCTAssertEqual(fixture.stateMonitor.startCount, 0)
  XCTAssertEqual(fixture.worker.readCount, 0)
  ```
  使用任务自建可注入fake fixture，以既有BluetoothPollingLifetimeTests的fake为参考，不能把本段fixture名字当产品API。
- [ ] 在run-swift下跑上述回归获得正确失败；以publisher传入快照进行reconciliation，保持`@Published willSet`语义；对所有事件开关/授权/睡眠进行统一调用。
- [ ] 为ProfilerCache实现显式安全回收：只有完整蓝牙读取需求关闭且无其他读者时reset；controller单独deactivate不能破坏共享reader。5秒过期仍需在读时校验，不新增轮询timer。
- [ ] 跑 `swift test --filter 'BluetoothDemand|BluetoothPollingLifetime|BluetoothPermissionTiming|BluetoothBattery|BluetoothProfiler|NearbyBLE|AppEnvironment'`；确认连接/电量/音频订阅与授权回归不变，写报告与red/green路径。

### Task 2：隐藏分区与闲置面板状态按需管理

**Files:** Modify `Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift`；Create `Tests/StatusTrioCoreTests/StatusPanelDemandTests.swift`、按需要修改既有 `StatusPanelViewModelTests.swift`。不改SystemStatusStore/StatusBarController。

**Interfaces:** 保持现有published属性供SwiftUI使用。增加 `func releaseInactivePresentationState()`（仅在presentation已stop且不可见时由Task3调用），释放可重建详情/设备行数组，保留小型summary可通过start同步重建。`start()`恢复全部当前enabled需求；`stop()`幂等取消订阅与pending updates。

- [ ] 先为隐藏bluetooth/audioInput/inputSource与未打开battery/wifi/wired详情建立测试：其源publisher更新不引起无用的区域published更新或构建；同一回合打开/关闭分区后正确绑定最新输入。保留音频区域AirPods能力。
- [ ] 对stop→release→start做回归：迟到scheduler action被generation挡住、无重复订阅、语言变化后第一次重开有最新文本、已禁用区域不保留大设备列表。既有summary初始值契约要兼容，不单纯删掉测试。
  ```swift
  panel.stop()
  panel.releaseInactivePresentationState()
  fixture.settings.setPopupSection(.bluetooth, enabled: true)
  panel.start()
  XCTAssertEqual(panel.visiblePopupSections, fixture.settings.visiblePopupSections)
  ```
- [ ] 跑 `swift test --filter 'StatusPanelDemand|StatusPanelViewModel'` 获取red；把`refreshAll()`拆成按需求派发，不为每一项新增长期Task，不依赖真实时间延迟。mapping错误/locale/音频必要dependency要保留。
- [ ] 在同一filter取得green，并运行 `PanelPresentation|BluetoothSummary|AudioPanel` 相关测试，记录完整结果和接口。

### Task 3：关闭即暂停，5秒回收重型面板

**Files:** Modify `Sources/StatusTrioCore/UI/StatusBarController.swift`；Modify/Create `Tests/StatusTrioCoreTests/PopoverLifecycleTests.swift`, `StatusBarMemoryPressureTests.swift`, `StatusBarContentLifecycleTests.swift`。

**Interfaces:** 使用Task2的`stop/start/releaseInactivePresentationState`。`popoverContentReleaseDelay=5`；构造参数注入release sleeper用于确定性测试；新增 `var onPopoverContentReleased: (() -> Void)?` 供Task4作为闲置资源清理边界，保证只在内容确实释放后通知。

- [ ] tests先覆盖关闭立即停订阅、5秒边界前保留/后释放、快速重开内容可复用且数值新、旧释放Task不可清掉重开的内容、详情立即释放、内存压力不能清正在显示的面板。使用测试sleep gate推进，不让测试真的等待5秒。
- [ ] 明确每条关闭/隐藏/pressure路径对`stop()`和回调幂等；重开先start再展示。将释放动作合为一个私有方法，避免每条路径清理不一致。
  ```swift
  panelViewModel.stop()
  // retention期届满且仍关闭后：
  popover.contentViewController = nil
  panelViewModel.releaseInactivePresentationState()
  onPopoverContentReleased?()
  ```
- [ ] `swift test --filter 'PopoverContentRetention|StatusBarContentLifecycle|StatusBarMemoryPressure|StatusBarControllerVisibility|StatusBarChargingAnimationTick|Issue30WiFiAlignmentTests'` red→green；保留不重复raster/可见墨迹断言和点击dismiss行为。

### Task 4：预览资源使用者结束后的安全回收

**Files:** Modify `App/AppEnvironment.swift`, `UI/Settings/SettingsWindowController.swift`, `UI/OnboardingWindowController.swift`；如有必要新增 `App/PreviewResourceLifecycle.swift`；使用既有 `UI/Icon/DockIconPreviewCache.swift`, `DockIconRenderer.swift`清理API。Create `Tests/StatusTrioCoreTests/PreviewResourceLifecycleTests.swift`。本任务在1/3完成后写入共享文件。

**Interfaces:** 设置/引导控制器提供显示生命周期回调（例如`onVisibilityChanged: ((Bool)->Void)?`），start时注册、stop时解绑。以小型集合持有可见preview owner，不保存view对象；Task3回调只是候选清理边界，必须先检查所有owner。

- [ ] 测试设置+引导同时可见，关一个不清另一个缓存；最后一个关闭时释放预览专用图和闲置scratch；重复关闭/stop无负数claim或再生成资源；当前menu/Dock图和活动帧group identity/rebuildCount不变。
- [ ] 不修改SettingsWindow已有的`window=nil`正确释放，不声称修了未证实窗口泄漏；如发现数据缓存被其他可见用途共享，保守保留或只清preview专用cache，记录范围裁定。
- [ ] `swift test --filter 'PreviewResourceLifecycle|GuideWindowLifecycle|DockIconPreviewCache|DockCharging|AppEnvironmentTelemetryLifecycle|Issue30WiFiAlignmentTests'` red→green。不得增加周期cleanup timer或改变现有image budget/像素。

### Task 5：峰值曲线工具和真实证据

**Files:** Create `scripts/measure-memory-lifecycle.swift`（也可选择以现有`measure-memory.py`为读数核心的同名Python入口，接口需相同）；工具验证放 `scripts/tests/`；Create `docs/performance/memory-lifecycle-2026-10-20.md`。不改产品源码。

**Interfaces:** CLI `--pid <pid> --seconds <duration> --interval-ms <100..1000> --output <jsonl>`，每样本输出timestamp/elapsed、PID+可执行path+启动identity、footprint、rss、lifetimePeak、visibleWindowCount；失败/进程更换立即非零退出，不能输出0作为有效内存。只读CGWindow元数据，不输出标题/屏幕内容/设备隐私。

- [ ] 参数错误/不存在PID/已退出PID/identity变化有测试；工具可采自身或短寿命测试进程；采样进程和observer与目标区分。Swift CLI在CI工具链可编译，Python入口也不新增依赖。
- [ ] 在独立开发测试bundle或原生测试harness中做启动→首次展开→关闭至少6秒→重开，并记录每阶段实际样本峰值；fixture有确定性phase marker。真实UI无法自动可靠控制时记录原生离线证据和手动尚缺，不把mock称为实机验收。
- [ ] 对比同功能开关/输入/图标placement/显示环境的旧新build；至少3次有identity的启动和窗口周期，旧的30/59和342数据保持为历史参考，不混入新统计。
- [ ] 优先检查首次SwiftUI hosting与大量临时mapping/图片decode。找到具体来源才补归属worker修复；未复现则列出测量协议/采样间隔限制/未定位结论与原始曲线，不承诺342峰值已消除。

### Task 6：集成与最终交付

**Files:** 本plan/spec、Task5performance报告；有新CI失败才写`docs/swift-ci-compatibility.md`。

- [ ] 每任务review和全部接口整合；所有worker改动在分支内，主workspace用户文件与原始测量不变。保存每项测试和ruling到本plan ledger。
- [ ] 完整执行并检查退出码：
  ```bash
  swift test
  swift build -c release
  swift test --filter Issue30WiFiAlignmentTests
  bash scripts/check-forbidden-patterns.sh
  VERSION=1.6.1 BUILD=38 PUBLISH=false bash scripts/validate-appcast-notes.sh
  python3 -m unittest discover -s scripts/tests
  git diff --check
  ```
- [ ] 全分支独立review（功能需求/授权/数据回收/缓存所有权/CI兼容），修复有证据问题后跑相关回归。
- [ ] 报告完成项、缓存持有数量/预算或对象释放证据、真实footprint曲线和仍未覆盖硬件。给出计划/变更路径和本地测试结果；不称未执行的远端CI/硬件验收通过。
- [ ] 本轮触及actor/SwiftUI等路径，按当前 AGENTS 在最终整合树上执行 `bash scripts/verify-local.sh full`；普通开发和合并不要求远端CI。只有维护者明确批准时才做可选远端诊断。

## 计划自检

- 五项建议分别落到Task1、2、3、4、5，Task6承担整合与证据边界。
- 共享文件AppEnvironment由Task1→Task4顺序写；StatusBarController由Task3独占，Task4只接其完成后的回调。Task2先提供清理接口再实现Task3。Task5不碰产品文件。
- 已保留所有真实消费者、权限边界、持久设置、menu/Dock像素/动画与macOS13兼容；预算数字不冒充真实节省量。
- 执行状态以本plan ledger为准；复用工作树不复用第一轮的task完成状态。

### Task 7：关闭音量和蓝牙区块时不读取音频设备详情（2026-10-22）

**Files:** Modify `Sources/StatusTrioCore/Store/SystemStatusStore.swift`；Create
`Tests/StatusTrioCoreTests/VolumeDetailsDemandTests.swift`；补充性能证据。

1. 先用真实 Store 和记录音频详情请求的测试边界复现：仅电池、网络的面板仍启用音频详情。
2. 详情需求由 Settings 窗口或可见面板中的音量、蓝牙任一区块持有；未绑定 Settings 的调用保留原有语义。面板内实时切换、重新绑定使用已送达的设置值，启用时立即刷新设备列表。
3. 基础音量监听和菜单栏、Dock 场景数据保持不变；最后一个详情消费者消失时走已有缓存清理路径。其他区块或设置更新不应触发额外设备列表读取。
4. 运行新回归、音量和蓝牙生命周期回归，以及 `bash scripts/verify-local.sh full`。记录当前分支基点与新获取的 `origin/main`；本修复不夹带上游麦克风控件改动。
5. 构建并替换同一分支开发包，保留旧包与设置；采样只报告实际测到的阶段，不把重启前后差值当作本修复的节省量。
