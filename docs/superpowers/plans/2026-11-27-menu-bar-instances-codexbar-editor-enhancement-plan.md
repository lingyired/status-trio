# Status Trio 菜单栏自定义实例：CodexBar 编辑器与渲染增强 Plan

- 目标分支：`dsh-22af0bcb-5a55`
- 基线：`main`（本次检查时分支领先 12 commits、落后 0 commits）
- 类型：现有功能的增量完善，不重新实现多实例基础架构
- 状态：待执行
- 相关现有文档：
  - `docs/superpowers/plans/2026-11-27-menu-bar-instances.md`
  - `docs/superpowers/specs/2026-11-27-menu-bar-instances-design.md`
  - `docs/menubar-instances-acceptance.md`

## 1. 目标

在保留当前分支已经完成的多实例运行时、指标注册表、采样需求、面板路由和配置持久化的基础上，将菜单栏实例设置页完善为用户已确认的自由组合编辑器，并借鉴 CodexBar 已验证的 SwiftUI 拖拽与 AppKit 富文本渲染实现。

最终体验必须满足：

1. 用户可以随意新建多个独立菜单栏实例，不必先选择 CPU、内存等预设。
2. 设置页保留已经确认的三栏布局：左侧实例列表、中间布局编辑器、右侧元素 / 数据源库。不改成 CodexBar 的单栏布局，也不重做 HTML Demo 已确认的交互结构。
3. 中间编辑器允许单行或双行；布局模式放在编辑器顶部显眼位置。
4. 用户可以从右侧数据源库拖动任意指标到上行或下行，并可拖动调整顺序、跨行移动、删除。
5. 数据源元素进入菜单栏后只显示该指标的值，不自动附加指标名称。例如 CPU 使用率只显示 `35%`；需要 `CPU` 文字时，由用户另外拖入自定义文字元素。
6. 用户可以创建任意文字元素、选择图标元素，并像指标一样拖入任意行、调整顺序。
7. 选中元素后可以编辑其内容 / 图标；行级样式和实例级样式仍有清楚的设置入口。
8. 菜单栏实际渲染和设置预览共用同一套数据解析与布局规则。
9. 不改变 Status Trio 主图标、Dock 图标、现有硬件采样体系和既有状态面板功能。

## 2. 当前分支审查结论

### 2.1 已有实现，应保留并完善

当前分支已经包含以下基础，不应在本次工作中重新造一套：

- `MenuBarInstanceModels.swift`：实例、行、文字 / 指标片段、颜色、图标、点击与悬浮动作、配置校验。
- `MenuBarMetricRegistry.swift` 与 `MenuBarMetricValueProvider.swift`：从已有硬件与状态快照读取数据并格式化，不单独采样。
- `MenuBarMetricColorResolver.swift`：菜单栏指标颜色解析的初步实现。
- `MenuBarInstancesController.swift`：每个实例一个 `NSStatusItem`，独立 autosave 名称，启用 / 禁用与删除分离。
- `MenuBarInstancesRuntime.swift`：把设置、实时快照、菜单栏状态项和点击动作连接起来。
- `MenuBarInstanceActivation.swift` 与 `StatusBarController.presentInstancePanel(...)`：复用现有状态面板路由，并按被点击实例按钮定位。
- `SettingsStore`、`SettingsSemanticCatalog`、`SettingsPreferenceCatalog`：实例配置持久化、语义描述与导入导出已经接入。
- 多个模型、Renderer、Controller、采样需求、动作路由和设置传输测试已经存在。

### 2.2 与最终目标之间的主要差距

| 区域 | 当前分支实际情况 | 本 Plan 的目标 |
|---|---|---|
| 实例创建 | 设置页主要提供 CPU / 温度 / 内存 / 网速 / 电池预设 | 首要入口是「新建空白实例」，预设仅作为快捷模板 |
| 设置 UI | 实例 List + 单独 Editor Sheet | 保留三栏：实例 / 编辑画布 / 元素库 |
| 数据源添加 | 行内 `Menu("Add data source")` | 右侧数据源库，支持拖动与点击添加 |
| 元素拖拽 | 当前没有 `.draggable` / `.dropDestination`；主要靠 Context Menu 的 Move left/right | 参考 CodexBar 的 Transferable + dropDestination + 纯函数 mutation |
| 自定义文本 | 有 `.text(String)` 模型和添加入口，但不是可拖动的 palette item | 右侧创建文本元素，再拖入画布；内容可编辑 |
| 图标 | 目前是 `MenuBarLine.icon` / `leadingIcon` 属性，不是可插入任意位置的独立元素 | 图标作为可拖动元素，可插入指标与文字之间 |
| 布局模式 | `top` / `bottom` 可选，单行可由缺少一行表达，但 UI 没有顶部单行 / 双行切换 | 显式 `singleLine` / `doubleLine` 控件，切换不丢失另一行内容 |
| 行样式 | Model 有部分样式字段和 setter，但 Editor UI 没完整呈现 | 选中行时可编辑颜色、字号、粗体、等宽数字、对齐、行图标 |
| 元素属性 | 没有统一的 selected element inspector | 选中文字 / 图标后可编辑其内容和图标属性 |
| Renderer | 当前返回 raster `NSImage` 并赋给 `NSStatusBarButton.image` | 验证 CodexBar 的 `NSAttributedString` / `attributedTitle` 路线，优先降低自绘复杂度 |
| 颜色 | Renderer 调用颜色解析时传入空的 overrides | 接入 Status Trio 用户指标颜色设置，继承色与固定色按配置生效 |
| 几何 | leading icon 宽度参与测量，但绘制起点未避开该列；outer margin 计入宽度却未正确偏移绘制起点 | 测量与绘制使用统一几何结果，修复重叠和边距偏差 |
| Retina | Renderer 的 `scale` 参数没有实际参与图像表示创建 | 使用 attributedTitle 时由 AppKit 排版；若保留 raster fallback，明确处理 backing scale |
| 可见性 | Tracker 有纯逻辑和测试，但 Controller / Handle 没有接入实际 `NSStatusItem.isVisible` KVO 观察 | 接入真实可见性观察，程序主动修改与用户拖出必须区分 |
| Hover | StateMachine 有模型和测试，但 Runtime 仅有 mouse-enter；没有完整 enter/exit 延迟和面板桥接生命周期 | 把状态机接入真实事件，保证互斥、延迟关闭、点击 pin 和跨实例切换 |
| 采样 | Runtime 通过 `.menuBarCenter` 汇总所有启用实例指标，能避免同一指标重复订阅；另有 `MenuBarInstanceDemandCoordinator`，但 Runtime 未使用 | 保留一个清晰、真实接入的聚合需求策略，不保留未接线的重复抽象 |
| 生命周期 | Runtime 持有 Combine subscriptions / Tracking Areas；未见完整 stop 清理链 | 增加明确 stop / cleanup，并由 AppEnvironment 生命周期调用 |
| 本地化 | 新 Editor 有多处硬编码英文 | 新增 UI 文案全部走 `LocalizationKey` 和现有语言资源 |

### 2.3 已发现的 Renderer 几何问题

当前 `MenuBarInstanceRenderer.measure` 中：

- `leadingIcon` 的宽度加进 `contentWidth`；
- 但 `render` 中每行的 `lineRect.minX` 仍从内容区左边缘开始；
- `draw(line:)` 也从 `rect.minX` 开始，未加 leading icon column width。

结果是左侧列图标可能覆盖第一行或第二行内容。

另外：

- `outerMargin` 加入 `totalWidth`，但绘制内容的起始 X 没有加 outer margin；
- `line.icon` 绘制总是使用 label color，无法完整遵循 `.inheritSource` / `.fixed`；
- `MenuBarMetricColorResolver.sourceColor` 目前收到的 `overrides` 是空字典，因此用户的指标自定义颜色没有进入该 Renderer；
- `scale` 参数没有在 raster 输出里实际使用；
- Runtime 的 `renderAll()` 在硬件 / 状态快照每次发布时都会为所有内容实例重新 measure + rasterize，没有按实例签名跳过未变化渲染。

这些问题需要在扩展图标元素和三栏 UI 前先处理，避免把旧几何问题带进新功能。

## 3. CodexBar 借鉴范围

CodexBar 当前为 MIT License。可以参考并在必要时移植小段实现，但不要把 CodexBar 作为依赖，也不要直接复制整套 provider-specific 布局实现。若复制实质性代码，必须在项目第三方声明中保留 MIT copyright / license notice。

重点参考：

1. `MenuBarLayoutEditor.swift`
   - `MenuBarLayoutPosition`：以 line + index 表达放置位置。
   - `MenuBarLayoutDragItem`：区分 Palette 新元素和已有元素，并携带来源信息。
   - `MenuBarLayoutEditorMutations`：把 append / insert / move / remove / addLineBreak / removeLineBreak 做成纯逻辑函数。
   - `sourceLayout` 校验：拖动过程中配置已变化时拒绝过期 drop。
2. `MenuBarLayoutEditorChip.swift`
   - Chip 用普通 View + `.draggable`，而不是让 Button 抢占鼠标拖拽手势。
   - 保留点击添加、键盘激活、Delete 删除与 VoiceOver 操作。
3. `MenuBarLayoutRenderer.swift`
   - 通过 `NSAttributedString` 组合每个元素独立的字体、颜色和 NSTextAttachment。
   - 用真实 attributed content 测量整体宽度。
   - 用换行符与 paragraph style 处理双行行高和垂直基线。
   - 返回渲染结果对象，由调用方决定写入 attributedTitle、leading image 或兼容 fallback。
4. `StatusItemController+MenuBarLayout.swift`
   - 在 `NSStatusBarButton` 上应用 `attributedTitle`、imagePosition、accessibility title 和 status item width。

CodexBar 参考源码（审查时的上游 commit）：

- [MenuBarLayoutEditor.swift](https://github.com/steipete/CodexBar/blob/a26ca57b518667a659d69524c473af2735069612/Sources/CodexBar/Menu/MenuBarLayoutEditor.swift)
- [MenuBarLayoutEditorChip.swift](https://github.com/steipete/CodexBar/blob/a26ca57b518667a659d69524c473af2735069612/Sources/CodexBar/Menu/MenuBarLayoutEditorChip.swift)
- [MenuBarLayout.swift](https://github.com/steipete/CodexBar/blob/a26ca57b518667a659d69524c473af2735069612/Sources/CodexBar/Menu/MenuBarLayout.swift)
- [MenuBarLayoutRenderer.swift](https://github.com/steipete/CodexBar/blob/a26ca57b518667a659d69524c473af2735069612/Sources/CodexBar/Menu/MenuBarLayoutRenderer.swift)
- [StatusItemController+MenuBarLayout.swift](https://github.com/steipete/CodexBar/blob/a26ca57b518667a659d69524c473af2735069612/Sources/CodexBar/StatusItem/StatusItemController%2BMenuBarLayout.swift)
- [CodexBar LICENSE](https://github.com/steipete/CodexBar/blob/main/LICENSE)

不复制 CodexBar 的 `UsageProvider`、`UsageSnapshot`、provider override、quota conditional 等业务模型。Status Trio 继续使用自己的 `MenuBarMetricRegistry` / `MenuBarMetricValueProvider`。

## 4. 最终 UI 结构（必须保留三栏）

### 4.1 顶部工具条

编辑器最顶部提供：

- 当前实例名称 / 重命名；
- 布局模式 Segmented Control：`单行` / `双行`；
- 当前实例启用状态；
- 可选的预览外观切换（跟随系统 / 浅色 / 深色，仅影响预览）。

布局模式不放在右侧样式选项深处，必须一眼可见。

### 4.2 左栏：实例管理

- 显示实例列表，每项包含名称、启用开关和紧凑内容预览。
- `+` 默认创建空白实例，不预先塞入 CPU 标签或某个指标。
- 保留可选预设入口（CPU、温度、内存、网速、电池），预设只是快捷模板，不是唯一创建方式。
- 支持选择、重命名、拖动排序、复制、删除、启用 / 禁用。
- 配置上限继续为 20；超限时给出明确反馈。
- 左栏排序只影响设置页实例顺序；菜单栏实际位置仍由 macOS / autosave 管理，不承诺设置列表顺序强制覆盖用户在菜单栏中的手动位置。

### 4.3 中栏：布局编辑画布

- 顶部显示使用真实 Renderer 规则生成的菜单栏预览。
- 单行模式只展示一个 drop row；双行模式展示上行、下行两个 drop row。
- 每行显示可拖动的元素 Chip。
- 从右栏拖入新元素：创建副本并插入目标位置。
- 在画布内拖动已有元素：移动原元素；支持同行排序、上行到下行、下行到上行。
- 支持点击 Palette 元素添加，作为拖拽的无障碍 / 触控板替代操作。
- 选中 Chip 后可编辑：
  - metric：只编辑该元素的显示格式（如精度 / 单位选项，若该指标支持）；不能自动插入指标名称；
  - text：编辑任意文字；
  - icon：选择 / 更换 SF Symbol、Emoji 或内置 Asset，并设置 tint。
- 选择行空白区域时显示行级属性：继承数据源颜色 / 固定颜色、字号、粗体、等宽数字、对齐、行图标。
- 实例级属性（左侧列图标、内外边距、点击 / 悬浮行为）放入独立的折叠设置区，避免挤占主要编辑画布。
- 提供明显的删除 drop target；选中元素可用 Delete 删除。

### 4.4 右栏：元素 / 数据源库

分组展示，但不是一个个监控功能开关：

**数据源**

- CPU：使用率、温度。
- GPU：使用率、温度。
- 内存：使用率。
- 磁盘：读取速度、写入速度。
- 网络：下载速度、上传速度。
- 风扇：转速。
- 电池：电量。
- Wi-Fi：连接状态（沿用现有 v1 定义；不擅自加入 SSID / RSSI）。
- 音量：输出音量。
- 亮度：屏幕亮度。

数据源库的标签是供用户识别的名称；拖入画布后，该元素只表示指标值。状态项最终输出不得自动拼接 `CPU`、`RAM`、`Download` 等名称。

**自定义文字**

- 提供输入框与「创建文字元素」操作。
- 用户可以输入任意单行文字（包括空格、标点和单位）。
- 创建后形成可拖动 Chip；点击画布 Chip 可继续编辑。
- 延续配置约束：文本长度最多 64 字符；拒绝或清理换行符，避免一个元素意外破坏两行结构。

**图标**

- 提供 SF Symbols 搜索 / 选择器。
- 提供 Emoji 输入或选择入口。
- 内置 Asset 可以列入资源分类。
- 选择后的图标形成独立 Palette Chip，可拖入任意行、任意位置，不只作为行头或实例左侧列图标。
- 不做用户图片文件导入（沿用当前 v1 范围）。

右侧 Palette 应支持搜索或分类折叠，避免数据源、SF Symbols 和 Emoji 数量增加后无法浏览。

## 5. 数据模型调整

### 5.1 显式布局模式

新增：

```swift
enum MenuBarLayoutMode: String, Codable, CaseIterable, Sendable {
    case singleLine
    case doubleLine
}
```

在 `MenuBarInstance` 增加 `layoutMode`。

规则：

- `singleLine` 只渲染上行；下行已有内容保留在配置中，切回 `doubleLine` 时恢复，不因切换模式而丢失。
- `doubleLine` 渲染上行和下行；允许某一行为空，但空行不应留下额外空白高度。
- 旧配置没有 `layoutMode` 时，根据原有 top / bottom 内容推导：bottom 有可见内容 → `doubleLine`，否则 `singleLine`。
- 新建空白实例默认 `singleLine`。

### 5.2 将元素提升为可识别对象

当前 `MenuBarLineSegment` 只有 `.text` / `.metric`，而图标存放在 `MenuBarLine.icon` 或 `MenuBarInstance.leadingIcon`。这不足以表达「一个图标 Chip 可以插在两个指标之间」。

建议引入：

```swift
struct MenuBarElement: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var content: MenuBarElementContent
}

enum MenuBarElementContent: Codable, Equatable, Sendable {
    case metric(MenuBarMetricID)
    case text(String)
    case icon(MenuBarIconSpec)
}
```

`MenuBarLine` 改为保存有序 `elements: [MenuBarElement]`。每个元素有稳定 UUID，解决重复指标 / 重复文字时无法可靠选中、移动和删除的问题。

迁移要求：

- 为配置 schema 升级到 v2（或项目统一认可的下一个版本）。
- 旧 `segments: [.text, .metric]` 解码后转换为拥有新 UUID 的元素。
- 原 `MenuBarLine.icon` 保留并映射为兼容的行首图标，或在解码迁移时转成首位 `.icon` 元素；二选一后统一编码格式，不要长期维持两套可编辑图标入口。
- `MenuBarInstance.leadingIcon` 作为实例级左侧列图标可以保留，因为它与行内图标用途不同。
- 旧 `top` / `bottom`、颜色、字号、对齐、padding、margin 和 click / hover 配置必须保留。
- 新配置只写 v2 结构；解码兼容现有 v1 结构。

### 5.3 元素与显示语义

- `.metric(id)`：渲染对应 reading 的 `text`，不拼接指标名。
- `.text(value)`：原样渲染用户输入内容。
- `.icon(spec)`：渲染图标附件或等价图形，不自动添加文字。
- 重复 metric 是合法的，每个实例和每个元素都独立存在。
- `MenuBarMetricAvailability` 非 `.measured` 时仍显示 `--`；真实 0 保留为 `0`。
- `stale` 不得显示为看似实时的旧值。

## 6. 拖拽引擎（参考 CodexBar）

新增独立的纯逻辑模块，例如：

- `MenuBarElementDragItem.swift`
- `MenuBarInstanceEditorMutations.swift`

拖拽数据至少表达：

- Palette 新元素 / 已放置元素两种来源；
- 放置元素的 `elementID`、源 `instanceID`、源行；
- 必要时携带源布局快照或 revision，避免拖动期间配置已经变化时误移动错误元素。

Mutation API 建议覆盖：

```swift
appendPaletteElement(_:to:)
insert(_:at:in:)
move(elementID:to:in:)
remove(elementID:from:)
setLayoutMode(_:for:)
```

约束：

- Palette drop = copy / create new element ID；
- Canvas drop = move existing element，不能因为重复 metric 而误删另一个相同指标；
- 拖拽到同一位置应返回无变化；
- 同行前后移动时正确修正目标索引；
- 跨行移动正确处理源行变空；
- 单行模式不能接受下行 drop；
- 无效或过期 source、超出每行元素数限制、未知 metric 均安全拒绝；
- 删除最后一个元素允许形成空行；
- 每次 mutation 只通过 `SettingsStore.updateMenuBarInstance` / 统一配置更新入口持久化。

SwiftUI 实现借鉴 CodexBar：

- Chip 使用普通 `View`，避免 Button 手势抢占 drag session；
- 使用 `Transferable` / `UTType` 表达拖拽 payload；
- `.draggable` 用于 palette 和 canvas 元素；
- `.dropDestination` 用于每行、每个 Chip 之间和删除区；
- 保留点击添加、键盘激活、Delete 和 VoiceOver actions。

本项目部署目标 macOS 13；所有使用的 SwiftUI / CoreTransferable API 必须确认 macOS 13 availability，不允许只按 CodexBar 当前 macOS 版本直接照搬。

## 7. Renderer 技术调整：先验证，再确定主路径

### 7.1 现状

当前 `MenuBarInstanceRenderer`：

- 自己 measure；
- 自己用 AppKit 绘制为 `NSImage`；
- `MenuBarInstancesController.update` 将结果赋给 `NSStatusBarButton.image`。

与原实现计划中的 custom subview 不同，当前真正落地的是 raster image 路线。

### 7.2 首选验证 CodexBar 的 attributedTitle 路线

新增一个小型技术验证 / renderer adapter，不要直接整体复制 CodexBar Renderer：

```swift
struct MenuBarRenderedContent {
    var attributedTitle: NSAttributedString
    var leadingImage: NSImage?
    var accessibilityLabel: String
    var measuredWidth: CGFloat
    var measuredHeight: CGFloat
}
```

验证 `NSStatusBarButton.attributedTitle` 能否满足：

- 单行和双行；
- 每行不同字号、粗体、颜色和对齐；
- 同一行多段不同颜色；
- 数字 tabular figures；
- inline SF Symbol / Emoji / Asset；
- 实例左侧列图标；
- 可变内容宽度和两行共宽；
- macOS 13、15、26+；
- 菜单栏亮 / 暗外观、非激活显示器、高对比度；
- 点击区域、右键、hover tracking 和用户拖出行为。

建议结构：

- 文本与数值用 `NSAttributedString`；
- inline icon 用 `NSTextAttachment` 或经验证的 attachment image；
- leading column icon 可以继续使用 `NSStatusBarButton.image`，并正确设置 `imagePosition`；
- 每个 paragraph 使用独立 paragraph style / line height / alignment；
- 使用最终 attributed string 的 bounding rect 测宽；
- `statusItem.length` = 测得内容宽度 + inner / outer margins。

如果上述能力通过 macOS 13+ 测试，优先把它作为真实菜单栏渲染主路径。不要为了沿用旧 `NSImage` 实现而忽略 CodexBar 已验证的 AppKit 原生文本排版能力。

### 7.3 Raster fallback 的保留条件

只有在 attributedTitle 无法满足具体需求（必须写出测试证明的限制）时，才保留或修复 NSImage raster 路线。

若保留 raster：

- 统一 measure 与 draw 的同一套 `MenuBarInstanceGeometry`；
- 内容起点必须同时考虑 outerMargin、innerPadding、leading icon column；
- 行内 icon 宽度必须参与行宽；
- 两行总宽为 max(topWidth, bottomWidth) + 2 * (innerPadding + outerMargin)；
- 每行 alignment 在扣除 leading column / row icon 后的内容区域计算；
- `scale` 必须真正决定 bitmap representation 尺寸；
- 外观、颜色、图标 tint 与高对比度需要有可预测结果；
- image 变为 nil 时清理旧 button image，不得留下上一次输出；
- 增加有上限的 cache，并在实例删除、配置变化或外观变化时正确失效。

### 7.4 颜色与格式化

- `MenuBarMetricValueProvider` 继续只从现有 snapshots 读取，不新增 reader 或轮询。
- `MenuBarMetricColorResolver` 必须接收 `SettingsStore.hardwareMonitorMetricColors` 等现有用户颜色覆盖，不能继续传空字典。
- `.inheritSource`：metric 元素使用数据源颜色；text 元素使用系统 label color；icon 根据 tint 语义处理。
- `.fixed`：行内 text / metric / 可 tint icon 使用该行固定颜色；Emoji 保留原始彩色。
- 颜色解析最终应和 Status Trio 现有硬件卡片 / 圆环颜色定义一致。可以先保留当前 resolver，但本次不能让用户自定义颜色在菜单栏失效。
- 所有格式化复用 `MenuBarMetricRegistry` / 现有 Formatter，不在 Renderer 中另写第二套单位格式。

## 8. Runtime / Controller 补齐

### 8.1 Status item 内容应用

- 将 `MenuBarInstancesController.update` 从简单的 `image + width` 扩展为统一 rendered content 应用。
- 使用 `NSStatusBarButton.attributedTitle` / image / imagePosition（若 Phase 7 验证通过）。
- 每个实例仍然拥有独立 `NSStatusItem` 和稳定 autosaveName。
- 主图标保持完全不变。
- 禁用保留实例配置与 autosave slot；删除才真正移除实例状态项。

### 8.2 用户拖出监听

当前 `notifyExternalVisibilityChange` 只是测试入口；`MenuBarStatusItemHandle` 没有暴露观察接口，Runtime 也没有注册真实 KVO。

需要：

- 在真实 handle 中为 `NSStatusItem.isVisible` 注册并持有 observation；
- Controller 将外部 visibility transition 送入 `MenuBarInstanceVisibilityTracker`；
- 程序主动 setVisible 必须有可靠抑制机制，不能将自己的写操作误判为用户拖出；
- 用户拖出只禁用对应实例；
- 菜单栏空间不足导致的遮挡不能被视为用户移除；
- 删除 / stop 时释放 observation。

### 8.3 Hover 状态机接入

当前 `MenuBarHoverPanelStateMachine` 只有纯模型和测试，Runtime 没有实际使用；Runtime 只安装 enter tracking，并立即调用 `presentInstancePanel`。

需要：

- 安装 enter / exit tracking；
- 使用明确的 dwell delay；
- enter / exit 的延迟任务绑定 generation；
- 从实例按钮移动到共享面板的过渡区不能提前关闭；
- 同时只允许一个实例拥有共享面板；
- A 实例面板打开后，hover / click B 应切换或按状态机规则 pin / close，不可简单因为 `isStatusPanelShown` 就忽略 B；
- hover 面板内点击交互控件或点击触发实例时，按现有 Status Trio hover panel 语义转为 pinned；
- 新会话必须使旧实例的 delayed close 失效。

优先复用 `StatusBarController` 已有 hover / pin / panel 生命周期能力，避免再造一套与主图标 hover 行为冲突的机制。

### 8.4 右键行为对齐

本分支当前 Implementation Plan Goal / §16 与 acceptance 文件将右键定为「禁用此实例」，但模型中仍保留 `InstanceRightClick.quickAction`，也有 `MenuBarInstanceRightClickMenu` descriptor；Runtime 实际只创建 Disable 菜单，设置 UI 也没有右键配置。

本次按该分支较新的明确产品决策执行：

- 右键菜单只显示「禁用此实例」；
- 删除仍只在左侧实例管理区完成；
- 清理未使用的 quickAction 配置与 descriptor，或将其明确标记为未来功能，不能让持久化模型暗示 UI 支持实际上不存在的行为；
- 不擅自增加快捷动作菜单。

### 8.5 需求聚合与 Runtime 生命周期

- 当前 Runtime 使用 `.menuBarCenter` 作为所有启用实例硬件指标的聚合需求，逻辑上能避免相同指标重复读取；`MenuBarInstanceDemandCoordinator` 存在但没有接入 Runtime。
- 本次选择一种真实策略：优先保留单一 `.menuBarCenter` 聚合 owner（因为 `HardwareMetricsService.Demand` 已为该 surface 预留独立需求 ID），每次配置变更重新计算所有启用实例的指标并一次性更新；移除未接入的伪 per-instance coordinator，避免双重抽象。
- 如果未来确有逐实例诊断需求，再统一扩展 HardwareMetricsService 的 owner 模型；本次不为形式上的 UUID owner 增加复杂度。
- `renderAll` 只渲染启用且有内容的实例；禁用状态项不需要继续生成图片。
- 按实例生成 render signature；只有配置、有效 readings、外观、颜色设置或渲染参数变化时才重新 render。
- 多次连续 snapshot 更新应合并到一次 MainActor render pass；不新增独立轮询。
- 删除实例时清理 button / tracking area / visibility observation / render cache。
- `MenuBarInstancesRuntime` 增加 `stop()`：取消 Combine subscriptions、结束 `.menuBarCenter` demand、清理所有跟踪与 status items；由 `AppEnvironment.stop()` 调用。
- 监听系统外观变化；即使硬件数据未变化，light / dark / contrast 切换也必须触发正确重绘。

## 9. 设置与持久化

- 保留当前 `menuBarInstances.v1` 的解码能力，迁移到新 schema 后使用明确版本号和迁移测试。
- `SettingsStore` 继续作为唯一配置写入入口；不要让 View 直接修改 UserDefaults。
- 每个 mutation 做完后统一 normalize / validate；限制：实例 ≤20、每行元素 ≤32、文字 ≤64、padding / margin 0…24、合法字号范围、可解析图标。
- 单行 / 双行切换时保留未显示行内容。
- `SettingsPreferenceCatalog` 继续支持导出 / 导入，并加入新 schema round-trip / downgrade tolerant tests。
- `SettingsSemanticCatalog` 更新布局模式、元素 / 样式设置的描述、约束与 accessPolicy；不要把每个 data-source token 变成一个全局启用开关。
- 更新 `docs/settings/settings-inventory.md` 和生成的 settings schema / skill reference。
- 所有 UI 字符串使用 LocalizationKey，更新全部现有语言资源；不要沿用当前 Editor 的硬编码英文。

## 10. 推荐实施阶段

### Phase 0：锁定分支基线与验证入口

- [ ] 确认工作区干净，当前 HEAD 仍是 `dsh-22af0bcb-5a55`。
- [ ] 读取并遵守 `.agents/rules/rendering.md`、设置 UI 和 SwiftUI drag/drop 相关 skill / rules。
- [ ] 运行现有 MenuBar 相关测试过滤器，记录当前通过 / 失败，不修改测试来规避已有失败。
- [ ] 确认原 `2026-11-27-menu-bar-instances` Plan 与本增量 Plan 的职责：原 Plan 记录既有基础实现，本 Plan 只处理差距。

### Phase 1：模型升级

- [ ] 新增显式 `MenuBarLayoutMode`。
- [ ] 新增带 UUID 的 `MenuBarElement` 与 `.metric / .text / .icon` 内容。
- [ ] 增加 v1 → v2 migration，旧 segments 和行图标配置不丢失。
- [ ] 更新默认空白实例、可见内容判断、allMetrics / demandedMetrics。
- [ ] 增加单行 / 双行、重复指标、重复文字、icon element、旧配置迁移、无效内容校验测试。

### Phase 2：Renderer 技术验证与几何修复

- [ ] 建立最小 `NSAttributedString` renderer spike，使用真实 `NSStatusBarButton.attributedTitle`。
- [ ] 比较当前 raster image 与 attributedTitle 在两行、颜色、字体、SF Symbol、Emoji、边距、亮暗、Retina 和 macOS 13+ 的表现。
- [ ] 根据验证结果确定主路径；优先 attributedTitle，不满足时才保留修复后的 raster fallback。
- [ ] 修正 leading icon / outer margin / inner padding 的统一几何。
- [ ] 接入用户指标颜色覆盖与 tint 语义。
- [ ] 增加渲染 snapshots / attributed string attributes / measured width tests。

### Phase 3：拖拽 mutation engine

- [ ] 引入 Transferable drag payload 和稳定元素 ID。
- [ ] 实现 Palette copy、画布内 move、同一行排序、跨行移动、删除和 stale drop 拒绝。
- [ ] 实现单行模式 drop 规则。
- [ ] 采用普通 View Chip，支持拖动 + 点击添加 + 键盘 / VoiceOver 操作。
- [ ] 增加纯逻辑 mutation 单元测试；不把复杂索引规则写在 SwiftUI View 里。

### Phase 4：三栏 Settings UI

- [ ] 把当前实例 List + Editor Sheet 改为三栏持续编辑布局。
- [ ] 左栏增加空白实例、预设、复制、重命名、排序、启用 / 禁用、删除。
- [ ] 中栏实现顶部单行 / 双行切换、实时预览、可拖拽的行画布、选中元素编辑器。
- [ ] 右栏实现指标库、任意文字创建、SF Symbol / Emoji / Asset 图标库。
- [ ] 数据源 Palette 拖入后只插入 metric 元素，不附带名称文字；所有名称只有用户主动拖入 text 才会出现在菜单栏。
- [ ] 行样式和实例样式控件接入已有 model 字段。
- [ ] 增加空状态、搜索、分类折叠、超限提示和多语言。

### Phase 5：Runtime / AppKit 集成

- [ ] 将新 Renderer 输出应用到 NSStatusBarButton；保留每个实例独立 NSStatusItem。
- [ ] 实际接入 `isVisible` KVO，并验证用户拖出只影响单个实例。
- [ ] 接入 hover state machine：延迟进入 / 离开、桥接区、共享面板互斥、点击 pin、跨实例切换。
- [ ] 右键固定为禁用当前实例，并清理模型与真实行为不一致的未用代码。
- [ ] Runtime 按启用实例的指标集合聚合 `.menuBarCenter` demand；保持现有硬件采样单一来源。
- [ ] 增加 render signature / coalescing / 外观变化刷新，跳过禁用项。
- [ ] 增加 Runtime stop / cleanup，并从 AppEnvironment.stop 调用。

### Phase 6：配置 / 质量 / 验收

- [ ] 完成 SettingsSemanticCatalog、PreferenceCatalog、schema、inventory 和 transfer migration。
- [ ] 完成所有新增本地化文案。
- [ ] 运行全部 MenuBar 相关单元测试和设置传输测试。
- [ ] 运行 `bash scripts/verify-local.sh`；涉及菜单栏图标 / Renderer 的高风险改动按项目规则执行 `full`。
- [ ] 使用 `VisibleUITestCase` 覆盖三栏编辑器、drag/drop、布局模式和真实 NSStatusItem 行为；默认跳过真实窗口测试的规则不变。
- [ ] 更新 `docs/menubar-instances-acceptance.md` 并逐项记录 PASS / FAIL。

## 11. 测试清单

### Model / Migration

- [ ] 新建空白实例默认 singleLine，且没有自动 CPU / RAM 文字。
- [ ] singleLine → doubleLine → singleLine 不丢失 bottom 内容。
- [ ] v1 `segments` 解码到 v2 elements，数据源顺序、文字、行图标和样式保持。
- [ ] duplicate metric / duplicate text 拥有不同 element ID，能单独选中 / 删除 / 移动。
- [ ] text 的空格和标点原样保存，换行与超长内容按约束处理。
- [ ] icon element Codable round-trip；非法 SF Symbol / asset 名称有安全 fallback。

### Drag / Editor

- [ ] Palette metric 拖入只生成 metric，不隐式生成标签。
- [ ] 任意文字从右侧创建后可拖入两行任意位置。
- [ ] SF Symbol / Emoji 可作为独立元素拖入两行任意位置。
- [ ] 同行重排正确；上下行移动正确；Palette 重复拖入生成副本。
- [ ] 选中元素 Delete 删除；拖入 Trash 删除；过期 drag payload 安全拒绝。
- [ ] 单行模式只出现一个 drop row；切回双行恢复原下行内容。

### Rendering

- [ ] 单行 / 双行 / 单空行 / 两行都为空。
- [ ] metric + text + icon 任意交错组合。
- [ ] 指标元素只输出值；用户文字按输入原样显示。
- [ ] 每个 metric 使用用户自定义颜色或来源色；fixed line color 覆盖来源色。
- [ ] Emoji 保持彩色；SF Symbol / template asset tint 正确。
- [ ] leading column icon 不覆盖行文本；line icon 不破坏 alignment。
- [ ] padding / margin / max-line width 测量和绘制一致。
- [ ] 9% / 10% / 100% 等值变化不会产生非预期抖动。
- [ ] macOS 13、15、26+，浅色 / 深色、高对比度、多屏幕、Retina 2x。
- [ ] VoiceOver 按行读出实例名、元素名称和当前值。

### Runtime / Lifecycle

- [ ] 两个实例各创建独立 NSStatusItem；隐藏 / 删除 A 不影响 B。
- [ ] 同一指标被多个实例引用只产生一份底层采样；禁用最后一个使用者后需求释放。
- [ ] 主图标的 menuBarArc demand 与实例的 menuBarCenter demand 不互相清除。
- [ ] disabled instance 不继续 render、不保留不必要的需求。
- [ ] 程序主动 setVisible 不被识别为 userRemoved；用户拖出只禁用对应实例。
- [ ] 菜单栏空间不足不误判为 userRemoved。
- [ ] A 的延迟关闭不能关闭 B 新打开的面板；按钮到面板移动不闪退；hover click 正确 pin。
- [ ] Runtime stop 后 publisher、tracking area、KVO、demand 和状态项得到清理。

## 12. 明确不做的事情

- 不改变左侧 / 中间 / 右侧三栏的信息架构；CodexBar 只作为交互和渲染实现参考。
- 不把整个 CodexBar 源码复制进 Status Trio，不引入 CodexBar package dependency。
- 不引入第三方插件数据源；首版只使用 Status Trio 已有内置指标。
- 不为菜单栏实例新建任何采样器、独立轮询或后台刷新循环。
- 不把每个监控指标做成一个全局 enable switch；是否显示由用户把它放进哪个实例的哪一行决定。
- 不在数据源元素里自动拼接名称；名称由用户显式添加 Text 元素。
- 不做用户自定义图片文件导入。
- 不改主菜单栏图标与 Dock 图标行为。
- 不承诺 macOS 能同时显示用户配置的全部实例；20 仍只是配置数量上限。

## 13. 交付标准

- 三栏 UI 与已确认 HTML Demo 的结构保持一致。
- 任意实例均可从空白开始自由组合：metric / text / icon 可混排、重排、跨行移动。
- 单行 / 双行切换清楚且不丢配置。
- 状态项渲染与预览一致；默认指标拖入只输出值。
- CodexBar 借鉴限于通用 SwiftUI drag/drop 与 AppKit rendering patterns；Status Trio 的数据源、SettingsStore、采样、颜色策略和 NSStatusItem 管理由自身架构负责。
- 当前分支已有的多实例、面板锚定、持久化、导入导出和采样行为不得回归。
- 所有测试与手动验收结果写回 `docs/menubar-instances-acceptance.md`。
