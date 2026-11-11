# Issue #330 蓝牙“系统设置删除后仍显示”修复：历史 PR 与回归基线审计（Phase 0）

## 0. 范围、基线与方法

- 审计对象：Issue #330《[Bug] 系统设置删除蓝牙设备后，App 里仍然显示》。
- 基线：worktree 从 `origin/main` 切出，当前 HEAD = `a6a7ab01`（`refactor(brightness)...(#331)`），与 `origin/main` 同提交。
- 代码基线：`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift` 共 1824 行；`Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift` 共 1050 行。下文行号均以本 worktree **干净 HEAD `a6a7ab01`** 为准（审计快照）。注意：本 worktree 由 Lead/其他成员并行实现 #330，`refresh()` 附近若已有未提交改动，行号会整体后移，复核时以符号名为准。
- 方法：`gh pr view <num> --json title,body` 读 PR 描述；`git log --all --oneline --grep` 定位提交；`git show <sha>` 看 diff；读当前实现与测试确认“是否仍有效”。
- 约束：本审计只读，唯一写入是本文件；未运行任何扫描/配对/改系统蓝牙状态的命令；未运行 swift 测试（Lead 已跑 `bash scripts/test.sh 'Bluetooth'`，219 tests passed）。
- 事实纪律：拿不到的结论标“待验证”，不臆造 PR 内容或行号。

### 0.1 先明确 #330 的三个数据来源（决定“是不是 bug”）

面板蓝牙列表不是单一来源，Issue 正文已点明，本审计在当前代码中逐条核实：

1. **系统已配对设备**：`SystemProfilerBluetoothPairedDeviceWorker` → `BluetoothPairedDeviceReader.parse`（`BluetoothDeviceController.swift:33-255`），来源 `system_profiler -json SPBluetoothDataType` 的 `device_connected` / `device_not_connected`。**这是“是否已配对”的唯一真源。**
2. **附近 BLE 设备（多为 Apple 设备）**：`NearbyBLEDeviceCatalog` / `BluetoothLEBatteryScanner`，成功电量读取产生的行跨扫描保留，存活期为 `BluetoothLEBatteryScanPolicy.resultLifetime = 180s`（`BluetoothLEBatteryScanner.swift:27`；`NearbyBLEDeviceCatalog.swift:86,112,192`）。
3. **Apple / iCloud / 连续互通设备**：`MobileBatteryController` 快照，`cacheLifetime = 1200s`（`MobileBatteryController.swift:7`），另加 `trustedAppleDeviceMetadata` 持久元数据。取消蓝牙配对**不会**影响 iCloud 设备。

**结论（对 #330 的定性）**：只有来源 1 的“已配对行”才应该随系统设置删除而消失；“附近 BLE 行”（≤180s）与“iCloud 行”（≤20min 且元数据持久）在语义上不是“已配对蓝牙”，它们继续显示**是设计行为，不是配对状态 bug**。这三类必须有视觉/开关区分，否则用户会误以为“删不掉”。是否对来源 2/3 增加“只显示已配对”开关属于产品决策。

---

## 1. 总览表（结论先行）

> 现状列中的文件/符号均为当前 worktree 实际代码；“是否改”仅针对 #330 本次修复范围，不代表这些机制本身有缺陷。

### A. 读取与生命周期

| 条目 | 目的 | 现状（当前代码证据） | 回归测试 | #330 冲突点 | 是否改 |
|---|---|---|---|---|---|
| PR #61 已配对列表/排序/显示策略 | 内联展示已配对列表；连接组优先、组内拖动排序、总行数上限+展开；面板与详情共用行视图；只展示不连接 | `BluetoothDeviceListModel.make`（`UI/BluetoothDeviceListPresentation.swift:14-60`）、`panelSystemRows`(`:85-105`)、`orderedDevices`(`:300+`)、`visibleDevices`；设置项 `showsBluetoothDeviceList`/`maxVisibleBluetoothDevices`/`bluetoothDeviceOrder` 在 `SettingsStore` | `BluetoothDeviceListPresentationTests`（`testUnifiedListSharesOrderHideLimitExpansionAndVisibleBLESelection`, `:290`）、`BluetoothDeviceListLayoutTests`、`BluetoothPanelMapperTests` | 列表成员来自 `devices`，来源 1 淘汰后行会消失；排序/上限不涉及配对态，**无冲突** | 否 |
| PR #62 连接/断开动作、异步、确认态 | 点未连接=连接、点已连接=断开；键鼠断开先在该行确认；不做乐观翻转；拒绝/10s 超时可见失败 | `BluetoothDeviceActionState`（`Models/BluetoothDeviceAction.swift:18-70`）；`deviceActionStates`(`Controller:480`)、`pendingDisconnectConfirmation`(`:491`)、动作流程 `:1666-1730`；`BluetoothDeviceActionPerformer` | `BluetoothDeviceActionsTests`（如 `testAConfirmationIsHeldUntilItIsCancelled`、`testAnAcceptedRequestThatNeverChangesTheReportTimesOut`、`testOnlyDisconnectingAnInputDeviceNeedsConfirmation`）、`BluetoothDeviceActionTargetingTests` | 只对来源 1 可操作；附近/iCloud 行 `isReadOverTheAir` 不给动作（`BluetoothDeviceAction.swift:60` 附近）。**无冲突** | 否 |
| PR #294 蓝牙 120s safety-net 与生命周期约束 | 有可见面板时每 120s 兜底重读；生命周期约束下不泄漏线程/轮询 | `safetyNetInterval = .seconds(120)`(`Controller:520,560`)、`schedulePeriodicRefresh`(`:1527-1566`)、`hasVisibleSurface` 门控(`visibleSurfaces:1057`、`:1073`、`:1554`)、`stopPeriodicRefresh`(`:1567`)；事件已覆盖则跳过该轮(`:1557-1562`) | `BluetoothPollingLifetimeTests`：`testSafetyNetPollRunsOnlyWhileASurfaceIsHeld`(`:379`)、`testSafetyNetSkipsACycleAnEventRefreshAlreadyCovered`(`:417`)、`testTheLastReleasedSurfaceStopsThePoll`(`:460`) | 120s 兜底是删除后最终收敛的**最后保障**。若 #330 缩短/取消该轮询，会让“系统已删但事件没来”的场景更慢发现。**不要削弱** | 否（仅可新增事件驱动的“删除后立即重读”路径，见 §4） |
| commit 26003a6 单次读取锁 + 最多一次合并刷新 | 防止每个 trigger 各起一个 `system_profiler`；`isDeviceReadInFlight` 锁 + `isRefreshPending` 只保留一次后续 | `isDeviceReadInFlight`/`isRefreshPending`(`Controller:414-417`)，`refresh()` 合并逻辑(`:745-756`)，token 化(`:757-773`) | `BluetoothPollingLifetimeTests`：`testReadsCoalesceIntoOneFollowUpWhileAReadIsInFlight`(`:45`)、`testSupersededReadReleasesTheLatchAndTheNextRefreshRuns`(`:70`) | #330 若新增“删除事件触发重读”，必须走 `refresh()` 而非直接起 worker，否则破坏合并。**约束，不改本体** | 否 |
| commit 0a5dc90 读取 watchdog、阻塞队列退役 | `system_profiler` 可挂起；watchdog 判定卡死、迟到回调不得发布、队列退役后仍在跑的 block 不阻塞新队列 | `ReadWatchdog`(`Controller:426`)，`abandonTimedOutRead`(`:840`)，`invalidateDeviceRead`(`:859`)，worker 队列退役(`SystemProfilerBluetoothPairedDeviceWorker:37-121`)，`refresh` 完成处 `token == self.readToken` 守卫(`:773`) | `BluetoothPollingLifetimeTests`：`testAReadThatNeverCompletesDoesNotWedgeTheLatchForever`(`:102`)、`testAnAbandonedReadsLateCompletionIsIgnored`(`:138`)、`testACompletedReadDisarmsTheWatchdog`(`:167`)、`testAReadRetiresTheQueueWhenThePreviousReadIsStillOutstanding`(`:294`)、`testALateCompletionFromARetiredQueueDoesNotStopTheNextRetirement`(`:325`) | 迟到回调不得覆盖新数据是硬约束；#330 任何“删除后重读”都必须保留 token 守卫。**不改本体** | 否 |
| commit aa3e2ad 读取失败后轮询/监听器清理 | 修复三处：消费已用 trigger、invalidate 时 `recordSuccess()` 重置退避、`.failed` 分支停掉连接事件与轮询 | `.failed` 分支(`:800-...` 与 `:1126-1134` 的非 available 清理)、`invalidateDeviceRead` 内 `recordSuccess`、`abandonTimedOutRead` 清 `isRefreshPending` | `BluetoothPollingLifetimeTests`：`testAnAbandonedReadConsumesItsPendingTriggerOnce`(`:197`)、`testDeactivationResetsTheWatchdogBackoff`(`:230`)、`testAFailedReadStopsThePollAndTheConnectionEvents`(`:266`) | **与 #330 直接相关**：`.failed` 时保留上次列表（`refresh` 成功分支才替换 `devices`，见 §2.4）。需在“失败保留”与“永久幽灵行”之间加边界/状态提示。见 §4 | 是（受限，见 §4.1） |

### B. 缓存与 UI

| 条目 | 目的 | 现状（当前代码证据） | 回归测试 | #330 冲突点 | 是否改 |
|---|---|---|---|---|---|
| Issue #232 缓存与面板高度修复（多提交） | 重开面板先显示上次成功读数（内存缓存）、首读落地前骨架占位、AirPods 电量行稳定、展开不跳动 | `cachedDevices`(`Controller:321`)、`cachedDeviceLimit = 24`(`:322`)、`hasLoadedDevices`(`:327`)；成功读后 `cachedDevices = Array(devices.prefix(24))`(`:788`)；视图 `isShowingCachedDevices`/`cachedDevices`(`BluetoothStatusView.swift:118-125`) | `BluetoothDemandLifecycleTests`：`testLastReadStaysInMemoryForTheNextOpen`、`testLastDemandClearsTransientDataWithoutChangingPreferences`；布局 `BluetoothDeviceListLayoutTests`、`BluetoothSummaryLayoutTests` | **核心冲突点**：#330 若粗暴清空/禁用 `cachedDevices` 会破坏“重开不闪、立即显示”。规则明确：普通关面板允许保留上次成功数据。删除场景的清理应走“新成功读替换缓存”而非全局清空。见 §4.2 | 否（不动缓存机制；只保证成功读覆盖） |
| Issue #265 关闭蓝牙后缓存失效 | 关蓝牙后不再画上次设备（含旧连接标记）；普通关面板仍保留缓存 | `clearCachedDevicesForPowerOff()`(`Controller:738-743`) 清 `cachedDevices`/`devices`/`hasLoadedDevices`/动作；调用点 `SystemStatusStore.setBluetoothPower(!enabled)` 分支(`Store/SystemStatusStore.swift:868-883`，第 880 行)；`releaseTransientState` 保留 `cachedDevices`(`:705-725`) | `BluetoothDemandLifecycleTests`：`testPoweringOffClearsCachedDevicesSoNoStaleDeviceRowsShow`、`testPoweringBackOnDoesNotRestoreTheClearedCache` | 提供“定向清理”范式：只在明确的失效事件（关蓝牙）清缓存。#330 的“删除设备”可借鉴“定向失效”，但**删除单设备 ≠ 清空整个缓存**。规则：关蓝牙必须清缓存，普通关面板不清 | 否（作为范式参考） |
| PR #104 minorType 设备类型识别 | 图标稳定：按 `device_minorType` 分类，避免用易变/宽泛字段误判 | `BluetoothDeviceKindResolver`(`Models/BluetoothDeviceKind.swift:92+`)，`minorTypeKeys = ["device_minorType","device_minorClassOfDevice_string"]`(`:96`)；当前还被 `isGhost`(`Controller:251-254`) 复用为“是否被系统分类”的判据 | `BluetoothDeviceKindTests`：`theMinorTypeOutranksTheMajorType`、`readsTheClassFromWhicheverKeyCarriesIt`、`theMajorTypeStillClassifiesWhenTheMinorTypeIsAbsent`、`anAbsentClassIsUnknown` | 规则明确“不要改 minorType 图标分类”。但注意 `isGhost` 复用同两键，改动分类会连带影响 ghost 判定。**只读不动** | 否 |
| PR #288 断连设备电量失效 | 断连设备不再显示 profiler 旧电量（只发布当前已连接地址） | `connectedBatteryLevels`(`Controller:1170-1177`) 按 `devices.filter(\.isConnected)` 的归一化地址过滤；成功读后 `batteryLevels = connectedBatteryLevels(...)`(`:786`)、`deviceSnapshotGeneration`(`:787`) | `BluetoothBatteryControllerTests`：`primaryLevelsOnlyPublishForCurrentlyConnectedAddresses`(`:221`) | #330 若删除设备但列表仍残留，其电量也因已断连被过滤（不会再显示为“实时”）。**与 #330 同向，不冲突** | 否 |

### C. BLE 与 Apple 设备

| 条目 | 目的 | 现状（当前代码证据） | 回归测试 | #330 冲突点 | 是否改 |
|---|---|---|---|---|---|
| PR #73 附近 BLE 扫描与读取生命周期 | 可选开启附近 BLE 电量；扫描/读取受需求与授权门控 | `BluetoothLEBatteryScanner`（`setInitialReadCandidateIDs:218/248/465` 等）、`updateNearbyBatteryScanner`(`Controller:1299-1406`)、`stopNearbyBatteryScanner`(`:1407`)、`receiveNearbyBatteryDevices`(`:1438`) | `BluetoothNearbyBatteryLifecycleTests`（如 `testScannerRequiresActiveControllerPopoverRequestAndAvailableBluetooth`、`testReleasingLastNearbyRequestClearsCacheAndStopsScanner`）、`BluetoothLEBatteryScannerStateTests` | 附近行存活 180s，删除配对后仍可能显示 → 属“来源 2 语义”，需标注/开关而非当配对 bug 修 | 否（产品决策范畴） |
| PR #86 iPhone/iPad BLE 电量与身份合并 | 读 iPhone 电量并折叠到同一行；iPad 横向图标；只读行不可连接 | `isReadOverTheAir`(`Models/WiFiNetworkModels.swift:376`)、`identifiedByModel`(`:442-457`)、共享投影合并 `BluetoothDeviceListPresentation.sharedDisplayRows`(`:107+`)、`BluetoothMobileDeviceModel` | `BluetoothDeviceListPresentationTests`（`testSharedProjection...` 系列 `:5-217`）、`BluetoothMobileDeviceModelTests` | BLE 身份（UUID）与系统蓝牙地址是两个身份域；合并只在“唯一无歧义”时发生。删除配对不应连带删 BLE 行（它是独立来源） | 否 |
| PR #93 可信 Apple 设备目录与合并 | 统一 Apple 设备行；可选后台电量刷新；可信目录按模型合并 | `BluetoothDeviceListPresentation.sharedDisplayRows` + `trustedAppleDeviceMetadata`、`MobileBatteryController` 快照(`MobileBatteryController.swift:7,330,347`) | `BluetoothDeviceListPresentationTests`（`testSourceCatalogsHideBothCompatibleAliasesBeforeSharedRowsMerge:217`、`testSharedProjectionKeepsAmbiguousOrBatteryOnlyNameMatchesSeparate:180`）、`BluetoothNearbyBatteryPresentationTests` | iCloud 行不随蓝牙取消配对消失（语义不同）。**规则：不删正常 iCloud/USB/网络可信设备** | 否 |
| PR #155 防 BLE 扫描重复触发配对 | 附近初次读取失败后按冷却期抑制重试，避免反复弹配对 | `nearbyBLEInitialReadSuppressedUntil`(`Controller:442,1269,1294,1364`)、`BluetoothLEInitialReadPolicy.attemptSuppressionExpiry`、初次/持续读权限区分 | `BluetoothLEBatteryScannerStateTests`：`initialAttemptSuppressionExpiresAfterCooldownOrVerifiedRowLifetime`(`:241`)、`initialAndOngoingReadsHaveDifferentVisibilityRequirements`(`:203`)、`retryCooldownSurvivesDemandStopAndConnectionsAreBounded` | **最高风险冲突点**：见 §3.3 特别注明。若 #330 用“配对状态过滤后的名字集合”反向喂 BLE 白名单，可能让 iPhone 消失或破坏抑制逻辑 | 否（严禁误改） |
| PR #300 屏幕睡眠下的扫描门控 | 显示/系统睡眠暂停附近 BLE 扫描，唤醒恢复 | `setSystemSleeping`(`Controller:974-983`)、`setDisplaySleeping`(`:990-1003`)、`SystemStatusStore` 观察 `screensDidSleep/Wake`(`Store/SystemStatusStore.swift:239,460-496,669-671,1190`) | `NearbyBLEControllerDemandTests`：`testBackgroundScannerStopsDuringDisplaySleepAndResumesOnWake`、`testBackgroundScannerStopsDuringSystemSleepAndResumesOnWake`、`testSystemWakeWithDisplayStillOffKeepsNearbyScannerStopped`；`SystemStatusStoreTests`（PR #300 新增段） | 门控是低功耗约束，与 #330 的“删除后立即消失”无关；不得为 #330 放宽睡眠门控 | 否 |

---

## 2. 逐条详细审计（重点项展开）

### 2.1 A 组：读取生命周期链的演进顺序

1. `26003a6`（2026-09-20）：先有单次读锁 `isDeviceReadInFlight` + 单次合并 `isRefreshPending`，解决“trigger 风暴 → 多个 `system_profiler` 进程”。
2. `0a5dc90`（同日稍晚）：在锁之上加 `ReadWatchdog`，把“挂起的 subprocess 永久占用队列”变成“超时后放弃并换新队列”，且迟到回调按 token 丢弃（`:757-773`）。
3. `aa3e2ad`（同日再晚）：修三处“形状错误”——消费已用 trigger、invalidate 时重置退避、`.failed` 分支停轮询与连接事件。
4. PR #294（2026-11-06）：把兜底轮询固化为 120s，并补线程/轮询上界。

这四步构成当前 `refresh()` 的完整约束。**#330 的任何“删除后触发重读”都必须复用 `refresh(isSafetyNet:)` 入口**，不得绕过锁与 token。

### 2.2 B 组：缓存机制是双刃剑

- `cachedDevices` 只在**成功读取**后写入（`:788`），普通关面板 `releaseTransientState` 保留它（`:705-725`），仅关蓝牙 `clearCachedDevicesForPowerOff` 清空（`:738-743`）。
- 因此“删除设备后仍显示”若来自缓存，只可能持续到**下一次成功读**；成功读会整体替换 `devices` 与 `cachedDevices`，旧行自然消失。
- 若“删除后永不消失”，说明不是缓存问题，而是：① 后续读持续失败（`.failed` 分支保留旧 `devices`）；② `system_profiler` 仍返回该设备；③ 行来自来源 2/3。

### 2.3 `isUnpairedGhost` 的边界（与 #330 的关键区分）

- `isGhost(properties:)`（`:251-254`）= 既无 `device_minorType` 也无 `device_minorClassOfDevice_string` → “扫到但从未配对”的条目。
- 面板 `filteredDevices` **无条件**丢弃 `isUnpairedGhost`（`UI/BluetoothDeviceListPresentation.swift:405-409`；测试 `testFilteredDevicesAlwaysDropsSystemGhostsRegardlessOfLegacyOption:680`）。即“从未配对”的幽灵行已被处理。
- **关键缺口**：一个**曾经配对、后在系统设置删除**的设备，若 profiler 仍以 `device_not_connected` 返回，通常仍带 `device_minorType`（曾被分类）→ `isUnpairedGhost == false` → **不会被 ghost 过滤** → 继续显示，直到 profiler 不再返回它（取决于 macOS 行为，**待验证**）。
- 这说明 #330 的“来源 1 残留”主因更可能是 **profiler 报告滞后 / 读失败保留**，而非 ghost 过滤失效。

### 2.4 读取失败保留旧列表（Issue #330 可能问题点 4）

- `refresh()` 成功分支才 `self.devices = devices`（`:783`）；`.failed` 分支不清空 `devices`（见 `:800-...` 与 `receiveSystemState` 的 `.available` 之外清理逻辑 `:1126-1134`）。
- 因此“`system_profiler` 持续失败 → 永久显示旧列表”与 #265 同类风险，是 #330 验收项“读取失败不造成永久幽灵行”的落点。

---

## 3. 必须保留（不得在 #330 中破坏）的清单

### 3.1 读取与生命周期硬约束
- 不重复启动 `system_profiler`；同一时刻最多一轮有效读取；触发风暴只合并**一个**后续读取（`isDeviceReadInFlight`/`isRefreshPending`）。
- 迟到回调不得覆盖新数据（`token == readToken` 守卫）。
- 读取超时（watchdog）不得永久占用队列（队列退役）。
- 面板关闭不得遗留无需求轮询（`hasVisibleSurface` 门控）。
- 读取失败恢复不得无限重试（退避 + `.failed` 停轮询/事件）。
- 蓝牙未授权不提前启动监控（`prepareForPresentation` 只读授权，`activate` 才 `stateMonitor.start()`，`:652-683`）。

### 3.2 缓存与 UI 硬约束
- `cachedDevices` 是**有意设计**，不删。
- 普通面板关闭允许保留上次成功数据（`releaseTransientState`）；**关闭蓝牙必须清理缓存**（`clearCachedDevicesForPowerOff`，`SystemStatusStore.swift:880`）。
- 过期数据不得显示为实时连接状态（`connectedBatteryLevels` 过滤断连 + 缓存只作占位）。
- 新鲜电量不得被错误设备列表覆盖（`deviceSnapshotGeneration`/`connectionGeneration` 门控，`:1144`）。
- **不要改 `minorType` 图标分类**（`BluetoothDeviceKindResolver`）。

### 3.3 BLE / Apple 设备硬约束（含特别注明）
- **BLE UUID 与系统蓝牙地址是两个独立身份域**；不用设备名称做不安全全局去重。
- 不重新启用未授权自动 GATT 连接；不改既有 BLE 失败退避/挂起/手动恢复（PR #155 语义）。
- 不删正常 iCloud / USB / 网络可信设备。
- **特别注明（PR #155 风险）**：`BluetoothDeviceController.knownNearbyAppleDeviceNames` 目前**来自系统设备列表**（`:456-463`，`Set(devices.map(\.name))` → `updateKnownNearbyAppleNames()` `:465-467` → `setKnownAppleMobileDeviceNames`）。它是“iPhone 只在与系统列表同名时才走 BLE 读取”的白名单。**若 #330 新增“按配对状态过滤”得到一份更窄的集合，不能未经验证地把该过滤结果反向用作 BLE 发现白名单**：一旦过滤把 iPhone/iPad 从名单剔除，BLE 读取会被抑制，iPhone 会从面板消失，或与 PR #155 的“抑制重复配对”逻辑相互抵消。任何此类改动必须：① 保留“未过滤系统名单”供 BLE 白名单使用，或 ② 为过滤后的集合单独建用途并在 `testKnownAppleNamesFollowTheSystemDeviceList`（`BluetoothNearbyBatteryLifecycleTests`）新增覆盖。

---

## 4. 对 #330 本次修改的判断

> 本节只给“改/不改”的边界，具体实现属 Phase 1，不在本审计写代码。

### 4.1 建议修改（与 #330 真正相关）
1. **读取失败保留旧列表需有边界**：`.failed` 分支不应让旧 `devices` 无限保留为“当前列表”。可加“连续失败计数 / 明确状态位”，在 UI 标注“上次读取/可能过期”，并在恢复后以新成功读整体替换。对应测试可在 `BluetoothPollingLifetimeTests` 新增“连续失败后不把旧设备当实时”的用例（复用 `testAFailedReadStopsThePollAndTheConnectionEvents` 的桩）。
2. **系统侧残留的设备需在“下一次成功读”即消失**：现有 `parse` 已整体重建列表，`devices = devices` 天然满足；但需要**测试锁定“删除后解析结果不含该设备”**（Issue 验收项）。建议在 `BluetoothPairedDeviceListTests` 增加“同一地址从报告消失后不再出现”的用例。
3. **（产品决策）来源区分**：给附近 BLE / iCloud 行加视觉标注或“只看已配对”过滤开关。若做，必须在 `BluetoothDeviceListPresentation` 层实现，**不得**把过滤结果反向喂给 `knownNearbyAppleDeviceNames`（见 §3.3）。

### 4.2 严格不该动
- `cachedDevices` 的存在与其“重开立即显示”语义（PR #232 基线）。
- 单次读锁 / 合并 / watchdog / token 守卫（26003a6 / 0a5dc90 / aa3e2ad）。
- 120s safety-net 与 `hasVisibleSurface` 生命周期门控（PR #294）。
- `minorType` 图标分类与 `isGhost` 判定所依赖的两键（PR #104）。
- BLE 身份域、PR #155 初次读取抑制、PR #300 睡眠门控、PR #86/#93 的 Apple 设备合并与可信目录。
- 关闭蓝牙清缓存与普通关面板保留缓存的区分（#265）。

### 4.3 待验证（`system_profiler` 系统侧行为）
- macOS 在“系统设置 → 蓝牙 → 删除设备”后，`system_profiler -json SPBluetoothDataType` **是否立即**从 `device_not_connected` 移除该设备、持续多久、是否保留 `device_minorType`。这是区分“App bug”与“系统报告滞后”的关键实验，**本审计未运行（遵守只读约束）**，须由 Lead/人工在真机验证。
- 附近 BLE 行（≤180s）与 iCloud 行（≤20min）在删除配对后的实际消失时延，需真机观察确认是否落在用户可接受范围。

---

## 5. 附：审计证据索引（便于复核）

- 读取/解析：`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:33-255`
- 授权/状态监控：同文件 `:260-312`
- 缓存/发布状态：同文件 `:316-338`、`:738-743`、`:783-795`
- 单读锁/合并：`:414-417`、`:745-773`
- watchdog/队列退役：`:426`、`:840`、`:859`；`:37-121`
- 生命周期：`:652-698`、`:705-725`、`:1527-1566`
- 安全网 120s：`:520,560,1532`
- 连接事件：`:1797+`；`BluetoothConnectionEventMonitor`
- 电量过滤（#288）：`:1170-1177`
- 附近 BLE（#73/#155/#300）：`:442,974-1003,1299-1406,1438`；`BluetoothLEBatteryScanner.swift:27,218,248,465`；`NearbyBLEDeviceCatalog.swift:31,40,86,112,192`
- iCloud 快照（#86/#93）：`MobileBatteryController.swift:7,330,347`
- 展示/过滤：`UI/BluetoothDeviceListPresentation.swift:14-60,85-105,261-263,405-409`；`Models/BluetoothDeviceListOptions.swift`；`Models/WiFiNetworkModels.swift:355-475`；`Models/BluetoothDeviceKind.swift:92-160`
- 关蓝牙清缓存调用：`Store/SystemStatusStore.swift:868-883`
- 测试：`Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`、`BluetoothDemandLifecycleTests.swift`、`BluetoothPairedDeviceListTests.swift`、`BluetoothDeviceListPresentationTests.swift`、`BluetoothDeviceActionsTests.swift`、`BluetoothBatteryControllerTests.swift`、`BluetoothDeviceKindTests.swift`、`BluetoothLEBatteryScannerStateTests.swift`、`BluetoothNearbyBatteryLifecycleTests.swift`、`NearbyBLEControllerDemandTests.swift`
