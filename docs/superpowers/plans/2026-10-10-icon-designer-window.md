# Status Trio 2.0 Independent Icon Designer Implementation Plan

> **2026-10-12 尺寸规范补充：** 本文件中涉及尺寸控件、首次编辑存储字段的旧条款，以[图标尺寸统一规范](../../icon-sizing-standard.md)为准：中心所有来源 100–180%，外环/底部描边 80–120%，外环文字 90–110%；以上百分比均以 5% 递增。旧倍率字段仅用于存储/渲染兼容，不作为交互范围。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 产品实现必须使用 `gpt-6-luna` / `high`；非 Luna 主会话先委派实现，不自行偷偷写产品代码。建议一个 Luna 实现者连续完成有依赖的任务，协调者验证；只有 disjoint write sets 才并行。用户在新会话明确要求执行本计划后才开始。

**Goal:** 把当前 2.0 图标设计器重构为独立大窗口，保留真实大图/菜单栏/Dock预览，以一个蓝牙入口组织设备，并把 source-bound 模拟数据移到独立浮动窗口。

**Architecture:** 复用 SettingsStore → IconResolutionInputs → IconCompositionResolver → 真实 renderer。一个只在内存中的 preview session 共享给主窗口和模拟 NSPanel；正式配置通过编辑适配器进入 SettingsStore，模拟输入永不进入真实图标控制器。窗口 controller 负责生命周期，编辑模型负责分组/默认/历史，预览负责分层渲染和短动效。

**Tech Stack:** SwiftPM、SwiftUI、AppKit、Combine、XCTest + 现有 Swift Testing；macOS 13+；无新增第三方依赖。

**Spec:** `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio/docs/superpowers/specs/2026-10-10-icon-designer-window-design.md`。

## Global Constraints

- worktree：`/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio`；branch：`codex/v2-settings-icon-designer`；检查时 HEAD `f02b764604ebe20adad1c5df6127e9fe1898f5b0`，但存在重要未提交实现。
- 主 checkout `/Users/lingsmbp/Documents/aiwork/status-trio` 不参与改动；不从干净 HEAD/main 重新开始，不覆盖任何已有改动。
- macOS 13+；SDK >=26；CI `macos-26 / Xcode 26.6 / Swift 6.3.3`；禁止 isolated deinit、weak let、实验隔离 compiler flags。
- 只本地开发版 `com.lingsmbp.StatusTrio.Dev` / 2.0.0 / Icon Designer；无 release/tag/appcast/push/merge/TCC reset/公证上传。
- 所有图标语义/外观改变同任务覆盖 menu/Dock controller subscription、render key、renderer 与测试；新动效仅预览。
- 12 语言、原生 ColorPicker、键盘/VoiceOver、Reduce Motion、无权限状态必须保留。
- 模拟 tool window 不影响主窗口布局或实际权限/监控；选择蓝牙目标不连接、配对或读取 GATT。
- 旧 `.automaticLegacy` 保留解码和渲染但不作为可选来源；只有明确选内容或确认恢复默认才写新配置。

## Review Focus

1. 旧配置含自动兼容、静态蓝牙符号、异常 payload 时，打开新窗口必须保持偏好字节和原始图案；Task 2 的兼容测试覆盖。
2. 选中的设备断开、权限被撤销、出现同名设备时，保留标准化地址并执行 fallback，不切换目标、不连接；Task 3/4 覆盖。
3. 普通设置/设计器/工具窗多种关闭顺序及初始权限发布，不能关掉另一窗口的 demand、弹开已关闭窗；Task 5/7 覆盖。
4. 拖动颜色、切模拟来源、其他设置页同时写图标偏好时，撤销不能影响样例或覆盖外部新配置；Task 8 覆盖。
5. 快速 Wi-Fi/蓝牙/数字切换、Reduce Motion、关闭窗口时，图层不残留、其他元素不移动、不遗留 timer；Task 9 覆盖。

---

## 0. 执行顺序与交接基线

Task 1（session）→ Task 2（来源/默认）→ Task 3（蓝牙适配）→ Task 4（模拟 inputs）→ Task 5（窗口）→ Task 6（主布局）→ Task 7（浮动数据窗）→ Task 8（编辑历史）→ Task 9（动效）→ Task 10（回归/本地运行）。每一任务红/绿测试之后再进入下一个。不要同时让多个代理改 SettingsStore、AppEnvironment 或 IconDesignerView。

- [x] 在新会话读 AGENTS.md、规格、本计划和已归档网页。网页只是视觉示意，尤其不执行其简化的网络/权限/百分比规则。
- [x] 核对当前状态并确认交接基线已保存到未跟踪的 `output/icon-designer-window/baseline/`：

```bash
cd '/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio'
mkdir -p output/icon-designer-window/baseline
git branch --show-current
git rev-parse HEAD
git status --short > output/icon-designer-window/baseline/status.txt
git diff --binary > output/icon-designer-window/baseline/tracked.patch
git ls-files --others --exclude-standard > output/icon-designer-window/baseline/untracked.txt
swift --version
xcrun --show-sdk-version
```

- [x] 确认交接基线的 `swift test` 和 `swift build -c release` 均已运行并保存 log 与退出状态。既有失败先定位，不能删测试或覆盖未提交文件来制造绿灯。不要把本计划编写视为已跑过这两项。
- [ ] 逐个审阅 dirty 路径。需要 checkpoint 时只在当前分支显式 stage 属于此前 2.0 开发的文件，先获用户授权；不 `git add .`/`-A`。不认识的变动保留，必要时问一个具体问题。
- [ ] 保存 Dev bundle signing requirement、版本/代号和 production executable hash 作后续对比，不导出完整真实设备目录或地址作为交付截图。

## 1. 文件边界与接口约定

下表路径均在 `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio` 下；新文件命名是本计划的约定，不表示目前已经存在。

| 单元 | 新建/主要修改文件 | 责任 |
|---|---|---|
| 共享样例 | `Sources/StatusTrioCore/Presentation/Icon/Preview/IconPreviewSampleValues.swift`、`UI/Settings/IconDesigner/IconDesignerPreviewSession.swift` | source-keyed 样例、模式、场景、编辑位置 |
| 选择/默认 | `UI/Settings/IconDesigner/IconDesignerSourceSelection.swift`、`IconDesignerDefaults.swift`、既有 `IconDesignerEditingModel.swift` | UI 分组、兼容、明确恢复默认 |
| 蓝牙适配 | `IconDesignerBluetoothEditor.swift`、`IconDesignerBluetoothTargetModel.swift`、既有 `IconSourceEditor.swift` | 跟随音频/指定在线设备、类型适用规则 |
| 输入构造 | `Presentation/Icon/Preview/IconPreviewInputBuilder.swift`、既有 `IconDesignerPreviewResolver.swift`、`IconPreviewScenario.swift` | deterministic mock inputs、真实 resolver |
| 窗口 | `UI/Settings/IconDesigner/IconDesignerWindowController.swift`、`IconPreviewDataWindowController.swift`、既有 `App/AppEnvironment.swift`、`UI/Settings/SettingsWindowController.swift`、`SettingsView.swift` | 独立 NSWindow/NSPanel、入口、生命周期 |
| 多窗口 demand | `UI/Settings/SettingsSurfaceVisibility.swift`、既有 `Store/SystemStatusStore.swift` | settings-visible owner 聚合，兼容旧入口 |
| 视图 | 既有 `IconDesignerView.swift`、新 `IconDesignerPreviewPane.swift`、`IconDesignerInspector.swift`、`IconPreviewDataView.swift` | 主窗口双列、真实预览、浮动面板表单 |
| 编辑历史 | `IconDesignerEditSnapshot.swift`、`IconDesignerEditHistory.swift`、`IconDesignerEditorModel.swift` | 有界撤销、正式配置事务、外部更新处理 |
| 动效 | `IconPreviewTransitionState.swift`、`IconAnimatedCenterPreview.swift`、必要的 `UI/Icon/StatusIconRenderer.swift` | 使用真实分层 artwork、短动效 |
| 本地化 | `Localization/LocalizationKey.swift`、12 `Resources/*.lproj/Localizable.strings` | 文案及即时语言刷新 |

既有来源域模型继续使用 `RingSource/CenterSource/FooterSource`，UI 归并不意味着把 Codable enum 改成新名字。最小必要扩展应向后可解码并测试，不能引入第二套持久化来源配置。

> **规范尺寸替代（2026-10-12）：** 本计划中任何旧 UI 尺寸范围、原始倍率及“首次编辑写入最终倍率”的表述，均由 [Icon Designer sizing standard](../../icon-sizing-standard.md) 取代：所有中心内容为 100–180% 可见尺寸百分比，外环和底部弧/点笔画为 80–120% 相对百分比。旧原始倍率和值域仅为持久化兼容、未显式编辑时的 legacy 渲染保留，不是 UI 范围；不得在打开界面或首次编辑时迁移/重写旧字段。

## Task 1: source-bound 共享 preview session

**Files:** 新 `IconPreviewSampleValues.swift`、`IconDesignerPreviewSession.swift`；先在新 `IconDesignerBluetoothTargetModel.swift` 建立共用 target enum（Task3再补行为）；复用 `CustomAirPodsPreviewSample.swift`；测试 `Tests/StatusTrioCoreTests/IconDesignerPreviewSessionTests.swift`。

**Interfaces:**

```swift
enum IconPreviewDataMode: Equatable, Sendable { case live, simulated }
enum IconPreviewSampleSource: Hashable, Sendable {
    case macBattery, airPods, network, bluetoothTarget, systemVolume
}
enum IconPreviewEar: Sendable { case left, right }
// 同时建立共用 target 型，避免Task1依赖尚未执行Task3才能编译。
enum IconDesignerBluetoothTarget: Equatable, Sendable {
    case currentAudioOutput
    case connectedDevice(address: String)
    case preservedUnboundGlyph
}
struct MacBatteryPreviewSample: Equatable, Sendable {
    var isPresent = true
    var percentage = 76
    var isCharging = false
}
enum IconPreviewNetworkKind: Equatable, Sendable {
    case wifi, noInternet, off, ethernet, hotspot, temporary, shared
}
struct NetworkPreviewSample: Equatable, Sendable {
    var kind: IconPreviewNetworkKind = .wifi
}
struct BluetoothTargetPreviewSample: Equatable, Sendable {
    var isOnline = true
    var isAudio = true
    var symbolName = "headphones"
}
struct VolumePreviewSample: Equatable, Sendable {
    var percentage = 62
    var isMuted = false
    var isAvailable = true
}
struct IconPreviewSampleValues: Equatable, Sendable {
    var macBattery = MacBatteryPreviewSample()
    var airPods = CustomAirPodsPreviewSample()
    var network = NetworkPreviewSample()
    var bluetoothTarget = BluetoothTargetPreviewSample()
    var systemVolume = VolumePreviewSample()
}
@MainActor final class IconDesignerPreviewSession: ObservableObject {
    @Published var mode: IconPreviewDataMode = .live
    @Published var selectedSlot: IconSlot = .outerRing
    @Published private(set) var samples: IconPreviewSampleValues
    init()  // 实时启动；样例存在但尚未应用。
    func setAirPodsBattery(_ ear: IconPreviewEar, _ value: Double)
    func applyScenario(_ scenario: IconPreviewScenario)
    func usedSources(configuration: IconConfigurationV1,
                     target: IconDesignerBluetoothTarget,
                     devices: [BluetoothDevice]) -> Set<IconPreviewSampleSource>
}
```

- [x] 写可执行失败测试（完整测试覆盖右耳/样例保留/共享来源/非法数值/一次性场景/非持久化）：

```swift
@MainActor
func testSelectingSlotDoesNotResetSharedAirPodsSample() {
    let session = IconDesignerPreviewSession()
    session.setAirPodsBattery(.left, 25)
    session.selectedSlot = .center
    session.selectedSlot = .outerRing
    XCTAssertEqual(session.samples.airPods.leftBattery, 25)
    XCTAssertEqual(session.mode, .live)
}
```

- [x] `swift test --filter IconDesignerPreviewSessionTests`：确认因未实现接口而失败，保存 red log。
- [x] 实现 typed source-keyed 值和 session；setter 拷贝 value 再发布；clamp `0...100`，NaN/Infinity 使用安全默认值；scenario 一次填充数据，不会覆盖后续修改。
- [x] `usedSources` 聚合主/备用和规则依赖；Mac 环/中间数字同一个 key；蓝牙音频使用音量颜色时即使 footer 为 none 也需要音量样例。样例不引用 SettingsStore/defaults。
- [x] 跑 focused tests，验证一次性 preset 后手动编辑、生效样例非 Codable、隐藏后保留先前值；绿灯并记录新增文件。

## Task 2: 来源归并和明确的恢复默认

**Files:** 新 `IconDesignerSourceSelection.swift`、`IconDesignerDefaults.swift`；修改 `IconDesignerEditingModel.swift`、`IconSourceEditor.swift`、`IconPresetPicker.swift`；测试 `IconDesignerSourceSelectionTests.swift`、`IconDesignerDefaultsTests.swift`，扩展 `IconConfigurationMigrationTests.swift`。

**Interfaces:** `IconDesignerCenterChoice: network, bluetoothDevice, macBatteryPercentage, none`；`IconDesignerDefaults.configuration()` 返回显式新版默认；`resetting(_:in:)` 只覆盖对应元素相关字段。读取旧配置的展示适配器不写 store。

- [x] 写失败测试：

```swift
func testDesignerDefaultNeverRestoresAutomaticLegacySources() {
    let value = IconDesignerDefaults.configuration()
    XCTAssertEqual(value.composition.outerRing.primary, .systemBattery)
    XCTAssertEqual(value.composition.center.primary, .network)
    XCTAssertEqual(value.composition.footer.primary, .systemVolume)
    XCTAssertNil(value.composition.outerRing.fallback)
    XCTAssertNil(value.composition.center.fallback)
    XCTAssertEqual(value.schemaVersion, 1)
}
```

- [x] `swift test` 确认默认/来源接口缺失时红灯（日志见 `output/icon-designer-window/task-2-red.log`）。
- [x] 默认工厂从 `.classic` 拷贝再替换 primary/fallback，不改全局 `.classic` 或首次加载迁移规则。slot reset 不清除 placement、语言、遥测、设备名单或 session。
- [x] `.automaticLegacy` 和 `.pinnedBluetoothGlyph` 保持解码；旧自动显示保留说明、不作为新选项。静态蓝牙 glyph 保持旧配置且不可被自动替换。非法/unsupported JSON仍沿用现有 load error 保护。
- [x] 覆盖 legacy payload no-write、slot reset 只改当前元素、pinned glyph 保留；focused + migration tests 通过。恢复操作的 auxiliary 字段纳入 Task 8 snapshot。

## Task 3: 蓝牙一个入口、类型适配与真实渲染 parity

**Files:** 扩充Task1建立的 `IconDesignerBluetoothTargetModel.swift`，新 `IconDesignerBluetoothEditor.swift`；修改 `IconSourceEditor.swift`、`IconBehaviorEditor.swift`、`SettingsStore.swift`；必要修改 `Presentation/Icon/Resolution/CenterResolver.swift`、`IconSourceSnapshot.swift`、`IconPaletteResolver.swift`、`UI/StatusBarController.swift`、`App/AppIconController.swift`、Dock cache key 路径；测试 `IconDesignerBluetoothTargetTests.swift`、`IconSceneRendererParityTests.swift`、`IconSurfaceIntegrationTests.swift`。

**Interfaces:**

```swift
// IconDesignerBluetoothTarget enum 已在Task1定义；preservedUnboundGlyph只读旧配置。
struct IconDesignerBluetoothTargetModel {
    static func isAudioTarget(_ target: IconDesignerBluetoothTarget,
                              devices: [BluetoothDevice]) -> Bool
}
```

- [x] 先建立设备 fixture，用现有设备模型 init（实际定义在 `Models/WiFiNetworkModels.swift`，不要猜另一个同名文件）；失败测试覆盖指定 AirPods 为 audio、键盘 non-audio、同名不同地址、在线过滤、离线目标保留。
- [x] `swift test --filter IconDesignerBluetoothTargetTests` 确认红灯。
- [x] 当前音频映射 `.bluetoothAudioOutput`；指定地址映射 `.connectedBluetoothDevice` 并使用 `connectedBluetoothIconDeviceAddress`。地址通过现有 `BluetoothBatteryReader.normalizedAddress` 归一；picker 只读设备目录，不调用 device actions。备用来源蓝牙目标与主来源复用当前 center 的同一个目标偏好，不创建含糊的第二份地址。
- [x] 音频目标（包括明确指定音频设备）显示适用控制，其他目标隐藏。图标固定/自动是 style，保留既有符号兼容；不得用“固定”样式把原本在线目标变成离线仍显示的来源。离线/权限失效通过 source availability 执行 fallback。
- [x] resolver 对指定音频的符号、音量色/网络错误优先支持到同一真实 scene；所需 source snapshot 扩展须有 backward-compatible 默认。所有相关 live publishers、render key 同步覆盖 menu/Dock。保持非当前输出音频的音量规则为“系统当前输出音量”，明确文案，不暗示读取另一设备音量。
- [x] focused + parity/integration tests；加入 spy 断言 picker 路径无 connect/pair/service discovery，权限缓存不能进入在线列表。保持测试源稳定排序。

## Task 4: 模拟 inputs 纯构造并复用真实 resolver

**Files:** 新 `IconPreviewInputBuilder.swift`；修改 `IconDesignerPreviewResolver.swift`、必要的 `IconPreviewScenario.swift`；测试 `IconPreviewInputBuilderTests.swift`、`IconPreviewScenarioTests.swift`、`IconDesignerCustomAirPodsPreviewContractTests.swift`。

**Interfaces:**

```swift
enum IconPreviewInputBuilder {
    static func simulated(samples: IconPreviewSampleValues,
                          configuration: IconConfigurationV1,
                          target: IconDesignerBluetoothTarget,
                          now: Date) -> IconResolutionInputs
}
// live 模式原样使用实际 inputs；simulated 模式只调用上面纯构造器。
```

- [x] 建立冻结日期和各来源 fixture；写失败测试 `testSameMacSampleDrivesRingAndCenterPercentage`、`testAirPodsSingleEarMirrorsForDualRing`、`testBothEarsUnavailableUsesFallback`、`testPermissionSampleDoesNotRequestPermission`。
- [x] `swift test --filter IconPreviewInputBuilderTests` 确认红灯。
- [x] 按现有 `StatusSnapshot`/`IconSourceSnapshot` 真正 init 补齐所有字段，显式 source availability。使用现有 AirPods mapper 和真实 resolver；不把网页 quarter arc、占位百分号、模拟蓝牙名字写入生产路径。
- [x] 用两份互不相同 live fixtures 证明相同模拟 samples 产出完全相同 scene；切回 live 恢复真实 inputs；写 spy 证明没有 defaults write、monitor poll、真实权限请求。样例的主/备用结果 trace 用于说明文案。
- [x] focused tests + `swift test --filter 'IconPreviewScenarioTests|IconSceneRendererParityTests'`；保留既有充电/网络场景用例。

## Task 5: 独立大窗口、入口和多窗口可见性

**Files:** 新 `IconDesignerWindowController.swift`、`SettingsSurfaceVisibility.swift`；修改 `AppEnvironment.swift`、`SettingsWindowController.swift`、`SettingsView.swift`、`SettingsNavigationModel.swift`、`SystemStatusStore.swift`；测试 `IconDesignerWindowControllerTests.swift`、`SettingsSurfaceVisibilityTests.swift`、既有 `SettingsWindowControllerTests.swift`、`AppActivationPolicyTests.swift`。

**Interfaces:**

```swift
@MainActor final class IconDesignerWindowController: NSWindowController {
    func show(slot: IconSlot = .outerRing)
    // init 注入 store/statusStore/localization/activationPolicy/
    // chargingEffectClock/session，沿用 SettingsWindowController 的注入模式。
}
struct SettingsSurfaceVisibility: Equatable {
    private(set) var owners: Set<String> = []
    var isVisible: Bool { !owners.isEmpty }
    mutating func setVisible(_ visible: Bool, owner: String) {
        if visible { owners.insert(owner) } else { owners.remove(owner) }
    }
}
```

- [ ] 写 `testClosingSettingsDoesNotHideVisibleDesigner`：纯 owner 测试，先 setVisible true settings/designer，再 false settings，assert isVisible true；再 false designer，assert false。增加重复 show/close 不累加、close顺序相反的测试。
- [ ] focused visibility/window tests 红灯；复用既有 SettingsWindowControllerTests 的 isolated defaults/activation spy，不读写用户真实 defaults。
- [ ] `SystemStatusStore.setSettingsVisible(_:)` 保留老签名，内部使用 legacy owner；新增 `setSettingsVisible(_:owner:)`。settings/designer 使用固定独立 owner，只有聚合 false→true 时 refresh；panel不申请 owner。不能改变 popover原有 demand。
- [ ] Designer NSWindow 按规格尺寸、resizable、独立 autosave；单实例、window close释放 hosting view，但 AppEnvironment 保留本次运行 session。AppEnvironment 注入共享 clock、localization，不形成强引用环。
- [ ] Battery/Network/Bluetooth/Audio 入口改为 controller.show 对应 slot。普通设置侧栏“图标”改为轻量入口与显示设置，不重复大编辑器；保留现有设备管理与有效普通设置。AppDelegate Dock/reopen/开机第一次点击行为不改。
- [ ] 重复 show 复用、权限初始发布不创建窗、用户关窗后权限变更不重开；普通设置仍可单独正常打开。focused controller/activation tests绿灯。

## Task 6: 主窗口双列与真实大预览

**Files:** 大小兼容还修改 `Presentation/Icon/Configuration/IconAppearanceConfiguration.swift`、`Presentation/Icon/Resolution/IconPaletteResolver.swift`及相应render key；重构 `IconDesignerView.swift`；新 `IconDesignerPreviewPane.swift`、`IconDesignerInspector.swift`；修改 `IconDesignerLayout.swift`、`IconSlotPicker.swift`、`IconSourceEditor.swift`、`IconAppearanceEditor.swift`、`IconSurfaceSettings.swift`、`StatusIconPreviewCard.swift`；测试 `IconDesignerLayoutTests.swift`、`IconDesignerAccessibilityTests.swift`、`UnifiedWiFiScaleMigrationTests.swift`、`StatusIconPreviewCardTests.swift`。

- [ ] 写宽度 900/1120/1440 下 pane 布局纯测试；右滚动/左固定契约测试，点击元素只更新 session.selectedSlot。完整图案不被蓝色选中效果污染。
- [ ] 运行 focused layout tests 红灯；原 `SettingsPage` pinned header 的88pt契约属于旧布局，按新规格更新具体断言，不能只删测试。
- [ ] 用 `HStack`/GeometryReader 提供左预览右 inspector；右侧一个 ScrollView；左不是承载所有表单的 ScrollView。工具窗入口只 show panel，无 inline samples。实现三个可键盘选中的 tabs、来源卡片、主规则/备用规则、外观和底部操作。
- [ ] 大图 240–300pt使用真实 StatusIconRenderer/menu style，mini menu真实尺寸，Dock128pt真实DockIconRenderer；必要新增 preview 内容类型，不改变普通设置页 menuBarOnly。沿用当前字号可见 ink 居中和AirPods镜像规则，保留解释位置。
- [ ] Center dimension policy is superseded by [Icon Designer sizing standard](../../icon-sizing-standard.md): use the optional source-independent 100–180% visible-size field and adaptive measured ink sizing for text, symbols, images, primitives, and fallbacks. Keep legacy fields/rendering untouched until an explicit edit; do not use the former 0.5–6 raw-symbol range as the UI standard.
- [ ] Apply the same semantic size to resolved primary/fallback center content; include it in menu/Dock scene identity. Keep the historical Codable fields for compatibility and test nil legacy rendering, explicit edit, undo/reset, and cache keys. See the durable sizing standard for authoritative calibration and acceptance cases.
- [ ] focused UI/scale/color/preview tests，至少 900×680和1120×800 手动检查 clipping、右栏可滚动、左预览不跳动。

## Task 7: 独立模拟 NSPanel

**Files:** 新 `IconPreviewDataWindowController.swift`、`IconPreviewDataView.swift`；修改 `IconDesignerWindowController.swift`、`IconDesignerPreviewPane.swift`；测试 `IconPreviewDataWindowControllerTests.swift`、`IconPreviewSampleVisibilityTests.swift`。

**Interfaces:** `IconPreviewDataWindowController.show(relativeTo: NSWindow)`；由 designer持有；view引用相同 previewSession，不创建自己的 samples副本。close只释放panel hosting，不释放session。

- [ ] 写 controller失败测试：两次 show同一个panel；close再show新panel同session；open/close期间主window frame、content size与主布局高度不变。
- [ ] focused panel tests 红灯。
- [ ] NSPanel按380×520/min340×360、floating/hidesOnDeactivate、可成为key，定位 clamped 到screen.visibleFrame；独立autosave。创建和关闭仅成对调整activation临时regular，不单独申请monitor demand。
- [ ] 表单只列usedSources；共享Mac/AirPods/网络/蓝牙/volume值；关闭不写defaults。禁用或隐藏不可用耳的电量滑块；presets只改样例。左工具入口 `编辑数据…` 进入simulated；返回live还原真实显示，保留面板样例，panel注明当前是否生效。
- [ ] designer close联动panel close；本次App运行内 reopen保留samples，App重新启动mode.live。聚合窗口关闭/权限更新测试绿灯；确认真实权限notice不被模拟授权标记取代。

## Task 8: 配置事务、撤销和外部更新

**Files:** 新 `IconDesignerEditSnapshot.swift`、`IconDesignerEditHistory.swift`、`IconDesignerEditorModel.swift`；修改各编辑器、preset/default操作；测试 `IconDesignerEditHistoryTests.swift`、`IconDesignerPersistenceBoundaryTests.swift`。

**Interfaces:**

```swift
struct IconDesignerEditSnapshot: Equatable {
    var configuration: IconConfigurationV1
    var airPodsAddress: String?
    var connectedBluetoothAddress: String?
    var bluetoothNetworkAddress: String?
    var refreshesAirPodsBatteryForIcon: Bool
    // 符号override已经包含configuration，不重复存另一份。
}
struct IconDesignerEditHistory {
    init(limit: Int = 64)
    mutating func record(before: IconDesignerEditSnapshot,
                         after: IconDesignerEditSnapshot)
    mutating func undo(current: IconDesignerEditSnapshot) -> IconDesignerEditSnapshot?
    mutating func invalidateForExternalChange()
}
```

- [ ] 构造snapshot fixture，写失败测试：same before/after不记录、64项cap、undo恢复选中地址和配置、当前不等于last.after拒绝旧undo、sample根本不属于snapshot。
- [ ] focused edit history tests 红灯。
- [ ] 所有正式配置UI经editorModel事务进入store；transaction内observed settings更新不会当外部修改处理。slider拖动和ColorPicker持续更新在开始/结束coalesce；无开始事件时至少按前后snapshot做确定性提交。undo只恢复本模型拥有的字段。
- [ ] store共享变动来自其他设置页/图标同步时清空不再适用历史并提示；不要用stale全量defaults export恢复。reset当前/all调用Task2工厂并记录同一事务，不包含samples/placement/language/analytics。
- [ ] spy测试 `testSampleChangesDoNotWriteUserDefaultsOrAddUndo`、`testResetDoesNotModifySampleValues`、`testExternalEditInvalidatesHistory`、`testOneColorGestureOneUndo`；focused绿灯。

## Task 9: 中间图层短动效与无障碍

**Files:** 新 `IconPreviewTransitionState.swift`、`IconAnimatedCenterPreview.swift`；必要修改真实renderer提供layer mask；测试 `IconPreviewTransitionTests.swift`、`IconSceneRendererParityTests.swift`、`StatusIconCenterTextAlignmentTests.swift`、`Issue30WiFiAlignmentTests.swift`。

**Interfaces:**

```swift
struct IconPreviewTransitionState: Equatable {
    private(set) var generation: UInt64 = 0
    private(set) var latestIdentity: String?
    private(set) var isVisible = true
    var reduceMotion = false
    mutating func request(identity: String) -> UInt64
    mutating func complete(generation: UInt64) -> Bool
    mutating func setVisible(_ visible: Bool)
}
```

identity 只包括显式来源/目标/样式，不包含电量、网络实时状态或颜色。request更新latestIdentity并递增generation；complete只接收当前generation且窗口可见的结果；hide使旧generation失效。样例数字/实时状态普通更新不排队。

- [ ] 纯transition状态测试：快速A→B→C最后C；旧completion generation失效；reduceMotion不位移；setVisible(false)结束pending。renderer测试证明合成layer结果与同尺寸完整scene一致。
- [ ] focused transition tests 红灯。
- [ ] 用同一geometry和renderer绘制static outer/footer以及旧/新center overlay；不能让空slot改变layout后再裁图强行对齐。确认Dock预览使用Dock几何而不是menu图层复用。
- [ ] `withAnimation`总200–240ms短移淡化；Reduce Motion<=100ms纯淡化。关闭窗口取消pending work；用generation guard防旧completion回填。不加常驻Timer或后台播放队列。预览充电仍用shared clock，AirPods没有充电效。
- [ ] focused parity/ink/text tests绿灯；真实App手动快速切来源、不同数字长度、缩放和Reduce Motion；确认菜单栏/Dock实际图标没有新增滑动。

## Task 10: 本地化、全回归、签名隔离与交付

**Files:** `LocalizationKey.swift`、12语言resources；既有build脚本只在必要时改；测试 `LocalizationParityTests.swift`、`SettingsPagesOptimizationContractTests.swift`；验收记录 `output/icon-designer-window/acceptance.md`。

- [ ] 补齐每项新增用户文案（不出现网页 CONCEPT/glyph 工程术语），12语言key parity、placeholder一致；即时切语言更新两个窗口标题与内容。将原设置页入口契约改为独立窗口route，保留原有效controls。
- [ ] 执行全套并保存实际exit status：

```bash
cd '/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio'
swift test
swift build -c release
bash scripts/test-local-dev-build-contract.sh
for path in Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings; do
  plutil -lint "$path" || exit 1
done
bash scripts/build-dev-app.sh release open
```

- [ ] 本地签名脚本选择现有唯一Developer ID；多证书时停并明确选择，不自动降级ad-hoc。重打包必须保留bundle id和designated requirement；不能保证所有系统权限一定沿用。验证production hash未变、Dev版本/代号正确、仅Dev进程被重启。
- [ ] 手动验收矩阵：两个主窗并开各关闭顺序；工具窗打开/关闭不改变主scroll/frame；主窗close无孤儿panel；网络/蓝牙/数字/none；双耳/仅左/仅右/均不可用；真实权限不足；离线保留地址fallback；固定/状态色和大小；键盘/VoiceOver/Reduce Motion；最小窗和大屏；切回live实际menu/Dock不被样例污染。
- [ ] 全分支review只针对本任务增量和与dirty baseline的交互；提交时显式paths，先test/release build。未授权不commit，更不push/merge/tag。用户新会话授权本地commit时可分任务commit，保持无关改动未stage。
- [ ] 如果后来用户要求合并/发布，因本任务触及@MainActor/SwiftUI bindings，必须先另行获授权push并运行下面非发布CI；此处不现在dispatch。失败run必须记录 `docs/swift-ci-compatibility.md`，不能省略：

```bash
# 先根据将来真正的版本/build填写用户批准的显式递增值；
# 不在本地开发阶段猜测或创建release。
gh workflow run release.yml --repo lingyired/status-trio   --ref "$BRANCH" -f version="$VERSION" -f build="$BUILD" -f publish=false
gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
```

## Definition of Done

主设计器为独立大原生窗口；模拟editor为独立工具panel；蓝牙统一入口及适用规则完整；preview与live输入严格隔离；所有现有图标渲染/权限/默认兼容边界保留；focused与全套测试、release build、本地Dev build成功，自动化/手动/硬件验证分开报告。输出分支/提交或未提交状态、App绝对路径、测试log、仍需用户实际AirPods验收的项；不声称已发布或CI工具链已验收。

## 自检与计划解释

本计划与规格逐项对应；网页inline样例区域已明确替换为panel。新输入法/中间音量不是本次开发工作。声明的新类型/接口需在所属任务建立，其余既有类型从当前worktree读，不从主checkout移植。接口代码是要求的contract与首个测试，不是可以跳过实现步骤直接粘贴所有文件的完整补丁。每任务的其余测试以具名行为与fixture条件明确，不用删除回归测试换绿灯。

文档编写阶段未执行上述产品任务、未运行新产品测试、未提交或发布。下一会话先阅读规格与计划；用户要求执行后沿任务顺序实现。