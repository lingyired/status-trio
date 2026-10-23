# 音量后端架构（RFC，本轮只写设计，不实现）

本文评估 Status Trio 音量控制的**后端选择策略**，为 Issue #115 之后的可扩展性
留出结构，同时明确本轮**没有**引入任何第三方依赖、虚拟音频驱动或新权限。

状态：**设计稿（未实现）**。文中的接口草案不是既有契约。

## 1. 现状（本轮改动之后）

```text
Core Audio 默认输出
  └─ VolumeMonitor
       ├─ Core Audio 可写（reading.scalar != nil && canSetVolume）  ← 优先，直接使用
       └─ DDCVolumeCoordinator（仅当前默认输出的唯一 DDC Service）
            └─ DDC VCP 0x62 Get / Set
```

- 选择顺序是**固定的两段**：Core Audio 可写即用 Core Audio，不发起任何 DDC 探测
  （`DDCVolumePresentationTests.testReadableWritableCoreAudioScalarKeepsPriorityOverDDC`）。
- DDC 只在“当前默认输出 + 唯一匹配的 Service + 完整合法 `0x62` 回复”时提供交互。
- 能力状态由 `DDCVolumeCapability` 承载：`unknown`、`unavailable(DDCReadFailure)`、
  `readable`、`writeVerified`、`writeUnverified`。UI 只在 `scalar != nil` 时允许拖动。
- 所有失败都带阶段标签（`resolve` / `requestWrite` / `replyRead` / `validate`），
  不再用 `unsupportedVolumeVCP` 统称。

## 2. 设计原则

1. **不做品牌判定。** 后端选择只依赖运行时探测结果
   （`nativeAvailable`、`ddcReadAvailable`、`ddcWriteVerified`），
   绝不出现“BenQ 走软件音量”“某型号禁用 DDC”这类硬编码。
2. **能力分离。** “能读”与“能写”是两个独立事实：`readable` 不能推出
   `writeVerified`；`writeVerified` 只表示寄存器读回与写入值一致，
   不表示人耳听到的音量一定变化。
3. **单一写入者。** 任一时刻只有一个后端被允许写当前输出，避免两个写入路径互相覆盖。
4. **fail closed。** 目标不唯一、回复不合法、读回不一致时一律不写、不显示乐观值。
5. **不静默安装、不静默提权。** 需要额外软件或权限的后端只能由用户显式启用。

## 3. 抽象草案（评估结论：本轮不落地）

```swift
enum VolumeCapability: Equatable, Sendable {
    case unknown
    case unavailable(reason: String)        // 稳定枚举字符串，不含设备身份
    case readable(current: Double)
    case writeVerified(current: Double)
    case writeUnverified(current: Double)
}

protocol VolumeControlBackend: AnyObject {
    var identifier: String { get }          // "coreAudio" / "ddc" / "betterDisplay" / "softwareMixer"
    var capability: VolumeCapability { get }
    func setVolume(_ scalar: Double) async -> Bool
}

struct VolumeBackendSelectionPolicy {
    /// 输入全部是探测结果，没有任何设备名称或厂商信息。
    var nativeWritable: Bool
    var ddcReadable: Bool
    var ddcWriteVerified: Bool
    var userEnabledBackends: Set<String>

    func selectedBackend() -> String
}
```

**为什么不本轮实现**：`VolumeMonitor` 已经承载 Core Audio 读取、设备枚举、DDC 协调、
watchdog 与 generation fence；把 `setVolume` 摘进后端协议会改动
`VolumeMonitor`、`SystemStatusStore`、面板绑定与既有 20 多个音量测试的调用形状，
属于与 #115 无关的重构风险。因此本轮只保留等价语义（能力枚举 + 阶段化失败），
等真正接入第三个后端时再抽接口。

未来判定规则（草案）：

| 条件 | 选择 |
| --- | --- |
| `nativeWritable` | Core Audio（现状不变） |
| 仅 `ddcReadable`（未验证写） | DDC，且写入后必须读回确认 |
| `ddcReadable` 为假但用户已显式启用其他后端 | 该后端 |
| 都不满足 | 不提供控制（`unknown`），不退化到缓存值 |

## 4. BetterDisplay 集成评估（未来可选，本轮不接入）

### 4.1 可用的公开接口

BetterDisplay 公开了多种集成方式（[Integration 指南](https://betterdisplay.pro/guide/integration/)，
[CLI 参考](https://betterdisplay.pro/guide/integration/cli-reference/)）：

- 命令行：`/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay <operation> [-参数]`。
- 独立 CLI 外壳 [waydabber/betterdisplaycli](https://github.com/waydabber/betterdisplaycli)，
  通过 Distributed Notification Center 转发一次性命令，要求 BetterDisplay ≥ 2.2.0
  正在运行且允许 CLI/通知集成（默认允许）；请求带 15 秒超时与失败退出码。
- HTTP（本地端口）与自定义 URL scheme 集成。
- macOS Shortcuts（App Intents）。

对应操作包括 `volume`（文档写明 “Affects only devices with hardware volume control
(DDC volume)”）、`mute`、`sendCEC=volumeUp` 等。

### 4.2 关键判断：它不自动成为我们的 fallback

1. **`volume` 被文档化为 DDC 音量操作。** 因此“用户装 BetterDisplay 后能用键盘调音量”
   不能证明存在独立的软件混音后端，甚至可能只是换了一个进程去写同一个 VCP `0x62`。
   它也不能证明我们的 I²C 读路径应该成功。
2. **行为未经验证。** 在报障用户的 BenQ 上，我们没有确认 BetterDisplay 的哪条路径
   真正改变了声音。在获得该验证之前，把它写成自动 fallback 等于把未验证假设
   变成用户可见承诺。
3. **必须用户显式启用。** 只能由用户安装、手动开启集成开关、在 Status Trio 中显式选择；
   不允许隐藏安装、不允许代启动其进程。
4. **单写入所有权。** 若同时启用 DDC 与 BetterDisplay，两边都会写同一个寄存器。
   策略必须保证同一时刻只有一个写入者；建议做法是选择 BetterDisplay 时停用我们的 DDC 写，
   并把 DDC 读（只读、无副作用）保留为观测。
5. **需要版本与错误反馈。** 命令失败（未运行、集成被关闭、版本过老、Pro 功能缺失）
   必须回落到“不可用”状态并给出原因，不能静默无反应。
6. **节流。** 调用是子进程/Distributed Notification 往返（外壳自带 15 秒超时），
   不能跟随拖动的每个像素；必须沿用现有 150 ms 防抖与写后确认，并限制并发调用。

结论：**值得继续研究，但必须先有一次用户侧实测**证明 BetterDisplay 在其 BenQ 上
走的是哪条后端、是否改变实际声音。这是独立的后续工作项，不是本轮范围。

## 5. 软件混音后端评估

需要区分两类完全不同的东西：

1. **虚拟音频设备**（BlackHole、Soundflower 一类）：把系统输出改接到一个虚拟设备。
   用户必须安装内核扩展/系统扩展并在音频 MIDI 设置里改路由；伴随延迟、
   采样率匹配、默认设备切换、与蓝牙/内建输出的恢复等问题。
2. **完整软件混音器**（如 eqMac 一类）：在虚拟设备之上再加每应用音量、EQ 与驱动层控制。

两者都需要：安装第三方组件、可能的新权限、系统默认输出变更（与引擎现有的
“默认输出为内建/蓝牙/USB DAC 时不触发 DDC”假设冲突）、以及设备切换后的恢复逻辑。

**本轮不引入任何虚拟音频设备**，也不改变系统默认输出。相关信息只作为
未来独立设计的输入，且任何软件混音后端都必须是用户显式安装并启用的独立组件。

## 6. 硬件读写能力进一步分离

一些显示器可能“只写不读”。当前策略是：**没有合法读回就不启用写入**
（未知最大值、未知当前值、无法确认静音状态时猜测 100 或使用本地缓存都不安全）。

未来若要做“只写”模式，需要满足：

- 用户显式开启（不是默认）；
- 明确告知最大值未知、初始值未知；
- 写入后仍尝试读回，读回失败只显示“已发送，未确认”，不显示百分比。

在本轮中，这种设备会稳定落在 `unavailable(replyReadFailed)` 或
`unavailable(replyRejected(...))`，并可通过日志区分，不需要新增 UI。

## 7. 冲突与禁用路径（现状 + 未来）

- 现状：Core Audio 可写时 DDC 完全不参与；DDC 不可用时滑块禁用但**静音能力仍按
  Core Audio 报告**（`canMute` 与 `canSetVolume` 独立）。
- 未来：每个后端都可被用户单独禁用；被禁用的后端不得参与选择，也不得在后台写入。
  切换输出、休眠/唤醒、热插拔都会清空后端状态与待写入命令（复用现有 generation fence）。
- 日志只记录后端标识、阶段与稳定失败枚举，不记录设备身份。

## 8. 未决问题

1. BetterDisplay 在报障用户机器上实际使用的后端（DDC VCP、HDMI-CEC 还是其他），
   以及它是否真的改变可听音量。
2. 是否存在“只写不读”的真实设备样本，用于验证只写模式的提示文案与安全边界。
3. 若同时允许 DDC 与第三方后端，用户可见的“当前由谁控制”提示如何呈现而不增加噪音。
