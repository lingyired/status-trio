# Status Trio 2.0 Presentation State Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持现有像素、界面、交互及监控生命周期的前提下，让图标与面板消费解析后的展示状态。

**Architecture:** 采用渐进迁移。纯图标 Mapper 产生共享 `IconSceneState`，`AppEnvironment` 持有一个展示所有者；Menu Bar、Dock 和预览消费同一映射契约，表面环境及动画帧独立。面板按区域迁移展示值与动作路由，保留现有领域控制器、实时更新渠道和按需监控。

**Tech Stack:** Swift、Combine、AppKit、Core Graphics、SwiftUI、SwiftPM，沿用各测试文件的 XCTest／Swift Testing 风格。

**Spec:** [2026-09-30-v2-presentation-state-design.md](../specs/2026-09-30-v2-presentation-state-design.md)（用户已通过书面审阅）。

## Global Constraints

- 验收环境：`macos-26`、Xcode `26.6`、Swift `6.3.3`；应用 SDK 至少 macOS 26。
- 分支 `codex/2.0-presentation-refactor`；worktree `/Users/lingsmbp/.codex/worktrees/status-trio-2-0/status-trio`；产品基准 `4176b78`。
- 只做架构重构；现有像素、布局、导航、默认值、设置键、本地化术语、VoiceOver 与生命周期保持一致。
- Menu Bar／Dock 同步迁移；不把新图标选项或行为留在单一表面。Dock 保持当前静态动画策略。
- Mapper／场景不 import AppKit、SwiftUI、CoreGraphics；场景 `Equatable / Hashable / Sendable`；帧不进入场景。
- 不加入插件、动态注册、HTTP 数据源、Panel DSL 或用户槽位配置。不重写监控器，不升级依赖或批量转换测试框架。
- 禁用 `isolated deinit`、`IsolatedDeinit`、`weak let`；actor 方法使用显式闭包。资源目录兼容规则照 `AGENTS.md` 执行。
- 每个 Swift 提交前 `swift test`、`swift build -c release`；最终必须通过 `publish=false` release preflight，失败写入 `docs/swift-ci-compatibility.md` 后再重试。
- 本计划不创建 tag、不发布 Release 或 appcast；当前 Ad-hoc 签名不能宣称 notarization。
- 实施使用当前最新可用 Luna，现为 `gpt-6-luna`。本文件完成后先由用户审阅并选择执行方式；不得从规划直接启动代码实施。

## Review Focus

1. `@Published` 在赋值前发送、连续修改共享线宽与模式：两端接收完整新值，不能读到旧配置；Task 5／6 加投递值与双表面测试。
2. 图片资源失效或系统缺少指定符号：显示现有 fallback；失败渲染不污染成功缓存；Task 3／4／6 分别测试来源、绘制与重试。
3. 拖动中收到旧硬件读回、输出／输入设备刚消失：保留本地草稿，不操作过期设备；Task 9／11 测试交互及稳定标识。
4. popover 保留内容但已关闭、蓝牙区域隐藏、Settings 仍持有设备表面：按现有 claim 释放，不能停错监控或新增扫描；Task 10／11 测试生命周期。
5. 像素不变时 SSID／精确音量／语言变化：VoiceOver 和面板仍更新，图标不栅格化；Task 6／8／11 测试独立 identity。

---

## 执行导航与提交纪律

本计划有一个共同 spec、两个顺序里程碑。**I：Tasks 1–7 完成图标链路，可独立运行与验证。II：Tasks 8–12 完成面板链路；Task 13 完成 CI 验收。** 面板不得在图标契约尚未稳定时并行改共享文件。

下文路径相对 worktree 根目录。每个任务有自己的测试循环；Task 1 是现有行为刻画，测试应首先通过，其他任务的新增能力先以失败测试证明缺口。示例代码是接口和关键断言，不授权照抄后跳过该任务列出的行为矩阵。一个阶段内的大步骤按函数或行为用例拆成 2–5 分钟动作，完成后勾选。

每个 Swift 任务提交前统一执行下列完整门槛；focused filter 只用于开发循环，不能替代此门槛：

```bash
swift test
swift build -c release
git diff --check
git diff --stat
```

只暂存当前任务 Files 内审阅过的文件，不使用 `git add .`。各任务末尾提供提交消息；不提交 `.build/`、生成图片或原 checkout 的未跟踪文件。每个可审阅提交保持编译可运行和两端既有行为一致。

## 文件与职责地图

| 位置 | 职责 |
|---|---|
| `Presentation/Icon/IconSceneState.swift` | 根场景和视觉标量归一化 |
| `Presentation/Icon/IconColorRole.swift`、`IconSymbolState.swift` | 颜色语义、符号／图片来源和手绘样式 |
| `Presentation/Icon/OuterRingState.swift`、`CenterState.swift`、`FooterState.swift` | 槽位视觉值，无领域类型 |
| `Presentation/Icon/IconPresentationConfiguration.swift`、`IconPresentationMapper.swift` | 内建偏好及纯领域→视觉映射 |
| `Presentation/Icon/IconPresentationViewModel.swift` | 图标初始值、共享输出及生命周期 |
| `App/IconPresentationResourceResolver.swift` | 现有设备分类、文件存在与符号可用性的平台边界 |
| `Settings/SettingsStore+IconPresentation.swift` | 完整设置投递，含 Menu Bar 尺寸及测试模式 |
| `UI/Icon/StatusIconRenderEnvironment.swift` | AppKit／CG 绘制环境，非领域配置 |
| 现有 renderer、cache、controllers、previews | 新输入接入，保持绘图与 surface 行为 |
| `Presentation/Panel/PanelSummaryState.swift`、各区域 `*PanelState.swift` | 局部可比较展示值，文案、能力和稳定标识 |
| `Presentation/Panel/PanelPresentationMapper.swift`、各区域 `*PanelMapper.swift` | 复用原文案／排序／失败规则，输出最终值 |
| `Presentation/Panel/StatusPanelViewModel.swift`、`StatusPanelActions.swift` | 区域派生订阅、意图协调及可见性回调 |
| `Presentation/Accessibility/AccessibilityPresentation.swift` | 独立 VoiceOver 文案和 richer input |
| `Tests/StatusTrioCoreTests/TestSupport/PresentationFixtures.swift` | 确定性输入，生产代码不依赖测试 fixture |
| `docs/presentation-state-architecture.md` | 最终维护边界、设置更新步骤及未来限制 |

地图中 `Presentation` 等位置均位于 `Sources/StatusTrioCore/`；新文件只在对应任务创建，提前不做空 scaffolding。各区域文件可按最终职责进一步拆分，不能因便利回到一个巨型 ViewModel 或 Mapper。

---

### Task 1：刻画迁移前行为并固定 fixture

**Files:** Create `Tests/StatusTrioCoreTests/TestSupport/PresentationFixtures.swift`；Create `Tests/StatusTrioCoreTests/PresentationBaselineTests.swift`；Create `docs/presentation-state-behavior-matrix.md`。Read `StatusMappingsTests.swift`、`StatusIconRendererTests.swift`、`Issue13IconParityTests.swift`、charging／cache tests。

**Interfaces:** Produces `PresentationFixtures.snapshot(rssi:scalar:muted:) -> StatusSnapshot`、`PresentationFixtures.bluetoothDevice -> AudioOutputDevice`；后续任务用该 fixture，不跨测试文件引用 private helper。

- [ ] 建立 fixture 和现有行为断言；这里是刻画基准，预期首先通过，不故意破坏旧实现。

```swift
enum PresentationFixtures {
    static func snapshot(rssi: Int = -61, scalar: Double? = 0.51,
                         muted: Bool = false) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 68, isPresent: true,
                isCharging: false, isLowPowerMode: false,
                isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: rssi),
            connection: .wifi,
            volume: VolumeStatus(scalar: scalar, isMuted: muted, deviceName: "Output"))
    }
    static var bluetoothDevice: AudioOutputDevice { SheetFixtures.bluetoothDevice }
}

func testDotBucketAndSignalBucketBaseline() {
    XCTAssertEqual(StatusMappings.wifiBars(rssi: -61), 2)
    XCTAssertEqual(StatusMappings.wifiBars(rssi: -62), 2)
    XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
    XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.74, isMuted: false), 3)
}
```

- [ ] Run `swift test --filter PresentationBaselineTests`；预期 PASS。矩阵每行填写当前测试名、实际分支规则、后续任务；缺少用例直接补刻画测试。
- [ ] 固定矩阵：电池全部状态／附件／缺失，中心全部优先级／特殊状态，点阵／弧线／颜色，比例／线宽／尺寸，动画／测试模式，无障碍／语言，面板六区及详情、蓝牙 claim 和实时控制。
- [ ] 对平台指纹记录 OS／SDK 条件；不要生成“当前实现和当前实现比较”的假回归。后续 Task 4 的旧新入口对照必须走不同逻辑路径。
- [ ] 完整提交门槛通过后提交：`test: capture presentation refactor behavior baseline`。

### Task 2：添加完整的当前视觉状态类型

**Files:** Create 图标目录中的 `IconSceneState.swift`、`IconColorRole.swift`、`IconSymbolState.swift`、`OuterRingState.swift`、`CenterState.swift`、`FooterState.swift`；Create `Tests/StatusTrioCoreTests/IconSceneStateTests.swift`。

**Interfaces:** Produces 下列契约。所有 struct／enum 均 conform `Equatable, Hashable, Sendable`；这里的字段是完整当前类型清单，不生成未来占位分支。归一化由构造器拥有，纯 Mapper 不重复实现。

```swift
enum IconColorRole { case primary, inactive, critical, lowPower, powered, bluetooth }
enum IconPrimitive { case wiredPort, screenWedge, arrowWedge, bolt, plug }
enum IconSymbolSource {
    case symbol(name: String, variableValue: Double?, fallback: String?)
    case image(url: URL, fallbackSymbol: String)
    case primitive(IconPrimitive)
}
struct IconSymbolState {
    let source: IconSymbolSource
    let color: IconColorRole
    let scale: Double
}
struct IconTextState { let text: String; let color: IconColorRole; let scale: Double }
enum RingGapStyle { case closed, indicator, value }
enum RingAccessoryState { case symbol(IconSymbolState), text(IconTextState) }
struct RingSegmentState { let progress: Double; let color: IconColorRole }
struct RingEffectState { let pulsesAccessory: Bool; let tintsAccessory: Bool }
struct OuterRingState {
    let segments: [RingSegmentState]
    let gap: RingGapStyle
    let accessory: RingAccessoryState?
    let effect: RingEffectState?
    let strokeScale: Double
}
enum CenterState { case symbol(IconSymbolState), text(IconTextState) }
struct DotsState {
    let count: Int; let activeCount: Int
    let color: IconColorRole; let strokeScale: Double
}
struct ArcState { let progress: Double; let color: IconColorRole; let strokeScale: Double }
enum FooterState { case dots(DotsState), arc(ArcState) }
struct IconSceneState {
    let outerRing: OuterRingState?
    let center: CenterState?
    let footer: FooterState?
}
```

- [ ] 加入失败测试，验证 activeCount clamp、finite progress、hash equality 和所有实际影响视觉的属性：

```swift
func testNonFiniteArcIsAnEmptyFill() {
    let invalid = ArcState(progress: .nan, color: .primary, strokeScale: 1)
    let empty = ArcState(progress: 0, color: .primary, strokeScale: 1)
    XCTAssertEqual(invalid, empty)
    XCTAssertEqual(Set([invalid, empty]).count, 1)
}
```

- [ ] Run `swift test --filter IconSceneStateTests`；预期因类型缺失失败。随后创建类型和构造器：finite progress clamp，非有限 progress 为 0；strokeScale 沿用 `0.5...2.5`／默认值；scale 沿用各现有有效默认值，由 Mapper 在合法配置入口确定。
- [ ] 默认槽位使用 `nil`；`ArcState(progress:0)` 仍画底轨。环段非空且每段 finite，本次连续绘制只生产一段，Renderer 对不支持的段数明确拒绝，不能静默画错。
- [ ] 再运行 focused tests，验证不同视觉属性导致不同 state；不为未来不可见功能加 enum。完整门槛后提交：`feat: add icon presentation value types`。

### Task 3：纯 Mapper、映射配置与资源适配边界

**Files:** Create `Presentation/Icon/IconPresentationConfiguration.swift`、`IconPresentationMapper.swift`；Create `App/IconPresentationResourceResolver.swift`；Create `Tests/StatusTrioCoreTests/IconPresentationMapperTests.swift`、`IconPresentationResourceResolverTests.swift`。Read `Models/StatusMappings.swift`、`Audio/AudioOutputDeviceIcon.swift`、`Models/*IconOptions.swift`。

**Interfaces:**

```swift
struct IconPresentationConfiguration: Equatable, Sendable {
    let battery: BatteryIconOptions
    let connection: ConnectionIconOptions
    let volume: VolumeIconOptions
    let bluetooth: BluetoothAudioIconOptions
    static let standard = Self(battery: .standard, connection: .standard,
                              volume: .standard, bluetooth: .standard)
}
struct IconPresentationInputs: Equatable, Sendable {
    let snapshot: StatusSnapshot
    let audioIcon: IconSymbolSource?
}
enum IconPresentationMapper {
    static func scene(inputs: IconPresentationInputs,
                      configuration: IconPresentationConfiguration) -> IconSceneState
}
@MainActor enum IconPresentationResourceResolver {
    static func inputs(snapshot: StatusSnapshot) -> IconPresentationInputs
}
```

上面的函数声明是计划接口；实现时需提供下列实际函数体和分槽位 helpers。Mapper 不自行调用 `AudioOutputDeviceIcon.source`，因为它查询文件和 `NSImage`。Resolver 复用当前设备分类与 fallback，转为 `IconSymbolSource`；注入文件存在／符号可用闭包测试 resolver 的平台分支，不能为测试替换全局环境。

- [ ] 新增两个失败测试，固定不可见 RSSI／dot noise 相等、arc noise 不相等：

```swift
func testDotAndSignalNoiseProduceOneScene() {
    let a = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(rssi: -61, scalar: 0.51), audioIcon: nil)
    let b = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(rssi: -62, scalar: 0.74), audioIcon: nil)
    XCTAssertEqual(IconPresentationMapper.scene(inputs: a, configuration: .standard),
                   IconPresentationMapper.scene(inputs: b, configuration: .standard))
}
func testMutedArcIgnoresHiddenScalar() {
    let configuration = IconPresentationConfiguration(battery: .standard,
        connection: .standard, volume: VolumeIconOptions(displayStyle: .arc), bluetooth: .standard)
    let a = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.2, muted: true), audioIcon: nil)
    let b = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(scalar: 0.9, muted: true), audioIcon: nil)
    XCTAssertEqual(IconPresentationMapper.scene(inputs: a, configuration: configuration),
                   IconPresentationMapper.scene(inputs: b, configuration: configuration))
}
```

- [ ] Run `swift test --filter 'IconPresentation(Mapper|ResourceResolver)Tests'`；预期接口缺失失败。
- [ ] 编写 battery／center／footer 三个纯 helper；从 Task 1 矩阵逐行移植语义。关键实现形式：

```swift
let finiteScalar = scalar.flatMap { $0.isFinite ? $0 : nil }
let steps = StatusMappings.volumeSteps(scalar: finiteScalar, isMuted: isMuted) ?? 0
let effectiveProgress = isMuted ? 0 : (finiteScalar ?? 0)
let dots = DotsState(count: 4, activeCount: steps, color: color, strokeScale: strokeScale)
let arc = ArcState(progress: effectiveProgress, color: color, strokeScale: strokeScale)
```

以 finite scalar 计算 steps，不能让 NaN 经旧 `volumeSteps` 返回有效点数。当前阶段可以调用旧纯语义 helper，Task 7 完成职责拆分。

- [ ] 用明确 state 断言覆盖：临界 `< threshold`、低电量与供电颜色优先；charging／charged／plug／百分比开关；effect 必须 present、charging、非 charged 且启用；Ethernet-as-Wi-Fi 固定 full level；零信号 inactive 色；off 和 unavailable 的可合并视觉；热点／临时／共享各开关；中心百分比优先；蓝牙覆盖在无当前输出时仍有效；网络错误优先；蓝牙 footer 色只由当前蓝牙输出决定。
- [ ] Resolver 测试图片来源缺失回分类符号；Renderer 仍负责读取时图片失败和符号 fallback。输入越界、nil、NaN、无穷、0／100% 全部有期望输出；同 scene equality 必须复用归一化状态。
- [ ] 完整门槛后提交：`refactor: resolve built-in status into icon scene`。

### Task 4：scene 渲染入口与独立旧新像素对照

**Files:** Create `UI/Icon/StatusIconRenderEnvironment.swift`；Modify `UI/Icon/StatusIconRenderer.swift`、`DockIconRenderer.swift`；Create `Tests/StatusTrioCoreTests/IconSceneRendererParityTests.swift`；Modify `StatusIconRendererTests.swift`、`DockIconRendererTests.swift`。

**Interfaces:** Produces `StatusIconRenderer.render(scene:environment:phase:) -> CGImage?`、`StatusIconRenderer.image(scene:size:scale:appearance:phase:) -> NSImage?`、`StatusIconRenderer.draw(scene:in:size:foreground:criticalColor:phase:) -> Bool`、`DockIconRenderer.image(scene:backgroundStyle:pixelLength:) -> NSImage?`。`phase` 为 `ChargingEffectPhase?`，size／scale 为 `CGFloat`；`StatusIconRenderEnvironment` 包含 `size`、`scale`、`foreground`、`criticalColor`，CGColor 仅在该 UI 层。

- [ ] 新测试以旧入口产生 expected，以新入口产生 actual：

```swift
@MainActor func testNormalSceneMatchesLegacyPixels() throws {
    let snapshot = PresentationFixtures.snapshot()
    let expected = try XCTUnwrap(StatusIconRenderer.render(snapshot: snapshot,
        size: 28, scale: 2, foreground: CGColor(gray: 1, alpha: 1)))
    let scene = IconPresentationMapper.scene(
        inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot), configuration: .standard)
    let environment = StatusIconRenderEnvironment(size: 28, scale: 2,
        foreground: CGColor(gray: 1, alpha: 1), criticalColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    let actual = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment, phase: nil))
    XCTAssertEqual(try PixelBuffer(image: expected).bytes, try PixelBuffer(image: actual).bytes)
}
```

比较前确认 legacy 默认 criticalColor 与 environment 一致；不要用不同 palette 的结果比较。测试循环固定前景和临界色后调用两端所有对应参数。Task 7 删除旧入口前将基准固化为已有像素约束或平台指纹，不永久保留 legacy renderer。

- [ ] Run `swift test --filter IconSceneRendererParityTests`；预期新入口缺失失败。逐个适配环、中心、底部绘图函数，先复用现有路径／字体／光学居中，不重画图形。
- [ ] 将 `BatteryColorRole` palette switch 改为 `IconColorRole`；底轨 alpha 仍为当前 `inactiveTrackAlpha`。`RingGapStyle` 解析到原 gap 宽度，保留附件影子和 boltScale；center text 保留中心数字字体，ring text 使用顶部数字字体。
- [ ] 新入口只访问视觉字段：

```swift
if let ring = scene.outerRing { drawOuterRing(ring, in: context, phase: phase) }
if let center = scene.center { drawCenter(center, in: context) }
if let footer = scene.footer { drawFooter(footer, in: context) }
```

`drawOuterRing`、`drawCenter`、`drawFooter` 为此任务定义的 private drawing helpers，保存／恢复相同 CGContext 状态。所有颜色从传入环境解析。SF Symbol fallback、image fallback 留在渲染层并保持旧顺序；主资源 URL 不进入领域判断。

- [ ] 参数化完整 Task 1 视觉矩阵，并覆盖 size／scale 非正或非有限拒绝、未知符号回 generic、不可读图片回 headphones、单段环、静态／steady／burst 帧及各表面背景。Dock 仍使用原 glyph frame、scratch buffer 和尺寸上限。
- [ ] focused parity + 既有 geometry／renderer／charging tests 通过，完整门槛后提交：`refactor: render native icon primitives from scene`。旧生产路径此时未切换。

### Task 5：共享图标展示所有者与设置输出

**Files:** Create `Presentation/Icon/IconPresentationViewModel.swift`、`Settings/SettingsStore+IconPresentation.swift`；Modify `Settings/SettingsStore+IconAppearance.swift`、`UI/Icon/ChargingEffectTestMode.swift`；Create `Tests/StatusTrioCoreTests/IconPresentationViewModelTests.swift`；Modify `IconAppearancePublisherTests.swift`。

**Interfaces:**

```swift
struct IconPresentationSettings: Equatable, Sendable {
    let configuration: IconPresentationConfiguration
    let menuBarSize: Double
    let testsChargingEffect: Bool
}
struct IconPresentationOutput: Equatable, Sendable {
    let scene: IconSceneState
    let menuBarSize: Double
    let menuBarTestScene: IconSceneState? // default nil; existing Menu Bar-only test projection
}
// SettingsStore.iconPresentationPublisher: AnyPublisher<IconPresentationSettings, Never>
@MainActor final class IconPresentationViewModel: ObservableObject {
    @Published private(set) var output: IconPresentationOutput
    init(snapshot: StatusSnapshot, settings: IconPresentationSettings,
         snapshots: AnyPublisher<StatusSnapshot, Never>,
         preferences: AnyPublisher<IconPresentationSettings, Never>,
         resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs)
    func start()
    func stop()
}
```

init 立即计算 output，start 才建立订阅；生产注入 store／settings publishers，测试使用 subjects。不创建第三个可独立变更的 configuration 权威。

- [ ] 失败测试使用 `CurrentValueSubject`，订阅 `$output` 记录投递值：

```swift
let snapshots = CurrentValueSubject<StatusSnapshot, Never>(PresentationFixtures.snapshot())
let settings = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
let model = IconPresentationViewModel(snapshot: snapshots.value, settings: settings.value,
    snapshots: snapshots.eraseToAnyPublisher(), preferences: settings.eraseToAnyPublisher(),
    resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) })
var delivered: [IconPresentationOutput] = []
let subscription = model.$output.sink { delivered.append($0) }
model.start()
snapshots.send(PresentationFixtures.snapshot(rssi: -62, scalar: 0.74))
XCTAssertEqual(delivered.count, 1)
subscription.cancel()
model.stop()
```

`initialSettings` 在测试内构造为 `.standard` configuration、28 size、false testMode，不能引用测试外隐含值。

- [ ] Run `swift test --filter IconPresentationViewModelTests`；预期缺失接口失败。实现 init／start／stop 与完整输出去重。分别订阅 snapshots／preferences，缓存最新**已投递**值；领域更新用可注入 main-actor scheduler 做 0.5 秒 trailing debounce，设置更新立即按最新 raw snapshot 解析。init 立即生成 output；start 幂等，stop 取消订阅及待执行 debounce，restart 从当前输入刷新。

每次解析 canonical scene 使用真实 snapshot；仅在 testsChargingEffect 开启时，同一个 Mapper／configuration 另生成 menuBarTestScene。发布前比较完整 output，避免重复发布。不要在 controller 内重做领域映射。用控制调度器测试领域 burst 只在 500 ms settled 边界输出，设置更改仍快速生效。

`ChargingEffectTestMode.snapshot(_:enabled:)` 是本任务在现有 `UI/Icon/ChargingEffectTestMode.swift` 添加的便捷投影，使用已存在的 `battery(_:enabled:)` 和 `StatusSnapshot.replacingBattery`；不写回 store。canonical scene 始终来自真实 snapshot，测试投影仅进入可选 menuBarTestScene；Dock 不消费测试投影。迁入 Presentation 前确认旧测试模式 API 的其他消费者。

- [ ] 设置 publisher 复用当前聚合已投递字段，转换为新设置值，再 combine `$testsChargingEffect`；共享 ringStroke 只聚合一次。覆盖每个现有开关、缩放、模式和无关设置不发布。不要在 sink 读取 `settings.iconAppearance` 拼新值。
- [ ] 测试 start 两次只一份订阅、stop 后无输出、restart 当前值刷新、连续 settings 发送完整新值、测试模式不改变原 snapshot、output 中没有 phase、仅 size 变化不改变 scene。
- [ ] focused + 完整门槛后提交：`refactor: own one shared icon presentation stream`。

### Task 6：两表面、缓存、动画和无障碍一起接入

**Files:** Modify `App/AppEnvironment.swift`、`App/AppIconController.swift`、`UI/StatusBarController.swift`、`UI/Icon/StatusBarRenderCache.swift`、`DockIconRenderCache.swift`、`StatusBarChargingFrameCache.swift`、`StatusBarAnimationLayerPresenter.swift`；Create `Presentation/Accessibility/AccessibilityPresentation.swift`；Modify `UI/StatusPopoverView.swift`（迁出无障碍 helper）；Create `Tests/StatusTrioCoreTests/IconSurfaceIntegrationTests.swift`；Modify 两端 controller／cache tests、`ChargingEffectFrameCacheTests.swift`、`ChargingEffectControllerTests.swift`、`StatusPresentationTests.swift`。

**Interfaces:** Both controller initializers 新增 `iconPresentation: IconPresentationViewModel`；AppEnvironment 新增同名 owned property。`StatusBarRenderKey(scene:iconSize:backingScale:appearanceName:phase:)`，`DockIconRenderKey(scene:backgroundStyle:pixelLength:)`；key 不再包含领域 status／options。`AccessibilityPresentation.statusItemValue(_ snapshot: StatusSnapshot, localization: Localization) -> String` 保留原 richer 规则。

- [ ] 失败测试从同一 model 的输出分别收集两端 renderer spy 参数，断言相同 scene；size、背景和 placement 改变仍使用最新 scene。Extend 既有 controller 测试注入能力，不为测试增加生产系统 IO。
- [ ] 加失败缓存测试：

```swift
func testFailedRasterDoesNotBecomeSuccessfulKey() {
    var cache = StatusBarRenderCache()
    let key = StatusBarRenderKey(scene: scene, iconSize: 28,
        backingScale: 2, appearanceName: "NSAppearanceNameAqua", phase: nil)
    XCTAssertTrue(cache.needsRender(key))
    XCTAssertTrue(cache.needsRender(key)) // 没有成功记录，允许重试
    cache.recordSuccessfulRender(key)
    XCTAssertFalse(cache.needsRender(key))
}
```

`scene` 在函数内由 Task 3 fixture 解析。两种 cache 均产生 `needsRender(_:) -> Bool`、`recordSuccessfulRender(_:)`、`reset()`；imageCache LRU 只在成功生成图片后写入。

- [ ] Run `swift test --filter 'IconSurfaceIntegrationTests|StatusBarRenderCacheTests|DockIconRenderCacheTests'`，确认缺口。再由 AppEnvironment 创建、start／stop 同一个 model，先启用共享输出，再启动消费者／领域监控，初始值不能依赖首个 poll。
- [ ] 保留既有 Menu Bar-only 充电测试模式：同一 owner 的 canonical scene 驱动 Dock，Menu Bar 消费 `menuBarTestScene ?? scene`；开关测试模式不得改变 Dock 图片或增加 Dock raster，须有集成测试。正常模式两端使用同一 scene。
- [ ] 两 controller sink 使用**投递的 output**，更新各自 latest output，再调度渲染；不得在 `$output` sink 回读尚未写入的 model.output。替换两个独立领域视觉订阅，保留 surface appearance、placement、background 和 interaction 订阅。
- [ ] UI Controller 保留领域操作和 popover 所有权；只从图标绘制链移除领域输入。Menu Bar 滚轮控制在后续 Task 11 连接面板动作，不提前删除。
- [ ] Cache identity 包含 backingScale；整组帧移除单次 phase，保留 heartbeat multiplier。将 pre-rendered／animation image API 改为 scene 输入；Dock 无 phase 订阅。无可见表面时 model 可算值，但不得栅格化；隐藏／恢复和 render failure 重试有测试。
- [ ] 无障碍独立订阅 richer snapshot 与 localization，只更新 VoiceOver 文案。测试 SSID、同一 dot bucket 精确音量与语言变化：scene／raster count 不变、spoken value 改变；原文案优先级和术语逐项保留。
- [ ] 参数化共享 setting 更改测试，覆盖 ring stroke、battery／wifi／Bluetooth scale、替换／错误优先、volume style、charging flags。完整门槛后提交：`refactor: drive menu bar and dock from shared scene`。

### Task 7：迁移所有预览并退出旧图标入口

**Files:** Modify `UI/IconPreviewComponents.swift`、`UI/IconGuideView.swift`、`UI/Settings/SettingsVisualPreviews.swift`、`StatusIconPreviewCard.swift`、`IconSizePreview.swift`、`AppIconImage.swift`、`AppIconSectionView.swift`、`UI/Icon/DockIconPreviewCache.swift`；Modify TestSupport `AppIconPreview.swift`、`DockIconSheet.swift`、`DockIconStateStrip.swift`、`IconStateSheet.swift`；Modify renderer、旧 appearance／mapping／status types 的实际调用方；Modify preview／guide／parity tests；Update 行为矩阵。

**Interfaces:** Produces `@MainActor IconPreviewScene.make(snapshot:configuration:) -> IconSceneState` in `UI/IconPreviewComponents.swift`；它只调用 resolver + Mapper，不实现新的选择规则。所有旧像素入口删除，renderer 只接受 scene；配置 adapter 可暂时供面板外消费者使用。

- [ ] 加预览共享映射失败测试：

```swift
@MainActor func testPreviewUsesCanonicalMapping() {
    let snapshot = PresentationFixtures.snapshot()
    XCTAssertEqual(IconPreviewScene.make(snapshot: snapshot, configuration: .standard),
        IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot), configuration: .standard))
}
```

- [ ] Run `swift test --filter 'StatusIconPreviewCardTests|DockIconPreviewWiringTests|IconGuideTests'`；迁移每个实际 preview／guide 调用方，保持尺寸、背景、sample 状态和 testMode／phase 规则。Task 4 对照证据固定到当前既有像素 convention 后再删除旧入口。
- [ ] 搜索调用方，分类并迁移：

```bash
rg -n 'StatusIconRenderer\.|DockIconRenderer\.|StatusIconAppearance|StatusMappings\.' Sources Tests
rg -n 'BatteryStatus|WiFiStatus|VolumeStatus|NetworkConnection|MenuBarStatus|BatteryIconOptions|ConnectionIconOptions|VolumeIconOptions|BluetoothAudioIconOptions' Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift
```

第二个搜索在最终 renderer 预期无领域输入；前者每个结果必须有真实职责。把图标纯 mapping helper 收入 Presentation，保留 `wifiSummaryAction` 等共享产品 helper，不机械删除 accessibility／Settings 消费者。

- [ ] 更新 tests 从“无效设置也强制 rerender”改为“只有有效 scene 变化才 rerender”，保留 setting publisher 覆盖。无关 `MenuBarStatus` 删除不作为完成条件。
- [ ] focused preview、全部像素回归及完整门槛后提交：`refactor: unify icon previews and retire legacy rendering inputs`。里程碑 I 完成，先审阅完整图标 diff 再推进面板。

### Task 8：面板 summary Mapper 与本地化边界

**Files:** Create `Presentation/Panel/PanelSummaryState.swift`、`PanelPresentationMapper.swift`；Modify `UI/StatusPopoverView.swift`（迁出原格式化函数）、`UI/WiFiSummaryPresentation.swift`、`WiredLinkPresentation.swift`、`BatteryPowerPresentation.swift`（有必要时移动，不复制）；Create `Tests/StatusTrioCoreTests/PanelPresentationMapperTests.swift`；Modify `StatusPresentationTests.swift`、`WiFiSummaryTests.swift`、`WiredLinkPresentationTests.swift`、`VPNRowSettingsTests.swift`。

**Interfaces:**

```swift
enum PanelTint: Equatable, Sendable { case primary, secondary, positive, caution, critical }
enum PanelSummaryIntent: Equatable, Sendable {
    case none, batteryDetails, wifiDetails, requestWiFiNameAccess, locationSettings, wiredDetails
}
struct PanelSummaryState: Equatable, Sendable {
    let title: String; let subtitle: String; let measurements: String?
    let symbol: IconSymbolSource; let tint: PanelTint
    let accessibilityLabel: String; let accessibilityValue: String
    let showsSettings: Bool; let intent: PanelSummaryIntent
}
@MainActor enum PanelPresentationMapper {
    static func battery(_ status: BatteryStatus, localization: Localization) -> PanelSummaryState
    static func network(wifi: WiFiStatus, connection: NetworkConnection,
        wired: PrimaryLinkDetails?, isConstrained: Bool, isResolvingName: Bool,
        localization: Localization) -> PanelSummaryState
    static func vpn(_ status: VPNStatus, localization: Localization) -> PanelSummaryState
}
```

- [ ] 加失败测试，展示值等于现有文案、意图为正确可用动作：

```swift
@MainActor func testAbsentBatteryHasNoDetailAction() {
    let localization = Localization()
    let battery = BatteryStatus(rawPercentage: nil, isPresent: false,
        isCharging: false, isLowPowerMode: false, isConnectedToPower: false)
    let row = PanelPresentationMapper.battery(battery, localization: localization)
    XCTAssertEqual(row.intent, .none)
    XCTAssertFalse(row.showsSettings)
    XCTAssertEqual(row.symbol, .symbol(name: "battery.slash", variableValue: nil, fallback: nil))
}
```

- [ ] Run `swift test --filter PanelPresentationMapperTests`。抽取原 `StatusPresentation` 的面板文案并复用现有 helpers；保留 battery summary 色的原阈值 `<=20`，不要误用 icon 的 `< configured threshold`。
- [ ] network state 已决定显示 Wi-Fi／wired；name awaiting 期间副标题 blank；SSID 显示 gate、band／signal、wired restriction 和 action permission 保持原规则。VPN 独立值不入图标。
- [ ] 本地化测试用现有 `StatusPresentationTests` 中创建语言偏好的方式，覆盖 `.english`、`.simplifiedChinese` 和其他实际语言；相同领域输入切换 language，row 文案变化。旧 panel helper 暂作 adapter，待视图迁完删除。
- [ ] 完整门槛后提交：`refactor: resolve panel summaries before SwiftUI rendering`。

### Task 9：音频展示状态、稳定标识与动作协调

**Files:** Create `Presentation/Panel/VolumePanelState.swift`、`AudioInputPanelState.swift`、`AudioPanelMapper.swift`、`StatusPanelActions.swift`；Modify `UI/AudioInputControlsView.swift`（提取现有 AudioInputPresentation）、`OutputDeviceListPresentation.swift`；Create `Tests/StatusTrioCoreTests/AudioPanelMapperTests.swift`、`PanelActionRoutingTests.swift`；Modify `AudioInputPresentationTests.swift`、`OutputDeviceListPresentationTests.swift`。Read `Audio/AudioOutputDevice.swift`、`Audio/AudioInputStatus.swift`、`Store/SystemStatusStore.swift`。

**Interfaces:** `PanelAudioDeviceID` 为 `(id: UInt32, uid: String?)` 的 Equatable／Hashable／Sendable struct；它同时校验瞬态 ID 和已知 UID。`PanelAudioDeviceRow` 保存 key、最终 name、symbol、selected、enabled、accessibilityLabel。`VolumePanelState` 保存 summary、scalar、percentageText、muted、canAdjust、canMute、muteSymbol、muteHelp、sliderLabel、showsDeviceList、rows。`AudioInputPanelState` 保存 summary、opaque `selectedDeviceIdentity: PanelAudioInputIdentity?`、scalar、percentageText、muteSymbol、muteHelp、canAdjust、canMute、isBusy、errorText、rows、sliderLabel、usageText。`PanelAudioInputIdentity` 只承载默认输入的稳定 ID 比较值；不携带 UID、名称或本地化信息。

`@MainActor AudioPanelMapper.volume(_:controllerAvailable:localization:) -> VolumePanelState` 保留可调用默认；增加默认化的窄值 preferences 参数承载现有 outputDeviceOrder／visibleOutputDeviceLimit（沿用原值类型及默认）。VolumePanelState 提供已解析的完整／收起行集合、可展开信息及现有文案；展开开关保持视图局部交互状态，不能在视图重排领域设备或本地化。`input(_:localization:) -> AudioInputPanelState`。所有 row 名称排序、重复／缺失名称、current marker、错误、输入使用标记由这里或现有被复用 helper 解析。

Input slider draft resets when `selectedDeviceIdentity` changes, even if the new device reports the same scalar. Same-device scalar readback keeps an active draft. The identity is derived only from `defaultDeviceID`, so a late UID, device label, or language update does not reset editing.

`StatusPanelActions` 接收现有 store 和 settings，并对外提供：`setVolume(_:)`、`finishVolumeAdjustment()`、`toggleMute()`、`selectOutput(_ key: PanelAudioDeviceID)`、`setInputScalar(_:)`、`toggleInputMute()`、`selectInput(_ key: PanelAudioDeviceID)`。为单测注入读取当前 devices 和执行命令的窄闭包，而非新建巨大的 monitor protocol。状态另保存实际需要的 input mute tint、list expansion 和可见行信息；不能用单一 bool 丢失 partial mute 的现有显示。

- [ ] 加失败测试，重复名称 rows 仍有不同 key 和读屏标签；busy／canSet／canMute 组合保留各自禁用行为，不能用一个 `isAvailable` 布尔替代。
- [ ] 动作消失设备测试直接注入闭包：

```swift
var devices: [AudioOutputDevice] = [PresentationFixtures.bluetoothDevice]
var selected: [UInt32] = []
let actions = StatusPanelActions(outputDevices: { devices },
    selectOutput: { selected.append($0.id) })
let stale = PanelAudioDeviceID(id: devices[0].id, uid: devices[0].uid)
devices = []
actions.selectOutput(stale)
XCTAssertTrue(selected.isEmpty)
```

本任务增加该窄 testing initializer；其他动作闭包以 `{}`／忽略参数作为默认，生产 initializer 从 store 填入完整 closures。输入 selector 比照校验 id／uid；UID 已知而不匹配时不写入。

- [ ] Run `swift test --filter 'AudioPanelMapperTests|PanelActionRoutingTests'`。实现解析与动作方法：

```swift
func selectOutput(_ key: PanelAudioDeviceID) {
    guard let device = outputDevices().first(where: {
        $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
    }) else { return }
    selectOutputDevice(device)
}
```

`selectOutputDevice` 是 initializer 保存的闭包；生产连接 `store.selectOutputDevice` 使用显式 closure。连续音量、结束 flush、静音和 input 动作保持现有 store 的能力及失败检查，不引入自己的 pending-write 缓冲。

- [ ] 测试各动作调用一次及参数、finite scalar、结束 flush、同 id 换 UID 不操作；输入 partial mute、未知 usage、错误、设备顺序与原 `AudioInputPresentation` 输出一致。不要让 unavailable 底轨数值假装成可操作 0%。
- [ ] 完整门槛后提交：`refactor: resolve audio controls and route stable device actions`。

### Task 10：蓝牙／详情展示和可见性动作契约

**Files:** Create `Presentation/Panel/BluetoothPanelState.swift`、`BluetoothPanelMapper.swift`、`PanelDetailState.swift`、`PanelDetailMapper.swift`；Modify `StatusPanelActions.swift`；Modify／复用 `UI/BluetoothDeviceListPresentation.swift`、`BluetoothNearbyBatteryListPresentation.swift`、`BluetoothBatteryLevelText.swift`；Create `Tests/StatusTrioCoreTests/BluetoothPanelMapperTests.swift`、`PanelDetailMapperTests.swift`；Modify `BluetoothDeviceActionTargetingTests.swift`、`BluetoothPermissionTimingTests.swift`、`BluetoothListeningModeControllerLifecycleTests.swift`、`BluetoothNearbyBatteryLifecycleTests.swift`。

**Interfaces:**

```swift
struct PanelDetailRow: Equatable, Sendable {
    let id: String; let label: String; let value: String
    let accessibilityValue: String; let tint: PanelTint
    let isCopyable: Bool = false
}
struct PanelDetailState: Equatable, Sendable {
    let title: String; let rows: [PanelDetailRow]
    let isLoading: Bool; let errorText: String?; let explanation: String?
}
struct PanelBluetoothDeviceRow: Equatable, Sendable {
    let address: String; let title: String; let subtitle: String?
    let icon: IconSymbolSource; let batteryText: String?
    let batteryLayout: BluetoothBatteryLayout; let batterySegments: [BluetoothBatterySegment]?
    let isConnected: Bool; let status: BluetoothDeviceRowStatus
    let statusText: String?; let statusTint: PanelTint
    let requiresConfirmation: Bool
    let actionTitle: String; let actionEnabled: Bool; let isBusy: Bool
    let accessibilityLabel: String; let accessibilityValue: String
}
struct BluetoothPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let pairedRows: [PanelBluetoothDeviceRow]
    let nearbyRows: [PanelBluetoothDeviceRow]
    let errorText: String?; let showsPairedHeading: Bool
    let canExpand: Bool; let confirmationAddress: String?
}
```

每种 detail Mapper 明确接收现有 controller 的值快照，不把 controller 保存到 state。battery／Wi-Fi／wired 的行集合沿用当前 details view 中已存在字段，按现有顺序生成稳定 row id；技术地址保持只在详情页显示。

`@MainActor PanelDetailMapper.battery(status: BatteryStatus, details: BatteryDetails?, localization: Localization) -> PanelDetailState`、`wired(details: PrimaryLinkDetails?, localization: Localization) -> PanelDetailState`。Wi-Fi 需要列表和控制，不能仅用文本详情行代替：新增 `WiFiPanelState`，含 `detail: PanelDetailState`、`knownRows`／`otherRows: [PanelWiFiNetworkRow]`、`powerIsOn`、`canSetPower`、`canRefresh`、`isScanning`、`message`、`messageIntent: PanelSummaryIntent`；row 含稳定 `key: WiFiNetworkIdentity`、已解析 name／signal symbol／security marker／selected／accessibilityLabel 及 `opensSettings`。identity 只是稳定动作标识，不能让 view 再解释 SSID 或 security。

对应 Mapper 接口为 `PanelDetailMapper.wifi(status: WiFiStatus, networks: [WiFiNetwork], details: WiFiConnectionDetails, listState: WiFiListState, localization: Localization) -> WiFiPanelState`。保留原已知／其他网络分组及 SSID 空白身份，不 trim SSID；当前未连接行打开系统设置，不能趁重构新增 app 内 join 行为。

`WiFiPanelState` 提供完整的已解析无线详情行、默认 collapsed row count、`visibleDetailRows(expanded:)` 和现有本地化 More／Less 文案。默认行数只控制显示切片，不丢弃剩余八行；展开状态继续留在 view。

`StatusPanelActions` 扩展 `refreshBluetooth()`、`rowTapped(address:)`、`performBluetoothAction(address:)`、`requestDisconnect(address:)`、`confirmBluetoothDisconnect(address:)`、`cancelDisconnect()`、`setListeningMode(address:mode:)`，`mode` 使用现有 `BluetoothListeningMode`。普通 row tap 复用 `BluetoothDeviceActionPolicy`：键盘／鼠标断开先请求确认，确认动作再验证当前 pending address；view 不解释设备类型。摘要 permission intent 明确区分 request authorization 与 open permission settings，并由独立命名的 action closure 执行。扩展 `batteryDetailsAppeared()`／`batteryDetailsClosed()`、`wifiDetailsOpened()`／`wifiDetailsClosed()`、`wiredDetailsOpened()`／`wiredDetailsClosed()`、`bluetoothSummaryAppeared()`／`bluetoothSummaryDisappeared()`、`volumeListAppeared()`／`volumeListDisappeared()`。settings／permission callbacks 保留独立命名的注入 closure，不并入视觉 Mapper。

补齐 `setWiFiPower(_ enabled: Bool)`、`refreshWiFi()`，直接调用现有 `wifiNetworks.setPower`／`refreshNow(nameAccess:)`；网络行由解析后的 `opensSettings` 决定 callback。`batteryDetailsAppeared()` 从当前 battery 构造 `BatteryPowerState` 再 activate，电源状态变化由协调器更新激活状态。新增 `moveOutputDevices(from: IndexSet, to: Int)` 和 `moveBluetoothDevices(from: IndexSet, to: Int, displayedAddresses: [String])`；Task 11 必须传当前实际显示的 pairedRows 地址切片（包含 collapsed limit），offsets 与该切片一致。collapsed destination `count` 插入在当前可见 slice 的末尾、未显示行之前；协调器重新解析并验证当前显示前缀，过期前缀无操作，再合并到全量设置顺序时保留 hidden／ghost／collapsed 行的 saved ranks。Settings 原始列表仍直接调用 SettingsStore move，不改变其语义。summary disappear 释放可见 surface 和 paired battery claim，Nearby opt-in 留到偏好显式关闭时再释放。无参数的方法均返回 Void。

- [ ] 新失败 Mapper tests 覆盖连接组排序、saved order、ghost／hidden filter、battery display 开关、nearby 开关、refresh 失败及 disconnect confirmation；与原 helper 输出比较，不重新定义规则。
- [ ] detail tests 覆盖 battery power 行 tint／timestamp／解释文字，wired 不可用仍显示既有五行；Wi-Fi poweredOff／noInterface／denied／failed／scanning／empty、power toggle、refresh capability、known grouping 和系统设置 action。听音模式优先复用已有 `BluetoothListeningModePresentation`；如将文案移入新状态，新增 `PanelListeningModeState`，含每个 mode 的原 action value、title、selected／target／enabled、group accessibility label 和 failure text，不能丢失 enabled selected capsule 语义。
- [ ] Run `swift test --filter 'BluetoothPanelMapperTests|PanelDetailMapperTests|PanelActionRoutingTests'`。从当前 view 解出设备行和 details 的最终文字、符号、能力，原控制器不改所有权。
- [ ] 动作按 normalized address 查找当前设备并执行现有 action targeting，未找到不发出命令；听音模式在当前 controller control 仍存在时调用 `setMode`。预览 synthetic devices 的现有规则由 Mapper／协调器复用 `ListeningModePreview`，不让真实设备被 preview language 覆盖。
- [ ] Bluetooth row tap／confirm 使用明确 action callback；permission request 与 Privacy & Security 打开路径由已解析 intent 区分。行 state 保留 connected、inline／component、battery segments（包括 charging-case glyph）、failure tint 和 confirmation policy。
- [ ] Nearby summary disappear 停止 surface scan但保留 summary opt-in 与 cache；popover／summary／Settings visibility tokens 仍独立，显式关闭 nearby preference 才释放 summary opt-in。
- [ ] 生产 reordering 测试通过 settings-backed actions 验证 hidden、ghost、saved ranks 和 collapsed slice destination，而 Settings 原始列表调用仍保留旧行为。
- [ ] 将原 `.onAppear`、`.task(id:)`、`.onDisappear` 的 claim／refresh 逻辑逐条搬进 actions 的具名方法：

```swift
func bluetoothSummaryAppeared() {
    bluetoothDevices.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
}
func bluetoothSummaryDisappeared() {
    bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
}
```

controller 保存到 actions 可以，保存到展示 state 不可以。battery／nearby 的单独 claim 和 test task id 规则照旧；volume listening mode discovery 只在设备集合或 preview config 改变时 refresh，不增加 timer。

- [ ] 保留并扩展既有 lifecycle tests：popover 关后 late result 丢弃，隐藏蓝牙区域释放自己的 token 但不释放 Settings token；volume disappear 停听音模式，不重启硬件。details 失败／加载／返回文案和动作一致。
- [ ] 完整门槛后提交：`refactor: present bluetooth and detail panels through value state`。

### Task 11：面板 ViewModel 和全部 SwiftUI 消费者接入

**Files:** Create `Presentation/Panel/StatusPanelViewModel.swift`；Modify `UI/StatusPopoverView.swift`、`StatusBarController.swift`；Modify `BatteryStatusView.swift`、`NetworkStatusView.swift`、`WiFiStatusView.swift`、`EthernetStatusView.swift`、`VPNStatusView.swift`、`BluetoothStatusView.swift`、`BluetoothDeviceList.swift`、`BluetoothDeviceRow.swift`、`NearbyBluetoothBatteryList.swift`、`NearbyBluetoothBatteryRows.swift`、`VolumeControlsView.swift`、`VolumeOutputSummaryView.swift`、`OutputDeviceList.swift`、`AudioInputControlsView.swift`、`BatteryDetailsView.swift`、`WiFiNetworkListView.swift`、`EthernetLinkView.swift`；审计并迁移仍解释领域模型的 `WiFiStatusIcon.swift`、`BluetoothDeviceRowIcon.swift`、`AudioOutputDeviceIconView.swift`，更新 `BluetoothListeningModeControl.swift` 的文案输入（需要时）；Create `Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift`、`PanelPresentationWiringTests.swift`；Modify 这些 views 的现有布局、scroll、permission、popover tests。

**Interfaces:** `@MainActor StatusPanelViewModel: ObservableObject` initializer 为 `(store: SystemStatusStore, settings: SettingsStore, localization: Localization, actions: StatusPanelActions)`；公开 private(set) published `battery: PanelSummaryState`、`network: PanelSummaryState`、`vpn: PanelSummaryState`、`bluetooth: BluetoothPanelState`、`volume: VolumePanelState`、`audioInput: AudioInputPanelState`、三种 detail 状态。`start()`／`stop()` 只负责展示订阅，不启动／停止领域监控。views 改为 `state:` + callbacks；Settings 的 UI 偏好可以由 ViewModel 投递，不能再让 view 解读设备领域对象。

detail 属性明确为 `batteryDetails: PanelDetailState`、`wifiDetails: WiFiPanelState`、`wiredDetails: PanelDetailState`。`PanelDetailRow.isCopyable` 携带现有 LinkDetailPresentation 的地址行资格，SwiftUI 通过显式 copy-value callback 处理点击，不在 view 重算地址策略。保留多个区域 publisher，不能对大型联合 state 每次任何变化都重新发布所有区域。

Wi-Fi details 保留 view-local More／Less toggle：通过 `wifiDetails.visibleDetailRows(expanded:)` 显示完整解析行集的折叠／展开切片，并使用 state 的 `showMoreTitle`／`showLessTitle`，不在 view 重映射 `WiFiConnectionDetails`。

Bluetooth summary 根据 `PanelSummaryIntent.requestBluetoothAuthorization`／`.openBluetoothPermissionSettings` 路由到独立 action callbacks；Bluetooth device row 普通点击调用 `rowTapped(address:)`，确认按钮调用 `confirmBluetoothDisconnect(address:)`，取消调用 `cancelDisconnect()`。呈现使用 state 的 connected、battery layout／segments、status text／tint 和 confirmation fields，不在 view 检查设备类别或重算 battery policy。当前 Bluetooth panel 和 output panel 均无拖放／`.onMove` 控件，保留原有堆叠布局且不新增排序交互；Settings 中已存在的 output reorder UI 保持不变。`moveBluetoothDevices` 与 panel 未使用的 `moveOutputDevices` 列入 Task 12 API 清理审计，不为使用 API 新增 UI。

- [ ] 新失败测试确保按独立源更新：`popupSnapshot` 更新 battery／network；`liveVolume` 立即更新 volume；`liveInput` 更新 input；VPN 更新不触发 icon。使用既有 mock monitors／store fixtures，重用当前测试的 ManualEventSleeper，不新增固定睡眠。
- [ ] Run `swift test --filter 'StatusPanelViewModelTests|PanelPresentationWiringTests'`。按区域 Combine delivered values，`removeDuplicates` 后发布；controller 多字段如只支持 `objectWillChange`，安排主 actor coalescer 在变更落地后读一致的 controller 快照，不在 willChange 回调读旧值。
- [ ] StatusBarController 组装一个 panel owner 并给 retained popover 使用；view 对 `PopupSection` 的 switch 保留，领域引用由 state + callbacks 替代。controller 保留 popover setVisible gate；ViewModel start 不能主动扫描。旧 SwiftUI preview／test initializer 可短期 adapter，必须标记调用方并在 Task 12 清掉。
- [ ] 音量 Slider 保留局部 draft／isAdjusting：

```swift
.onChange(of: state.scalar) { _, newValue in
    guard !isAdjusting else { return }
    draftVolume = newValue ?? 0
}
```

editing begin／end 使用现有对称动作，在 end 调 `finishVolumeAdjustment`；不因 model 更新重复 setVolume。scroll target 的 bounds 注册和自然滚动设置保持；Menu Bar 滚轮仍作用同一 store 动作，通过协调入口传递。

- [ ] 迁移 output／input row select 为稳定 key，列表重排不误选；SwiftUI 本地 expansion／drag 可保留，但排序和过滤输入已由展示层解析。synthetic listening controls、preview language、设备行颜色及 busy 控制一并保持。
- [ ] lifecycle spy 测试 state 更新不触发 scan；appear／disappear 配对，关闭全部 details，返回后正确释放；语言切换能更新 retained view，图标 raster 不变。System Settings URL 次序保持，运行 `swift test --filter StatusMenuBuilderTests`。
- [ ] 全部六区／详情的布局快照、scroll targets、input capability、Bluetooth action tests 和完整门槛通过后提交：`refactor: bind status panel views to presentation state`。

### Task 12：清理、架构保护与维护文档

**Files:** Modify 旧 panel adapters、`Models/StatusMappings.swift`、`Models/MenuBarStatus.swift`、`Models/StatusIconAppearance.swift`（仅仍有真实调用者时保留）；Update `docs/presentation-state-behavior-matrix.md`；Create `docs/presentation-state-architecture.md`；Create `Tests/StatusTrioCoreTests/PresentationArchitectureTests.swift`；Modify `ForbiddenPatternGuardTests.swift` 仅在已有结构检查适合时使用。

**Interfaces:** 最终生产入口只有 scene + environment；主要 UI state 不含领域 model 或 controller；旧 `StatusPresentation` 名称无混杂职责。compile-time dependency 优先，不为每个文件写字符串快照。

- [ ] 先增加独立架构行为断言：

```swift
func testSceneDoesNotDependOnSSID() {
    let base = PresentationFixtures.snapshot()
    let renamed = StatusSnapshot(battery: base.battery,
        wifi: WiFiStatus(state: base.wifi.state, rssi: base.wifi.rssi, ssid: "Renamed"),
        connection: base.connection, volume: base.volume)
    XCTAssertEqual(IconPresentationMapper.scene(
        inputs: IconPresentationInputs(snapshot: base, audioIcon: nil), configuration: .standard),
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: renamed, audioIcon: nil), configuration: .standard))
}
```

- [ ] Run `swift test --filter PresentationArchitectureTests`，预计 behavior PASS；删除 obsolete adapter 后以编译发现任何未迁消费者，不绕过错误加回域模型入口。搜索 renderer 域类型、视图原 `StatusPresentation` 调用、旧 render key 参数和旧 preview mapping。
- [ ] 行为矩阵每行填写最终 owning tests 和结果，不留下“以后补”。测试多余源字符串检查不作为唯一验收；现有 ForbiddenPatternGuard 的编译禁用规则保持。
- [ ] 文档写入流向、各类职责、设置新增的完整更新清单、颜色／尺寸／phase cache identity、publisher delivered-value 规则、panel lifecycle 和 accessible identity；写明未来 state producer 不得直接绘制、Dock 当前 static、split ring／remote 示例未实现。
- [ ] 图标里程碑和面板里程碑的完整 diff 各审阅一次，确认没有监控重写、设置键迁移或指纹无解释更新。最后完整门槛后提交：`docs: document and enforce presentation architecture boundaries`。

### Task 13：非发布 release preflight 与最终交接

**Files:** Read `.github/workflows/release.yml`、`Support/Info.plist`、`scripts/validate-appcast-notes.sh`、`scripts/build-app.sh`、`scripts/verify-platform-version.sh`；Modify `docs/swift-ci-compatibility.md`（仅有失败时）；Create／Modify `release-notes/<实际验证版本>/en.md`、`zh-Hans.md`（workflow 缺失所需材料时）。不得改 appcast 或发布 tag。

**Interfaces:** 输入为已验证的分支 commit、明确 version 和未用的递增 build；输出为该 SHA 的成功 Actions run URL、toolchain／test／SDK／DMG 检查结果。执行时填写实际数据，不能把本文的变量名直接传给 workflow。

- [ ] 确认本地 diff 与任务范围，执行完整本地门槛，保存实际命令结果；读取 plist 和已有 notes，读取发布／run／appcast 信息确定 version／build：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist
gh release list --repo lingyired/status-trio --limit 10
gh run list --repo lingyired/status-trio --workflow release.yml --limit 20
read -r PREFLIGHT_VERSION
read -r PREFLIGHT_BUILD
```

同时读取仓库 `appcast.xml` 中最大 published build 和本次 version 使用历史；下一 build 大于已发布值且未在相关已执行／排队 run 中使用。`gh run view` 展开涉及的 run inputs／logs，不能只把 run number 当 published build。保留本次预检的明确取值记录。

- [ ] 验证 notes coverage。`publish=false` 所需 en／zh-Hans 每个文件以包含 `%VERSION%` 和 `%BUILD%` 的 `#` 标题开头；notes 内容依据实际重构和支持术语，不把第一启动命令放入 Sparkle 内容。Run `env VERSION="$PREFLIGHT_VERSION" BUILD="$PREFLIGHT_BUILD" PUBLISH=false bash scripts/validate-appcast-notes.sh`；材料变更审阅后单独提交。此次不要求准备真正 `publish=true` 的全部 12 语言发行材料。脚本当前允许缺目录时 skip，但本计划必须实际准备 en／zh-Hans 并验证，不能以 skip 充当 notes 验收。
- [ ] 推送当前分支，然后在终端明确输入选定值：

```bash
git push -u origin codex/2.0-presentation-refactor
gh workflow run release.yml --repo lingyired/status-trio \
  --ref codex/2.0-presentation-refactor \
  -f version="$PREFLIGHT_VERSION" -f build="$PREFLIGHT_BUILD" -f publish=false
```

自动执行者可以使用已确定的 literal 值替代前一步的两个 read；必须先记录真实取值并确认与 notes validator 的版本选择一致。shell 变量名使用任务专属前缀，不复用 HOME／CODEX_HOME。

- [ ] 获取本次 branch、时间及 head SHA 匹配的实际 run ID，watch 并检查 jobs：

```bash
gh run list --repo lingyired/status-trio --workflow release.yml \
  --branch codex/2.0-presentation-refactor --limit 5 \
  --json databaseId,headSha,status,conclusion,url,createdAt
read -r PREFLIGHT_RUN_ID
gh run watch "$PREFLIGHT_RUN_ID" --repo lingyired/status-trio --exit-status
gh run view "$PREFLIGHT_RUN_ID" --repo lingyired/status-trio
```

只将实际 dispatch run ID 传给 watch。确认 Show toolchain、tests、app build、platform SDK 检查、DMG creation 和非发布分支均成功；Release upload／appcast publication 应是跳过，不能报告“已发布”。

- [ ] 如果失败，停止进入合并／发布流程，记录 run ID、失败阶段、根因、修复和验证结果到 compatibility 文档；修复后重跑必要本地测试并用新 SHA 重新 preflight。已成功 run 不能为后续 Swift 修改背书。
- [ ] 最终报告 branch／SHA、图标及面板里程碑、测试结果、成功 CI 链接、已知限制和清理状态。大版本重构适合 PR 记录；只有用户选择整合步骤后创建／合并，保持当前独立分支，不自行 fast-forward main。正式 2.0 发布仍是另一次明确的发行任务。

## Spec 覆盖索引与计划自审

| Spec 要求 | 实施任务 |
|---|---|
| 目标、范围、现有问题、所有权（§1–4） | Task 1、5、6、11；全局约束 |
| 状态、视觉属性、归一化、未来边界（§5） | Task 2–4；Task 12 文档 |
| 发布、动画、缓存、语言及 VoiceOver（§6） | Task 5–8、11 |
| 六区、详情、动作、失败与生命周期（§7） | Task 8–11 |
| 渐进迁移、旧入口退出（§8） | Task 1–12；里程碑顺序 |
| 分层测试与指定 CI（§9） | 各 task 验收、Task 13 |
| 风险、最终文档与实施交接（§10–11） | Review Focus、Task 12–13、下述审阅门槛 |

任务接口以本文定义为准；代码片段中省略函数体的接口清单仅用于签名说明，实际修改步骤已给出核心实现／迁移规则。实施发现像素、生命周期或 CI 要求需要改变已审阅设计时，先说明具体差异并更新文档，不悄悄扩大范围。

## 用户审阅与执行方式

先审阅本计划，再选执行方式。两种方式均按用户要求由 `gpt-6-luna` 实施产品代码；规划代理不得自行实现。

- **逐任务子代理（推荐）**：每个任务由新的 Luna 实施者执行，再由独立 reviewer 审阅，最后整分支审阅。上下文成本更高，但适合本次多个绘制／缓存／生命周期边界的长期迁移。
- **单个 Luna 实施者**：一个 Luna 接续全部任务，阶段末做独立整分支审阅。上下文开销较低，需要严格遵守里程碑和接口。

使用多代理执行前读取 `subagent-driven-development`；单个实施者读取 `executing-plans`。用户选择后才启动对应执行流程。完成实施计划本身不授权执行全部代码任务。
