# 统一「中间图标」选择器 设计文档

日期：2026-11-02
状态：已批准，2026-11-02 开始实现。

评审裁定：蓝牙子项持有独立设置 demand，出现时申请、消失时释放；授权只通过明确点击发起。指定设备也受统一网络异常优先控制。旧电量/功耗用户默认开启网络异常优先，这是本次明确的行为调整，不要求断网场景像素不变。

## 1. 意图与原因

状态图标中间那个「槽位」现在到底显示什么，被拆在两个设置页里，而且互相打
架：

- **「网络」页**：一个「中间图标」来源菜单（自动 / 当前输入法 / 电池百分比 /
  功耗），选了输入法时还会显示一个「优先显示网络异常」开关，外加 `wifiScale`。
- **「蓝牙」页**：一个「使用蓝牙设备图标代替网络图标」开关，选中后出现「使用
  哪台蓝牙设备」和「音频图标」子项，再跟一个「网络异常优先于蓝牙图标」开关。

真正的渲染优先级写在 `IconPresentationMapper.centerState` 里，是硬顺序：
功耗 → 电池百分比 → 输入法 → 蓝牙替代 → 有线/Wi‑Fi。

问题：

1. **蓝牙开关会静默失效。** 蓝牙「代替网络图标」只挂在「自动」分支上。只要
   中间图标选了输入法 / 电池 / 功耗，蓝牙开关就再也不生效，但 UI 还在、还能点。
2. **两个「网络异常优先」开关语义几乎一样**，一个跟输入法、一个跟蓝牙，分成两处。
3. 同一个决定（中间显示什么）散在两个 tab，**「电池百分比 / 功耗」放在「网络」
   页里显得别扭**——它们跟网络没有关系。

目标：把「中间显示什么」收进**一个**选择器，蓝牙变成其中的一个来源，优先开关
只留一个，整体搬到「应用图标」页里。这就是用户确定的「真正的中间图标选择器」。

## 2. 目标 / 非目标 / 反目标

**目标**

- 一个「中间图标」分组，含唯一来源选择器、唯一「网络异常时优先显示网络图标」
  开关、蓝牙子选项。
- 蓝牙设备图标成为中间图标的一个**来源**，不再是一个会被静默忽略的独立开关。
- 「电池百分比 / 功耗」移出「网络」页。
- 默认（全新安装）行为与今天像素一致。

**非目标**

- 不改 `IconPresentationMapper` 之外的渲染管线；不新增渲染表面。
- 不重做「蓝牙」页的其它内容（面板显示、符号缩放、音量蓝色、电量、聆听模式）。
- 不改 Wi‑Fi 图标变体（有线/热点/临时连接用 Wi‑Fi 图标）与「显示本机 IP」。
- 不改菜单栏 / Dock 的图标绘制代码；两者共用同一 `IconSceneState`，来源变化会
  自动生效。

**反目标（即使“能跑”也算失败）**

- 老用户已选来源丢失；除已明确的全来源断网优先外，正常联网时外观被改变。
- 留下一个能点但无效果的开关。
- 只在菜单栏生效、Dock 表现不同（必须同一来源一致）。

## 3. 约束

- macOS 13+；渲染相关改动按仓库规则走 `full` 验证档，并跑
  `Issue30WiFiAlignmentTests`、Dock/Menu Bar 一致性、`ChargingEffectRenderingTests`。
- 菜单栏与 Dock 渲染/设置必须同一来源（`AGENTS.md` 不变量）。
- 本地化需覆盖所有已发布语言（12 种），键名按现有约定。
- 状态图标的 `wifiScale` 目前同时是 Wi‑Fi 字形和数字中间槽的缩放来源，本次继续
  复用，不新造缩放项。

## 4. 方案（已选）

用户已选定：**并入「应用图标」页，新增「中间图标」分组**；不新开侧栏页。
理由：不新增第 9 个侧栏项；「中间显示什么」本就属于状态图标；该页顶部有实时
预览，改完立刻可见。

### 4.1 数据模型

把 `ConnectionCenterSource` 从「自动」改为显式的「网络」，并新增蓝牙来源：

```swift
enum ConnectionCenterSource: String, CaseIterable, Identifiable, Sendable {
    case network            // 原是 .automatic；纯网络（有线/Wi‑Fi），不再内嵌蓝牙替代
    case bluetoothDevice    // 新增：蓝牙设备图标（见 4.2）
    case inputSource
    case batteryPercentage
    case power
}
```

移除两个独立布尔：

- `replacesNetworkIconWithBluetoothAudio`：语义并入 `centerSource == .bluetoothDevice`。
- `prioritizesNetworkErrorsOverInputSource` 与
  `prioritizesNetworkErrorsOverBluetoothAudio`：合并为一个
  `prioritizesNetworkErrors`。

保留：

- `bluetoothNetworkIconSymbolName`（指定设备时的字形覆盖）
- `bluetoothAudioIconChoiceRawValue`（音频图标选择）
- `usesBluetoothAudioVolumeColor`、`bluetoothSymbolScale`（留在蓝牙页）
- `wifiSymbolScale`

### 4.2 蓝牙子选项

`centerSource == .bluetoothDevice` 时在分组内显示：

- **使用哪台设备**：`跟随当前音频输出`（默认）/ `指定某台已配对设备…`
  （复用现有 `BluetoothNetworkIconSource` 菜单与 `BluetoothNetworkIconSourceOption`）。
- 选「跟随音频输出」时，再显示现有的**音频图标选择**（仅 `.audioDevices` 分支）。

「跟随当前输出」的语义保持今天一致：当前输出是蓝牙音频才用其图标，否则回退
网络。复用 `StatusMappings.shouldReplaceNetworkIcon` 的传输判定；「指定设备」
因有 `networkIconSymbolOverride` 而无需当前输出为蓝牙；统一网络异常优先仍可覆盖该设备字形。

### 4.3 唯一的优先开关

`prioritizesNetworkErrors` 默认 `true`，**对任何来源都生效**（用户明确要求，含
功耗与电量）：当真实断网/无网络时，中间槽改显示网络状态，而不是所选来源。

- 选 `.network` 时开关无意义（本来就是网络），**隐藏**该开关。
- 选其余四种来源时**显示**该开关。

渲染上把它提到 `centerState` 的最前层统一判断，而不是像今天那样分别散在蓝牙和
输入法分支里：

```
if source != .network && prioritizesNetworkErrors && isNetworkOffline(...) {
    // 跳过所选来源，走网络判定
} else {
    // 按来源返回：power / batteryPercentage / inputSource / bluetoothDevice
}
// 网络判定：以太网 / Wi‑Fi（含离线态）
```

功耗 / 电量被网络异常覆盖时，顶部电池指示仍照常显示电量，不会丢失电量信息。

### 4.4 设置界面

在 `AppIconSectionView` 增加「中间图标」分组，包含：

1. 来源菜单：网络 / 蓝牙设备 / 当前输入法 / 电池百分比 / 功耗。
2. `.bluetoothDevice` 时的设备子选项（4.2）。
3. 非 `.network` 时的「网络异常时优先显示网络图标」开关。
4. 一句说明性 hint（例如“中间位置一次只显示一种内容；网络异常可优先显示网络”）。

从 `NetworkSectionView` 移除：中间图标菜单、优先开关、蓝牙回退 hint。保留连接
图标变体折叠区、`wifiScale`、「显示本机 IP」。

从 `BluetoothSectionView` 移除：代替网络图标开关、设备来源行、音频图标选择、
网络异常优先开关。保留其余。

### 4.5 迁移（老用户）

在 `SettingsStore.init` 一次性迁移，迁完删除旧键，避免覆盖之后的手动选择：

- 旧 `showsBatteryPercentageInConnectionSlot == true` → `.batteryPercentage`（保留
  现有逻辑，最高优先级）。
- 否则读旧 `connectionCenterSource` 字符串：
  - 缺省或 `"automatic"` → 若旧 `replacesNetworkIconWithBluetoothAudio == true`，
    则 `.bluetoothDevice`（跟随当前输出）；否则 `.network`。
  - `"inputSource" / "batteryPercentage" / "power"` → 同名新值。
- 新 `prioritizesNetworkErrors`：默认 `true`；若旧来源是输入法则取旧
  `prioritizesNetworkErrorsOverInputSource`，若是蓝牙则取旧
  `prioritizesNetworkErrorsOverBluetoothAudio`，否则 `true`。
- 删除旧键：`replacesNetworkIconWithBluetoothAudio`、两个旧优先键。

### 4.6 受影响的引导与预览

- `IconGuideView` 的 `connectionCenterSourceOverride` 与示例场景改用新枚举 +
  单一优先开关。
- 测试支撑 `IconStateSheet` / `DockIconSheet` 里「网络异常时保留 Wi‑Fi 图标」等
  文案与场景同步。
- `StatusIconPreviewCard` 经 store 发布者自动跟随，无需改。

## 5. 部件清单（改动面）

- 模型：`ConnectionCenterSource.swift`、`ConnectionIconOptions.swift`、
  `BluetoothAudioIconOptions.swift`、`StatusMappings.swift`。
- 设置存储：`SettingsStore.swift`（属性、默认值、迁移、发布者组合）、
  `SettingsStore+IconAppearance.swift`。
- 渲染：`IconPresentationMapper.swift`（统一优先判断）。
- 界面：`AppIconSectionView.swift`（新增分组）、`NetworkSectionView.swift`、
  `BluetoothSectionView.swift`；`BluetoothNetworkIconSource(.swift|Option.swift)` 复用。
- 引导：`IconGuideView.swift`。
- 本地化：`Resources/*.lproj/Localizable.strings` 全语言增删键。
- 测试：见第 7 节。

## 6. 默认与不变量

- 全新安装默认：来源 `.network`、`prioritizesNetworkErrors = true` → 与今天
  `.automatic` + 蓝牙替代关闭像素一致。
- 菜单栏与 Dock 共用同一 `IconSceneState`，来源一致。
- 不新增轮询 / 动画 / 后台任务；功耗采样仍只在 `.power` 时按需开启。

## 7. 验证

按 `AGENTS.md`：这是渲染 + 状态/存储改动，走 `full` 档；并额外：

- `Issue30WiFiAlignmentTests`（隔离墨迹 + 合成图，不得放宽）
- `ChargingEffectRenderingTests` 指纹保持
- Dock / Menu Bar 一致性测试

重点定向测试：

- `ConnectionCenterSourceTests`（迁移：automatic→network/bluetooth、旧百分比开关、
  两个旧优先键合并）
- `IconPresentationMapperTests`、`PresentationBaselineTests`（含优先开关覆盖
  电量/功耗的新行为）
- `IconAppearancePublisherTests`、`SettingsStoreTests`、`SettingsViewTests`
- `BluetoothAudioIconOverrideLifecycleTests`、`InputSourceSettingsTests`、
  `StatusMappingsTests`、`IconGuideRedesignTests`
- Dock：`DockIconPreviewWiringTests`、`DockChargingEnvironmentTests`、
  `IconSceneRendererParityTests`

## 8. 留给 builder 的判断（已定，供复核）

1. 优先开关在 `.network` 时隐藏（无意义），其余来源显示。
2. 两个旧优先布尔合并时按“旧来源”取对应那个，其它默认 `true`。
3. 蓝牙子选项默认「跟随当前音频输出」。
4. 数字缩放继续复用 `wifiScale`，本次不新增独立缩放项。
5. 蓝牙「音量蓝色」与「符号缩放」留在蓝牙页，不随中间图标分组迁移。

## 9. 实现期间的细化（2026-11-02）

评审后按实际视觉反馈调整，最终形态以本节为准：

- **来源选择器用图片选择器，不是下拉框。** 五个来源各自渲染一张真实状态图标，
  只替换中间内容；方块外观复用「外环线条粗细」那排的圆角、1px 描边和选中环。
- **大小统一为「中间图标大小」。** Wi‑Fi 符号、蓝牙设备图标、输入法、数字共用
  一个缩放值（持久化仍用 `wifiSymbolScale`，旧 `bluetoothSymbolScale` 迁移后删除）；
  该值在 `iconAppearancePublisher` 末端统一折叠，避免一次改动发布两个半成品。
- **网络图标样式搬入同一分组。** 有线/热点/临时连接/互联网共享的 Wi‑Fi 图标变体
  只在选中「网络」时显示；「网络」页只保留本机 IP 开关。
- **中间文字基准略低于符号。** 同一缩放值下，电量/功耗数字按符号的 90% 绘制，
  避免数字看起来比 Wi‑Fi/蓝牙字形更重。
- **中间内容锚在圆环圆心。** 原来锚在 `y=64`，圆环几何圆心是 `y=61.49`，
  内容偏低约 2.5 单位；现在符号和文字都锚在圆心。
