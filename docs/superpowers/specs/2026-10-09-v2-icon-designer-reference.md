# Status Trio 2.0 — Icon Designer / Composition System

> **Codex 可执行开发计划（基于已合并的 `main`）**
>
> 仓库：<https://github.com/lingyired/status-trio>
>
> 规划基线：`main`，核对提交 `2ec5b81ce1f4731dca4d1f2ed61bfdbbb53e426e`（2026-10-09 检查）。**实际执行前先 `git fetch`、检查当前 HEAD，并根据当前文件调整路径。不要重置或覆盖用户未提交的改动。**
>
> 目标平台：`Package.swift` 当前为 `platforms: [.macOS(.v13)]`，新实现必须保持 macOS 13+ 的源码/API 兼容性，避免无保护地引入 macOS 14/15/26 才有的 SwiftUI/AppKit API。
>
> 计划定位：在既有 `IconSceneState` / Presentation ViewModel / Renderer 基础上增量演进，不推翻已完成的 Presentation Refactor；**既要交付新的 UI-first 设置体验，又要严格控制监控生命周期和 CPU 占用。**

---

## 0. 给 Codex 的执行指令（务必先读）

**请将本文视为实施合同，而非一次性代码生成提示。**

1. 先审查 `main` 当前实现及已有测试，完成 Phase 0 的基线报告；不能凭本文片段盲目替换代码。
2. 在独立功能分支工作，例如 `codex/icon-designer-composition`；不改动不相关的 telemetry、网络、蓝牙业务功能或其他人的改动。
3. **按 Phase 0 → 1 → 2 → 3 → 4 → 5 顺序实施**，每个阶段需单独可编译、可测试、可回滚，建议按阶段提交；不要在同一次提交中同时完成模型迁移、页面重排、BLE 监听与分段 Renderer。
4. 对本文所列模型和文件名，可因现有项目结构进行合理调整，但必须保持职责分界、行为兼容、验证标准，并在阶段总结中解释差异。
5. **禁止引入通用规则引擎、无限优先级列表、通用 JavaScript/插件执行器、常驻 BLE 扫描或额外的一整套蓝牙设备轮询。**
6. 优先复用当前 `SystemStatusStore`、`BluetoothDeviceController`、`IconPresentationViewModel`、`StatusIconRenderer`、`StatusIconPreviewCard` 和现有缓存；不要并行发明第二套 status 管道。
7. 功能开关、蓝牙权限与设备选择应遵守已有隐私/授权设置。用户不选择新来源时，启动行为、权限弹窗、后台监听、外观必须与基线一致。
8. 对每阶段报告：具体文件、关键决定、已运行测试及结果、未解决风险、与既有行为的差异；编译/测试失败不要声称通过。
9. 当前已有其他重构/兼容性工作，保留 macOS 13 支持、现有多语言结构和现有菜单栏/Dock 同步机制。

### 完成定义

- 用户能够从 **Outer Ring / Center / Footer** 角度配置图标内容和样式，而非必须先理解电池/网络/蓝牙功能菜单。
- 每个槽位至多 **Primary + 一个 Fallback**；Center 可配置有限且预定义的网络异常条件覆盖（Override）。
- 来源特有选项和槽位外观选项分离；支持自定义颜色、独立线宽/缩放、充电指示与动画等既有能力。
- 新版本迁移既有设置后，用户此前的显示结果与优先逻辑不改变；**手动固定设备图标**语义保留。
- 提供真正通过生产 Mapper + Renderer 的**状态模拟预览**，解释当前显示来源、不可用原因和覆盖规则。
- 无新来源配置时无额外蓝牙探测/电量读取/轮询；使用 AirPods 电量时只激活必要的既有读取能力并在解除需求后清理。
- Scene、菜单栏、Dock、设置预览保持一致，渲染缓存正确纳入新样式输入。

---

## 1. 当前 `main` 代码基线与改造边界

先检查以下文件，而不是另起炉灶：

| 现有文件 | 已有职责 | 修改目标 |
|---|---|---|
| `Sources/StatusTrioCore/Presentation/Icon/IconSceneState.swift` | `outerRing` / `center` / `footer` 最终状态 | **保留作为唯一渲染产物**；仅在需要新视觉形式时小幅扩展 |
| `.../Presentation/Icon/OuterRingState.swift`、`CenterState.swift`、`FooterState.swift` | 图标各区域渲染状态 | 保留，新增必要的多段圆弧数据表达时不得破坏单段 |
| `.../Presentation/Icon/IconPresentationConfiguration.swift` | 当前包含 battery/connection/volume/bluetooth 四组 Options | 新增/迁移成 Composition、Source-Slot Behavior、Appearance；兼容旧调用 |
| `.../Presentation/Icon/IconPresentationMapper.swift` | **当前写死** battery → ring、connection/Bluetooth → center、volume → footer | 薄入口 + 三个 Slot Resolver；复用既有状态映射 |
| `.../Presentation/Icon/IconPresentationViewModel.swift` | Combine 管道、Scene 发布与节流 | 尽量不改调度；只注入新增配置与经过筛选的输入 |
| `.../App/IconPresentationResourceResolver.swift` | 音频图标资源解析 | 复用符号/图片解析，避免每次绘制进行昂贵设备解析 |
| `.../Models/StatusSnapshot.swift` | Mac 电池 / Wi-Fi / 网络 / 音量 | **不要直接追加所有 Bluetooth 状态**；额外采用窄范围的 IconSourceSnapshot |
| `.../Models/StatusIconAppearance.swift` | 菜单栏/Dock 共用的当前图标设置 | 确保新设置由同一发布链传播到两者 |
| `.../Settings/SettingsStore+IconAppearance.swift`、`SettingsStore+IconPresentation.swift` | 图标选项 Publisher | 接入单一、无中间不一致状态的配置发布；避免 `@Published` willSet 顺序问题 |
| `.../UI/Settings/SettingsView.swift` | 现有 Battery / Network / Bluetooth / Audio 导航 | 重组为图标编辑、状态面板、常规、关于；先保留旧业务配置入口直到迁移完成 |
| `.../UI/Settings/StatusIconPreviewCard.swift` | 真正使用图标 Renderer 的预览 | 增加可选模拟输入、区域选择和来源诊断；不要另画近似图 |
| `.../UI/Icon/StatusIconRenderer.swift` | Scene 渲染器 | 加颜色策略；后期支持双分段圆弧；当前 `supports` 要求 ring 恰好一个 segment |
| `.../UI/Icon/StatusBarRenderCache.swift`、`DockIconRenderCache.swift` | Scene 与样式渲染缓存 | 纳入影响 raster 的有效 Palette/Appearance；充电动画时继续避免无意义重绘 |
| `.../Monitoring/BluetoothDeviceController.swift` | `batteryLevels`、可见面板及 claim 管理 | 优先复用 `requestBatteryLevels` / `releaseBatteryLevels`；小幅扩充 icon 需求管理 |
| `.../Monitoring/BluetoothBatteryReader.swift` | `BluetoothBatteryLevel(main/left/right/caseLevel)` | 优先用现有电量渠道数据；不要将 0% 当 unavailable |
| `.../Store/SystemStatusStore.swift` | 核心监控、Popover 可见性、设备 controller | 添加轻量 icon source bridge；不要破坏现有隐藏态低频 watchdog / popover gating |
| `.../Monitoring/MobileBatteryController.swift` | iPhone/iPad/Watch 等可信移动设备采集 | 不要误认为它是 AirPods 电量的必需入口；新版本不启用重型移动电量流程 |

其他已知注意点：

- 当前 `StatusSnapshot` **不含 AirPods 电量**，即使 `BluetoothBatteryLevel` 已包含 L/R/Case。
- 当前中心槽位含“电池百分比取代网络”的高优先级行为，且其优先级高于蓝牙与网络异常；迁移必须保留。
- 当前 `BluetoothAudioIconOptions.networkIconSymbolOverride != nil` 时，手动指定设备**只是固定图标符号**，无须当前输出为蓝牙、无须设备连接；不可误迁移为“连接时才显示”。
- `StatusMappings.shouldReplaceNetworkIcon` 的网络异常定义包含 `notAssociated/noInternet/off/unavailable`，并尊重 wired/offline 判断；迁移后先完全等价，不能擅自把弱 RSSI 当做抢占条件。
- 旧 `ringStrokeStyle` 同时影响 Outer Ring 和 Footer，迁移时**同值初始化两个独立槽位**。
- 旧 Mac Battery 在 `isPresent=false` 的占位行为是现有兼容测试的一部分，**Classic/Legacy 模式必须原样复现**；只有用户明确开启新 fallback 策略时才采用严格 availability 语义。
- 当前 `Package.swift` 最低为 macOS 13；任何 SwiftUI 新 API 必须检查 availability。

### Phase 0：记录基线（无功能变化）

- [ ] 记录 `git rev-parse HEAD`、构建系统/测试命令、所有当前图标配置的默认值。
- [ ] 对照现有测试确定 Classic 外观、状态优先级、蓝牙固定图标、充电动画、深浅色、菜单栏/Dock 的实际行为。
- [ ] 为三个槽位收集“当前场景 → 当前 Scene”的基准快照（不用像素快照也可以先做 Scene equality）。
- [ ] 复用 `IconPresentationMapperTests.swift`、`IconSceneRendererParityTests.swift`、`IconSurfaceIntegrationTests.swift`、`IconAppearancePublisherTests.swift`、`BluetoothPollingLifetimeTests.swift` 等现有测试；确认实际文件名和断言。
- [ ] 记录闲置时采样策略、BluetoothDeviceController 是否激活、各后台任务数量；新增可测试计数器或 debug signpost（不得常驻高频日志）。
- [ ] 不改变任何默认权限、通知或 telemetry 配置。

**验收**：产生简短基线说明、提交前测试结果；无业务改动。

---

## 2. 设计约束：配置、数据、渲染分开

### 2.1 一个槽位只有一个主来源和一个备用来源

**不要**使用 `[Source]` 无限列表、全局数字 priority 或可组合规则 DSL。

建议领域模型（示意，Codex 需要按实际 Codable/Sendable 类型补全）：

```swift
struct SlotSelection<Source: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var primary: Source
    var fallback: Source?        // 最多一个；nil = 没有备用
}

struct IconCompositionConfiguration: Codable, Equatable, Sendable {
    var outerRing: SlotSelection<RingSource>
    var center: SlotSelection<CenterSource>
    var footer: SlotSelection<FooterSource>
    var centerOverride: CenterOverridePolicy
}

enum RingSource: String, Codable, Sendable {
    case systemBattery
    case airPodsBattery         // Phase 5 才真正启用
    case none
}

enum CenterSource: String, Codable, Sendable {
    case automaticLegacy       // 仅迁移/兼容，可隐藏在新 UI 中
    case network
    case bluetoothAudioOutput  // 当前音频输出为蓝牙时才可用
    case pinnedBluetoothGlyph // 无连接要求：保留旧手动固定图标行为
    case connectedBluetoothDevice // 扩展：指定设备在线时才可用
    case systemBatteryPercentage
    case none
}

enum FooterSource: String, Codable, Sendable {
    case systemVolume
    case none
}

struct CenterOverridePolicy: Codable, Equatable, Sendable {
    var networkProblemOverridesPrimary: Bool
}
```

- 这些只是建议类型；若更少类型即可正确处理现有设置，优先简洁。
- Source 只能出现在自己**声明兼容**的 Slot 中；UI 不提供无意义跨区域组合。
- 禁止 `primary == fallback`；设置层自动归一化，旧配置校验时可用 `nil` 替代非法值。
- `none` 与 unavailable 不同：`none` 是用户有意留空，不应悄悄触发后续来源。
- 进入新系统后允许某个区域为 `nil` Scene，但不能让其他槽位或整个 icon 绘制失败。

### 2.2 Source、Behavior、Appearance 的归属规则

**Source** 仅定义“从哪里取得数据”；**Behavior** 定义“这个 Source 在这个 Slot 怎样表达”；**Appearance** 定义“该 Slot 最终视觉风格”。

- 外圈线宽、圆弧几何比例、颜色样式 → `OuterRingAppearance`。
- Mac 电池百分比/闪电/插头/临界阈值、充电动画 → `SystemBatteryRingBehavior`。
- AirPods 单/双圆环、L/R 与 Case 策略 → `AirPodsRingBehavior`（Phase 5）。
- 中心 Wi-Fi 状态符号、蓝牙设备图标策略 → Center 中相应 source-slot behavior。
- Footer dots/arc、点数/大小（限定兼容范围）→ `FooterAppearance` / `VolumeFooterBehavior`。
- 相同来源可在不同槽位有不同 Behavior；不用一个全局 Battery Options 强行覆盖所有槽位。
- Fallback 换成另一来源时：slot appearance 保持不变，source-slot behavior 切换为该来源各自保存的一份配置；**不要复制 primaryOptions/fallbackOptions 两套冗余状态**。

例如：

```swift
struct IconConfigurationV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var composition: IconCompositionConfiguration
    var behaviors: IconBehaviorConfiguration
    var appearance: IconAppearanceConfiguration
}

struct IconAppearanceConfiguration: Codable, Equatable, Sendable {
    var outerRing: RingAppearance
    var center: CenterAppearance
    var footer: FooterAppearance
}

struct RingAppearance: Codable, Equatable, Sendable {
    var strokeScale: Double
    var color: SlotColorStyle
}
```

对于每个 `Behavior`，优先复用现有 `BatteryIconOptions`、`ConnectionIconOptions` 等转换函数，保留回归断言。不要在一个阶段既重命名全部类型又重写内部计算方式。

### 2.3 Availability 需要区分不可用原因和数据时效

建议：

```swift
enum UnavailabilityReason: Equatable, Sendable {
    case deviceDisconnected
    case dataNotYetAvailable
    case permissionDenied
    case dataExpired
    case unsupported
}

enum SourceResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unavailable(UnavailabilityReason)
}
```

可包含 `observedAt` / 最后更新时间（只在确有需求时）；具体实现要区分 `unknown`、`temporarilyStale`、`disconnected`。

**重要规则**：

- `0%`、静音音量 `0`、网络关闭状态，都可以是**有效状态**，不能按 `false`/空判断为缺失。
- AirPods 的 L/R/Case 可能只读到部分通道；可配置综合电量映射，但不能默默杜撰缺少的通道，尤其不要把 Case 作为左右耳的平均值。
- 对新来源的临时数据丢失采用 bounded last-known-good + 轻量迟滞（例如建议初始默认 1–2 秒，具体需测试调整），但明确断连/用户切换应立即更新。
- 拒绝权限和数据过期应被可见地解释，而不是永久显示旧值。
- **不得通过额外的高频 timer 实现迟滞**；复用状态流和至多一个可取消的短期任务。

### 2.4 解析规则：简单、确定、可诊断

1. 判断是否存在针对该 Slot 的固定产品级 Override；目前仅 Center 的网络异常覆盖（且须语义合法）。
2. 尝试 primary 是否 available。
3. 否则尝试 fallback。
4. 都不可用时返回 `.none` 或明确约定的空状态。
5. 输出 `IconSceneState` 同时输出纯诊断信息（但诊断变化不应导致生产图标无谓重绘）。

建议诊断模型：

```swift
struct SlotResolutionTrace: Equatable, Sendable {
    var selectedSourceID: String?
    var reason: ResolutionReason  // primary, fallback(reason), overridden(rule), none(reason)
}
```

`IconResolutionTrace` 只供设置 UI/Debug 使用；不要成为高频渲染缓存键。诊断文本通过 Localization 格式化。

**Center 特别注意：**

- 旧 `.showsBatteryPercentageInConnectionSlot` 的行为优先于蓝牙和网络异常；新系统需用 `.automaticLegacy` 兼容或经证明等价的明确 override/preferred 组合实现。
- 旧蓝牙设备 pinned glyph 无连接要求；新 `connectedBluetoothDevice` 才启用断连 fallback。
- 网络异常覆盖只在已有网络状态中判断，不要为抢占新建联网探测/可达性轮询。
- 保留以太网连接时网络异常判定的旧约定及网络 icon 表达方式。

---

## 3. Phase 1 — 配置模型与迁移（必须无视觉变化）

### 任务 1.1：建立可版本化的配置

- [ ] 增加 `IconConfigurationV1` 与 Composition / Behavior / Appearance 相关模型（新建 `Presentation/Icon/Configuration/` 或现有 Models 目录均可）。
- [ ] 仅允许清晰可序列化的 `Codable, Equatable, Sendable` 存储类型；不要直接在 UserDefaults 中保存 `SwiftUI.Color`、`NSColor`、闭包、设备对象或 `CGColor`。
- [ ] 增加基础 normalize/validate：不合法的枚举、不支持槽位来源、重复 fallback、NaN/Inf、错误颜色值、过大缩放等；遵守合理限制。
- [ ] 新配置持久化使用带 schemaVersion 的**单份 snapshot**（`UserDefaults` JSON Data 或遵守现有 Store 习惯）；更新一次应发布一次完整一致的 `IconConfigurationV1`。
- [ ] 新增默认 `.classic` 以忠实复刻今天的默认状态，而非某个新的实验组合。
- [ ] 禁止模型初始化创建监控器或触发权限。

### 任务 1.2：旧设置迁移

- [ ] 新建明确的 `IconConfigurationMigration`：只在“无新配置”的旧用户启动时读取旧设置，生成新配置；**绝不清空原始 defaults**。
- [ ] 含迁移版本和错误处理；未来 schema 更新留有入口。
- [ ] 复刻现有 `showsBatteryPercentageInConnectionSlot` 高优先级、`replacesNetworkIconWithBluetoothAudio`、`prioritizesNetworkErrorsOverBluetoothAudio`、Wi-Fi/Ethernet/Hotsport/Temporary/Shared 显示规则、音量 dots/arc、充电显示/动画、所有大小及颜色规则。
- [ ] `bluetoothNetworkIconSymbolName` / pinned source 需保存固定图标的语义（即使设备离线也继续显示）。设备标识如需持久化，不改变旧值的归一化策略。
- [ ] 旧 `ringStrokeStyle` 同步赋给 `outerRing.strokeScale` 与 `footer.strokeScale`；迁移后允许分别编辑。
- [ ] 迁移发生在 Publisher 启动前；避免发布一半旧设置、一半新设置的中间状态。
- [ ] 新配置成为 Icon 唯一真源。过渡期如保留旧页面，需将其控件绑定到新配置的适配层；不得两套设置彼此独立并持续双向写入。
- [ ] 旧设置中与 Panel / 权限有关的值仍归原有控制器所有，不混入图标配置中强制开关，例如 `showsAppleDevicesAndBattery` 不可被悄悄打开。
- [ ] 仅当新设置某个来源需要权限时显示相应引导，不自动提示蓝牙权限。

### 任务 1.3：稳定 Publisher

- [ ] `SettingsStore+IconAppearance.swift`、`SettingsStore+IconPresentation.swift`、`StatusIconAppearance.swift` 注入新配置，一次改变发出一次一致快照。
- [ ] 确保 `@Published` 的 willSet 顺序不造成旧值与新值混合；可使用单值 `@Published var iconConfiguration` 生成衍生 publisher。
- [ ] `removeDuplicates()` 继续避免重复 Scene；改变无关设置不触发渲染。

### Phase 1 验收测试

- [ ] 旧版默认配置迁移后，`IconSceneState` 对关键输入与基准一致。
- [ ] `showsBatteryPercentageInConnectionSlot=true` + Bluetooth connected + noInternet：结果与旧版完全一致。
- [ ] pinned Bluetooth glyph 不因设备离线消失。
- [ ] ringStrokeStyle 迁移到 ring/footer 同值、修改其中之一不改另一个。
- [ ] 自定义/无效 JSON 配置读取、默认恢复、版本迁移、退化处理可测试。
- [ ] 第一次启动不增加蓝牙权限弹窗，不增加后台工作。

**Gate：必须保持旧测试通过且用户可见外观零变更后才能进入 Phase 2。**

---

## 4. Phase 2 — Slot Resolver / Source-Slot Behavior / Fallback

### 任务 2.1：把当前 Mapper 改成薄入口

推荐新增（最终命名依现有架构）：

```text
Presentation/Icon/
  IconPresentationMapper.swift        // 单入口，仅组装
  Resolution/
    IconSourceAvailability.swift
    IconSourceSnapshot.swift
    IconResolutionTrace.swift
    OuterRingResolver.swift
    CenterResolver.swift
    FooterResolver.swift
    CenterOverrideResolver.swift
  Behavior/
    SystemBatteryRingMapper.swift
    NetworkCenterMapper.swift
    BluetoothAudioCenterMapper.swift
    SystemVolumeFooterMapper.swift
```

- [ ] 新 resolver 是纯函数：`Configuration + InputSnapshot → Resolved Scene + Trace`。
- [ ] 将旧 `IconPresentationMapper.batteryState` / `wifiState` / `footerState` 原样抽出，优先避免逻辑变化；映射与监控不混合。
- [ ] 不使用动态注册和插件 runtime；以 compile-time `switch` + 受限的来源列表更适合第一版。
- [ ] 增加 `SupportedSources.forSlot` 之类的轻量 metadata，供 UI picker 和配置校验共用，避免 UI/Resolver 不一致。

### 任务 2.2：新增 resolution 行为

**Ring**

- 默认：Mac Battery → nil，完全复刻 Classic。
- 新选择：AirPods Battery → Mac Battery（Phase 5 才可用，未实现前 UI 不要提供不可用功能）。
- 明确 `none` 是否为 intentional blank 并保持一致。

**Center**

- 默认：复刻现有自动策略（Mac 电量百分比、蓝牙图标、网络等的原始优先级）。
- 显式模式：Bluetooth Audio Output → Network；启用内置 `networkProblemOverridesPrimary` 时，网络异常可以抢占蓝牙，但不会凭空抢占固定图标，除非用户开启该规则且设计约定明确。
- pinned glyph 与 connected-specific glyph 在 UI/状态机中区分。

**Footer**

- 仅 System Volume / None，样式 dots/arc 维持现有处理；不扩展无意义的来源列表。

### 任务 2.3：状态来源与切换防抖

- [ ] `SourceResult` 必须区别 truly unavailable 与 0 值。
- [ ] 按身份关联设备，不因名称相同串台；设备名称仅用于界面显示。
- [ ] 对瞬断的电量快照使用显式 freshness/最后更新时间机制和有限迟滞；已断开的设备不一直展示缓存。
- [ ] 防止 BT state / battery state 交替导致 UI 频繁跳动；不新增持续 high-frequency timer。
- [ ] `IconResolutionTrace` 可解释 `Primary`、`Fallback`、`Network Override`、`Permission denied`、`No data` 等原因。
- [ ] 确保 Trace 与生产 Scene 同次求值产生，不再额外运行一套决策逻辑。

### Phase 2 测试矩阵（至少）

| 测试条件 | 预期 |
|---|---|
| Bluetooth 正常可用，网络正常 | 选定蓝牙主要来源 |
| Bluetooth 不可用，网络正常 | 选中网络 fallback |
| Bluetooth 可用，Wi-Fi No Internet，开启异常覆盖 | 显示网络异常 |
| Bluetooth 可用，网络恢复 | 恢复主要蓝牙来源 |
| 当前输出不是蓝牙音频，但指定设备图标 pinned | 保持 pinned glyph（旧语义） |
| connected-only 指定设备断连 | 使用 fallback |
| Volume scalar 0 / muted | 有效音量状态，不按 unavailable 误处理 |
| Battery 0% | 有效 0% 圆弧，不按无数据处理 |
| 设备读取瞬断与明确断连 | 前者短暂稳定，后者及时切换 |
| primary/fallback 配置相同或不受该槽位支持 | normalize 或拒绝保存 |
| 网络异常但正在使用 Ethernet | 保持既有网络判断 |

**Gate：新增 resolver 对 Classic 的输出必须与老 mapper 等价，所有三部分可用性逻辑均有单测。**

---

## 5. Phase 3 — 自定义外观与语义颜色（先不做任意主题引擎）

### 任务 3.1：每个槽位的 Appearance

支持：

- Outer Ring：线宽、顶部内容缩放（保持旧 textScale 的默认效果）、ColorStyle。
- Center：图标大小、ColorStyle；不同来源仍可有自有符号选择。
- Footer：dots/arc、粗细/点大小、ColorStyle。
- 全局 iconSize 仍服务 Menu Bar；Dock 背景/可见性仍按当前独立设置；MenuBar/Dock 使用**同一 Scene + 同一语义颜色规则**，允许背景/尺寸差异。
- 对不支持的控件隐藏或禁用，不提供没有渲染意义的数值。

### 任务 3.2：颜色模式

第一版给每个 Slot：

1. **Automatic**（默认）：复用 `.primary/.inactive/.critical/.lowPower/.powered/.bluetooth` 等 `IconColorRole`。
2. **Single color**：一枚用户选择颜色，对该槽位普通状态统一上色。
3. **Custom by state**：由来源需要的语义状态映射颜色，如 Battery Normal/Charging/LowPower/Critical；先覆盖真实需要的状态，不造无限枚举。

建议：

```swift
struct StoredRGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

enum SlotColorStyle: Codable, Equatable, Sendable {
    case automatic
    case fixed(StoredRGBAColor)
    case semanticOverrides([StoredSemanticColorRole: StoredRGBAColor])
}
```

> 实际枚举编码建议显式 discriminator/tag，确保向后兼容；Hashable 与 renderer 的 key 要完整。颜色数值必须 clamp/校验、拒绝 NaN。

设计要求：

- `IconPresentationMapper` 仍产出**语义角色**而非内嵌 RGB；Renderer 或独立 `IconPaletteResolver` 最后解释颜色。
- 仅自定义颜色模式下才使用设置 RGB，其他模式维持系统深浅色/动态 foreground 的旧行为。
- 允许 Light/Dark 外观使用自适应自动色；自定义模式首版可单色同时适用两个外观，后续扩展为日/夜双色时无需改 Provider。
- 网络警告、充电低电量等语义色不要因单色选项而变得不可区分却毫无说明；UI 提供清晰预览或可选“警告保持系统色”，第一版不强制复杂高级颜色规则。
- `ChargingEffectPalette` 与自定义圆环颜色协调：充电高亮清晰可见，减少视觉过曝；macOS Reduce Motion 必须受尊重。

### 任务 3.3：缓存一致性

- [ ] 检查 `StatusBarRenderKey`（scene/size/scale/appearance/phase）与 `DockIconRenderKey`（scene/background/pixel size），使改变有效 Palette 时缓存命中失效。
- [ ] 不把本不影响画面的配置对象全部塞入缓存键；只保留**resolved raster inputs**。
- [ ] Dock 的 staticScene 仍忽略仅用于动态效果的 phase，避免逐帧更新静态 Dock。
- [ ] 任意 Appearance 更改立即刷新 MenuBar、Dock 与 Preview；不等待下一次状态轮询。
- [ ] 色彩渲染在不同外观/不同 scale 的快照测试中正确。

### Phase 3 验收

- [ ] 完整测试 Automatic / Fixed / Semantic state 颜色，正常/充电/临界/蓝牙/网络异常场景。
- [ ] 仅修改 Outer Ring 颜色不影响 Center/Footer。
- [ ] 修改颜色后 UI 立即变化；缓存 miss 一次，重复设置不反复绘制。
- [ ] 默认配色与原版本截图/Scene 一致；Dark/Light + Dock 背景没有明显对比度问题。

---

## 6. Phase 4 — UI-first Icon Designer、诊断、模拟预览（核心交付）

### 任务 4.1：重组设置导航

推荐新 Sidebar：

```text
Icon Designer
Status Panel
General
About
```

`Icon Designer` 内可以按视觉部件选择 Outer Ring、Center、Footer，此外保留 Placement / Size / Dock Background 的集中配置。

**迁移策略**：第一阶段仅把影响 icon 的选项搬入 Icon Designer；Bluetooth 设备列表、权限、后台刷新、网络详细设置、音频面板控制等仍留在 Status Panel 或相关二级页面。不要把“所有蓝牙设置”误塞进 Center。

建议 UI 结构：

```text
┌────────────────────────────────────────────────────────────────┐
│  Sidebar         │ Icon Designer                              │
│                  │                                             │
│  Icon Designer ● │  [真实菜单栏 / Dock 预览]   Light / Dark      │
│  Status Panel    │       ↖ 点击 Ring / Center / Footer         │
│  General         │                                             │
│  About           │  [Outer Ring] [Center] [Footer]            │
│                  │                                             │
│                  │  Content                                    │
│                  │  Primary:  [Mac Battery ▼]                  │
│                  │  Fallback: [None ▼]                         │
│                  │                                             │
│                  │  Source Behavior                            │
│                  │  Top:      [Auto ▼]                         │
│                  │  Show charging indicator [✓]               │
│                  │  Charging animation [✓]                    │
│                  │  Critical threshold [20%]                  │
│                  │                                             │
│                  │  Appearance                                 │
│                  │  Thickness [Thin | Regular | Bold]         │
│                  │  Color [Automatic ▼]                        │
│                  │                                             │
│                  │  Preview Mode [Live ▼]                      │
│                  │  Showing: Mac Battery (Primary)             │
└────────────────────────────────────────────────────────────────┘
```

要求：

- [ ] 顶部真实预览固定/可见，参数区域可滚动；点击 Ring/Center/Footer 的 hit areas 大于实际 icon glyph，支持键盘焦点与 VoiceOver。
- [ ] 窄窗口/小屏幕布局不挤压图标；macOS 13+；延续项目已有原生 `SettingsPage`、`SettingsGroup`、`SettingsRow` 等风格，而非引入不兼容的第三方 UI 框架。
- [ ] 槽位可通过预览点击和 Segmented Control 双途径选择，**不能只有小图标热点**。
- [ ] Source picker 只显示该槽位支持的来源及明确状态；不能因为当前未连接就隐藏已配置来源。
- [ ] `Primary`、`Fallback` 语义文案面向一般用户，专家术语仅在说明中显示。
- [ ] 与来源无关的 Appearance 始终显示；来源行为按当前编辑的 source 动态显示。为编辑 fallback 的行为提供切换编辑对象的 UI（如 `Edit primary` / `Edit fallback`），避免永远只能修改主来源配置。
- [ ] Provider 级选项只保存**一份**。把 Primary 和 Fallback 对调后，各自 Behavior 原样保留。
- [ ] Center 网络异常覆盖只在有关来源组合下显示；不要给每个槽位都显示空的 Override 配置。
- [ ] 支持每个 Slot 的 `Restore Defaults`（必须带清晰确认/撤销习惯），并保留全局恢复。
- [ ] 多语言沿用 `LocalizationKey.swift` / `.lproj`；核对所有支持语言的 key 完整性，避免硬编码英文业务文案。

### 任务 4.2：生产 Renderer 驱动的状态模拟

**强烈推荐首版交付**，不是普通装饰性功能。

预览下拉：

- Live（真实系统状态）
- AirPods connected（如果 Phase 5 未实现，可只作为源 availability 的模拟，不展示尚不能渲染的双段）
- AirPods disconnected
- Network healthy
- Network no Internet
- Wi-Fi off / Ethernet connected
- Battery charging
- Battery critically low
- Volume muted

实现：

- [ ] 新建纯值 `IconPreviewScenario`，产生 deterministic `IconPresentationInputs`（及额外窄来源快照），经正式 resolver → `IconSceneState` → 正式 Renderer。
- [ ] 禁止为模拟修改 `SystemStatusStore` 真实状态、macOS 音量/网络或蓝牙连接；禁止为模拟开启监控、BLE scan、额外 `system_profiler`、网络请求。
- [ ] 进入/退出预览仅切换输入值；退出重回 Live 立刻正常工作。
- [ ] 预览充电动画沿用既有 preview clock / charging effect 流程，离开页面立即释放；尊重 Reduce Motion。
- [ ] 必须演示 Fallback 与 Override 转换，而非只展示不同图片。
- [ ] 每次预览显示英文/中文可本地化说明，例如 `Showing Network · Network issue override`，`Showing Mac Battery · AirPods not connected`。
- [ ] Preview 层与生产 Source availability 规则保持相同，避免两个 resolver。

### 任务 4.3：预设与导入导出（低成本、分级实施）

- **必须交付**：`Classic` 预设；一键恢复当前旧版本外观和行为。至少在内部模型中支持预设静态配置。
- **条件交付**：`AirPods Focus`（Phase 5 AirPods 成功后才展示）；`Minimal`（三个 Slot 的子集）。
- **延后**：导入/导出 JSON 配置 UI。模型需保持 Codable/schemaVersion，将来实现时校验 schema、数据范围与兼容来源；默认不导出设备地址、配对信息、用户敏感配置或遥测标识。不要为预设启动自动切换规则。

### Phase 4 验收

- [ ] 图标预览/Segment Control 都能切换编辑槽位，按钮/控件可通过键盘/VoiceOver 操作。
- [ ] 预览模拟断网时触发网络 Override、模拟 AirPods 断开时触发 Fallback，并正确显示切换原因。
- [ ] 预览模式不影响系统真实音量/蓝牙/联网/系统状态和后台采集需求。
- [ ] 常规功能（Wi-Fi 网络列表、Bluetooth 设备列表、Popover、General、About）仍可通过新导航找到。
- [ ] 各语言文本完整、Mac 13 可构建、浅色/深色/Dock 对比清晰。

---

## 7. Phase 5 — AirPods 电量来源与双分段圆环（独立交付）

> Phase 5 与前面的大多数重构解耦。**必须在 Phase 1–4 已可运行并通过测试后再开始。** 如果 Phase 5 超出范围，先交付稳定的 Icon Designer；不要让 AirPods 复杂度阻塞核心 UI。

### 任务 5.1：复用现有 Bluetooth Battery 数据

当前 `BluetoothBatteryLevel` 包含 `main / left / right / caseLevel`；需要一个轻量 adapter：

```swift
struct AirPodsBatteryIconSnapshot: Equatable, Sendable {
    var deviceID: String?       // 内存中稳定标识，非显示名称
    var isConnected: Bool
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var observedAt: Date?
}
```

**注意**：

- [ ] 区分 AirPods Bluetooth battery 与 `MobileBatteryController` 的 iPhone/Watch trusted-device battery，不因为前者需求而启动后者。
- [ ] 复用 `BluetoothDeviceController.batteryLevels`、`BluetoothBatteryReader`、已有 accessory fallback；先确认已连接设备列表与电量 key 的关联逻辑。
- [ ] 当前音频输出状态可能不等于 AirPods 连接状态；要选择一致的“用户想监控哪副 AirPods”策略：首版可支持 **当前连接的 AirPods** 或明确选定的设备，切勿盲目匹配名称。
- [ ] 耳机未连接、缺少有效电量或数据过期时正确触发 Mac Battery fallback；仅 Case 有电量而没有耳机数据时不要错误声称是左右耳综合电量。
- [ ] 数据不全要显示合理的 available/partial/unavailable 语义，按明确 documented policy 回退，绝不杜撰 0 或平均值。

### 任务 5.2：使用 claim / demand，不重复启动 Controller

**严禁：**

- 只要选择 AirPods Source，就无条件常驻 `CoreBluetoothLEBatteryScanner`。
- 直接以新定时器每秒查询 `system_profiler`、`pmset` 或所有配对设备。
- 为菜单栏再创建第二个 `BluetoothDeviceController`，与 Status Panel 的设备列表各扫一次。
- 为探测可用性无条件扫描附近 BLE。

**实现：**

- [ ] 首先让轻量设备连接/输出事件可唤醒 source availability；不依赖详细电量读取的永久运行才能获知设备重新出现。
- [ ] 为图标增加独立的 demand token（如 `icon.outerRing.airPodsBattery`），复用现有 `requestBatteryLevels` / `releaseBatteryLevels`，或在需要时增加真正 owner-aware 的 `IconSourceDemandBridge`。
- [ ] 连接不活跃或用户取消 AirPods Source 时，释放详细电量读取；设备再次连接应自动恢复。
- [ ] 若现有 `BluetoothDeviceController.activate/deactivate` 是单 owner，**不要让图标无条件调用 `deactivate` 导致 Settings/Popover 使用者失效**。优先为激活增加 reference-counted owner/claim 并独立保持 popover visibility gating；完整检查控制器已有生命周期。
- [ ] 只监控真正被 Icon 使用的设备，不默认对所有已配对设备采电量；若现有 reader API 只能读全量设备，至少确保事件唤醒、去重、合理节流和最小可接受频率，并记录这个限制。
- [ ] 当权限未授予时不自动申请，预览提示可在设置页主动请求授权；尊重 existing opt-in 和用户隐藏设备选项。
- [ ] 遵守已存在的后台刷新许可选项，不把只对 Popover 授权的行为扩展为后台。若确需图标独立后台许可，应提供明确可理解的 opt-in，并默认关闭。
- [ ] 用户未选择 AirPods Source 时相关 icon demand 为零，所有额外 observer / Task 释放。

### 任务 5.3：Renderer 先支持两种受控布局

- **Single ring**：Mac Battery、AirPods main 或明确文档化的综合电量（不得默默合成缺失渠道）。
- **Dual segment ring**：仅 AirPods Left/Right；分段角度固定且有可见间隙，保持当前 ring stroke、top gap 和 accessory 的可读性。
- **Case**：可在顶部 accessory 展示（如果能在 16–36 pt 的菜单栏尺寸清晰读出）；否则暂留 Status Panel；不要强塞第三个分段。

当前 `StatusIconRenderer.supports(_:)` 只允许 `ring.segments.count == 1`：

- [ ] 扩展明确的 geometry/representation（如 `RingLayout.single` 与 `.dual`），而非简单删除 supports 限制并遍历 segments。
- [ ] 更新 `StatusIconGeometry` 和 `StatusIconRenderer`，处理角度、Gap、inactive track、颜色、零电量和满电量等边界。
- [ ] 充电效果先只支持 Single，Dual 若未确认设计则关闭效果并在 UI 说明；不要复用单环相位计算造成绘制错乱。
- [ ] 保持旧 Single 路径 pixel-perfect；多段额外绘制在新分支，旧 tests 不变。
- [ ] Dock、菜单栏不同尺寸/Retina scaling 下不能溢出或无法辨认；动态色彩与状态切换一致。

### Phase 5 验收矩阵

- [ ] L/R 都存在、单独缺 L、单独缺 R、仅 main、仅 case、完全无电量、设备断开。
- [ ] 两副设备（包含同名设备）不会串台；切换音频输出不导致错误设备电量覆盖。
- [ ] 出现/消失瞬间无频繁闪烁，断开时 fallback。
- [ ] BLE 权限拒绝时 icon 正确 fallback，用户可以理解原因。
- [ ] Popover 关闭、Settings 关闭、屏幕休眠、系统休眠、用户取消来源后不遗留额外读取任务。
- [ ] 未选择 AirPods Source 时后台行为与 Phase 0 基线相同。
- [ ] `StatusIconRenderer` Single 回归及新 Dual 像素/几何测试通过。

---

## 8. 性能、资源与隐私：不可省略的跨阶段 Gate

### 性能层级

| 级别 | 示例 | 默认策略 |
|---|---|---|
| 基础/现有 | Battery / Wi-Fi / 当前音频输出 / Volume 的已有系统事件 | 优先复用现有 monitor；不引入新监视者 |
| 条件采集 | AirPods L/R/Case、指定 Bluetooth 设备详细信息 | 只有配置需要且授权时，通过 demand 激活 |
| 高成本 | BLE discovery/GATT、`system_profiler`、`pmset` fallback、MobileBattery Helper、外部 HTTP metrics | 默认绝不因新 UI 常驻；显式授权/选择、限速、数据缓存和停止路径 |

### 具体必须覆盖的测试

- **无新增来源**：初始启动后 5 分钟，`BluetoothDeviceController` 激活状态与基线一致，无新增 accessory battery task、BLE scan、periodicRefreshTask 或 helper 调用。
- **来源启用/关闭**：重复 20 次配置 AirPods → Mac → AirPods，不泄漏 observer/Task/claim，不因相同 token 重复读取。
- **Popover 与 Icon 同时持有**：关 Popover 后 Icon 的必要订阅继续；关闭 Icon 后 Popover 所需订阅继续；两者都关后停止。
- **设置/模拟预览**：反复打开关闭 Designer，查看无新增权限弹窗、无扫描和设备命令；Preview 不触发真实设备读取。
- **前后台/休眠**：正确暂停/恢复昂贵任务，保留足够轻的唤醒信号；不会因为 display-wake 丢失通知无限冻结。
- **高速状态变化**：网络断开/恢复、蓝牙连接/断开、音量变化，确保 coalescing 和 dedup，不因每个 raw 电量变化强制整个 UI 高速重绘。
- **Render**：修改 irrelevant Option 及更新无关 `MobileBatterySnapshot` 不应造成 MenuBar/Dock redraw。
- **CPU 基线**：使用 Release 或同一构建配置、同一采样区间/设备环境对比 idle CPU/wakeups；不给没有测量支撑的“零开销”结论。设定回归门槛：未启用新来源时无可重复检测的额外持续采集/唤醒；量化异常必须修复或说明。
- **安全**：不请求额外 Bluetooth 权限，不自动扩大后台电量授权，不在诊断日志打印私有设备 ID/持久地址。

推荐 instrument：测试替身记录 `request/release` 次数、active token 集合、reader 调用次数、BLE start/stop、周期轮询任务数量、scene render key miss；线上默认关闭详细日志。

---

## 9. UI/UX 细节与新增 ideas 的处理决定

**必须实施**：

1. **可点击预览 + Tab/Segment 双入口**：Ring/Center/Footer 选择区域清晰。
2. **Preview Scenario**：连接/断开、断网、低电量、充电、静音；不改变真实设备状态。
3. **Why am I seeing this?**：显示 active source、primary/fallback、override、原因；只诊断当前结果。
4. **单独恢复默认**：每个 Slot 可以重置，保持另一两个不动。
5. **配置可用性提示**：权限拒绝/设备断连/数据未到时保留用户选择，不悄悄换掉 picker value。
6. **平滑 fallback**：短时 transient failure 不闪烁，明确断连立即回退。
7. **颜色继承与覆盖**：Automatic/Single/By-state，按 Slot 独立；颜色变化进入正确缓存键。
8. **兼容现有固定蓝牙图标语义**：显示选择与当前连接分开。

**低成本一期预留 / UI 可见但不扩大业务范围**：

- 预设：Classic 为必需；更多预设仅在来源实现且测试通过后展示。
- Accessibility：每个槽位可键盘选中、合适 hit area、颜色之外有状态文字提示、尊重 Reduce Motion。
- 轻量自诊断：只在 Settings 展示当前激活来源/切换原因，无需新增“常驻运行情况”服务。

**明确延后**：

- 任意优先级/任意条件规则编辑器。
- 复杂图层叠加、自绘插件 UI、脚本/HTTP source、动态自定义动画。
- 三段以上圆环、复杂时间曲线、完整主题商店。
- 自动按时间/应用/位置切换图标配置。
- 用户导入导出任意插件与敏感设备配置。

---

## 10. 测试、交付与防止范围蔓延

### 单元测试建议文件（允许按现有目录合并）

```text
Tests/StatusTrioCoreTests/
  IconConfigurationMigrationTests.swift
  IconConfigurationValidationTests.swift
  IconSlotResolverTests.swift
  IconSourceAvailabilityTests.swift
  IconSourceBehaviorTests.swift
  IconPaletteResolverTests.swift
  IconPreviewScenarioTests.swift
  IconResolutionTraceTests.swift
  IconDependencyDemandTests.swift
  AirPodsRingGeometryTests.swift          // Phase 5
  AirPodsBatterySourceTests.swift        // Phase 5
```

同时扩充现有：

```text
IconPresentationMapperTests.swift
IconPresentationViewModelTests.swift
IconAppearancePublisherTests.swift
IconSceneRendererParityTests.swift
IconSurfaceIntegrationTests.swift
StatusIconRendererTests.swift
StatusIconPreviewCardTests.swift
DockIconRenderCacheTests.swift
BluetoothPollingLifetimeTests.swift
BluetoothBatteryControllerTests.swift
SettingsStoreTests.swift
SettingsViewTests.swift
```

### 编译与验证命令

1. 确认本机 Xcode/Swift toolchain 和签名环境，查看 README / CONTRIBUTING / CI 的现有测试命令。
2. 在可执行的 macOS 开发环境运行（若 SwiftPM 当前支持）：

```bash
swift test
swift build -c release
```

3. 若构建依赖 `.xcodeproj`/workspace 或脚本，请使用**仓库实际提供**的等价命令；不要假装 Linux 环境能验证 macOS/AppKit 行为。
4. 对 macOS 13 与当前最新目标（至少 macOS 26+）的 API/布局做兼容性核验；如无法实际运行老系统，至少构建最低 deployment target 并清楚报告未实测内容。
5. 视觉差异使用现有 Preview / Icon pixel tests 校验，手工 smoke 覆盖菜单栏、Dock、Popover、Settings、浅色/深色、外接显示器 scale、Reduce Motion。

### 每阶段可交付报告模板

```markdown
## Phase N Completion
- HEAD / commit:
- Files changed:
- Public behavior change:
- Migration/compatibility notes:
- Tests run and results:
- Performance / demand lifecycle observations:
- Known limitations:
- Next phase risk:
```

### 中止条件

以下任何一项成立时，不得继续下一阶段，应先修复：

- 旧用户升级后图标外观或 pinned device 语义发生意外改变。
- 背景蓝牙电量读取/扫描在用户未配置来源时启动。
- UI 预览触发系统设备操作或改变真实状态。
- MenuBar 与 Dock 在同一个 Scene 上显示不同含义（除明确允许的独立动画/背景）。
- 自定义颜色改变后复用旧缓存，导致色彩不刷新。
- macOS 13 编译兼容性下降。
- 测试失败却以“暂不影响功能”为由掩盖。

---

## 11. 最终交付验收清单

- [ ] `main` 现有图标 Presentation 路径保持单一，不存在第二套 renderer 或并行 Monitor。
- [ ] 新的 Icon Designer 主视图可配置三部分，各自 Primary + 最多一个 Fallback。
- [ ] 既有电池闪电/插头/百分比、充电动画、阈值、Wi-Fi/蓝牙替换、音量点/弧和尺寸设置完整迁移。
- [ ] 旧用户当前数据下 Scene 和外观与更新前一致；设备固定图标仍可离线显示。
- [ ] 按 Slot 独立设置颜色/粗细；语义颜色与 Dark/Light 外观可正常渲染。
- [ ] 网络异常覆盖条件受限、可预测、无新联网探测。
- [ ] UI 内能模拟异常/断开/充电并明确解释显示来源；模拟不增加后台采集。
- [ ] Popup、Wi-Fi/Bluetooth/Audio/General/关于等现有功能都仍能找到、能使用。
- [ ] 每个 Slot 恢复默认、经典预设、配置版本及迁移测试通过。
- [ ] 设置改变实时同步菜单栏和 Dock，缓存不因新增颜色出错。
- [ ] 新增监控遵守授权、按需 claim、正确停止；无启用时额外持续消耗。
- [ ] AirPods 来源与单环/双环（如果本轮执行 Phase 5）通过数据缺失、断开、绘制、性能验收。
- [ ] 项目按当前 `Package.swift` 最低 macOS 13 构建，并保持现有多语言和辅助功能。
- [ ] 更新相关开发文档/用户设置说明，列出新旧配置对应关系及可观察的行为变更。

---

## 12. Codex 第一条实际操作指令

请从 **Phase 0 和 Phase 1 开始**。先阅读现有 `IconPresentationMapper`、`IconPresentationViewModel`、`StatusIconAppearance`、`SettingsStore+IconAppearance`、`SettingsStore+IconPresentation`、`SettingsView`、`StatusIconRenderer` 与相应测试，确定完整的向后兼容映射表；创建新的 `IconConfigurationV1`、迁移测试和模型验证测试。在确认 Classic 模式与旧版完全等价前，**不要直接大改设置 UI，也不要开启 AirPods 后台读取**。各阶段通过后再依本文顺序继续。
