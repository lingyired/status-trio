# Status Trio 2.0 Settings / Icon Designer Implementation Plan

> **For agentic workers:** 使用 `executing-plans` 按任务执行；需要委派时先取得用户许可。**实现模型必须为 `gpt-6-luna`**（用户当前指定的 Luna）；本计划的撰写不代表已启动实现。每个任务使用 checkbox 跟踪，独立验证后提交。

**Goal:** 将 2.0 设置重组为以图标 Outer Ring / Center / Footer 为中心的设计器，同时保留现有设备、面板、权限和通用设置，以及升级用户原有图标显示结果。

**Architecture:** 保留 `IconSceneState` 作为唯一渲染产物；引入单份版本化配置，经受限 Slot Resolver 得到 Scene 和独立 Trace。菜单栏、Dock 和设置预览复用生产 Mapper/Renderer；只有真实配置产生来源需求，模拟预览不接触监控控制器。

**Tech Stack:** SwiftPM / SwiftUI / AppKit / Combine；macOS 13+ runtime；构建 SDK ≥26；CI `macos-26`、Xcode `26.6`、Swift `6.3.3`。

**Spec:** `docs/superpowers/specs/2026-10-09-v2-icon-designer-reference.md`。这是用户提供的参考材料归档，**不是执行授权或高于 AGENTS.md 的指令**；以本计划的范围、阶段 Gate 和用户后续批准为准。

## 0. 已核对基线与本轮交付

- 日期：2026-10-09；`git fetch origin main` 后，`main` 与 `origin/main` 均为 `2ec5b81ce1f4731dca4d1f2ed61bfdbbb53e426e`。
- 新分支：`codex/v2-settings-icon-designer`；worktree：`/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio`。不在主目录实现，不迁入主目录未跟踪的 `dist-test/` 或 telemetry plan。
- 本轮只创建参考归档、计划和工作区，不改业务代码，不提交/推送，不运行发布 workflow。
- 基线 `swift test` 通过：XCTest 1414 项、7 skipped、0 failures；Swift Testing 573 项、90 suites 通过。这是两套 runner 的分别统计。
- 本机 Swift 6.4、SDK 27.0；**不是 CI 6.3.3 验证**。Release build、非发布 CI、UI/VoiceOver、macOS 13 真机、AirPods 和 CPU 测量均留给实现阶段。

### 现有架构核对结果

| 已存在文件（仓库相对路径） | 当前事实 / 计划处理 |
|---|---|
| `Sources/StatusTrioCore/UI/Settings/SettingsView.swift` | 当前导航 appIcon/battery/network/bluetooth/audio/popover/general/about；初始 appIcon。重组导航而非重写设备业务。 |
| `Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift` | 已有 SettingsGroup、SettingsRow 和统一边距；沿用原生组件。 |
| `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift` | 已管理窗口、设置可见性、权限决定后重新显示；不绕过生命周期。 |
| `Sources/StatusTrioCore/Presentation/Icon/IconPresentationConfiguration.swift` | 当前四组 Options + snapshot/audioIcon 输入；多个 Options 不具备 Codable，不能直接序列化。 |
| `Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift` | 电池→ring、网络/蓝牙→center、音量→footer；百分比在 center 的优先级高于蓝牙和网络错误。 |
| `Sources/StatusTrioCore/Presentation/Icon/IconPresentationViewModel.swift` | 现有 Combine 管道、500ms snapshot debounce 和可注入 scheduler；不另建 status pipeline。 |
| `Sources/StatusTrioCore/Presentation/Icon/OuterRingState.swift` | 已有 segments 数组，但没有双环几何布局协议；不能仅传两条 segment 就声称双环完成。 |
| `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` | key 已包含 Scene；会构造去 effect 的 staticScene。新增 Scene 字段须在重建中保留。 |
| `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift` | 已有 batteryLevels、request/releaseBatteryLevels(token)、visible surface claim；activate/deactivate 仍需 owner 审计。 |
| `Sources/StatusTrioCore/Store/SystemStatusStore.swift` | 真实来源及页面可见性由此协调；模拟不得修改该 store。 |

## 1. 设计决定与范围（待用户审阅）

**建议方案：增量 Composition，而不是仅重排旧控件，也不是全面重写 Renderer。** 仅重排无法实现 fallback/trace；全面重写风险扩大且破坏已完成的 Presentation Refactor。

### 2.0 核心交付：Phase 0–4

1. 导航：Icon Designer / Devices / Panel / General / About。原 App Icon 页进入 Designer 的“图标位置与 Dock”组；Devices 保留 Battery / Network / Bluetooth / Audio 子页，只有来源/设备/权限设置，不重复维护图标外观真源。
2. Designer：顶部固定生产预览；预览热点和三段切换器双入口；下方滚动 Source、Source Behavior、Appearance、当前显示原因；Primary/Fallback 均可编辑行为。
3. 配置：每槽一个 Primary + 至多一个 Fallback；只有 Center 支持预定义网络异常覆盖。默认 Classic；旧中心自动语义作为可见的“兼容当前配置”选项，不把隐藏的 picker value 留在非法状态。
4. 核心来源：ring=Mac Battery/None；center=Network/Bluetooth Audio Output/Pinned Bluetooth Glyph/Battery Percentage/Legacy/None；footer=System Volume/None。Connected Bluetooth Device 与 AirPods 来源随 Phase 5 上线，不展示可选但未实现的来源。
5. 预览：Live、Network Healthy、No Internet、Wi-Fi Off + Ethernet、Charging、Critical Battery、Muted；AirPods unavailable 的模拟只在 Phase 5 支持对应来源后开放。

### 独立后续交付：Phase 5

AirPods 电量来源、Connected Bluetooth Device、单环/左右耳双环、owner-aware demand、AirPods Focus。**不作为 Phase 4 UI 验收前置条件**。原参考中 Case 分段策略首版不扩大为第三段；仅 Case 有值不冒充耳机电量。

### 明确不做

任意规则引擎、无限优先级列表、插件/脚本/HTTP 来源、主题商店、自动配置切换、JSON 导入导出 UI、常驻 BLE discovery。保留 Codable 只为持久化与未来扩展。

## 2. Global Constraints

- macOS 13+ API/source 兼容；SDK ≥26；不能删除 `build-app.sh` / `verify-platform-version.sh` 的 SDK Gate。
- 图标选项同步走 SettingsStore→StatusBarController/AppIconController→Scene→MenuBar/Dock/Preview；Dock 专用背景/位置仍独立，菜单栏大小不改变 Dock 分辨率。
- 新配置单份 snapshot、一次事务一次完整发布；不清空旧 defaults；新 schema 未知/损坏时保留原始 Data，不静默覆写。与 telemetry、通知、面板权限无关的值不修改。
- `none` 意味主动留空，不调用 fallback；0%/0音量/Wi-Fi关闭可为有效状态；明确断连和权限拒绝立即回退，临时缺数据最多持有 2 秒，过期释放，不增高频 timer。
- 一切 Swift 提交前 `swift test` + `swift build -c release`；涉及绑定/actor/generics/resources 时合并前 `publish=false` CI；每次 Actions 失败写入 `docs/swift-ci-compatibility.md`。
- 遵守 actor compatibility：不使用 isolated deinit / weak let；actor 方法值用显式 closure；本地化沿用项目资源与 lowercase lproj fallback。
- 12 种已有语言完整覆盖；业务文案不硬编码英文；敏感设备 ID/地址不进入 trace 文案或日志。
- 禁止恢复默认、Classic 或模拟模式悄悄打开蓝牙、Apple Devices、后台电量许可、MobileBattery Helper。

## 3. 接口契约与文件结构

以下是**新接口契约**，不是声称 main 已存在的 API。所有新值类型使用 Codable/Equatable/Sendable（渲染值还需 Hashable）；持久化存 Foundation 值，不存 SwiftUI.Color/NSColor/设备对象。

```swift
enum IconSlot: String, Codable, CaseIterable, Sendable { case outerRing, center, footer }
enum RingSource: String, Codable, Sendable { case systemBattery, airPodsBattery, none }
enum CenterSource: String, Codable, Sendable {
    case automaticLegacy, network, bluetoothAudioOutput, pinnedBluetoothGlyph
    case connectedBluetoothDevice, systemBatteryPercentage, none
}
enum FooterSource: String, Codable, Sendable { case systemVolume, none }
struct SlotSelection<S: Codable & Hashable & Sendable>: Codable, Equatable, Sendable {
    var primary: S
    var fallback: S?
}
enum UnavailabilityReason: String, Codable, Sendable {
    case permissionDenied, disabled, disconnected, unknown, temporarilyStale, expired, unsupported
}
enum SourceResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unavailable(UnavailabilityReason)
}
enum SelectionRole: Equatable, Sendable { case primary, fallback, none }
struct SlotChoice<S: Equatable & Sendable>: Equatable, Sendable {
    let source: S?
    let role: SelectionRole
    let primaryFailure: UnavailabilityReason?
}
// Task 3 定义：显式 none 不继续查询；不在此函数持有历史或执行 IO。
func chooseSource<S: Codable & Hashable & Sendable>(
    _ selection: SlotSelection<S>, none: S,
    availability: (S) -> SourceResult<Bool>
) -> SlotChoice<S>
```

新文件按职责划分，实际任务内详细指定：

- `Presentation/Icon/Configuration/`：Composition、Behavior、Appearance、Versioned Configuration、Validation/Migration。
- `Presentation/Icon/Resolution/`：来源可用性、三 Slot resolver、Trace；历史状态只由独立可测试 hold policy 管理。
- `Presentation/Icon/Preview/`：确定性 Scenario，调用生产 resolver。
- `UI/Settings/IconDesigner/`：页面、选择器、行为/外观编辑、诊断与 preview；不持有设备控制器。
- `App/IconSourceDemandBridge.swift`：仅 Phase 5；统一需求 reconciliation，不做渲染。

### 跨任务接口

| 任务 | 产出契约 |
|---|---|
| 1 | `IconConfigurationV1.classic`；`normalized() -> Self`；`resetting(_ slot: IconSlot) -> Self`；`IconConfigurationCodec.decode(_ data: Data) throws -> IconConfigurationV1`；`encode(_ value: IconConfigurationV1) throws -> Data`。 |
| 2 | `IconConfigurationMigration.makeConfiguration(from legacy: IconPresentationConfiguration) -> IconConfigurationV1`；`configuration.legacyPresentationConfiguration -> IconPresentationConfiguration`；SettingsStore `iconConfiguration`（只读发布）和 `updateIconConfiguration(_ edit: (inout IconConfigurationV1) -> Void)`。 |
| 3 | `chooseSource`；`IconSourceSnapshot.empty`（无额外设备输入）；`IconResolutionInputs(system: IconPresentationInputs, sources: IconSourceSnapshot)`；`IconResolutionOutput(scene: IconSceneState, trace: IconResolutionTrace)`；`IconResolutionTrace` 持有三个槽位的 `SlotResolutionTrace`（sourceID、role、primaryFailure及有限override原因），不参与Scene Hashable；`IconCompositionResolver.resolve(inputs:configuration:) -> IconResolutionOutput`。 |
| 4 | `IconSourceHoldPolicy()`（初始空历史）；`update(_ result: SourceResult<Bool>, at: Date) -> SourceResult<Bool>`；`reset()`；2秒 hold，只保护临时未知/temporarilyStale；其他失败立即结束。 |
| 5 | `IconRGBA(red: Double, green: Double, blue: Double, alpha: Double)`；`.custom(IconRGBA)` 扩展 IconColorRole；单色/按语义配置解析为 Scene 的颜色值。 |
| 6 | `IconPreviewScenario.makeInputs(basedOn: IconResolutionInputs) -> IconResolutionInputs`；场景无捕获控制器；Live直接返回原输入。 |
| 7–9 | `SettingsNavigationModel`（纯值导航及可见来源列表）；`IconDesignerView` 只消费 store/configuration/liveInputs/localization；预览选择状态不持久化。 |
| 11–12 | `IconSourceDemandPolicy.requiresAirPods(_ configuration: IconConfigurationV1) -> Bool`；bridge `reconcile(configuration:)` / `stop()`；`AirPodsRingMapper.resolve(_ snapshot: AirPodsBatteryIconSnapshot, layout: AirPodsRingLayout) -> SourceResult<OuterRingState>`。 |

Behavior 不直接存现有非 Codable Options：定义有限 Codable DTO，逐字段投影成 Options。Battery 的充电指示/阈值、Network 的符号策略、Pinned glyph、Volume 的 dots/arc 各保存一份；槽位交换 primary/fallback 不复制行为。Ring/Footer strokeScale 初始由同一个旧 RingStrokeStyle 迁移，后续可独立编辑。Appearance 取值范围优先沿用已有 normalized helpers（stroke 0.5...2.5）；其他 scale 以现有 Options 构造器范围为准，在 Task 1 写明确边界测试后冻结。

## 4. Review Focus

1. 百分比 center + 蓝牙替换 + 网络错误同时存在：迁移前后 Scene 相同（Task 0/2/3）。
2. 损坏/未来 schema、不合法颜色/非有限 scale：保留原始 Data、提供显式重置，不 crash/静默覆盖（Task 1/2/5）。
3. 无电池 Mac、Wi-Fi关闭、静音、设备断连：0不是缺失，None不fallback，断连不hold（Task 3/4）。
4. 仅 Trace/未选来源变化：生产不重绘；设置预览关闭释放 clock，模拟无真实 demand（Task 4/6/9）。
5. 图标/Popover/Settings共同消费电量及睡眠唤醒：释放一个 owner 不停其他 owner，全部释放后无新任务（Task 11/12）。

## 5. 执行任务

所有代码任务采用同一个明确闭环：**先写下列命名失败测试 → `swift test --filter <Suite>` 确认目标失败 → 最小实现 → suite及全套测试/Release build → scoped commit**。禁止只因缺依赖/测试拼写失败而把它当行为 RED。下列新增文件路径相对本 worktree；不在主 checkout 执行。

### Task 0 — 固化 Classic 的兼容基线（Phase 0）

**Files:** 新增 `Tests/StatusTrioCoreTests/IconLegacyCompatibilityTests.swift` 和 `docs/superpowers/specs/2026-10-09-v2-icon-designer-baseline.md`；复用 `Tests/StatusTrioCoreTests/TestSupport/PresentationFixtures.swift`。

- [ ] 写 `testLegacyPercentagePreemptsBluetoothAndNetworkError`、`testPinnedGlyphSurvivesDisconnectedAudio`、`testEthernetAndWiFiOffMapping`、`testSharedStrokeAffectsRingAndFooter`；照现有 MapperTests 创建 Options/snapshot。
- [ ] 固定旧 Scene 断言而不是把新旧 Mapper 互相比当唯一 oracle；覆盖充电/满电/低电/无电池、dots/arc、hotspot/temporary/shared 网络。
- [ ] 跑 `swift test --filter IconLegacyCompatibilityTests`，此任务是特征测试应直接 GREEN；不为制造 RED 改生产代码。
- [ ] 记录旧监控 owner、battery请求、BLE/scanner和采样配置；Release闲置5分钟 CPU/wakeups留存同设备基线，未测项明确标记“未测”，不猜测零开销。
- [ ] `swift test && swift build -c release`；只 stage 两个新增文件，提交 `test: pin legacy icon composition behavior`。

### Task 1 — 版本化配置、校验和恢复默认（Phase 1）

**Create:** `Sources/StatusTrioCore/Presentation/Icon/Configuration/{IconCompositionConfiguration,IconBehaviorConfiguration,IconAppearanceConfiguration,IconConfigurationV1,IconConfigurationCodec}.swift`；`Tests/StatusTrioCoreTests/IconConfigurationValidationTests.swift`。

- [ ] 写 roundtrip、重复 fallback归一化、未知schema拒绝、损坏Data拒绝、slot reset只改变目标区域、Classic无监控构造测试。
- [ ] 先实现本文件第3节契约；schemaVersion=1；duplicate fallback清nil；primary None归一化为fallback nil；DTO完整映射旧Options字段。
- [ ] `IconConfigurationCodec.decode` 先读schema，再解码；未来版本抛 typed error，不改输入Data；未知枚举按失败处理，不擅自迁移旧defaults。
- [ ] 示例测试（新增契约）：

```swift
func testClassicCodecRoundTrip() throws {
    let data = try IconConfigurationCodec.encode(.classic)
    XCTAssertEqual(try IconConfigurationCodec.decode(data), .classic)
}
func testDuplicateFallbackIsRemoved() {
    var value = IconConfigurationV1.classic
    value.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .systemBattery)
    XCTAssertNil(value.normalized().composition.outerRing.fallback)
}
```

- [ ] `swift test --filter IconConfigurationValidationTests`；全套测试/Release；提交 `feat: add versioned icon configuration`（显式stage上述文件）。

### Task 2 — 迁移和原子 SettingsStore 发布（Phase 1）

**Create:** `Presentation/Icon/Configuration/IconConfigurationMigration.swift`；`Settings/SettingsStore+IconConfiguration.swift`；`Tests/StatusTrioCoreTests/IconConfigurationMigrationTests.swift`。
**Modify:** `Settings/SettingsStore.swift`、`Settings/SettingsStore+IconPresentation.swift`、`Settings/SettingsStore+IconAppearance.swift`、`Tests/StatusTrioCoreTests/IconAppearancePublisherTests.swift`。（Sources前缀均为`Sources/StatusTrioCore/`。）

- [ ] 写首启迁移/第二次不迁移/不删旧key/损坏新Data不覆盖/原子publisher/不变update零发布/旧控件写入新真源测试；使用隔离UserDefaults suite及既有TestUserDefaults工具。
- [ ] 从现有完整Options读取生成新配置，初始化结束前完成迁移。持久key明确为`iconConfigurationV1`。新配置有效时永不由旧keys重新生成。
- [ ] 若新Data损坏或未来schema：保留Data，用内存兼容外观显示错误；直到用户确认重置才允许替换。取消确认不修改任何持久值。
- [ ] 保留过渡旧UI时把控件setter改为新配置adapter；新配置→旧Options只是投影，不持续双写defaults或构造两个独立publisher。
- [ ] 迁移等价测试核心：

```swift
func testStandardMigrationKeepsScene() {
    let input = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(), audioIcon: nil)
    let migrated = IconConfigurationMigration.makeConfiguration(from: .standard)
    XCTAssertEqual(IconPresentationMapper.scene(inputs: input, configuration: .standard),
        IconPresentationMapper.scene(inputs: input, configuration: migrated.legacyPresentationConfiguration))
}
```

- [ ] 扩展Task0所有fixture比较；单变更一次一致发布。跑 migration/publisher suites、全套测试/Release；提交 `feat: migrate icon settings atomically`。

### Task 3 — Slot Resolver、Fallback与有限Override（Phase 2）

**Create:** `Presentation/Icon/Resolution/{IconSourceAvailability,IconSourceSnapshot,IconResolutionTrace,IconCompositionResolver,OuterRingResolver,CenterResolver,FooterResolver}.swift`；`Tests/StatusTrioCoreTests/{IconSlotResolverTests,IconSourceAvailabilityTests,IconResolutionTraceTests}.swift`。
**Modify:** `Presentation/Icon/IconPresentationMapper.swift`、`Presentation/Icon/IconPresentationConfiguration.swift`。

- [ ] 写 primary可用/fallback/双不可用/显式None/0值有效/permission/legacy优先级测试，先 RED。
- [ ] 抽取旧Mapper行为为有限source-switch；没有新来源时Classical路径保持Task0所有输出。`automaticLegacy`直接复用旧center映射，不把网络Override插到它前面。
- [ ] `chooseSource`只查primary，失败再查fallback；None不查fallback。Trace保存source/role/reason，不含私有ID，不参与Scene equality。
- [ ] 示例：

```swift
func testExplicitNoneDoesNotConsultFallback() {
    var queried = false
    let result = chooseSource(SlotSelection<RingSource>(primary: .none, fallback: .systemBattery),
        none: .none) { _ in queried = true; return .available(true) }
    XCTAssertEqual(result.role, .none)
    XCTAssertFalse(queried)
}
```

- [ ] network override只有显式enabled且语义合法的center组合触发；battery percentage/pinned/legacy保留各自规则。短路规则用测试固定。
- [ ] `swift test --filter 'Icon(SlotResolver|SourceAvailability|ResolutionTrace|LegacyCompatibility)Tests'`；全套测试/Release；提交 `feat: resolve icon slots with bounded fallback`。

### Task 4 — 时效、VM接线与重绘去重（Phase 2）

**Create:** `Presentation/Icon/Resolution/IconSourceHoldPolicy.swift`；`Tests/StatusTrioCoreTests/IconSourceHoldPolicyTests.swift`。
**Modify:** `Presentation/Icon/IconPresentationViewModel.swift`、`App/IconPresentationResourceResolver.swift`、`UI/StatusBarController.swift`、`App/AppIconController.swift`；扩充 `IconPresentationViewModelTests.swift`、`IconSurfaceIntegrationTests.swift`。

- [ ] 用假时钟写unknown 0/1/2秒、过期timer、明确断连、权限拒绝、用户切source、stop/start不复用旧设备缓存测试，不用真实sleep等待2秒。
- [ ] hold最多2秒；临时失败只允许一个可取消一次性expiry任务，generation避免旧任务写回；空历史立即unavailable。
- [ ] Example：

```swift
func testDisconnectDoesNotHoldLastSuccess() {
    var policy = IconSourceHoldPolicy()
    let now = Date(timeIntervalSince1970: 0)
    _ = policy.update(.available(true), at: now)
    XCTAssertEqual(policy.update(.unavailable(.disconnected), at: now),
                   .unavailable(.disconnected))
}
```

- [ ] VM产Scene和独立trace；保留现有500ms管道，明确断连不得被hold再次延长；配置改动立即生效。MenuBar/Dock dedup只看自己的实际渲染key。
- [ ] 写trace变化不render、未选来源变化不render、来源切换重置hold、VM停止释放scheduler测试；全套测试/Release；提交 `feat: publish resolved scenes without redundant redraws`。

### Task 5 — 独立外观、自定义颜色及缓存一致性（Phase 3）

**Create:** `Presentation/Icon/Configuration/IconRGBA.swift`、`Presentation/Icon/Resolution/IconPaletteResolver.swift`；`Tests/StatusTrioCoreTests/IconPaletteResolverTests.swift`。
**Modify:** `Presentation/Icon/{IconColorRole,OuterRingState,CenterState,FooterState}.swift`、`UI/Icon/{StatusIconRenderer,DockIconRenderer,DockIconRenderCache,DockIconPreviewCache}.swift`、`Tests/StatusTrioCoreTests/{IconSceneRendererParityTests,DockIconRenderCacheTests,StatusIconRendererTests}.swift`。

- [ ] RED：独立ring/footer宽度、自定义颜色roundtrip、低电量优先、fallback保持appearance、浅深色角色映射、仅trace不变key；颜色必须进入Scene Hashable值。
- [ ] Automatic保留所有旧roles；Single和By-state通过`IconPaletteResolver`生成`.custom(IconRGBA)`；RGBA每分量0...1，非finite使用明确默认，alpha支持但不得让关键告警不可辨认。
- [ ] By-state只列当前source真实semantic role；Battery临界优先充电/低功耗，沿用旧StatusMappings优先级。不造无限状态列表。
- [ ] 用两个只颜色不同的Scene证明Dock/MenuBar raster及key都不同；检查Dock staticScene重建不丢新字段。字体/比例/线宽均不需重启。
- [ ] 全套测试/Release；提交 `feat: support per-slot icon appearance on all surfaces`。

### Task 6 — 生产管道状态模拟（Phase 4）

**Create:** `Presentation/Icon/Preview/IconPreviewScenario.swift`、`Tests/StatusTrioCoreTests/IconPreviewScenarioTests.swift`。
**Modify:** `UI/Settings/StatusIconPreviewCard.swift`、`Tests/StatusTrioCoreTests/IconPreviewSceneTests.swift`。

- [ ] RED：每个scenario固定输出、Live等于原输入、模拟不改store、不claim电量、不改变系统网络/音量；设置预览与生产resolver Scene一致。
- [ ] 构造新StatusSnapshot值及source snapshot，不更新SystemStatusStore；No Internet沿用现有connection表达而非新增reachability请求。
- [ ] 同输入经正式`IconCompositionResolver.resolve`再正式Renderer；可视化fallback/override原因而不是换静态图片。
- [ ] Example（Task3契约需已完成）：

```swift
func testLiveScenarioDoesNotRewriteInput() {
    let input = IconResolutionInputs(system: IconPresentationInputs(
        snapshot: PresentationFixtures.snapshot(), audioIcon: nil), sources: .empty)
    XCTAssertEqual(IconPreviewScenario.live.makeInputs(basedOn: input), input)
}
```

- [ ] `.empty`由Task3定义为无额外设备输入；场景切回Live立即使用最新真实输入。全套测试/Release；提交 `feat: add deterministic production icon previews`。

### Task 7 — 新导航与旧功能可达性（Phase 4）

**Create:** `UI/Settings/SettingsNavigationModel.swift`、`UI/Settings/IconDesigner/IconDesignerView.swift`、`Tests/StatusTrioCoreTests/SettingsNavigationModelTests.swift`。
**Modify:** `UI/Settings/SettingsView.swift`、`UI/Settings/AppIconSectionView.swift`、`UI/Settings/SettingsWindowController.swift`。

- [ ] RED：旧8页面功能都有新路径；默认Designer；Devices四子页可达；App Icon位置/Dock背景不丢；窗口关闭仍调用已有settings visibility清理。
- [ ] 先提取旧sections到明确页面组件，不同时重写网络/蓝牙列表。Drawer/sidebar分组用已有SettingsChrome；保留设备gear正确System Settings route。
- [ ] Designer固定preview区域与滚动编辑区；小窗口布局不压缩preview glyph，支持文本长语言滚动。窗口尺寸延续既有最小限制后测量调整，不无保护引入macOS14+ API。
- [ ] appIcon旧入口映射到Designer位置组；UI选中slot/preview mode仅为session state。
- [ ] navigation及既有SettingsRowHitArea/StatusMenuBuilder suites、全套测试/Release；提交 `feat: reorganize settings around icon design`。

### Task 8 — Source/Behavior/Appearance编辑器与Classic（Phase 4）

**Create:** `UI/Settings/IconDesigner/{IconSlotPicker,IconSourceEditor,IconBehaviorEditor,IconAppearanceEditor,IconPresetPicker}.swift`、`Tests/StatusTrioCoreTests/IconDesignerEditingTests.swift`。
**Modify:** `UI/Settings/IconDesigner/IconDesignerView.swift`、配置validation；移除旧设备页重复图标编辑控件。

- [ ] RED：主备swap保存两来源behavior、编辑fallback不改primary、unsupported来源不入picker、已配置不可用来源仍显示、slot reset不改其余slots/global权限。
- [ ] Sources共用Task3兼容列表；Legacy值显示“兼容当前配置”，用户显式选新source才离开legacy；Phase5未完成时不显示AirPods可选项。
- [ ] 编辑事务使用`store.updateIconConfiguration`，Behavior仅保存一份；Fallback=无可选，重复primary不能提交；Appearance一直可见，Override仅合法center组合可见。
- [ ] Classic只恢复icon configuration；恢复单slot带确认，保留其他slots、Dock背景、权限。Minimal等更多预设不在此任务上线。
- [ ] editing/model tests + source wiring检查 + 实际点击/键盘冒烟；全套测试/Release；提交 `feat: edit icon slots and restore classic configuration`。

### Task 9 — 诊断、本地化、可访问性及预览生命周期（Phase 4）

**Create:** `UI/Settings/IconDesigner/{IconResolutionExplanation,IconDesignerPreview}.swift`、`Tests/StatusTrioCoreTests/{IconDesignerAccessibilityTests,IconDesignerLifecycleTests}.swift`。
**Modify:** `Localization/LocalizationKey.swift`、`Resources/*.lproj/Localizable.strings`、`UI/Settings/StatusIconPreviewCard.swift`、既有guide入口。

- [ ] RED：primary/fallback/override/none + unavailable reason均有key；每种现有语言完整；切页/关窗停止preview clock；Reduce Motion关闭动画；显示trace不印设备地址。
- [ ] 三个slot热点使用Button + full frame/contentShape；必须同时提供Segmented Control；VoiceOver读slot名称、当前source、选中状态。
- [ ] 普通文案“首选来源/备用来源/当前显示原因”，技术词仅说明中；权限错误保留用户选择并给主动授权入口，不自动弹窗。
- [ ] 非AirPods阶段只开放Task6完整scenario。动画用既有ChargingEffectClock可见性机制，关Settings和切出Designer清理。
- [ ] `find Sources/StatusTrioCore/Resources -name Localizable.strings -exec plutil -lint '{}' \;`；自动化只能证明model/key/lifetime，不宣称VoiceOver已验证；全套测试/Release；提交 `feat: explain icon resolution with accessible localized settings`。

### Task 10 — 核心2.0交付Gate（Phase 4完成）

**Modify:** baseline报告；`release-notes/2.0.0/en.md`、`release-notes/2.0.0/zh-Hans.md`（及正式发布需要的其余10种语言）；所有workflow失败记录在`docs/swift-ci-compatibility.md`。

- [ ] 全套测试/Release/资源lint/`git diff --check`/`bash scripts/validate-appcast-notes.sh`。本地package以`scripts/build-app.sh`真实支持参数执行，核对SDK Gate输出。
- [ ] 新配置/旧defaults升级各一次真实启动，MenuBar/Dock/Designer场景及颜色一致，旧列表和pane route不回归。
- [ ] macOS13兼容运行；浅/深色、窄窗口、长文本、键盘/VoiceOver、Reduce Motion人工验收。没有相应设备时明确未测，不把source grep当运行验证。
- [ ] 对比同环境Release闲置5分钟CPU/wakeups、反复开关Designer20次；额外BLE/helper请求为0，没有稳定额外采集/唤醒；波动不设无基线的百分比阈值。
- [ ] 经用户批准推送后运行下文非发布CI，成功才合并；本任务不自动发布2.0或给AirPods未完成能力写发行说明。

### Task 11 — AirPods来源适配及owner-aware demand（Phase 5，核心Gate后）

**Create:** `Presentation/Icon/Resolution/AirPodsBatteryIconSnapshot.swift`、`App/IconSourceDemandBridge.swift`、`Tests/StatusTrioCoreTests/{AirPodsBatterySourceTests,IconDependencyDemandTests}.swift`。
**Modify:** `Store/SystemStatusStore.swift`、`Monitoring/BluetoothDeviceController.swift`、Task3source inputs、App两surface接线。

- [ ] RED：未配置请求0次/重复reconcile一次/切Mac释放/用户后台opt-in关闭不读取/Popover与Icon claim不互杀/重复20次无泄漏/睡眠和唤醒正确恢复。
- [ ] snapshot从既有batteryLevels的main/left/right/case读取；deviceID仅内存或已有合法选设备存储，不按显示名匹配；多副AirPods默认当前蓝牙音频输出匹配的那一副，无法唯一匹配则提示选择，禁止任取第一副。
- [ ] `requiresAirPods`检查primary和fallback：即使当前正在Mac fallback，仍需轻量连接信号以发现AirPods恢复；断连释放详细读取而不是移除所有唤醒事件。
- [ ] bridge固定token `icon.outerRing.airPodsBattery`；复用request/releaseBatteryLevels，若activation为单owner先改owner集合；不得在icon消失时直接deactivate整个Controller。
- [ ] 保持现有后台许可默认；需要后台电量时提供独立明确opt-in，不把popover授权升级为后台。拒绝权限不自动申请，不启动BLE discovery/MobileBattery Helper。
- [ ] 同device缺数据hold2秒；超过来源缓存期限标expired；新鲜度阈值复用现有reader/cache实际策略并写入baseline，不发明永久有效时间。Connected Bluetooth Device同时在resolver中实现，没设备/离线按fallback。
- [ ] 全套Bluetooth lifetime suites、测试/Release、非发布CI；提交 `feat: drive accessory icon sources through shared demand ownership`。

### Task 12 — AirPods单/双环几何、预览与最终Gate（Phase 5）

**Create:** `Presentation/Icon/Behavior/AirPodsRingMapper.swift`、`Tests/StatusTrioCoreTests/AirPodsRingGeometryTests.swift`。
**Modify:** `Presentation/Icon/OuterRingState.swift`、`UI/Icon/{StatusIconGeometry,StatusIconRenderer,DockIconRenderer,DockIconRenderCache}.swift`、Designer行为页、preview scenario、localization。

- [ ] RED：Single/双环不交叉、间隙/文字/线宽安全、0值有效、onlyLeft/onlyRight/both/caseOnly/mainOnly/过期断连、MenuBar/Dock像素一致。
- [ ] Single策略：优先main，否则左右耳均值（仅两个都存在时），只有一个耳就显示已知耳的电量；Case-only unavailable。必须在UI说明综合策略。
- [ ] Dual固定左右两区；L/R均有效时双段；只有一耳时降级single已知耳并显示partial；仅main时single；Case不替代缺失耳、不生成第三段。
- [ ] Scene新增明确布局值，existing Single渲染保持不变；所有新几何/颜色/布局进入Scene Hashable及Dock staticScene复制路径；不用Task名字推断renderer自动支持双环。
- [ ] 上线AirPods Source/场景/AirPods Focus预设；设备断连模拟必须从生产resolver触发Mac fallback。Preview仍不得持有真实demand。
- [ ] 重跑Task10的全套Gate；真实AirPods断连/重连/盖盒、休眠唤醒和多owner验证留给硬件人工测试。提交 `feat: render accessory battery layouts across icon surfaces`，CI成功后再讨论是否并入2.0或后续版本。

## 6. CI、提交与合并操作

代码步骤每次只stage任务文件；所有`git`/`swift`命令从worktree根运行。约定路径前缀缩写只用于上文文件列表，不应把花括号路径原样传给stage。

```bash
cd /Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio
swift test
swift build -c release
git diff --check
```

本计划规模大，使用PR留审查记录；执行方式和推送/合并由用户另行批准。合并之前必须完成独立审查（未授权subagent时先本地自查，不能声称独立审查已完成）。

非发布workflow的版本建议`2.0.0`，build必须由执行时最新已发布CFBundleVersion递增确定，不使用文档日期或旧run number猜测。准备`release-notes/2.0.0`中至少en/zh-Hans，首行含`%VERSION%`与`%BUILD%`，再执行：

```bash
# 在用户批准推送后，并确保 worktree 的 HEAD 已推至同名 remote branch。
git push -u origin codex/v2-settings-icon-designer
export NEXT_VERSION=2.0.0
: "${NEXT_BUILD:?先根据最新已发布 build 设置更大的明确整数}"
gh workflow run release.yml --repo lingyired/status-trio \
  --ref codex/v2-settings-icon-designer \
  -f version="$NEXT_VERSION" -f build="$NEXT_BUILD" -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml \
  --branch codex/v2-settings-icon-designer --event workflow_dispatch --limit 5 \
  --json databaseId,headSha,createdAt,status,conclusion
```

选择`headSha == git rev-parse HEAD`且createdAt对应该次dispatch的run，再执行`gh run watch <实际databaseId> --repo lingyired/status-trio --exit-status`；不要盲拿列表第一项，也不要在不知道run-ID时伪造命令值。检查Tests、SDK/平台校验、DMG及artifact阶段成功；`publish=false`应不创建Release、不改appcast。失败记录run-ID/阶段/root cause/fix/再验证结果；不按flaky重试掩盖编译器问题。Ad-hoc签名，不宣称已notarized。

## 7. 阶段依赖、暂停点与验收记录

```text
Phase0 Task0 → Phase1 Task1→2 → Phase2 Task3→4 → Phase3 Task5
   → Phase4 Task6→7→8→9→10 → 用户审阅核心UI
   → Phase5 Task11→12（独立批准，不阻塞核心UI）
```

每任务预计为4–8小时级别（含测试）；owner生命周期/硬件验证可能超过8小时。不是本轮已花费时间，也不是保证工期；不要把一个任务整块实现完才第一次跑测试。

每阶段完成报告必须填：实际改动文件、具体决定、已运行命令及结果、手动/硬件未测项、是否改变旧行为、下一Gate。出现连续3次修复失败停止并指出可疑假设；不能继续猜测。

### 用户确认清单

- [ ] 同意“Designer / Devices / Panel / General / About”结构及Devices四子页。
- [ ] 同意Phase0–4是2.0核心，AirPods/Connected Device/demand作为后续独立阶段。
- [ ] 同意旧设置迁移保持原有显示优先级，Classic和slot恢复不改变权限。
- [ ] 指定开始执行后由`gpt-6-luna`接手；本轮不实现。
- [ ] 确认可用的macOS13/AirPods人工验收环境与正式2.0 build（开始CI前再确定即可）。
