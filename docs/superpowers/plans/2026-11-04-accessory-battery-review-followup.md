# #248 / #249 电量链路审查补修 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Watch 备用读取路由被耗尽预算、发现错误被当作成功空列表、跨路由计数重复三处缺口，并补齐 AirPods 归属与断连证据。

**Architecture:** 延续现有 Reader → Wire → DiscoveryController/电量 Controller 链。Watch 采用路由预算分配保证备用路由有执行机会；发现诊断通过带结果的协议方法向 controller 传递，保留部分成功数据。AirPods 沿用宁缺勿错，只有实机证据能决定分组键是否需要调整。

**Tech Stack:** Swift 6、Foundation、Combine、OSLog、Swift Testing / XCTest、现有 MobileBattery native helper。

**Spec:** 本会话用户的 #248/#249 要求、2026-11-04 GPT Sol 独立审查；既有证据与未验项见 [验证记录](../../issue-248-249-verification.md)。本计划是补修，不能把上轮 full 通过等同于本轮修复或硬件验收通过。

## Global Constraints

- 按用户最新要求新增分支/worktree：`fix-248-249-review-followup`，从 `fix/248-249-bluetooth-battery` 的 `3ff11ffbad0f1b0aeb27f362c72897ee7ac5907d` 开始；原分支基线 `053fb3c29b0b1c33c0c48a8c7bf04038f2fd1ab4`。原 worktree 与未提交计划保留不动；子任务使用 `group/smart-auto`。执行前重新检查状态，不覆盖后续改动。
- macOS 13 起，构建 SDK 26 或更新；不改变依赖、签名、Helper 权限和发布配置。
- Watch 每 job 总执行预算仍为 5 秒，read 最多 2 个并发、cycle timeout 25 秒；进程退出清理仍由现有 BoundedProcessInvocation 负责，不能声称墙钟时间严格等于 5 秒。
- 发现仍最多 8 个 phone group、每台仅已有 USB/network 路由；常规候选预算 8、首组允许 9；不额外探测设备、不读取电量来验证发现。
- 不新增周期轮询、持久路由缓存或权限；保留需求、取消和请求代次边界。日志无名称、UDID、地址、UUID、rowID；错误类别固定白名单。
- BLE 结果有效期保持 180 秒，失败冷却保持 60/300 秒，连续 3 次失败暂停；多 identifier 无法归属时整轮回退放弃。
- 普通测试不打开原生窗口/菜单栏，不启用 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1`。真机不能完成的项目明确写 NOT RUN。
- 最终交付须跑 `bash scripts/verify-local.sh full`；未验收前不合并、不推送、不关闭 #248/#249。

## Review Focus

1. USB 把分给它的时间用完后，已有 network 路由仍可执行；不是只验证“USB 很快失败”。归 Task 1。
2. `--list` 成功、发现路由全部超时/坏 JSON，不能显示 `failure=none`；部分成功不能被另一台失败抹掉。归 Task 2。
3. USB 的 `[p]` 与 network 的 `[p,w]` 是 2 个设备、3 个路由观察，不能混用统计口径。归 Task 3。
4. 同一 identifier 的 records 相互矛盾，不能一条匹配便为整组背书；断连事件至 profiler 完成间，晚回调不能补回旧电量。归 Task 4。
5. AirPods L/R/Case 的 identifier 是否共享必须有真实样本；键鼠样本、手写 fixture 不构成该证据。归 Task 5。

## 文件与顺序

| 任务 | 主要文件 | 顺序 |
| --- | --- | --- |
| 1：备用路由预算 | `Monitoring/MobileBatteryHelperReader.swift`、`MobileBatteryHelperReaderTests.swift` | 先做 |
| 2：发现结果与失败诊断贯通 | `Models/MobileBatterySnapshot.swift`、`Monitoring/MobileBatteryHelperReader.swift`、`Monitoring/AppleDeviceDiscoveryController.swift`、三者对应测试 | 任务 1 后 |
| 3：候选去重计数 | `Monitoring/MobileBatteryHelperReader.swift`、对应测试 | 任务 2 后 |
| 4：AirPods 一致性/晚回调防护 | `Models/BluetoothBatteryLevelFallback.swift`、`Monitoring/BluetoothDeviceController.swift`、对应测试 | 可与 1–3 并行 |
| 5：硬件证据和最终验证 | parser/fixture（仅证据需要时修改）、既有验证记录与 Watch 文档 | 所有代码冻结后 |

表中源码路径相对 `Sources/StatusTrioCore/`，测试相对 `Tests/StatusTrioCoreTests/`。任务 1–3 共写一个 Reader，必须串行；所有 Swift 编译/测试也由一个执行者串行运行。

---

## Task 1：保证 Watch 的备用读取路由不会被饿死

**Files:** 修改 `Sources/StatusTrioCore/Monitoring/MobileBatteryHelperReader.swift`；测试 `Tests/StatusTrioCoreTests/MobileBatteryHelperReaderTests.swift`。

**Interfaces:** 保留 `MobileBatteryReading.read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult`。在 Reader 增加纯函数 `static func watchRouteTimeout(remaining: Duration, remainingRouteCount: Int) -> Duration`，返回剩余预算除以剩余可尝试路由数；调用前保证两参数为正。

- [ ] 添加 `watchReadReservesBudgetForNetworkAfterUSBTimeout`：真实 Reader + scripted executor，listing 含 USB/network；USB 等到传入 timeout 后抛 timedOut，network 返回指定 Watch 61%。断言调用顺序为 USB→network、结果含该 Watch、USB timeout 不大于 2.5 秒、network timeout 为正。
- [ ] 添加纯预算断言：5 秒/2 路由 = 2.5 秒；只剩 1 路由获得全部剩余预算。覆盖只有 USB、只有 network、USB 成功后不调用 network、取消后不启动下一条、两条都失败时不重试第三次。
- [ ] 运行 `bash scripts/test.sh 'MobileBatteryHelperReaderTests'`，确认旧实现对“USB 用满预算”用例失败。
- [ ] `readWatch` 每次按当前 deadline 重算剩余预算，并用上述函数分配当前路由 timeout；不延长总预算、不并发读同一块 Watch。循环前检查取消。
- [ ] 同命令转绿，保留现有快失败/共享预算/部分成功测试。用例不得靠固定很短的 sleep 假装超时。
- [ ] 只暂存本任务文件，提交 `fix(apple-watch): reserve time for the alternate battery route`。

**取舍：** 本轮先修“备用路由永远不执行”，不增加跨 controller 的成功路由缓存；双路由时首路预算更短，需在真机中检查慢 USB 的影响。不能保证所有设备都在 5 秒内读取成功。

## Task 2：把发现路由失败传到 controller

**Files:** 修改 `Sources/StatusTrioCore/Models/MobileBatterySnapshot.swift`、`Sources/StatusTrioCore/Monitoring/MobileBatteryHelperReader.swift`、`Sources/StatusTrioCore/Monitoring/AppleDeviceDiscoveryController.swift`；对应 `MobileBatteryHelperReaderTests`、`MobileBatterySnapshotTests`、`AppleDeviceDiscoveryControllerTests`；同步 `docs/apple-watch-battery.md`。

**Interfaces:**

- 新增 `MobileBatteryDiscoveryResult: Sendable`：`candidates: [AppleDeviceCandidate]`、`routeDiagnostics: MobileBatteryDiscoveryRouteDiagnostics?`。
- `MobileBatteryDiscoveryRouteDiagnostics: Equatable, Sendable`：`attemptedRouteCount: Int`、`failedRouteCount: Int`、`failureCategories: Set<MobileBatteryDiscoveryFailureCategory>`。
- `MobileBatteryDiscoveryFailureCategory: String, Sendable, Hashable` 为固定枚举：`helper-unavailable`、`helper-timeout`、`helper-failed`、`helper-output-too-large`、`invalid-envelope`、`unsupported-schema`、`trust-required`、`host-identity-missing`、`session-unavailable`、`other`。
- 协议新增 `func discoverWithDiagnostics() async throws -> MobileBatteryDiscoveryResult`；扩展的默认实现包装既有 `discover()`、诊断置 nil，兼容其他实现，不伪造路由计数。生产 Reader 实现新方法，旧 `discover()` 委托新方法返回 candidates。
- Controller 改调新方法；`AppleDeviceDiscoveryDiagnostics` 增加可选 routeDiagnostics，并将它纳入 Equatable/日志变化去重。真实 Reader 的诊断始终非 nil；默认实现的 nil 表示未提供诊断。

- [ ] 添加 Reader→Controller 的集成用例（注入实际 Reader + executor）：空 listing、全部 timedOut、全部坏 JSON、一个 phone 成功另一个失败、USB 失败 network 成功、helper envelope 含 session-unavailable。
- [ ] 断言：空 listing 的 attempted=0/failed=0；两条路由均超时为 attempted=2/failed=2 且包含 helper-timeout；部分成功保留已验证 candidates；坏 JSON 为 invalid-envelope；未知原生类别归 other。上述失败不能显示为 `failure=none`。
- [ ] 先运行 `bash scripts/test.sh 'MobileBatteryHelperReaderTests|MobileBatterySnapshotTests|AppleDeviceDiscoveryControllerTests'`，确认新错误传播用例能抓住当前失败。
- [ ] 每条实际启动的 route 计 attempted；executor/decode 抛错，或成功 envelope 带 failure 时，计一次 failed 并归类；多个 failure 不把同一路由重复计数。所有子任务返回局部结果，由 task group 合并，不新增共享可变状态。
- [ ] `--list` 整体失败继续 throw 给现有 controller 错误处理。Task cancellation 直接取消，不作为一次“发现失败”发布。单 route 失败保留其他 route/phone 的成功候选。
- [ ] summary 按顺序明确记录状态：failed=attempted>0 为 all-routes-failed；0<failed<attempted 为 partial-failure；failed=0 且 candidates 为空为 empty；其余为 success。诊断为 nil 时记录 not-reported，不能伪造成功。另保留具体类别与 candidates 数，避免把“有 phone metadata 但 companion 没结果”误报成确认无 Watch。
- [ ] 同命令转绿，补关闭 surface/禁用 master 后迟到诊断不能覆盖新代次的断言。更新文档，说明 native companion 失败仍无法区分“没配 Watch/服务不可用”。
- [ ] 明确文件暂存并提交 `fix(apple-watch): propagate discovery route failures to diagnostics`。

## Task 3：统一发现和保留候选的计数口径

**Files:** 修改 Reader 及 `Tests/StatusTrioCoreTests/MobileBatteryHelperReaderTests.swift`，同步 Watch 文档。

**Interfaces:** 保留 `MobileBatteryDiscoverySummary` 六个既有字段。`discoveredCandidates` 计按 AppleDeviceID 去重的候选数；`retainedCandidates` 计实际返回候选数；`droppedWatchCandidates` 计真实省略的 Watch identity 数，不按 transport 重复算。

- [ ] Reader 初始化器增加 `discoverySummarySink: @escaping @Sendable (MobileBatteryDiscoverySummary) -> Void = { _ in }`，每周期汇总后调用一次；测试用现有锁保护的结果盒收集。生产仍只输出现有有界 debug，不增加另一路日志。不能只手工构造 groupShapes 来测试统计。
- [ ] 添加 `discoverySummaryDeduplicatesAcrossTransports`：USB=[p]、network=[p,w]，断言 discovered=2、retained=2、droppedGroups=0、droppedWatchCandidates=0。再覆盖多台手机重复路由、首组 9、后续组被预算丢弃。
- [ ] `bash scripts/test.sh 'MobileBatteryHelperReaderTests'` 先红；按 identity 去重每个 phone group 后再构造 shape/统计，保留 phone-ID 排序、整组保留与既有 cap 行为。
- [ ] 同命令转绿，日志不含标识符；提交 `fix(apple-watch): deduplicate discovery summary identities`。

## Task 4：AirPods 输入一致性和真实断连窗口

**Files:** 修改 `Sources/StatusTrioCore/Models/BluetoothBatteryLevelFallback.swift`、`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`；测试 `BluetoothBatteryLevelFallbackTests.swift`、`BluetoothAccessoryBatteryEventTests.swift`、必要时现有连接事件测试。

**Interfaces:** 保留 `merged(levels:accessories:devices:)`。controller 私有 `receiveConnectionEvent()` 的电量失效发生在 debounce 之前，不改变系统事件源接口。

- [ ] 添加“同 UUID 左耳 v76/p8207、右耳 v1133/p45915”的失败用例：整组拒绝，不能输出 L93/R12。只有组中每条 reading 的现有 identityMatches 判据都支持同一目标时，才能作为该目标的候选组；同型号/缺型号按既有明确规则处理，不凭名字或型号推导 UUID↔MAC 关系。
- [ ] 添加受控异步 controller 用例：挂起 accessory read → 发出连接变化事件 → 在新 profiler 完成前交付旧 reading；旧读数不得重新出现。用 continuation/手动 sleeper，不用抢时序的 sleep。
- [ ] 运行 `bash scripts/test.sh 'BluetoothBatteryLevelFallbackTests|BluetoothAccessoryBatteryEventTests|BluetoothConnectionEventTests'` 先红；确认当前 gate 仅在新 profiler 到达时失效，替换成 self.devices 并未解决更早窗口。
- [ ] 连接变化通知不带设备地址，因此收到任一有效通知即保守调用现有 `clearBatteryLevels()`，同步推进 batteryRequestGate 并清掉旧值，然后保留既有 debounce 刷新。合并突发事件时只由首个事件失效一次。此举会暂时清空其他设备的电量，文档需说明；不把事件当作蓝牙权限授权。
- [ ] 修同 identifier 的一致性检查；补合法 L/R/Case 共享 ID、多 ID 不能归属、已断连同型号邻居、无 ID、已有 primary level 保持不变的回归。
- [ ] 同命令转绿，再覆盖 master 关闭、蓝牙 unavailable、失去最后需求后的晚回调；提交 `fix(bluetooth): reject inconsistent groups and invalidate battery reads on connection changes`。

## Task 5：真实样本裁决与交付验证

**Files:** 更新 `docs/issue-248-249-verification.md`、`docs/apple-watch-battery.md`；仅有实机证据需要时修改 parser、分组与对应 fixture。

**Interfaces:** 交接以具体 SHA、命令、exit、PASS/FAIL/NOT RUN、实际硬件/系统为证据。不改变系统信任/配对，不抢前台。

- [ ] 采集真正 AirPods 的多 part `pmset -g accps -xml`，同时保留该时刻 profiler 连接状态；检查 Accessory Identifier/Group Identifier/Part Identifier、型号及各 part 的关联。公开 fixture 用一致替换后的虚构标识符；原始标识符不入常规日志或仓库。
- [ ] 测一套 L/R/Case、两套同型号、一连一断、离场、重新连接；分别观察 primary 与 accessory fallback，不能把 primary 正常显示当作 fallback 验收。若相同套的 parts 不共享 Accessory Identifier，先按证据补失败 fixture，再修分组；没有证据不自动改用 Group Identifier。
- [ ] 特别记录“列表外同型号旧 accps 仍存在”的场景；当前唯一型号匹配不证明身份。若真机复现错配，单独补用例并收紧回退，不能继续声称已完全阻止串台。
- [ ] 用已信任 iPhone+配对 Watch 验证 USB 正常、USB companion 失败但已有 Wi-Fi 可用、USB 单路、手机离线、取消/关闭面板。未连接硬件或无法安全操作则明确 NOT RUN，软件测试照常完成，但两 issue 不视为硬件验收通过。
- [ ] 若需要 live UI，先读 `.agents/skills/background-ui-testing/SKILL.md` 并采用项目后台测试方式；需要用户信任、配对、配置 Finder Wi-Fi 同步或前台操作时保留人工验收步骤。
- [ ] 最终集成先跑：

```bash
bash scripts/test.sh 'MobileBatteryHelperReaderTests|MobileBatterySnapshotTests|AppleDeviceDiscoveryControllerTests|MobileBatteryControllerTests|BluetoothBatteryLevelFallbackTests|BluetoothAccessoryBatteryTests|BluetoothAccessoryBatteryEventTests|BluetoothConnectionEventTests|NearbyBLEDeviceCatalogTests'
```

- [ ] fetch 比较最新 origin/main，记录共享文件冲突；源码冻结后执行 `bash scripts/verify-local.sh full`，完整通过才标本地验证 PASS。任何代码再改须重验受影响范围，并在最终整合树完成 full。
- [ ] 更新验证报告，明确上轮 PASS 对应旧 SHA，本轮新 SHA 和完整日志路径；去掉“改当前列表已经证明解决竞态”等不成立说法，保留真实 identifier 语义/硬件 NOT RUN。
- [ ] 明确文件暂存并提交证据文档；保留分支/worktree，等用户验收后才考虑合并和 issue 状态。

## 执行建议与完成定义

推荐同一执行者串行做任务 1–3（共用 Reader 和协议），任务 4 可由另一人独立做；测试串行，最终由新 reviewer 复核整条分支。若采用单人执行，顺序 1→2→3→4→5 即可。

**软件补修完成：** 三处 Watch 缺口和两类 AirPods 防护有真实先红后绿的回归、最终 full 通过、诊断边界与成本写清楚。

**Issue 验收完成：** 还必须有真实双 AirPods/多 part 身份样本、离场与 iPhone+Watch 结果。硬件缺失不阻止可独立完成的软件修复，但必须保留 NOT RUN，不能凭 mocks 关闭 issue。
