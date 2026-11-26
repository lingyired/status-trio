# 菜单栏自定义实例（Menu Bar Instances）设计

- 日期：2026-11-27（v2，已并入独立评审意见）
- 状态：**已定稿（用户已确认）**；进入实现计划（writing-plans）
- 范围：Status Trio macOS 应用，菜单栏部分；不涉及主图标、Dock、Helper、发布流程

## 1. 背景与意图

Status Trio 已经采集了大量系统监控数据（CPU/GPU 使用率与温度、内存、磁盘、网络上下行、风扇、电池、Wi‑Fi、音量、亮度等），但目前菜单栏只有**一个主图标**（场景渲染的电池/环形图标）。

用户希望把这些数据直接显示在菜单栏上，并能像 `tauri-plugin-multiline-menubar` / `fund01` 那样**自定义菜单栏实例**：

- 一个实例在菜单栏显示**上下两行**，每行内容、样式各自定义。
- 可创建**任意多个**实例，彼此独立。
- 移除/隐藏一个实例，只影响它自己，不能把整个 App 的菜单栏项都关掉（反例是 Stats）。

本设计落在原生 AppKit 上（Status Trio 是 Swift/AppKit 应用，用不了 Tauri 插件），沿用插件已被验证的实例模型与交互语义。

## 2. 目标（Goals）

1. 用户可创建 N 个独立实例，每个是一个独立 `NSStatusItem`。
2. 每行 = 若干片段（文字 / 数据源，可混排多个数据源）+ 可选行内图标 + 行级样式，用可视化 chip 编辑器编辑。
3. 行级样式：颜色、粗体、字号、等宽数字、水平对齐；可选行内图标；可选实例级左侧列图标（两行共用、垂直居中）。
4. 颜色：默认继承数据源自带颜色定义（含阈值/语义变色），可对整行覆盖为固定色。
5. 宽度：自适应（按内容测量），用户可调内边距 / 外边距；配合等宽数字，数值变化尽量不抖动。
6. 空值 / 不可用：该片段显示 `--`（不隐藏、不空白，保持槽位稳定）。
7. 每个实例分别定义左键打开什么、悬浮打开什么；两者可不同，也可「不打开」。
8. 右键：统一为实例菜单（首项按配置的快捷行为 / 跟主图标一致，固定带「禁用此实例」；删除只在设置页）。
9. 位置/顺序：尽力持久化（重启后尽量回到原位与顺序）。
10. 移除实例只隐藏该实例；设置页可重新启用。

## 3. 非目标 / 反目标

非目标：

- **不改主图标**：现有单图标、场景渲染、Dock 一致性逻辑保持不变。文案里现有菜单栏图标统一称「主图标」。
- 一行支持多数据源片段混排，但不做通用富文本——片段只有「文字」「数据源」两类，样式在行级统一（不做逐片段独立样式）。
- 不在 Dock 上做对应自定义实例。
- 本版不做第三方 / 插件式自定义数据源。
- 不新增独立于现有采样体系的轮询。
- 新实例是独立**显示与交互**单元，但**不是独立数据采集单元**：指标读取、格式化、颜色、采样一律复用现有体系。

反目标（即便「能用」也算失败）：

- 拖出/隐藏一个实例，导致整个 App 的菜单栏项都消失。
- 数值从 `45%` 变 `8%` 时，菜单栏整体左右跳动。
- 系统菜单栏空间不足被挤掉的实例，被误判为用户移除、进而释放采样或标记禁用。
- 隐藏 / 禁用的实例仍在后台持续采样、耗电。
- 重启后实例乱位、重复出现、或全部消失。

## 4. 现状（代码调查结论）

- **单一状态项**：`Sources/StatusTrioCore/UI/StatusBarController.swift` 只有一处 `NSStatusBar.system.statusItem(...)`（约 334 行）；按钮 `action=handleClick`，`sendAction(on:[.leftMouseUp,.rightMouseUp])`；自绘图标走 `StatusIconRenderer` + `IconSceneState` 场景体系。
- **面板**：`AnchoredStatusPanel`（约 1157 行）；`StatusPanelRoute` = `summary / battery / wifi / ethernet / inputSource / hardwareDetail(HardwareDetailKind)`，`HardwareDetailKind` = `cpu/gpu/memory/network/disk/fan`；锚定用 `statusItemButtonScreenFrame()`（主图标按钮），区分 inline / alongside（`StatusPanelDetailCoordinator`）。
- **右键**：`StatusMenuBuilder`（版本更新/设置/退出）+ `MenuBarRightClickRouter` 把用户选择映射为 `MenuBarRightClickOutcome`（showContextMenu / toggleLowPowerMode / toggleChargeToFullNow / toggleMute / toggleWiFi / refreshStatus / openXXXSettings），当前是**一个**被选中的行为。
- **数据源**：`HardwareMonitorMetric` = `cpuUsage, gpuUsage, memoryUsage, cpuTemperature, gpuTemperature, batteryTemperature, fan, downloadSpeed, uploadSpeed, volume, wifiSignal, batteryLevel`；`HardwareMetricID` 另含 `diskRead/diskWrite`；`HardwareMetricAvailability` = measured / unsupported / temporarilyUnavailable / stale / collecting；`MetricProgressMapper`、`NetworkSpeedFormatter` 等负责格式化与阈值。
- **颜色**：目前解析逻辑在 `HardwareDetailView.metricColor(_:)`（View 内），输入是 `HardwareMonitorMetric` 的 recommended base color + 用户 `metricColors` 覆盖 + 电池状态色。
- **采样**：按需采样，`HardwareMetricDemandResolver` / `HardwareSampler` 依据订阅需求启停；需求需有 owner 与停止路径。
- **设置**：`SettingsStore`（`@Published` + UserDefaults）；`SettingsSemanticCatalog`（`Sources/StatusTrioCore/Settings/Semantic/`）；导出/导入白名单 `SettingsPreferenceCatalog`；侧栏 `SettingsView.Section` / `SettingsNavigationModel`；本地化 `LocalizationKey`。
- **装配**：`AppEnvironment.swift`（约 729 行）构造 `StatusBarController`。

## 5. 方案选择

选定 **方案 A**。

### A. 每个实例一个 `NSStatusItem`，button 上挂自绘 `NSView`（选定）

- 每个实例 = 一个 `NSStatusBar.system.statusItem`；在 `statusItem.button` 上添加自绘子视图，用 CoreText/`NSString` 绘制两行文字与图标。
- 宽度由 `statusItem.length` 控制（按宽度策略计算，padding 计入）。
- 位置：`statusItem.autosaveName = "statusTrio.menuBarInstance.<stable-id>"`（官方建议多状态项都设 autosave；系统按名字记住位置）。
- 用户拖出：`statusItem.behavior = .removalAllowed`，拖出由 AppKit 置 `visible = NO`（详见 §9.4）。
- 左键 action、右键 `menu.popUpMenu`。
- 优点：两行排版 / 行内图标 / 左侧列图标 / 对齐 / 字号 / 粗体 / 宽度全可控；插件已趟过两行排版、图标、亮暗、拖出恢复的坑。
- 代价：需自写文本绘制 + 测宽 + 亮暗重绘。

### B. 每实例整体画成 `NSImage` 塞进 `button.image`（未选）

与主图标管线一致，但 `StatusIconRenderer` 是图标场景渲染器不是文本排版，仍要另写文本绘制并自接点击区域/宽度，收益不抵消复杂度。

### C. `button.attributedTitle`（排除）

做不了行内图标、固定宽度/外边距、两行精确对齐。

## 6. 数据模型

### 6.1 配置容器（带版本）

持久化为 `SettingsStore` 的一个 `Codable` 属性（落 UserDefaults）：

```
MenuBarInstancesConfiguration {
  schemaVersion: Int            // 当前 1；迁移入口
  instances: [MenuBarInstance]  // 保序，顺序即创建顺序
}
```

校验（导入与启动都跑）：

- `id` 唯一；重复则整条丢弃并警告。
- 内边距 / 外边距范围 0…24；字号按行角色 clamp。
- 单行片段数上限 32；单个文字片段长度上限（如 64）。
- 未知 / 不支持的 `MenuBarMetricID` → 丢弃该片段并警告（降级安全）。
- 实例数 > 20：**导入时整份拒绝并提示**；正常运行上限 20（配置上限，不等于能显示 20 个）。

### 6.2 MenuBarInstance

```
MenuBarInstance {
  id: UUID                      // 稳定；autosaveName 用；删除后不复用
  name: String                  // 设置页显示名（空 → 自动命名）
  isEnabled: Bool               // 应用层启用状态（≠ 系统可见性，见 §9.4）
  top: MenuBarLine?
  bottom: MenuBarLine?
  leadingIcon: MenuBarIconSpec? // 实例级左侧列图标（两行共用、垂直居中）
  innerPadding: CGFloat         // 内容与实例边缘的内边距，默认 0
  outerMargin: CGFloat          // 实例外侧额外留白，默认 4
  clickAction: InstanceActivation   // 默认 .panel(.summary)
  hoverAction: InstanceActivation   // 默认 .none（悬浮仅允许面板类/不打开）
  rightClick: InstanceRightClick    // 默认 .sameAsMainIcon
}
```

- `top`、`bottom` 都为空 → 视为禁用，不创建状态项。
- 至少一行有内容才创建；单行时垂直居中。

### 6.3 MenuBarLine 与片段

```
MenuBarLine {
  segments: [MenuBarLineSegment]  // 按顺序渲染
  icon: MenuBarIconSpec?          // 行内小图标（整行最左侧）
  color: LineColor                // .inheritSource（默认） | .fixed(ColorValue)
  isBold: Bool                    // 默认 false
  fontSize: CGFloat?              // nil = 默认（按布局角色）
  usesMonospacedDigits: Bool      // 默认 true
  alignment: LineAlignment        // .leading（默认） | .center | .trailing
}

MenuBarLineSegment = .text(String) | .metric(MenuBarMetricID)
```

- 空值：某个 `.metric` 片段无有效读数 → 该片段渲染 `--`，同段其它片段照常，整行不隐藏。
- 颜色：`.inheritSource` 时每个数据源片段用自身颜色、文字片段用系统 label 色（跟随亮暗）；`.fixed` 时整行统一固定色。

### 6.4 图标规格与 tint 语义

```
MenuBarIconSpec { type: .sfSymbol(name) | .emoji(String) | .asset(name); tint: Bool }
```

首版仅内置来源（无自定义图片导入）。tint 三者语义必须区分：

- **SF Symbol**：可 tint，跟随行色（或指定色）。
- **Template 内置资源**（单色模板图）：`tint=true` 走 template image 语义，用行色绘制；`tint=false` 保留原色。
- **Emoji**：默认保留彩色、不 tint（`tint` 对 emoji 无效，设置里禁用该开关）。

因为一行可能有多个不同颜色的数据源片段，"图标是否跟随行色"要按上面语义明确，不笼统继承。

### 6.5 宽度：自适应 + 内外边距

产品决定（取代评审 P0‑1 的固定宽度方案）：

- **宽度自适应**：实例宽度 = 两行内容所需宽度的较大值 + 左右内边距 + 左右外边距。内容变宽变窄，宽度跟着变。
- 用户可调两个量：**内边距**（内容与实例边缘之间）、**外边距**（实例外侧额外留白），各自 0…24，默认内边距 0、外边距 4。
- 不做固定宽度 / 最小宽度的开关（用户明确只要自适应 + 边距）。
- 抖动缓解：数字使用等宽（tabular）字形；极端位数变化仍可能轻微变宽，属可接受。
- 两行仍共享同一实例宽度，各自按 `alignment` 对齐。

### 6.6 激活与右键模型

```
InstanceActivation =
  .none
  | .sameAsMainIcon
  | .panel(StatusPanelRoute)                 // 主面板 / 各详情页
  | .openAppSettings                         // 打开本 App 设置
  | .openActivityMonitor                     // 打开「活动监视器」
  | .openSystemSettings(SystemSettingsPane)   // 网络/蓝牙/电池/声音等，复用现有 pane 路由规则

InstanceRightClick = .sameAsMainIcon | .quickAction(MenuBarRightClickOutcome)
```

悬浮 `hoverAction` 只允许 `.none / .sameAsMainIcon / .panel(route)`；不允许会启动外部应用的 `.openXXX`（避免划一下就弹设置/活动监视器）。

## 7. 指标注册表（共享展示层）

新增 `MenuBarMetricRegistry`，**只做展示层**，不另造采集。每个条目：

- `id: MenuBarMetricID`
- 标题本地化 key
- 取值来源：硬件快照 / 网络快照 / 电池快照 / 音频快照 / 亮度
- 值类型：`numeric`（带格式化 + 单位）或 `text`（如 Wi‑Fi 连接状态）
- 格式化：百分比 / 摄氏度 / RPM / B/s / GB / 文本
- 默认颜色：复用现有解析（见 7.2）
- `HardwareMetricAvailability` → 显示映射（非 measured 一律 `--`；`measured` 的 0 显示 0）
- 采样 demand key + owner

### 7.1 指标清单（精确名）

CPU 使用率、CPU 温度、GPU 使用率、GPU 温度、内存占用、**磁盘读取速度**、**磁盘写入速度**、网络下载、网络上传、风扇转速、电池电量、**Wi‑Fi 连接状态（文本）**、输出音量、屏幕亮度。

- 磁盘拆读取/写入两条（`HardwareMetricID.diskRead/diskWrite`）。
- Wi‑Fi 做**连接状态**（文本型指标）：只显示「已连接 / 未连接」，不显示 SSID。v1 **不单独做信号强度**。
- 亮度走 `BrightnessMonitor`；`HardwareMonitorMetric` 未覆盖磁盘吞吐与亮度，注册表按现有 reader 补齐映射。

### 7.2 颜色解析（P1‑1，先复制后收敛）

- 由于现有解析在 View（`HardwareDetailView.metricColor`）内且未抽共享，本版**先复制一份最小的纯逻辑实现**给菜单栏用（recommended base + 用户 `metricColors` + 电池状态色），**不改动现有详情页行为**。
- 加 `// TODO(p3): 与 HardwareDetailView 收敛为单一来源`，后续单独重构。

### 7.3 采样 Owner 聚合（P1‑2）

- 每个启用实例作为一个需求 owner：`menuBarInstance:<UUID>`。
- 同一指标被主图标 / 多个实例订阅 → 合并为一份采样，不重复采集。
- 实例 `isEnabled=false`、用户移除、删除 → 释放该 owner，无残留。
- 实例渲染缓存随实例销毁释放。

## 8. 渲染与布局

- `MenuBarInstanceRenderer`（纯逻辑，输入实例配置 + 快照 → 绘制/测量）。状态项与设置预览**共用**同一渲染器（见 §11）。
- 逐行：可选行内图标（高度=行 cell 高、保持比例、固定间距）→ 依次画每个片段（文字 / 数值，各自颜色）→ 按 `alignment` 整串水平定位。
- 左侧列图标：独占固定列宽、垂直居中，两行都从右侧开始（与行内图标共存）。
- 两行共宽，各自在实例宽度内按 `alignment` 对齐；单行垂直居中；某行为空则只画另一行。
- 字体：等宽数字（tabular）+ 可选字号/粗体；行高按布局角色。
- 宽度恒为自适应：内容多宽实例就多宽（含内外边距），不主动截断；内容过长时由系统菜单栏空间自行处理。
- 亮暗：监听 `NSApp.effectiveAppearance` 重绘，无轮询。
- 重绘：仅当数值字符串、配置、外观或宽度策略相关输入变化才重绘；绘制合并（coalesce）。
- 无障碍：`accessibilityLabel` 读出实例名 + 两行文本，且数据源片段读「指标名 + 数值」（不能只读 `--` 或原始数字）。

## 9. 交互

### 9.1 左键 / 悬浮

- 左键按 `clickAction`：`.panel(route)` 打开面板并**锚定到该实例按钮的屏幕 rect**（非主图标 rect）；`.openAppSettings/.openActivityMonitor/.openSystemSettings(pane)` 直接调起（复用现有 `openSystemSettings` 与「System Settings Pane Routes」规则）。
- 悬浮按 `hoverAction`（仅 `.none/.sameAsMainIcon/.panel`），复用现有 hover 呈现。

### 9.2 右键（P0‑4，统一为实例菜单）

- 右键**总是弹 `NSMenu`**：
  1. 首段 = 按 `rightClick` 配置的动态项：`.quickAction(x)` → 一个用 x 标题、按可用性 enable/disable 的项；`.sameAsMainIcon` → 镜像主图标当前右键结果（其配置的快捷行为，或标准上下文菜单项）。
  2. 分隔线。
  3. 固定项：「禁用此实例」（仅禁用，保留配置，可在设置页重新启用）。
- **右键不提供删除**；删除只在设置页里做。
- 绝不让右键误触发左键动作。

### 9.3 悬浮面板状态机（P1‑5）

- 共享单个面板会话：`{ isOpen, sourceInstanceID, presentedByHover, pinned }`，同一时刻 app 内只开一个面板。
- 悬浮进入延迟开、离开延迟关；从实例按钮到面板之间的间隙视为「桥接区」，不触发关闭（防闪退）。
- 延迟关闭任务绑定会话代次（generation）；新开面板使旧任务失效（旧任务不得关掉别的实例刚开的面板）。
- 悬浮打开的面板上，点击实例按钮 = **固定（pin）**，不关闭（对齐现有 `statusItemClickAction`：presentedByHover → pin）。
- 面板锚点始终是「当前会话的实例按钮」。

### 9.4 移除与系统可见性（P0‑2）

- `isEnabled` = 应用配置：决定是否创建/保留实例、是否注册数据需求。
- `NSStatusItem.isVisible` = 系统状态：App 想不想显示；系统因空间不足挤掉时它**不会**变 false（SDK：visible "even if obscured by the application menu"）。
- 判定「用户拖出」：仅当 `isEnabled == true` 且 visible 由 true→false 且**非我方程序改动**（用抑制标记 `selfInitiatedVisibilityChange` 防自激）。命中才把该实例 `isEnabled=false` 并持久化（仅此实例）。
- 我方主动 `setVisible(...)` 一律设抑制标记，不被 KVO 误判为用户移除。
- 系统空间不足（item 未被展示但 visible 仍 true）：不释放需求、不改 `isEnabled`；设置页给宽度估算与空间不足提示。
- 实现期需验证：个别系统上空间不足是否也会把 visible 置 false / button.window 失联。若会，改用「button.window 失联 + 用户手势」作为附加判据，避免误判。此点列为实现期必验项。

## 10. 持久化与启动（P1‑7）

- `MenuBarInstancesConfiguration` 保序存 `SettingsStore`；启动按数组顺序 create，`autosaveName` 用稳定 id。
- 位置归 macOS：只承诺「尽可能恢复」，不承诺跨重启稳定。
- 删除实例才真正 `remove` 并清 autosave；普通禁用只 `setVisible(false)`（保留 slot，避免位置丢失——fund01 教训）。删除的 UUID 不复用。
- 不依赖、不清理系统 `NSStatusItem` 的私有 autosave 存储。
- 默认实例数组为空 → 行为与现在完全一致。

## 11. 设置界面

- 新增**顶级侧栏分类**「菜单栏实例」（`SettingsView.Section` 新 case + `SettingsNavigationModel` + 本地化）。
- 实例列表：拖动排序、启用开关、复制、删除；点开进入编辑器。
- 编辑器：
  - 两行实时预览：**复用 `MenuBarInstanceRenderer` + mock 快照**，不创建真实状态项、不注册采样（P1‑4）。
  - 每行**可视化 chip 编辑器**：加「文字」块 / 加「数据源」块、拖拽排序、删除、编辑文字内容。
  - 行级：图标（内置来源）、颜色（继承/固定）、粗体/字号/对齐。
  - 实例级：内边距 / 外边距、左键/悬浮/右键行为。
- 预设一键添加：CPU、温度、内存、网速、电池等（只填配置，不产生隐藏副作用）。
- 上限 20 只是配置上限；列表顶部显示宽度估算与「菜单栏可能放不下」提示（P1‑6）。
- 全部文案走 `LocalizationKey`；改动实时生效（无独立「保存」）。

## 12. 设置 / 导出接入（项目硬规则）

- `SettingsSemanticCatalog` 增加菜单栏实例描述（类型、默认、约束、`accessPolicy`）。
- `SettingsPreferenceCatalog`：菜单栏实例**属于**可导出/导入用户配置，纳入白名单，实现校验/读/写/round‑trip 测试；导入非法用默认 + 警告；导入 >20 整份拒绝并提示。
- 更新 `docs/settings/settings-inventory.md` 与生成的 schema / skill 产物。

## 13. 性能红线

- 采样需求按「主图标 + 所有启用实例」引用计数聚合；禁用/移除/删除即释放；无无主采样。
- 配置上限 20；绘制仅在输入变化时进行；格式化稳定避免抖动。
- 不新增轮询、动画、日志、缓存或后台工作，除非有明确 owner 与 stop path。

## 14. 测试与验收矩阵

- 单元：注册表映射/格式化（含文本型 Wi‑Fi 状态）、自适应宽度 + 内外边距测量、多片段拼接与排序、`--` 分支、颜色解析（继承/固定/阈值）、配置 `Codable` 往返、导出/导入 round‑trip、采样 owner 聚合。
- 控制器：创建/删除/启用禁用/排序、`autosaveName`、拖出仅隐藏本实例、程序改 visible 不误判、禁用释放需求、系统空间不足不误判。
- 渲染：两行 + 行内图标 + 列图标 + 单行 + 空行 + 亮暗 + Retina 2x 的快照/指纹（参考 `Issue30WiFiAlignmentTests`）。
- 面板：实例点击/悬浮锚定自身 rect；悬浮多实例互斥；hover→click pin；gap 桥接不闪退。
- 真实状态项/窗口 UI 测试走 `VisibleUITestCase` 边界，默认跳过。
- 交付前：`bash scripts/verify-local.sh full`（图标/场景渲染属高风险）。

## 15. 实现顺序（内部，不含独立原型门禁）

用户决定：不单独做原型、直接全量实现、次日验收。内部按依赖顺序推进：

1. 数据模型 + 配置版本/校验 + 指标注册表 + 颜色最小实现。
2. `MenuBarInstanceRenderer`（纯函数，先能出预览图）。
3. 状态项管理器（create / width / setVisible / removal 判定）。
4. 交互（左右键、hover 状态机、面板锚定）。
5. 采样 owner 聚合。
6. 设置页 + chip 编辑器 + 预览。
7. 导出/导入 + 语义目录 + inventory 文档。
8. 测试 + `verify-local.sh full` + 交付说明。

## 16. 本轮已确认决策

- 不做独立原型，直接全量实现，次日验收。
- 颜色解析**先复制最小实现，后续收敛**（不动现有详情页）。
- Wi‑Fi 做**连接状态**（文本：只显示「已连接 / 未连接」，不显示 SSID）；v1 不做信号强度。
- 宽度自适应，用户只可调内边距 / 外边距；不做固定/最小宽度。
- 右键只可「禁用此实例」；删除只能在设置页做。
- 导入 >20 整份拒绝并提示；实例 UUID 删除后不复用。
- 设置入口为新顶级分类「菜单栏实例」。

## 17. 评审意见处理对照

| 评审项 | 处理 |
|---|---|
| P0‑1 宽度策略 | **部分采纳（用户决定）**：不做固定/最小宽度，改为自适应宽度 + 可调内/外边距 |
| P0‑2 启用 vs 系统可见 | 采纳：`isEnabled` 与 `isVisible` 分离 + 抑制标记 + 空间不足不误判 |
| P0‑3 原型先行 | **不采纳（用户决定）**：直接全量实现，次日验收 |
| P0‑4 右键语义 | 采纳：统一实例菜单（动态首项 + 编辑/删除） |
| P1‑1 指标注册表展示层 | 采纳：只做展示层；颜色先复制后收敛 |
| P1‑2 采样 owner 聚合 | 采纳 |
| P1‑3 布局/图标 tint | 采纳：共宽/单行居中/截断 + 三种 tint 语义 |
| P1‑4 预览复用渲染器 | 采纳：mock 快照、不建真状态项、不注册采样 |
| P1‑5 悬浮状态机 | 采纳：sourceInstanceID + 代次失效 + 桥接 + pin |
| P1‑6 20 只是配置上限 | 采纳：宽度估算 + 空间提示 |
| P1‑7 位置归 macOS | 采纳：只承诺尽力恢复、UUID 不复用、不碰私有存储 |
| P1‑8 配置版本与校验 | 采纳：`schemaVersion` + 校验 + 迁移 |
| P2 `--` 语义 / 无障碍 / 验收矩阵 | 采纳：0 显示 0、stale 不冒充、读出指标名+值、验收矩阵 |
