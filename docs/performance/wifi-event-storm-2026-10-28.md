# CoreWLAN Wi-Fi 事件风暴分析与修复计划（2026-10-28）

## 结论

现有证据把问题指向 CoreWLAN 事件回调的持续投递，以及应用侧“每个回调创建一个
MainActor `Task`”再触发立即重连的放大链。它更像系统事件对象和队列的持续保留，
不是普通 Swift 对象泄漏，也不是图标设计器或图标渲染器的热点。

本次修复先消除应用侧可确认的无界放大：同一回调窗口只创建一个主线程任务；
invalidated 重连使用有界退避和窗口预算；常规恢复复用现有 `CWWiFiClient`；
每个客户端代际的回调都携带代际令牌，被替换客户端上的迟到回调在 mailbox 锁内
拒绝；停止时取消待执行恢复。异常 CoreWLAN 状态本身尚未在本地复现，因此不能
宣称已经证明或修复 macOS/CoreWLAN 内部缺陷。

## 现场证据与边界

以下现场数据由问题报告提供，本次工作树没有重新采集原始 `sample`、`heap`、
`leaks` 或进程 RSS 序列：

- 异常进程运行约 3 天 14 小时，CPU 约 98%，RSS 从约 988 MB 增长到 1.6 GB。
- 约 6 分钟内，48 字节堆块从 8,662,379 增至 14,882,993，增加 6,220,614 块。
- `sample` 热点位于 `com.apple.wifi.xpcclient.event.*` 队列和 CoreWLAN 的
  `__startMonitoringEventWithType:`，没有图标渲染热点。
- `leaks` 报告 0 leaks。
- 对照进程：1.7.0 运行约 15 小时为 0% CPU / 169 MB RSS；1.7.5 运行约
  2 小时 17 分为 0% CPU / 207 MB RSS。
- 重启 1.7.5 和 2.0 诊断版后，空闲状态正常，说明异常不是启动时必现。

### 数据口径校正

48 字节块增加 6,220,614 个，仅按请求字节计算的原始载荷是：

```text
6,220,614 × 48 = 298,589,472 bytes ≈ 284.8 MiB
```

因此不能把“48 字节块增加数”直接解释成约 714 MB。RSS 的 988 MB 到 1.6 GB
变化、同期 allocator 元数据、更大对象、碎片和不同采样时间窗需要分别保留。
原始报告中的“约 714 MB”如果没有对应的起止 RSS 或 `heap -s` 时间戳，应标为
待复核，而不是由 48 字节块数量推导。

`leaks` 为 0 也不能排除保留型增长。它不等同于 XPC、CoreFoundation 或系统框架
对象仍被正常引用但生命周期异常长的情况。

## 受影响代码

工作树基线为 `58b195f8ae9efa8010dff37f900fe41935d2cd1e`。交付前重新
核对时，`origin/main` 已前进到
`067ae966205463547acf40cb819817a744e25f09`；该区间只修改发布工作流和
发布文档，没有修改 Wi-Fi 监控或相关测试。以下版本的 Wi-Fi 文件哈希仍一致。
用
`git show <rev>:Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift | shasum -a 256`
核对，以下版本的文件哈希均为
`242e6a7c05769d9845eedcc15bf3884799e241fc892c00c2b0c96245b8d90d1b`：

- `v1.7.2`
- `v1.7.3`
- `v1.7.4`
- `v1.7.5`
- `origin/main`
- 修复前的工作树基线 `58b195f8ae9efa8010dff37f900fe41935d2cd1e`

`WiFiStatusReader.swift` 在上述版本中也一致，SHA-256 为
`5ff12d150c237aba6cc920cfc0b7f410f2c36c4a5c4217c6554d9fabb5b4ab90`。
这支持“旧版本并不缺少该监控路径，而是没有进入相同系统异常状态”的判断。

本地 macOS 27 SDK 的 `CWWiFiClient.h` 明确说明 `CWWiFiClient` 是重对象，
调用方应使用一个长期实例，而不是创建多个短生命周期实例。修复前的
`restartMonitoring()` 每次恢复都会执行 `eventMonitor.restart(...)`，而
`CoreWLANWiFiEventMonitor.restart(...)` 会重新创建客户端。

## 放大链

1. CoreWLAN 在异常状态下高频投递 Wi-Fi 事件。
2. 每个 delegate 回调此前都直接创建一个 MainActor `Task`，任务数量和保留时间
   由系统回调速率决定，没有应用侧上限。
3. `clientConnectionInvalidated()` 到达主线程后立即 `recover()`，每个回调都可
   触发旧事件监听拆除和新 `CWWiFiClient` 创建。
4. 新客户端重新注册六类事件；如果系统仍处于异常状态，回调继续到达，形成
   “回调 → 主线程任务 → 客户端替换 → 再回调”的循环。
5. `leaks` 看不到传统泄漏，但 XPC/CoreWLAN 事件对象和任务队列可以持续增长，
   同时主线程和 Wi-Fi XPC 队列维持高 CPU。

第 3、4 点是当前最强的应用侧放大假设。系统中为何进入持续 invalidation 尚未
通过可重复实验确定，仍需要现场诊断日志和框架内部样本。

## 实施计划与完成状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | 记录版本哈希、现场热点和证据口径，确认不是渲染路径 | 完成（现场原始文件待复核） |
| 2 | 增加线程安全 mailbox，合并事件并保持 RSSI/关联变化顺序 | 完成 |
| 3 | invalidation 使用 1/2/5/15/30 秒退避，300 秒最多 5 次，超限暂停 | 完成 |
| 4 | 常规恢复复用客户端；invalidation/暂停恢复才创建新客户端 | 完成 |
| 5 | 用代际代理和代际 mailbox 丢弃已替换客户端的迟到回调 | 完成 |
| 6 | stop 取消恢复任务；避免已取消任务清理较新的恢复任务 | 完成 |
| 7 | 增加可选诊断日志和焦点/全量自动化验证 | 聚焦完成；全量已执行并被既有渲染指纹失败阻断 |
| 8 | 2 小时空闲与 72 小时异常状态浸泡 | NOT RUN |

### 事件合并

`Sources/StatusTrioCore/Monitoring/WiFiEventMailbox.swift` 在锁内维护一个待处理
批次。只有本批次第一次入队会创建 MainActor `Task`；后续回调合并到：

- 一次 refresh 需求；
- 最新一次 RSSI；
- interruption、invalidation、association、mode 各一个布尔信号。

关联变化会丢弃同批次中发生在它之前的 RSSI；发生在它之后的 RSSI 保留。这样
不会把上一个网络的 RSSI 带到新关联，也不会让回调速率决定任务数量。

每个 CoreWLAN 客户端注册周期都有独立代际。代理把回调连同代际传入 mailbox；
激活新代际时，旧代际待处理批次被清空，之后到达的旧代际回调在锁内直接拒绝。
因此即使代理完成 target 查找后、调用前发生客户端替换，也不能污染新代际。

### 有界恢复

`WiFiMonitor` 对 invalidation 使用以下策略：

- 退避：1、2、5、15、30 秒。
- 预算：任意 300 秒窗口最多 5 次替换尝试。
- 超限：停止 CoreWLAN 事件监听，保留普通状态读取和路径监控。
- 恢复：外部 `recover()` 重置预算；窗口过期后的成功接口读取也会恢复监听。

停止或 deinit 会取消待执行恢复。恢复任务带 attempt ID，已取消的旧任务不能
清除较新的任务引用，避免并发恢复绕过节流。若外部 `recover()` 在退避等待期间
到达，它会取消等待，并在已有 invalidation 或暂停状态要求时立即替换客户端；
健康状态下的普通恢复复用现有客户端。普通无接口恢复不会与该替换竞争。

### 客户端生命周期

`CoreWLANWiFiEventMonitor` 现在区分两种重启：

- 常规无接口读取恢复：停止并重新注册事件，复用现有客户端。
- invalidation 或暂停后的恢复：创建新客户端，因为旧客户端已明确失效。

每次注册都使用新的 delegate proxy。代理在锁内完成“检查代际并投递”，重启时
先 invalidate 旧代理，等待已经通过检查的回调进入 mailbox，再激活新代际；因此
不会出现旧客户端回调越过交接窗口后静默丢失的情况。激活会返回尚未 drain 的完整
批次，重启路径据此应用 pending association/RSSI/refresh，并在其中含 invalidation
时强制替换客户端。代理弱引用目标，不形成监控器循环引用。

## 诊断日志

默认关闭。需要诊断时，从 Terminal 直接启动当前构建，让环境变量进入进程：

```bash
STATUS_TRIO_WIFI_DIAGNOSTICS=1 \
  "/Applications/Status Trio.app/Contents/MacOS/StatusTrio"
```

Dev 构建使用实际的 `.app/Contents/MacOS/<executable>` 路径替换以上命令。
然后观察：

```bash
log stream --style compact \
  --predicate 'subsystem == "com.lingsmbp.StatusTrio" AND category == "WiFiMonitor"'
```

日志最多每 5 秒输出一次，包含当前代际、callback 分类计数、已交付批次、最大
待处理信号数、窗口内替换次数和 suspended 状态。日志不输出 SSID。恢复或暂停时
强制记录一条。

## 自动化验证

风险等级为高：改动涉及 `@MainActor`、回调线程、任务取消、重试和生命周期。

聚焦回归已执行：

```bash
bash scripts/test.sh 'WiFiClassifierTests|WiFiEventMailboxTests|StatusMenuBuilderTests'
```

结果为 `107/107`：

- `WiFiClassifierTests`：`92/92`
- `WiFiEventMailboxTests`：`9/9`
- `StatusMenuBuilderTests`：`6/6`

覆盖事件合并、并发入队、代理交接 barrier、关联/RSSI 顺序、pending association
跨重启、单次替换、1/2/5/15/30 秒退避、窗口暂停、外部恢复、成功读取后恢复、
停止取消、旧任务清理隔离、客户端复用/替换和迟到代际回调。

全量命令已执行：

```bash
git diff --check
bash scripts/verify-local.sh full
```

结果：

- `git diff --check`：通过。
- `bash scripts/verify-local.sh docs`：通过，覆盖 shell 检查、禁止模式、
  本地化回归和 workflow policy。
- PowerHelper XCTest：`15/15` 通过。
- Core XCTest：`1957` 个，`8` skipped，`2` 个 assertion failure，均来自未修改的
  `AppIconPreviewTests.testCommittedIconComposerArtworkMatchesTheRenderer`
  light/dark 指纹。AppIcon 不一致已在改动前的 clean-base 复现。
- Swift Testing：`763` 个、`112` suites，`1` 个 issue，来自未修改渲染路径的
  `ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`。
- 因上述既有失败，`verify-local.sh full` 在 Swift test step 以 exit 1 停止；没有
  跳过、放宽或修改这些测试。后续步骤已按同一最终树手动逐项执行。
- Release build、非 Universal app bundle、macOS 13/SDK 27 平台契约、Mobile
  Battery bundle、Privileged Helper bundle：通过。
- 22 项 native/offline 契约检查：`22/22` 通过。

完整本地 profile 不证明真实 CoreWLAN 异常状态、macOS 13 运行时、签名、
notarization、DMG、Universal 打包或发布产物。

## 运行时验收

最终树使用 arm64 macOS 27.2，启动后预热 15 秒，再连续采样 60 秒，并额外做
6 次 10 秒 CPU/RSS 点采样：

- CPU：6 次均为 `0.0%`。
- RSS：中位数 `82.33 MiB`，峰值 `82.45 MiB`；点采样保持约 `84 MB`，无增长。
- Physical footprint：中位数 `18.58 MiB`，峰值 `18.67 MiB`。
- `leaks <pid>`：`0 leaks for 0 total leaked bytes`。
- `heap <pid> -s`：退出成功，最终 physical footprint `18.6M`。

更早的首次冷启动运行在 12–14 秒观察到一次约 `332 MiB` 的 footprint 瞬时峰值，
随后回落到约 `41 MiB`；预热后的最终运行没有该峰值。该瞬时峰值的来源尚未定位，
不能归因到 Wi-Fi 代码。

以下仍未完成，不得标记为通过：

- 2 小时运行：0% 空闲 CPU，RSS 无单调增长；打开/关闭详情不影响结果。
- 72 小时现场等价运行：CPU、RSS、`heap -s` 和 CoreWLAN 回调计数稳定。
- Wi-Fi 开关、睡眠/唤醒、网络切换、网卡消失/出现后事件监听仍可用。
- macOS 13 真机运行：PASS / FAIL / BLOCKED / NOT RUN 单独记录。
- 异常状态复现时保存 `sample <pid> 10 -file`、`heap <pid> -s`、`leaks <pid>`
  以及 `STATUS_TRIO_WIFI_DIAGNOSTICS=1` 时间窗。

## 止损与下一步

如果日志显示回调仍高速到达但替换次数已受控，说明应用侧放大已收敛，但
CoreWLAN 系统事件风暴仍存在；此时应保留诊断版并提交 Apple 反馈，不要继续缩短
轮询间隔或用更多客户端重建掩盖问题。

如果日志显示替换次数在窗口内异常增长，应先检查是否存在外部高频 `recover()`、
睡眠唤醒风暴或未覆盖的旧客户端回调，再调整预算；不能直接移除日志或放宽测试。
