# Issue #330 修复交付报告：蓝牙取消配对后的设备一致性

- 分支：`fix/330-bluetooth-unpair-consistency`
- 基线：`origin/main` @ `a6a7ab01`
- 关联 Issue：https://github.com/lingyired/status-trio/issues/330
- 配套产物：
  - [Phase 0 历史审计](issue-330-bluetooth-regression-audit.md)
  - [Phase 2 配对状态只读实验](issue-330-pairing-evidence-experiment.md)
  - [既有蓝牙滞后调查](bluetooth-stale-state-investigation.md)

---

## 1. Root Cause（已证实 / 未证实严格区分）

### 1.1 已证实（可复现、有失败测试佐证）

问题不是“缓存本身内存泄漏”，而是两个状态机缺口叠加：

1. **`.failed` 读失败后无法恢复。** `refresh()` 的入口守卫是 `availability == .available`，而读失败会把 `availability` 置为 `.failed` 并停止 safety-net。`refreshFromUser()` 只是调用 `refresh()`，于是**用户在面板内点刷新、在 `.failed` 状态下完全不产生新读取**；`testAManualRefreshRetriesAfterAFailedReadAndRestoresTheSafetyNet` 在修复前断言 `readCount == 2` 超时失败，证明只能重启 App 才能恢复。
2. **重开面板的缓存占位会在读失败后冒充“实时”。** 面板重开时 `releaseTransientState()` 把 `devices` 清空、保留 `cachedDevices`，视图用 `isShowingCachedDevices` 把缓存行当作可用数据绘制，并把 `effectiveAvailability` 强制为 `.available`。但该判断**没有检查 availability**：一旦这次接续读失败（`availability == .failed`），缓存行（含已在系统设置里删除的设备）会继续以“可用/已连接”渲染，且没有任何读会再来覆盖它——这正是“系统设置删除后 App 里仍显示”的可复现形态。

复现路径（无真实硬件，注入式 mock）：已配对 A/B/C → 重开面板触发一次读取 → 该次读取返回 `.failed` → A/B/C（含被删的 B）继续显示且不可操作/不可恢复。

### 1.2 未证实（本次无法在真机确证，不臆断）

- **系统侧 profiler 残留**：用户删除设备后，`system_profiler -json SPBluetoothDataType` 是否仍把该设备列在 `device_not_connected`（且带 `minorType`，从而绕过 `isUnpairedGhost`）——这决定了“App bug vs 系统报告滞后”。本次 Phase 2 只读实验**未复现**该残留（profiler 与 IOBluetooth 7/7 一致、全部 `isPaired == true`），故**不做结论**。
- 「成功读取仍列出已删除设备」这类系统报告滞后，App 侧无法凭现有信息纠正（见 §6）。

---

## 2. Historical PR Audit

完整审计见 [issue-330-bluetooth-regression-audit.md](issue-330-bluetooth-regression-audit.md)（覆盖 PR #61/#62/#294、commit `26003a6`/`0a5dc90`/`aa3e2ad`、#232/#265/#104/#288、PR #73/#86/#93/#155/#300）。核心结论：

- **与 #330 相关且本次可改**：读失败保留旧列表的边界（本报告 §3）、`cachedDevices` 的展示门控（本报告 §3）、同地址从 profiler 消失后的解析/快照测试。
- **严格未动**：`cachedDevices` 机制（#232 高度稳定）、单读锁/合并刷新/watchdog/token（`26003a6`/`0a5dc90`/`aa3e2ad`）、120s safety-net 与 `hasVisibleSurface` 门控（#294）、minorType 分类（#104）、关蓝牙清缓存（#265）、Apple 合并（#86/#93）、BLE 配对抑制与睡眠门控（#155/#300）。
- **最高风险点**：`knownNearbyAppleDeviceNames` 来自系统设备列表；不得把“配对状态过滤结果”反向喂给 BLE 发现白名单，否则 iPhone 会消失或破坏 #155。本次**没有**触碰 BLE 白名单。
- **近 BLE（≤180s）/ iCloud（≤1200s）行**：属独立来源，语义上不是“已配对蓝牙”；本次按“来源独立”保留，未做合并改动（是否加“只显示已配对”开关属产品决策）。

---

## 3. Code Changes（最小补丁）

### 3.1 `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`

- 把 `refresh()` 的读推进体抽成 `private func performDeviceRefresh(isSafetyNet:)`，`refresh()` 保持原 `.available` 守卫不变。
- 新增 `func retryDeviceReadAfterFailure()`：**只允许 `.failed`** 重试；断电/未授权/不可用一律拒绝；仍走单读锁 + 合并后续规则；`.failed` 状态保留到真正成功为止（不把旧设备当实时）。
- `refreshFromUser()`：`availability == .failed` 时走 `retryDeviceReadAfterFailure()`，否则维持原 `refresh()`。
- 成功分支若 `periodicRefreshTask == nil`（即读失败曾停掉过 safety-net），重新 `schedulePeriodicRefresh()`，恢复 120s safety-net 与连接事件监听。

**必要性**：修复 §1.1 的第 1 点；不新增任何定时器、observer 或常驻读取，重试完全由用户操作/既有生命周期触发，重复点击仍被单读锁合并。

### 3.2 `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`

- 新增纯函数 `static func showsCachedDevices(availability:isRadioOff:showsList:hasLoadedDevices:devices:cachedDevices:)`：只有 `.idle/.initializing/.available`（仍有读会到来）才允许用缓存行占位；`.failed/.poweredOff/.unavailable/授权类` 一律不显示。把原视图私有逻辑变成可单测的判定。

**必要性**：修复 §1.1 的第 2 点；`cachedDevices` 本身保留（#232 快速展示不变），只是不再在读失败后冒充实时。

### 3.3 `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`

- `isShowingCachedDevices` 改为调用上面的纯函数（行为等价于原逻辑 + availability 门控）。

**最小性**：全改动仅 3 个生产文件、约 60 行（含注释），无 schema/设置项/BLE 路径改动，未删除任何历史逻辑。

---

## 4. Regression Tests

先红后绿（TDD）：新增 8 个测试，修复前其中 2 个行为测试与 4 个视图判定测试为红。

| 测试 | 文件 | 覆盖 |
|---|---|---|
| `testAManualRefreshRetriesAfterAFailedReadAndRestoresTheSafetyNet` | BluetoothPollingLifetimeTests | 读失败→手动刷新重试成功→列表恢复且 safety-net 重建 |
| `testASuccessfulReadDropsADeviceTheSystemNoLongerReports` | 同上 | A/B/C → A/C：B 成功读取后从 `devices` 与 `cachedDevices` 同时消失 |
| `testRepeatedRefreshDuringFailedRecoveryIsCoalesced` | 同上 | 多次刷新仍“一次读取 + 一次合并后续”，不炸 profiler |
| `testAManualRefreshDoesNotRetryWhileTheRadioIsOff` | 同上 | 断电状态不发起无效读取 |
| `testCachedDevicesAreShownWhileAReadCanStillLand` | BluetoothDeviceListPresentationTests | `.idle/.initializing/.available` 可占位 |
| `testCachedDevicesAreHiddenAfterAFailedRead` | 同上 | `.failed/断电/不可用/授权类` 不占位（#330 主回归） |
| `testCachedDevicesRequireAnEmptyLiveListAndAnUnloadedRead` | 同上 | 关屏/已加载/有实时列表/空缓存等边界 |
| `testAFailedReadHidesTheListAndReportsTheFailure` | 同上 | `.failed` 下列表隐藏、summary 为 `readFailed`，即使内存里仍有旧设备 |

结果：
- 修复前聚焦红测：`testAManualRefresh...`、`testRepeatedRefresh...` 超时失败（证明根因）。
- 修复后：8/8 通过。
- 全量蓝牙回归：**442 tests，2 skipped，0 failures**（基线 434 tests / 0 failures，本改动 +8 测试，无既有用例被删/放宽）。
- **完整 Swift 套件**：`3058 tests，99 skipped，0 failures`（`scripts/verify-local.sh full`，head `a6a7ab01`）。基线无失败，本改动未引入新失败，无“既存失败”需要归因。

既有未破坏的关键套件均通过：`BluetoothPollingLifetimeTests`、`BluetoothDemandLifecycleTests`（缓存重开保留、关蓝牙清缓存）、`BluetoothSummaryLayoutTests`、`BluetoothDeviceListPresentationTests`、`BluetoothBatteryControllerTests`、`NearbyBLEControllerDemandTests` 等。

---

## 5. Performance Comparison（含未执行项）

| 维度 | 修改前 | 修改后 | 结论 |
|---|---|---|---|
| `system_profiler` 常驻调用 | 120s safety-net + 事件触发 | 不变；仅在用户手动刷新且原为 `.failed` 时多一次（用户操作驱动，非定时） | 无常驻新增 |
| 定时器 / observer / 常驻读取 | — | 未新增；重试复用既有 watchdog/单读锁/合并 | 无新增 |
| 缓存上限 | `cachedDeviceLimit = 24` | 不变 | 有界 |
| 生命周期 | 面板关闭/断电/睡眠释放 | 不变（未新增 surface/claim） | 由既有测试覆盖 |
| CPU/内存/唤醒 | — | 静态分析无新增持续开销 | 运行态实测 **NOT RUN**（本环境不启动前台 App；见下） |

- 已验证（测试证据）：一次触发只启动一次读取、重复刷新被合并、radio off 不读取、surface 释放后停轮询、成功后重启 safety-net。
- **NOT RUN**：真实设备的每分钟 profiler 次数、单轮刷新耗时、首开/再开响应、CPU/内存、睡眠唤醒次数、BLE/GATT 次数——这些需要前台运行 App 抓取，属人工/真机验收项，本会话未执行，不虚报。

### 5.1 本地验证门（`bash scripts/verify-local.sh full`）

**PASS（exit 0）**，head `a6a7ab01`，scope `full`：
- Swift 套件 + 禁用模式检查：3058 tests / 99 skipped / 0 failures。
- Release build、非 Universal 本地 App bundle、平台/SDK 契约（macOS 13.0 / SDK 26）、Mobile Battery 与 Privileged Helper bundle 契约：全部通过。
- 原生兼容/依赖检查与离线发布流水线仿真：全部通过。

（该门不等价于签名、公证、DMG、正式发布 CI、Universal 打包或 macOS 13 / 26+ 运行时验收。）

---

## 6. Remaining Limitations

1. **系统报告滞后**：若 `system_profiler` 在一次**成功**读取里仍列出已被“忽略/删除”的设备（带 minorType，绕过 ghost 判定），App 会照实显示。本次 Phase 2 只读实验**未复现**该残留；不改用 IOBluetooth 硬过滤（`pairedDevices()` 可用但仅 7/7 全 paired 样本、未验证 BLE/旧版/多设备覆盖，且断电/拒权会返回空导致误删）。建议作为**非破坏性诊断证据**保留，进生产需另立议题。
2. **版本/硬件边界未验证**：macOS 13、经典蓝牙 vs BLE HID、AirPods 多设备、第三方适配器的配对枚举覆盖未验证。
3. **读超时长期挂起**：若某次读取一直超时、永不返回，重开缓存行会持续占位直到某次读返回（watchdog 会退避重试）。这是既有行为，未在本次改动中加“缓存过期”，以免重新引入 #232 面板跳动。
4. **运行时性能实测**：见 §5 的 NOT RUN 项。

---

## 7. 完成标准对照

- [x] 系统已删除且不再上报的设备，在下一次成功读取后从已配对列表消失（`testASuccessfulReadDrops...`）。
- [x] 读取失败可恢复，无需重启 App（`testAManualRefreshRetries...`）。
- [x] 不破坏 #232/#265/#104/#155/#288/#294/#300（全量蓝牙回归 + 审计逐项确认）。
- [x] 不新增常驻轮询/扫描/无界缓存（改动仅用户驱动重试 + 有界缓存门控）。
- [x] 不引入新配对弹窗或连接副作用（未触碰 BLE/GATT/pairing 路径）。
- [x] 不降低已连接设备/电量/AirPods/iPhone/Apple Watch 支持（未改这些数据路径）。
- [x] 不造成面板高度跳变（正常重开仍用缓存占位；仅 `.failed` 时隐藏旧行，属正确行为）。
