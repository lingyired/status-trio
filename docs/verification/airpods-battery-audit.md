# AirPods 电量准确性 / 蓝牙性能专项 —— 问题链路表与审计

- 分支：`bluetooth-stale-battery-connection`（已 rebase 到最新 `origin/main`，基线 `e7bb4eb3`）
- worktree：`.agents/worktrees/bluetooth-stale-battery-connection`
- 性质：代码审查 + 单元测试；真机/性能项按 `NOT RUN` 记录
- 用户现象：AirPods 实际约 30%，面板显示 90%；放回充电盒（已断开）仍显示连接；曾出现两副 AirPods 电量串台

## 1. 真实数据流

### 1.1 配对耳机（主链路，唯一来源）

```
system_profiler -json SPBluetoothDataType (4s BoundedProcessInvocation)
  → BluetoothPairedDeviceReader.parse        // 设备列表 + isConnected(device_connected/not_connected)
  → BluetoothProfilerReportCache.store(now)  // 原始 JSON 复用，maxAge 5s
  → BluetoothBatteryReader.parse             // 只取 device_connected 段 → main/left/right/case
  → BluetoothDeviceController.connectedBatteryLevels // 只保留当前已连接地址
  → batteryLevels @Published
  → BluetoothPanelMapper / BluetoothDeviceListModel / BluetoothDeviceRow(segments)
```

连接状态与电量**来自同一份 profiler 报告**：`isConnected` 由 `device_connected`/`device_not_connected` 段决定；电量解析器只接受 `device_connected` 段。因此“哪个接口负责连接状态”和“哪个接口提供电量”是同一个上游数据源。

### 1.2 配件补缺（第二来源，只在主源无电量时）

```
pmset -g accps -xml
  → BluetoothAccessoryBatteryReader.parse   // 按 Accessory Identifier 标识配件，part→left/right/case
  → BluetoothBatteryLevelFallback           // 仅当 profiler 对该设备无电量时补；只补缺，不覆盖
  → readAccessoryLevelsIfNeeded → batteryLevels
```

### 1.3 附近 BLE（独立来源，非配对耳机主链路）

```
BluetoothLEBatteryScanner（仅 nearby 界面需要时）→ NearbyBluetoothBatteryDevice(lastUpdated, 180s 过期)
  → BluetoothNearbyDeviceMerge（仅 Apple 移动型号按名称折叠进配对行；其它为 nearby 行，isConnected=false）
```

## 2. 问题链路表（分类）

| # | 现象 / 假设 | 类别 | 证据 / 位置 | 结论 |
|---|---|---|---|---|
| P1 | 打开面板前已连接的设备没有断连观察者，断开只能靠 120s 安全网 | **已证实（源码）** | `BluetoothConnectionEventMonitor.start()` 只注册系统级 connect；disconnect 仅在 `deviceConnected` 内为该设备注册 | 已在分支修复：启动时枚举已连接设备补注册断连（见 §4） |
| P2 | 断连后旧电量被继续当作实时值 | **已证实（已被现有代码防护）** | `receiveConnectionEvent`→`connectionGeneration++`+`clearBatteryLevels()`（advance batteryRequestGate）；`refreshBatteryLevels` 的 `deviceSnapshotGeneration==connectionGeneration` gate；`connectedBatteryLevels` 过滤；`snapshotsExpireLevelsAndLateReadsCannotRestoreThem` 测试 | 无漏洞；补充测试覆盖 |
| P3 | 旧请求回调（90%）晚于新读取（30%）返回并覆盖 | **已证实（已防护）** | `batteryRequestGate.advance/accepts`；cache 命中不重设 `storedAt`（`cacheServedReadDoesNotExtendTheReportLifetime`） | 无漏洞；测试覆盖 |
| P4 | 配件读取 `readDataToEndOfFile()+waitUntilExit()` 无界阻塞 | **已证实（源码）** | `PmsetAccessoryBatteryWorker.readAccessoryPowerSources` 原实现 | 已修复：改用 `BoundedProcessInvocation.runSync`（见 §5） |
| P5 | profiler 与 pmset 数值冲突（90 vs 30）时如何取舍 | **合理怀疑 / 需真机证据** | `BluetoothBatteryLevelFallback` 注释与实现：主源有值即不覆盖 | 保守策略：主源优先、辅助只补缺；数据冲突时**不自动选高/低值**。若主源本身错，App 无法自动判定（见 §3） |
| P6 | 系统 profiler 本身返回旧值（真实 30 却报 90） | **需真机证据（类别 A）** | `docs/known-limitations.md`；电量无硬件采样时间戳 | 若属此类，属 macOS 数据源，非解析错误；需用户同一时刻的 `system_profiler`/`pmset` 输出取证 |
| P7 | 把 Case/单耳数值误当整机电量 | **已证实（已防护）** | `BluetoothBatteryReader` 通道解析；`parsesComponentAndAggregateBatteryLevels`；fallback part→channel | 无漏洞；`Main` 只来自 `device_batteryLevelMain`，不由单耳/仓推导 |
| P8 | 两副同型号 / 同名 AirPods 串台 | **已证实（已防护）** | `BluetoothBatteryLevelFallback` 按 Accessory Identifier 唯一匹配；同名/同型号拒绝回退；`BluetoothBatteryLevelFallbackTests` 覆盖 | 无漏洞；无法唯一匹配即不回退 |
| P9 | 缓存/晚回调让 30/30/29 或相同值被抑制或“纠偏” | **设计原则** | 无基于“数值变化”的抑制逻辑 | 每次读取都按原值发布；新增 `everyReadPublishesEvenWhenTheLevelRepeatsOrBarelyChanges` |
| P10 | 陈旧窗口：120s 安全网 + 事件去抖 750ms | **已知设计权衡** | `safetyNetInterval=120s`、`connectionEventDebounceInterval=750ms` | 不改；本次不引入任何高频轮询 |

## 3. 30% 显示 90% 的三类区分（Task 2.1）

必须用用户真机同一时间窗口取证，不能靠 mock 测试下结论：

```bash
system_profiler -json SPBluetoothDataType   # 看 device_connected 段该设备 main/left/right/case
pmset -g accps -xml                          # 看 accessory 的 Percentage/Part Identifier
```

- **A：系统本身返回 90%** → 非解析错误，属 macOS 缓存/数据语义；App 只能忠实显示或显示未知，不能凭空“修对”。
- **B：系统返回 30%，App 显示 90%** → 才是 App 侧（旧回调 / 缓存 / 合并 / UI 状态）；现有 gate 已覆盖，若仍出现需按 B 单独取证定位。
- **C：不同通道不同值（如 Case 90 / L 30 / R 30）** → 不得把 Case 当整机；解析与展示已按通道分离。

`observedAt` 只能表示“App 取到数据的时刻”，不能代表硬件采样时刻；在无硬件时间戳时不伪造新鲜度保证（`docs/known-limitations.md`，`system_profiler`/`pmset` 均无时间字段，已实测）。

## 4. 连接事件缺口修复（分支已有 commit）

- `IOBluetoothConnectionEventMonitor.start()`：注册系统 connect 通知后，枚举 `IOBluetoothDevice.pairedDevices()` 中 `isConnected()` 的已配对设备，逐个补注册 disconnect 通知（adopt）。
- 补注册不触发刷新 handler；token 生命周期与既有 connect 路径一致（替换/断开/stop 解注册）；空标识与 SDK 返回 nil 安全。
- 不使用额外轮询。
- 测试：`BluetoothConnectionEventTests.testAdoptedConnectedDevicesGetTheSameDisconnectBookkeepingAsAConnect`。

## 5. pmset 子进程有界化（本次修复）

- 原 `PmsetAccessoryBatteryWorker.readAccessoryPowerSources()` 使用裸 `Process()` + `readDataToEndOfFile()` + `waitUntilExit()`，子进程/后代持有管道时无限阻塞 serial queue。
- 改为复用 `BoundedProcessInvocation.runSync(executableURL:arguments:timeout:)`，超时杀进程、限制输出、区分失败与成功空结果；`timeout` 默认 4s。
- 测试：`BluetoothAccessoryBatteryTests` 新增 `hungChildTimesOut`（/bin/sleep 30 被 ~0.3s 内终止返回 nil）、`nonZeroExitAnswersNil`、`boundedReadReturnsStdout`。

## 6. 现有性能基线（本次不改动）

| 机制 | 基线 |
|---|---|
| 蓝牙设备兜底刷新 | 120s，仅可见时 |
| 连接事件防抖 | 750ms |
| Accessory 电量通知防抖 | 3s |
| Profiler 共享报告缓存 | 5s |
| Profiler 超时 | 4s |
| Nearby BLE 扫描窗口 / 最短间隔 | 5s / 60s |
| pmset 读取超时（本次新增） | 4s（有界） |

## 7. NOT RUN（需真机 / 需真实硬件）

- 30%/90% 真实复现与 A/B/C 归类（需用户真机 `system_profiler`/`pmset` 同时刻数据）。
- AirPods 断连事件在真实硬件上是否触发（adopt 后）。
- CPU / 内存 / Energy Impact / 子进程次数的真实性能对比（Phase 5.3 A–D）。
- 两副同型号真实 AirPods 串台真机验证。
- macOS 13 运行时兼容性。
