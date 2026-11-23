# Built-in Icon Plugins and Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有内置图标来源接入统一的插件注册、解析和依赖契约，同时简化图标设计器的编辑流程。

**Architecture:** 内容插件提供描述、呈现、设置能力及依赖，宿主统一处理主/备用与网络异常覆盖，既有 renderer 继续生成菜单栏、Dock 和设计预览。V1 持久化通过集中兼容适配器转换为插件绑定；本轮不引入外部包加载或新的持久化格式。

**Tech Stack:** Swift/SwiftUI/AppKit、SwiftPM、XCTest 与现有 Swift Testing；macOS 13+，构建 SDK 26+；CI macos-26 / Xcode 26.6 / Swift 6.3.3。

**Spec:** `docs/superpowers/specs/2026-10-19-builtin-icon-plugins-and-editor-design.md`（用户已确认）。

## Global Constraints

- 仅在 `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio`、`codex/icon-plugins-editor` 实现；起点 `5e21c1b714bf68087c263cce726e30ad104b3eef`。原 `codex/v2-settings-icon-designer` 和主 checkout 保留不动。
- 不提交、推送、合并、发布或修改 appcast；若以后获准提交，必须先 `swift test`、`swift build -c release`。不自动执行技能中的提交建议。
- macOS 最低 13，构建 SDK 至少 26；CI `macos-26 / Xcode 26.6 / Swift 6.3.3`；本地较新工具链不证明 CI 兼容。
- 保留原生 NSWindow、独立 NSPanel、真实与模拟隔离、既有撤销及网络覆盖语义；插件不读写 SettingsStore，不自行启动设备监控或定时器。
- 中心尺寸 100–180%、外环/底部描边 80–120%、外环文字 90–110%，均以 5% 递增；遵守 `docs/icon-sizing-standard.md` 的旧值投影与显式编辑规则。
- 保留现有颜色语义和 renderer，不增加不可渲染角色；菜单栏与 Dock 使用共同解析状态；不降低 Issue #30 墨迹居中标准。
- 外部安装、脚本/动态二进制、AI 接入、新指标、新显示形态、V2 存储和个人预设库不属于本轮。

## Review Focus

1. 首选 AirPods 离线、Mac 备用可用时，预览说明显示 Mac，右侧明确当前编辑的内容；改备用行为不会误写首选。
2. 首选、备用或两个元素引用同一依赖时监控只申请一次；移除最后一个图标引用也不释放其他 owner 的需求。
3. 输入法/蓝牙/电量/无作为中心，网络覆盖开启与关闭时，异常及恢复都保持既有优先规则。
4. 旧配置缺尺寸标记、含旧静态图案或不可选来源时，打开/切换/折叠不写 defaults，撤销恢复原始 payload。
5. 快速切换内容、移除备用或切换元素后，编辑目标和颜色角色同步有效；模拟值、折叠状态和窗口操作不进历史。

## File Structure and Contract Ownership

`Sources/StatusTrioCore/Presentation/Icon/Plugins/` 放纯模型与运行时模块：

- `IconContentPlugin.swift`：描述、绑定、呈现能力、解析上下文、类型明确的 payload 和插件协议。
- `IconContentPluginRegistry.swift`：唯一注册目录、重复注册验证、按位置过滤、查找和分发。
- `IconContentLegacyAdapter.swift`：V1 枚举 ↔ 插件绑定；本轮唯一兼容映射。
- `IconContentDependencies.swift`：样例与监控需求、配置级去重聚合。
- `IconPluginSlotResolver.swift`：首选/备用选择、单次解析及 trace。
- `Builtin/` 下分别放 `SystemBatteryIconPlugin.swift`、`AirPodsBatteryIconPlugin.swift`、`NetworkIconPlugin.swift`、`InputSourceIconPlugin.swift`、`BluetoothDeviceIconPlugin.swift`、`SystemVolumeIconPlugin.swift`、`LegacyIconPlugin.swift`、`BuiltinIconPlugins.swift`。

UI 专有文件放现有 `UI/Settings/IconDesigner/`：`IconDesignerInspectorModel.swift`（有效编辑目标与摘要）、`IconDesignerSourcePicker.swift`（内容选择）、`IconDesignerFallbackSection.swift`（备用编辑）、`IconDesignerCurrentDisplay.swift`（一份状态说明）。既有设备、行为、颜色控件按职责复用，不复制为第二套表单。

后续任务引用的接口在下面各任务定义。实现若发现与现有类型冲突，先在本计划统一改名，再修改调用方，不能并存两份职责相同的注册器。

## Task 1: 注册契约和 V1 兼容适配

**Files:** 创建 `IconContentPlugin.swift`、`IconContentPluginRegistry.swift`、`IconContentLegacyAdapter.swift`；新增 `Tests/StatusTrioCoreTests/IconContentPluginRegistryTests.swift`、`IconContentLegacyAdapterTests.swift`、`TestSupport/TestIconContentPlugin.swift`。

**Interfaces — produces:**

```swift
struct IconContentBinding: Equatable, Hashable, Sendable {
    let pluginID: String
    let presentationID: String
}

struct IconContentPresentation: Equatable, Sendable {
    let id: String
    let slot: IconSlot
    let title: LocalizationKey
    let isSelectable: Bool
}

struct IconContentPluginDescriptor: Equatable, Sendable {
    let id: String
    let presentations: [IconContentPresentation]
}

enum IconContentPayload: Equatable, Sendable {
    case outerRing(OuterRingState?)
    case center(CenterState?)
    case footer(FooterState?)
}

struct IconContentContext: Sendable {
    let inputs: IconResolutionInputs
    let configuration: IconConfigurationV1
    let legacy: IconPresentationConfiguration
    let now: Date
}

protocol IconContentPlugin: Sendable {
    var descriptor: IconContentPluginDescriptor { get }
    func resolve(presentationID: String, context: IconContentContext)
        -> SourceResult<IconContentPayload>
}
```

`IconContentPluginRegistry.init(plugins: [any IconContentPlugin]) throws` 检查重复插件 ID、同插件重复呈现 ID、空 ID；`presentations(for: IconSlot)` 返回按显式注册顺序排列的可选 `(binding, presentation)`，内部可用具名 `IconContentOption` 包装。`resolve(_:for:context:)` 查找插件、验证呈现位置及返回 payload 的位置。错误查找/位置返回 `.unavailable(.unavailable)`，不改配置。

兼容接口：`IconContentLegacyAdapter.binding(for: RingSource/CenterSource/FooterSource) -> IconContentBinding?`（三个重载）；`ringSource(for:)`、`centerSource(for:)`、`footerSource(for:)` 返回相应可选枚举；`sourceID(for:) -> String?` 生成原 trace 的来源 rawValue。none 为 nil；legacy 映射到不可选插件呈现。

映射必须穷尽：

| Plugin ID | Presentation ID → V1 来源 |
| --- | --- |
| `builtin.system-battery` | `ring` → systemBattery；`percentage` → systemBatteryPercentage |
| `builtin.airpods-battery` | `ring` → airPodsBattery |
| `builtin.network` | `center` → network |
| `builtin.input-source` | `center` → inputSource |
| `builtin.bluetooth-device` | `output` → bluetoothAudioOutput；`connected` → connectedBluetoothDevice；`pinned-glyph` → pinnedBluetoothGlyph（不可选） |
| `builtin.system-volume` | `footer` → systemVolume |
| `builtin.legacy` | `ring` → RingSource.automaticLegacy；`center` → CenterSource.automaticLegacy（均不可选） |

- [x] **Step 1 — 测试先行：** 建立下面的测试插件；枚举所有 V1 cases 检查双向映射，明确 none 为 nil、legacy 不可选。创建重复插件/呈现的注册测试并断言抛错；两个插件有同名 presentation 合法。

```swift
struct TestIconContentPlugin: IconContentPlugin {
    let descriptor: IconContentPluginDescriptor
    let result: SourceResult<IconContentPayload>

    func resolve(presentationID: String, context: IconContentContext)
        -> SourceResult<IconContentPayload> { result }
}

func testBatteryRingBindingRoundTrips() {
    let binding = IconContentLegacyAdapter.binding(for: RingSource.systemBattery)
    XCTAssertEqual(binding, IconContentBinding(
        pluginID: "builtin.system-battery", presentationID: "ring"))
    XCTAssertEqual(binding.flatMap { IconContentLegacyAdapter.ringSource(for: $0) }, .systemBattery)
    XCTAssertNil(IconContentLegacyAdapter.binding(for: RingSource.none))
}
```

- [x] **Step 2 — RED：** `swift test --filter 'IconContentPluginRegistryTests|IconContentLegacyAdapterTests'`，记录缺类型/行为的实际失败。
- [x] **Step 3 — 实现：** 按上述接口完成普通 Swift value types、验证和集中映射；不依赖 SwiftUI 或全局设置。registry 使用只读存储；协议值保持 Sendable。为 payload 添加位置投影，不使用 Any 强转。
- [x] **Step 4 — GREEN：** 重跑上述 focused tests；编码前后分别 `JSONEncoder().encode(configuration)` 检查适配器纯读取不改 V1 对象。对未知 ID、空 ID、错误位置验证返回不可用或注册错误，不能降级成成功值。

## Task 2: 内置模块与真实解析链路

**Files:** 创建 `Builtin/` 全部文件和 `IconPluginSlotResolver.swift`；修改 `Resolution/IconCompositionResolver.swift`、`OuterRingResolver.swift`、`CenterResolver.swift`、`FooterResolver.swift`；新增 `Tests/StatusTrioCoreTests/IconContentPluginResolutionTests.swift`，扩展 `IconSlotResolverTests.swift`、`IconResolutionTraceTests.swift`。

**Interfaces — consumes:** Task 1 全部契约。**Produces:** `BuiltinIconPlugins.makeRegistry() -> IconContentPluginRegistry`（返回一次构造后缓存的只读内置 registry，不能每帧重新建表）；`IconCompositionResolver.resolve(inputs:configuration:now:registry:)` 增加末尾默认内置 registry 参数，现有调用保持源码兼容；`IconPluginSlotResolver.resolve(primary:fallback:slot:context:registry:) -> IconPluginSlotOutput`，输出包含 `payload: IconContentPayload?`、`binding: IconContentBinding?`、`trace: SlotResolutionTrace`。

- [x] **Step 1 — 测试先行：** 在现有样例构造器上建立新解析测试。注入同 ID 的测试插件替换 battery 模块，断言真正的组合结果采用该模块的不可用结果并回退，证明实际渲染经过 registry。

```swift
func testInjectedBatteryFailureChangesRealComposition() throws {
    let configuration = IconDesignerDefaults.configuration()
    let inputs = IconPreviewInputBuilder.simulated(
        samples: IconPreviewSampleValues(), configuration: configuration,
        target: .currentAudioOutput, now: Date(timeIntervalSince1970: 1_000))
    let fake = TestIconContentPlugin(
        descriptor: .init(id: "builtin.system-battery", presentations: [
            .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceSystemBattery,
                  isSelectable: true)
        ]), result: .unavailable(.permissionDenied))
    let registry = try IconContentPluginRegistry(plugins: [fake])
    let output = IconCompositionResolver.resolve(
        inputs: inputs, configuration: configuration,
        now: Date(timeIntervalSince1970: 1_000), registry: registry)
    XCTAssertNil(output.scene.outerRing)
    XCTAssertEqual(output.trace.outerRing.primaryFailure, .permissionDenied)
}
```

另以不同的 `test.custom` ID 调用通用 slot resolver，验证非 V1 模块确实可分发；不将它放入生产目录或声明可持久化。写 `primary=nil/fallback!=nil` 的测试，必须保持隐藏，不能反向显示备用。

- [x] **Step 2 — RED 与基准：** 运行 `swift test --filter 'IconContentPluginResolutionTests|IconSlotResolverTests|IconResolutionTraceTests'`。提取现有 resolver 的主/备用样例，在接线前保存预期 scene 和 trace 的断言，涵盖所有内置呈现、旧 legacy、蓝牙图案/音频颜色、网络覆盖和无内容。
- [x] **Step 3 — 提取模块：** battery/volume/legacy 调用既有纯 mapper；AirPods 保留 freshness、holding、双耳/单耳和 top symbol；network 保留显式网络不被蓝牙替换；input-source 保留 icon/label/keyboard 次序；Bluetooth 保留目标能力和符号覆盖。把原 switch 的状态生成逻辑移入对应模块，现有 resolver 只做兼容入口和 slot 投影，不能出现调用环。
- [x] **Step 4 — 接线：** 通用 slot resolver 每个候选只解析一次，缓存这次结果后选择 primary/fallback，保留 primaryFailure 与原 raw source ID。全局网络覆盖在 composition 层先处理，并通过 network 插件生成内容；palette 应用一次。center 的 palette source 通过已解析绑定反向映射取得，不用配置首选来源冒充实际来源。
- [x] **Step 5 — GREEN 与回归：** 重跑 focused tests，再执行 `swift test --filter 'IconSceneRendererParityTests|InputSourceIconPresentationTests|IconDesignerCenterColorRoleModelTests|Issue30WiFiAlignmentTests'`。旧样例 scene/trace 必须相等；可见像素无意图变化，不重录 fingerprints 来掩盖差异。

## Task 3: 共享依赖与编辑能力目录

**Files:** 创建 `IconContentDependencies.swift`；修改插件协议及内置模块、`UI/Settings/IconDesigner/IconDesignerEditingModel.swift`、`IconDesignerSourceSelection.swift`、`IconDesignerPreviewSession.swift`、`IconPreviewDataView.swift`、`App/IconSourceDemandBridge.swift`；新增 `Tests/StatusTrioCoreTests/IconContentDependencyTests.swift`，扩展 `IconDependencyDemandTests.swift`、`IconDesignerPreviewSessionTests.swift`、`IconDesignerBehaviorCapabilityTests.swift`。

**Interfaces — produces:**

```swift
struct IconContentDependencyContext: Sendable {
    let configuration: IconConfigurationV1
    let targetIsAudio: Bool
}

struct IconContentDependencies: Equatable, Sendable {
    var samples: Set<IconPreviewSampleSource> = []
    var requiresBluetoothMonitor = false
    var requiresAirPodsBattery = false
}
```

插件新增 `dependencies(presentationID:context:) -> IconContentDependencies` 与 `capabilities(presentationID:context:) -> Set<IconDesignerBehaviorCapability>`。把既有 `IconDesignerBehaviorCapability` 枚举原样移至纯插件契约文件，不复制类型。Task 1 的测试插件通过协议默认实现返回空集合，内置插件必须显式实现实际能力。新增配置聚合 `IconContentDependencyResolver.dependencies(configuration:targetIsAudio:registry:)`。

- [x] **Step 1 — 测试先行：** 验证以下关键依赖：Mac ring+percentage 只有 `.macBattery` 一份；AirPods 仅备用也需要蓝牙；Bluetooth 音量配色仅音频目标增加 `.systemVolume`；网络覆盖即使 center=none 也增加 `.network`。明确 shared samples 不因切元素丢失。

```swift
func testSameBatterySourceHasOneSampleDependency() {
    var configuration = IconDesignerDefaults.configuration()
    configuration.composition.center = SlotSelection(primary: .systemBatteryPercentage)
    configuration.composition.footer = SlotSelection(primary: .none)
    let dependencies = IconContentDependencyResolver.dependencies(
        configuration: configuration, targetIsAudio: false,
        registry: BuiltinIconPlugins.makeRegistry())
    XCTAssertEqual(dependencies.samples, [.macBattery])
    XCTAssertFalse(dependencies.requiresBluetoothMonitor)
}
```

- [x] **Step 2 — RED：** `swift test --filter 'IconContentDependencyTests|IconDependencyDemandTests|IconDesignerPreviewSessionTests|IconDesignerBehaviorCapabilityTests'`。
- [x] **Step 3 — 实现依赖表：** battery→macBattery；AirPods→airPods+Bluetooth monitor+battery flag；network→network；input→inputSource；Bluetooth→bluetoothTarget，connected 维持 monitor；volume→systemVolume；legacy 保持现有需求，不隐式增加权限或后台读取。Bluetooth 依据 targetIsAudio 和 usesVolumeColor 加音量样例。网络覆盖依赖在宿主合并。
- [x] **Step 4 — 接线：** `usedSources`、来源菜单及 behavior capabilities 从注册目录读取；UI 蓝牙别名合并规则保留单一入口。监控仍由现有 bridge owner token 申请/释放，用户 opt-in 与连接条件继续在宿主检查；不把请求放进插件。模拟数据行按插件已声明样例和现有 source editor 显示，同来源只一行。
- [x] **Step 5 — GREEN：** 重跑 focused tests；扩展原 demand tests 检查两次 reconcile 不重复申请、移除最后一个引用才释放、其他 owner 持有时不停止监控、用户 opt-out 时不读取电量。sample values 必须能在移除/恢复来源后保留。

## Task 4: 清晰的编辑对象、折叠备用与唯一显示说明

**Files:** 创建 `UI/Settings/IconDesigner/IconDesignerInspectorModel.swift`、`IconDesignerSourcePicker.swift`、`IconDesignerFallbackSection.swift`、`IconDesignerCurrentDisplay.swift`；修改 `IconDesignerView.swift`、`IconSourceEditor.swift`、`IconBehaviorEditor.swift`、`IconSlotPicker.swift`、`IconResolutionExplanation.swift`、`IconDesignerPreviewSession.swift`、`UI/Settings/StatusIconPreviewCard.swift`、`Localization/LocalizationKey.swift`、`Resources/*.lproj/Localizable.strings`；新增 `Tests/StatusTrioCoreTests/IconDesignerInspectorModelTests.swift`，更新相关编辑/布局/辅助功能/本地化测试。

**Interfaces — produces:** `IconDesignerInspectorModel.effectiveTarget(_:slot:configuration:) -> IconDesignerBehaviorTarget` 和 `hasEditableBehavior(slot:target:configuration:targetIsAudio:registry:) -> Bool`；`IconDesignerPreviewSession.expandedFallbackSlots: Set<IconSlot>` 为仅会话 UI 状态。右侧专用控件显式接收有效 behavior target，不能继续在来源卡和行为卡各保存一份相互独立的 target。

- [x] **Step 1 — 测试先行：** 写备用删除后同步回到 primary 的模型测试，以及切元素后会话展开状态独立保留。沿用当前存储测试设施，断言纯 UI 操作不改图标配置和 undo count。

```swift
func testRemovedFallbackCannotRemainEditingTarget() {
    var configuration = IconDesignerDefaults.configuration()
    configuration.composition.outerRing = SlotSelection(
        primary: .airPodsBattery, fallback: .systemBattery)
    XCTAssertEqual(IconDesignerInspectorModel.effectiveTarget(
        .fallback, slot: .outerRing, configuration: configuration), .fallback)
    configuration.composition.outerRing.fallback = nil
    XCTAssertEqual(IconDesignerInspectorModel.effectiveTarget(
        .fallback, slot: .outerRing, configuration: configuration), .primary)
}
```

- [x] **Step 2 — RED：** `swift test --filter 'IconDesignerInspectorModelTests|IconDesignerEditingTests|IconDesignerEditHistoryTests|IconDesignerAccessibilityTests|IconDesignerLayoutTests'`。
- [x] **Step 3 — 重排结构：** 在右侧滚动区之外固定元素选择/标题；滚动内容依次为首选内容及专用设置、共享外观、折叠备用、中心提醒与切换。备用展开时包含其来源/目标和专用行为；删除/交换仍通过 editorModel 事务，配置变更后同步计算 effectiveTarget。无行为时隐藏空卡，none 时隐藏无效控件。必要权限/未绑定提示留在对应内容区域。
- [x] **Step 4 — 状态与文案：** 左侧所有预览只渲染一份选中元素 trace 说明。新增 view 使用 resolved source 而非 primary 名称；显示当前来源和 resolver 已提供的数值，数值不可得则省略。右侧展示“编辑备用内容：{来源}”。不要借此读取设备、触发权限或使用模拟字段冒充实时数值。实时/模拟切换入口仍在现有 NSPanel，主窗口不新加模式开关。
- [x] **Step 5 — 本地化与操作：** 为编辑元素、内容/备用摘要、具体恢复名称、当前显示/编辑文本增加 12 语言键值，沿用现有术语。选择器用原生轻量菜单/列表并显示用途提示；不增加商店/搜索步骤。保留 Cmd+Z、既有恢复确认、原生 focus/VoiceOver、减少动态效果及所有尺寸范围。
- [x] **Step 6 — GREEN 与界面证据：** 重跑 focused tests 和 `swift test --filter 'LocalizationParityTests|IconDesignerCenterColorRoleModelTests|IconDesignerReviewRegressionTests|IconDesignerLifecycleTests'`。更新测试中已被批准改动取代的旧布局约束，保留未变的模拟隔离与几何约束；不为每一行文案添加实现镜像测试。真实界面手动检查 AirPods 回退编辑、备用设备/行为、折叠、窄窗口、长文本、快速切换和撤销。

## Task 5: 整体回归、文档与交付

**Files:** 按需更新 `Tests/StatusTrioCoreTests/IconSceneRendererParityTests.swift`、`IconDesignerReviewRegressionTests.swift`、`Issue30WiFiAlignmentTests.swift`，新增 `docs/icon-content-plugins.md` 和本地验收记录 `output/icon-plugins-editor/acceptance.md`；仅当实际远程 CI 失败时更新 `docs/swift-ci-compatibility.md`。

**Interfaces — consumes:** Task 1–4 全部已接通接口；不增加新的扩展协议。

- [x] **Step 1 — 整体验证：** 覆盖所有 primary/fallback 组合的实际 scene、trace、尺寸与颜色，特别是网络覆盖→恢复，AirPods 单耳/双耳/离线，音频→非音频目标，以及旧静态符号。通过 Task 2 的注入插件测试证明正式解析并未绕开注册器。
- [x] **Step 2 — 运行必需检查：**

```bash
swift test
swift build -c release
swift test --filter Issue30WiFiAlignmentTests
git diff --check
```

只在新改动、失败或证据缺口出现时重跑已经通过的完整检查。结果记录测试计数、退出码和本地工具链，不写成 CI 通过。

- [x] **Step 3 — 本地 Dev 构建与 GUI：** 先核对 `scripts/build-dev-app.sh` 支持的参数，再使用现有 `bash scripts/build-dev-app.sh release open` 构建并打开本 worktree 的 `com.lingsmbp.StatusTrio.Dev`。记录运行进程的真实可执行路径，不能覆盖正式应用。通过 UI 验证主窗口/NSPanel、实时与模拟、备用编辑、单份说明、撤销、菜单栏与 Dock；实际硬件读数和系统权限未测时明确列出。
- [x] **Step 4 — 接入文档：** `docs/icon-content-plugins.md` 说明注册模块、声明呈现/依赖/编辑能力、接入 V1 适配及如何编写 fake plugin 测试。明确编译内置边界、外部安装前需要新持久化设计，附内置插件与呈现 ID 表。验收记录标明已跑/未跑项目，勿写待补数字或未经执行的通过结论。
- [x] **Step 5 — 授权边界：** 当前只交付本地未提交代码/文档。涉及 actor、SwiftUI bindings 或 generics，因此未来合并/发布前必须跑 release.yml 的 publish=false 预检。需远程分支时先取得 push 授权；不为满足 CI 规则自动推送。每次实际失败的 GitHub Actions run 必须记录 run ID、阶段、根因、修复与验证结果。

## Execution and Review

任务 1–4 依赖同一套接口，推荐 Native：在本会话顺序实现，每个任务运行相应 RED/GREEN 和回归，最后进行一次独立整体审查。用户也可选逐任务子代理实现和审查；在用户选定前不创建工作代理、不开始产品实现。

用户需要先评审本计划并选择执行方式。实现者读本计划及规格；实现前确认当前分支、保留规格/计划文档，再从 Task 1 的测试开始。文档阶段的 baseline 记录在 `/tmp/status-trio-icon-plugins-editor-baseline-20261019.log`，实际通过与否以进程退出码及日志结尾为准。

2026-10-19 基线实测：`swift test` 退出码 0；XCTest 1947 项、7 项跳过、0 失败，Swift Testing 664 项、102 suites、0 失败。本轮只有规格与计划文档改动；这个结果用于实施前基线，不证明尚未实施的插件重构通过。

2026-10-19 执行完成：任务 1–5 已实施，最终独立审查的 3 项 Important 均修正。最终完整测试 1947 XCTest（7 跳过）及 685 Swift Testing 通过，Release、Issue30 7 项和 Dev 打包通过。GUI 已验证备用编辑、撤销、单份说明、警告外观入口和实时／模拟切换，测试配置已与快照核对还原。网络异常→恢复的 GUI 选值因弹出菜单工具操作未生效而保留未验收；逻辑测试通过。硬件与远程 CI 边界见 `output/icon-plugins-editor/acceptance.md`。未提交、推送、合并或发布。
