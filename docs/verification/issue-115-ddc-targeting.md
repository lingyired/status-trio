# Issue #115：当前默认音频输出的 DDC 目标匹配

本文记录 Issue #115 的实现依据、映射规则、验证边界与不能支持的形态。
文中不保存原始 Core Audio UID、完整 EDID、显示器序列号或完整 IORegistry 路径。

## 问题

“系统只有一个默认音频输出”不等于“只有一个可访问的 DDC Service”。
`Core Audio UID → framebuffer` 与 `framebuffer → DDC Service` 是两次独立映射，
前者唯一不能证明后者。因此旧实现里的 `externalFramebufferUUIDs.count == 1 && externalServices.count == 1`
只是“单屏时恰好成立”的偶然条件；改成删除 `count == 1` 再用 `.first` 取第一个 service，
会在多屏时向错误的显示器写入。

## 硬件采样（Gate 0）

在 Apple Silicon 实机上从 IORegistry 采集到如下结构（单台外接屏）：

- framebuffer：`IOMobileFramebufferShim`，`IONameMatched = "dispextN,t603x"`，
  属性 `EDID UUID` 与 Core Audio 外接输出的 UID 相同。
- 外接 `DCPAVServiceProxy`（`Location = External`）位于
  `.../dispextN:dcpav-service-epic:U/DCPAVServiceProxy`，其祖先节点名携带
  与 framebuffer 相同的 `dispextN` 分支标记。

共享键是固件注册的分支标记 `dispextN`：framebuffer 的 `IONameMatched` 前缀，
与 service proxy 祖先名 `dispextN:dcpav-service-epic:*` 的分支段一致。
该标记来自 DCP 固件，不是枚举顺序。

`IOAVServiceCopyEDID` 在本机（macOS 27）两种调用约定下均会崩溃，因此**未采用**，
改用上述拓扑标记做关联。

## 映射规则（实现）

纯匹配器 `DDCTargetResolver.resolve(outputUID:framebuffers:services:)` 依次要求：

1. 输出 UID 非空；否则 `missingAudioUID`。
2. 只考虑 `dispext*` 外接 framebuffer 与 `Location == "External"` 的 service；
   内置 `disp0` 分支永不成为 DDC 目标。
3. `EDID UUID == outputUID` 的 framebuffer 必须**恰好一个**，
   否则 `noMatchingFramebuffer` / `ambiguousFramebuffer`。
4. 该 framebuffer 的 `dispextN` 必须等于**恰好一个** external service 的分支标记，
   否则 `noAssociatedService` / `ambiguousService`。

只有第 3、4 步都唯一，才打开对应 `IOAVService` 并做 VCP `0x62` **只读**探测；
读数必须通过既有完整 reply 校验才允许写入，写后读回确认。
任何不确定情况一律 fail closed：不打开、不写入任何 service。

**受限旧路径**：若固件完全未注册分支标记（所有 service 的 `branchName == nil`），
仅在“一个 framebuffer + 一个 external service”这一严格无歧义形态下保留旧行为；
只要存在具体但矛盾的标记，则不回退。

## 协调器生命周期

- `DDCWorker` 的目标缓存按 UID 保存；`topologyChanged()` 调用 `invalidateTarget()`，
  因此 **UID 相同但拓扑变化**（例如换接口重插）不会复用旧 service，下一次读取会重新 resolve。
- 每次物理 I2C 读写前后都校验 `outputID`/`UID`/`generation`；切换输出、休眠/唤醒、
  拓扑变化都会使旧排队写命令失效，不会绑定到新目标。
- 无唯一匹配时发布 `scalar = nil`、`canSetVolume = false`，不显示上一设备的旧百分比；
  Core Audio 优先路径与 `canMute` 行为不变。
- 继续复用 150 ms 防抖、2 s / 10 s 轮询、看门狗与退避、单串行 worker；
  仅为当前默认输出 resolve，不新增常驻轮询。

## 诊断

失败原因通过 `os.Logger`（subsystem `com.lingsmbp.StatusTrio`，category `DDCTarget`）
输出**阶段 + 稳定枚举名字符串**，不含 UID/EDID/序列号/IORegistry 路径。

解决阶段（`stage=resolve`）：

`missingAudioUID`、`noMatchingFramebuffer`、`ambiguousFramebuffer`、
`noAssociatedService`、`ambiguousService`、`unsupportedArchitecture`、
`transportUnavailable`。

读取/写入阶段（`stage=requestWrite|replyRead|validate|set|readback`）：

`serviceUnavailable`、`requestWriteFailed`、`replyReadFailed`、
`replyRejected(wrongHeader|wrongVCP|wrongLength|zeros|untouched|badChecksum|invalidRange|displayReportedError)`、
`vcpRejected`、`timeout`。

> 早期 Build 38/40 的 `unsupportedVolumeVCP`、`readFailed`、`transportFailure`、
> `noProfile` 已被上面的阶段化词表取代：把“主机发不出去”“显示器不回”
> “回复不合法”“显示器明确拒绝”混成一个标签，是本次要修的可诊断性缺陷之一。
> 见本文件最后的“第三轮”与 `docs/design/audio-volume-backends.md`。

## 验证状态

| 项目 | 状态 |
| --- | --- |
| 单台外接 XV272U（`VCP 0x62` 读写） | **实机验证**（本轮：默认输出为 XV272U 时可调节音量） |
| 单台外接屏的拓扑关联（UID → framebuffer → service） | **实机验证**（只读探测 matched） |
| 空 UID / 内置输出 / 蓝牙输出 | **实机验证**：unavailable，零 DDC 写入 |
| 拓扑变化后同 UID 重新 resolve、A→B→A、无映射不写入 | **单元测试覆盖** |
| 双外接屏分别在 A/B 作为默认输出、只改当前一台 | **未验证**（本机只有 1 台外接屏） |
| 同型号同 EDID、扩展坞/DisplayLink 的判别 | **单元测试覆盖**（歧义即拒绝），未做真实多屏实机 |
| Intel Mac | 不适用，沿用现状不新增 DDC |

## 不能支持的形态

- 双（多）外接屏在**缺乏可证明 framebuffer→service 关联**时不提供控制；
  这是刻意 fail closed，不是缺陷。
- 同型号、同 EDID 且无独立端口证据的显示器无法区分，控件不可用。
- 需要 `IOAVServiceCopyEDID` 才能判别的机型在本机崩溃，未采用该 API。

## 工具链与自动化证据

- 本机：Swift 6.4、Xcode 27.0、macOS 27.0.1（M3 Max）。
- CI 基准：`macos-26`、Xcode 26.6、Swift 6.3.3。
- `swift test`：XCTest 1620 项（10 skipped，0 失败）+ Swift Testing 587 项 / 91 suites。
- `swift build -c release`：通过。
- 非发布预检 `release.yml`（`publish=false`）：见 PR 描述。

## BenQ 兼容性测试 Build（第二轮）

Issue #115 的报障设备是 Apple M5 Pro + BenQ，PR #116 的 Build 38 未修复。
本轮不改匹配器（除非日志证明它阻止了唯一匹配），只排查**匹配成功之后的 DDC/CI
读请求协议与回复校验**。

### Task A：Get VCP 请求封包显式化

`DDCPacket`（`Sources/StatusTrioCore/Audio/DDCReadProfile.swift`）用命名枚举而不是
布尔参数表达协议选择：

- `.standard`：校验和含数据地址 `0x51` → `82 01 62 DE`。
- `.legacy`：原实现，不含数据地址 → `82 01 62 8F`。

Set VCP 写入封包保持不变（`0x6E ^ 0x51`），写入前后仍做读回确认。

### Task B：同一 Service 内的受限只读 profile 探测

对**已经唯一确定的 Service**按顺序只读探测，命中即停止：

| 顺序 | Get VCP 校验和 | `ReadI2C` 第三参数 |
| --- | --- | --- |
| P1 | standard `DE` | `0x51` |
| P2 | standard `DE` | `0` |
| P3 | legacy `8F` | `0x51` |
| P4 | legacy `8F` | `0` |

- 目标不唯一时连只读探测都不运行（沿用 #116 的 fail closed）。
- 每个候选最多 2 次尝试，候选之间约 75 ms 总线空闲；实测单候选耗时约 75 ms，
  远小于 2 s watchdog。
- 只有通过 `DDCVolumeReply` 完整语义校验（头部、结果码、VCP 回显、校验和、范围）
  的回复才能选中 profile；全零、未改写的 `0xFF`、坏校验、错误 VCP、非法范围、
  显式拒绝（结果码 1）都不会解锁。
- 显式 `vcpRefused` 直接停止探测：显示器已经理解了请求，继续换候选没有意义。
- 选中的 profile 缓存在 `DDCDisplayTarget` 上，与当前 Service / UID / generation
  同生命周期；重新 resolve（切换输出、拓扑变化、唤醒）即失效重选。
- 探测整体失败后按 `readsBetweenProbes = 6` 节流，不会每次轮询都重跑全套。

### Task C：诊断

`os.Logger`（subsystem `com.lingsmbp.StatusTrio`，category `DDCTarget`）输出稳定命名的
低频行，不含 UID / EDID / 序列号 / IORegistry 路径，用**会话内随机短 ID** 关联：

```
ddc.resolve result=matched branch=dispext0 framebuffers=1 services=1 session=<rand>
ddc.resolve result=unavailable reason=noMatchingFramebuffer framebuffers=1 services=1 session=<rand>
ddc.probe profile=P1 replyKind=valid attempts=1 session=<rand>
ddc.selectedProfile profile=P1 result=usable elapsedMs=75 session=<rand>
ddc.write result=ok session=<rand>
```

`replyKind` 取值：`valid`、`zeros`、`untouched`、`wrongLength`、`wrongHeader`、
`wrongVCP`、`vcpRefused`、`badChecksum`、`invalidRange`、`transportFailure`、
`noProfile`。读取失败按“形状变化”去重，稳态不会每 2 秒刷屏。

测试者命令（已用真实设备验证可读取）：

```bash
log show --last 15m --info --style compact \
  --predicate 'subsystem == "com.lingsmbp.StatusTrio" AND category == "DDCTarget"'
```

### 本轮验证状态

| 项目 | 状态 |
| --- | --- |
| XV272U 在本轮的 P1（standard `DE`）读取 | **实机验证**：matched → P1 valid，读到当前值（只读，未写） |
| 上面四条诊断行能被 `log show --info` 取出 | **实机验证**（真实设备 + 真实调用的探针） |
| 空/未知 UID → `unavailable reason=noMatchingFramebuffer` | **实机验证** |
| 请求字节、Set VCP 0/50/100、profile 顺序与停止、拒绝即停、缓存与节流 | **单元测试覆盖**（新增 26 项） |
| BenQ（M5 Pro）能否用 P1–P4 之一读出 `0x62` | **未验证**：需报障用户回报日志 |
| P3/P4（legacy）在新代码里的实机行为 | **未验证**：XV272U 在 P1 就成功，未触发回退 |
| 双外接屏分别作为默认输出 | **未验证**（本机只有 1 台外接屏） |

## 第三轮（本次）：`vcpRefused` 误判、能力状态与失败分层

Build 40 之后用户仍反馈无效，但我们先修**自身可复现的协议判定缺陷**，
不改变 PR #116 的 `Core Audio UID → framebuffer → DCPAVServiceProxy` 唯一匹配算法，
也不改变 P1–P4 候选集合、顺序、Set VCP 封包与音量最大值映射。

### Task A：`vcpRefused` 假阳性（先红后绿）

旧 `DDCVolumeReply.classify()` 在检查 VCP 回显与校验和**之前**先看结果码：

```swift
if bytes[3] == 0x01 { return .vcpRefused }   // 旧行为
```

于是残留帧、错误 VCP 或坏校验和的帧只要第 4 字节是 `01`，就被判成
“显示器明确拒绝 `0x62`”，而 `DDCReadProfileProbe.select` 把该结果当作终止信号，
**P2–P4 再没有机会运行**。

现在校验顺序为：长度 → 空数据（全 0 / 全 `0xFF`）→ reply 头 → 回显 VCP →
完整校验和 → 结果码（`0` 通过、`1` → `vcpRefused`、其它 → `displayReportedError(UInt8)`）
→ 范围 → 取值。结论：

- 只有**长度、头、回显 VCP、校验和全部合法**的帧才能被判定为 `vcpRefused`，
  也只有它能让探测提前终止。
- 未知非零结果码不再被当作“支持证据”，也不再被误记为 `wrongHeader`。
- 复现测试：`DDCVolumeReplyTests.testResultCodeOneWithAWrongEchoedVCPIsNotARefusal`、
  `…WithABadChecksumIsNotARefusal`、`…OnATruncatedBufferIsNotARefusal`（修复前 3 项红）；
  `DDCReadProfileSelectionTests.testAStrayResultByteInAnInvalidFrameDoesNotEndTheProbe`。

### Task B：能力状态与读写验证分离

- 读结果从 `nil` 改为 `DDCVolumeReadResult.reply(...)` / `.failure(DDCReadFailure)`；
  失败分阶段：`serviceUnavailable`、`requestWriteFailed`、`replyReadFailed`、
  `replyRejected(<分类>)`、`vcpRejected`、`timeout`。
- 协调器发布 `DDCVolumeCapability`：`unknown`、`unavailable(reason)`、`readable`、
  `writeVerified`、`writeUnverified`。
- `writeVerified` **只**表示 I²C ack 之后的读回与写入寄存器值一致；
  读回失败或数值不一致时发布 `unavailable` / `writeUnverified`，
  UI 不会保留乐观值（`DDCVolumeCapability.scalar == nil` 即禁用滑块）。
- 写后只有一次读回，没有重试环；切换输出、休眠/唤醒、拓扑变化、
  worker reset 都会清空能力、待写值与 profile（沿用现有 generation fence）。
- UI 未改动：没有新文案、新设置项或新权限；`canMute` 仍只由 Core Audio 决定。

### Task C：排障矩阵

| 日志形态 | 说明 | 下一步 |
| --- | --- | --- |
| `ddc.resolve result=unavailable reason=…` | 没定位到唯一 Service：设备身份或连接路径问题 | 检查连接方式（HDMI / DP / USB-C / 扩展坞）、只有一个外接屏且无歧义 |
| `ddc.resolve result=matched`，但所有 `ddc.probe` 失败 | 已定位，但 Get VCP 读不回来 | 看 `stage=`/`outcome=` 分辨是主机发不出、显示器不回，还是回复不合法 |
| 完整合法的 `vcpRejected` | 目标设备拒绝 `0x62` Get | **不等于** Set 也不支持；不要据此推测其它指令 |
| `ddc.selectedProfile result=usable` + `ddc.write stage=set result=acknowledged` + `ddc.readback result=mismatch` | 写被 ack 但设备未接受目标值 | 协议/固件不一致；不要把它当成“已生效” |
| `ddc.readback result=verified` 但人耳音量不变 | 寄存器一致 ≠ 可听结果 | 需要另查显示器固件/音频路径或软件混音，单次读回无法判定 |

### 本轮验证状态

| 项目 | 状态 |
| --- | --- |
| `vcpRefused` 假阳性（错误 VCP / 坏校验和 / 截断帧） | **单元测试复现并修复**（修复前 3 项红） |
| 伪拒绝不终止探测、只有完整合法拒绝才终止 | **单元测试覆盖** |
| `readable` / `writeVerified` / `writeUnverified` / `unavailable` 分离 | **单元测试覆盖**（fake transport） |
| 失败不残留旧标量、无写坏目标、无重试环 | **单元测试覆盖** |
| BenQ（M5 Pro）实际读/写行为 | **未验证**：仍需该机型日志 |
| 真实外接屏（XV272U）的写后读回 | **实机验证**：Build `1.6.1 (41)` 上 4 次 Set VCP 均为 `acknowledged` + `verified`（39/47/95/100） |
| 写回一致与人耳音量一致的关系 | **未单独验证**：本轮只确认寄存器读回一致，不宣称可听结果由此证明 |

实机日志（XV272U，`session=cbec`）：

```
ddc.resolve result=matched branch=dispext0 framebuffers=1 services=1 session=cbec
ddc.probe profile=P1 stage=validate outcome=valid attempts=1 session=cbec
ddc.selectedProfile profile=P1 result=usable stage=validate elapsedMs=96 session=cbec
ddc.write stage=set result=acknowledged session=cbec
ddc.readback stage=readback result=verified requested=39 readBack=39 session=cbec
ddc.readback stage=readback result=verified requested=47 readBack=47 session=cbec
ddc.readback stage=readback result=verified requested=95 readBack=95 session=cbec
ddc.readback stage=readback result=verified requested=100 readBack=100 session=cbec
```

结论边界：这证明当前匹配、P1 读取、Set VCP 写入与读回确认在本机 XV272U 上工作；
它**不**证明 BenQ（M5 Pro）可用，也不证明所有显示器在写回一致时可听音量都会变化。
