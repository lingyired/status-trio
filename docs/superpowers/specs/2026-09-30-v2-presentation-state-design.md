# Status Trio 2.0 — Presentation State / MVVM 架构设计

## 1. 文档状态与设计依据

本设计基于用户提供的《Status Trio — Presentation State / MVVM Architecture Refactor Plan》，结合当前仓库代码重新整理。用户已确认：采用渐进迁移，保持现有界面和行为，仅重构图标与状态面板的展示架构，为未来扩展建立边界。

三部分对话设计已获确认：状态所有权与数据流、展示状态契约、迁移与验收规则。本文件是供用户审阅的书面 spec；书面审阅通过后再生成详细实施计划。它不授权产品代码实施、版本发布或创建 tag。

- 基准提交：`4176b78`（当前 `main`）。
- 工作分支：`codex/2.0-presentation-refactor`。
- 独立 worktree：`/Users/lingsmbp/.codex/worktrees/status-trio-2-0/status-trio`。
- 初始 worktree 的 `swift test` 已以退出码 0 完成；这是迁移前基线，不代表后续修改或 CI 验证。
- 原 checkout 中未跟踪的文档及 `output/` 不属于本次工作，不复制或修改。

## 2. 目标、成功标准与范围

领域状态描述系统正在做什么；展示状态描述 Status Trio 要显示什么。渲染器和 SwiftUI 展示组件消费已解析的展示结果，不再各自判断电池、网络、音量的产品语义。

成功标准是：同一逻辑图标场景驱动 Menu Bar、Dock 和预览；渲染器不解释领域模型；面板主要内建区域消费展示状态并通过明确的动作边界操作领域层；像素、布局、导航、设置、无障碍及按需监控行为保持一致；无视觉变化的领域更新不增加栅格渲染。

### 2.1 本次包含

- 电池外环、进度、颜色、顶部空隙、百分比／闪电／插头附件及充电效果。
- Wi-Fi、Ethernet、热点、临时连接、互联网共享、错误状态、蓝牙音频替换和用户指定符号，以及中心电池百分比。
- 音量点阵、连续弧线、静音、不可用状态及蓝牙音量颜色。
- Menu Bar、Dock、设置预览、图标说明、渲染缓存和充电帧缓存。
- 电池、网络、VPN、蓝牙、音量、音频输入面板的主要展示状态及动作边界，包括当前设备列表和控制能力。
- 架构文档、语义测试、像素对照和集成回归测试。

### 2.2 本次排除

不实现插件运行时、插件协议／清单、XPC／JavaScript 扩展、HTTP／WebSocket 数据源、动态模块注册、表达式引擎、通用键值状态仓库、Panel DSL、模块市场或用户自定义模块。

不开放图标槽位选择器、AirPods 分段环、输入法中心文本等新产品功能。不改版面板，不改现有设置键、默认值、用户偏好或本地化术语，不重写正常工作的监控器。不在此规划阶段提升版本／build、准备发行说明或发布 2.0。

## 3. 当前代码与针对性问题

| 现有位置 | 当前职责／问题 | 迁移目标 |
|---|---|---|
| `Models/MenuBarStatus.swift` | 面向图标的领域投影，亦服务其他消费者 | 退出像素入口；有真实消费者时保留或针对职责重命名 |
| `Models/StatusMappings.swift` | 混合视觉映射和共享产品语义 | 按用途拆分，不机械搬迁整个类型 |
| `Models/StatusIconAppearance.swift`、`Settings/SettingsStore+IconAppearance.swift` | 统一设置发布，仍包含领域选项 | 保留设置覆盖和发布时序，分离映射配置与渲染输入 |
| `UI/Icon/StatusIconRenderer.swift` | 同时决定产品语义和绘制像素 | 只解释视觉图元，复用成熟绘图实现 |
| `UI/Icon/StatusBarRenderCache.swift`、`DockIconRenderCache.swift` | 两端缓存键独立表达领域状态；Dock 已做部分归一化 | 基于解析后的场景和渲染环境建立 identity |
| `UI/StatusBarController.swift`、`App/AppIconController.swift` | 两端独立订阅和解析领域快照 | 注入同一个图标展示状态所有者 |
| `App/AppEnvironment.swift` | 所有者组装、共享时钟和监控生命周期 | 增加共享图标状态所有者，保留现有生命周期职责 |
| `UI/StatusPopoverView.swift` | `StatusPresentation` 文案规则与领域绑定集中在视图文件 | 拆分面板映射、无障碍展示和组合视图 |
| `Store/SystemStatusStore.swift` | 维护 `snapshot`、`popupSnapshot`、`liveVolume`、`liveInput` 和按需控制器 | 继续作为领域权威，不合并这些更新渠道 |

现有 `BatteryPowerPresentation`、`WiFiSummaryPresentation`、`WiredLinkPresentation`、设备列表和音频输入等展示辅助类型应先审计，再复用或移动；不重复创建同一语义的第二套 Mapper。

## 4. 架构与状态所有权

```text
System APIs / Monitors
        ↓
Domain Models → SystemStatusStore
                       │
SettingsStore ──────────┤
                       ↓
        IconPresentationMapper（纯函数）
                       ↓
        IconPresentationViewModel（共享所有者）
                       ↓
                 IconSceneState
            ┌──────────┴──────────┐
            ↓                     ↓
     Menu Bar Renderer       Dock Renderer
     + surface inputs        + surface inputs

Preview snapshot + preview configuration
        → 同一个 Mapper → 同一个 Scene → 同一个 Renderer

SystemStatusStore / existing controllers + preferences + localization
        → PanelPresentationMapper / StatusPanelViewModel
        → Panel presentation state → Existing SwiftUI

View intent → ViewModel / coordinator → Domain action
```

`SystemStatusStore` 是领域状态权威，`SettingsStore` 是偏好权威。`IconPresentationViewModel` 只拥有派生展示结果，由 `AppEnvironment` 创建并向两端注入，不拥有监控器，不写回系统状态，也不各自为 Menu Bar 和 Dock 创建实例。

图标所有者采用 `@MainActor`，沿用现有 Combine 机制，暴露初始可读值和去重后的输出；是否为 SwiftUI 提供 `ObservableObject` 取决于实际消费者，不为类名套用额外框架。新增目录为 `Sources/StatusTrioCore/Presentation/Icon/` 与 `Presentation/Panel/`。

图标 Mapper 和状态类型不依赖 AppKit、SwiftUI 或 Core Graphics。纯 Mapper 可接收当前领域快照与映射配置；只有映射边界理解领域。渲染器不能接收 `BatteryStatus`、`WiFiStatus`、`VolumeStatus` 或 `NetworkConnection` 来决定画什么。

## 5. 图标状态契约

### 5.1 场景与视觉图元

`IconSceneState` 为 `Equatable / Hashable / Sendable` 值类型，包含可选的 `outerRing`、`center`、`footer`。缺省槽位统一使用 `nil`，不同时引入另一种等价的 `.empty` 表示。

- `OuterRingState`：环段、进度、语义颜色、顶部附件、空隙样式及效果意图。环段结构不以电池命名；本次生产只生成现有连续环。
- `CenterState`：已选定的符号、文本或组合视觉图元。符号来源支持 SF Symbol、现有资源标识与现有手绘图元；保留分类蓝牙图标及用户指定符号，不将所有图形强制转换为 SF Symbol。
- `FooterState`：本次生产采用点阵或连续弧线。点阵保存总数与激活点数；弧线保存已解析的有效填充进度，并区分需要绘制的底轨与填充。
- `IconColorRole`：语义角色，能保持现有前景、临界、低电量模式、供电及蓝牙颜色。渲染器按外观解析实际颜色，不把 `NSColor`、`CGColor` 或 SwiftUI `Color` 存入场景。

特殊 Wi-Fi 绘制、Ethernet、临时／共享连接标记和静音底轨必须由已解析的视觉信息表达，不能通过把领域 enum 改名为 RendererState 来隐藏耦合。图元内部可以使用手绘样式标识和视觉等级，不能再问连接类型或错误优先级。

顶部附件必须区分百分比、闪电、插头和无附件，以及现有样式需要的空隙规则；不可假设 `nil` 附件必然等于缺失整个外环。电池缺失状态以旧渲染结果为准，不能在重构时自行改变。

### 5.2 映射配置与渲染输入

`IconPresentationConfiguration` 表达用户偏好的映射规则，允许暂时保留内建的电池、连接、音量和蓝牙配置组，但不成为渲染器的领域选项入口。

每一个现有选项必须归入下列边界之一：

| 输入类别 | 归属 | 举例 |
|---|---|---|
| 产品选择规则 | 映射配置 | 是否替换中心、网络错误优先、临界阈值 |
| 当前图元的视觉属性 | 场景中对应图元 | 符号比例、文本比例、环线宽比例、点阵样式、心跳意图 |
| 渲染目标环境 | surface rendering inputs | Menu Bar 尺寸、backing scale、有效外观、Dock 像素长度／背景 |
| 时间及运行策略 | 动画／surface 层 | 当前帧、Reduce Motion、显示器休眠、表面动画许可 |

坐标、路径、半径和光学校准常量仍在 `StatusIconGeometry`／渲染器内。用户选择的比例是视觉属性，不能因“几何留在渲染器”而遗漏。Mapper 只保留当前可见图元实际使用的属性；未启用选项不应制造无意义的场景差异。

`iconSize` 进入 Menu Bar 的 surface 输入，Dock 保留其现有像素尺寸规则；两端共享场景不意味着使用同一栅格尺寸。逻辑场景和相关 surface 配置需以一致的输出值交付，避免消费者短暂读取不同版本的配置。

### 5.3 归一化与选择优先级

Mapper 保持现有产品规则，包括中心电池百分比、蓝牙指定符号、当前音频设备、网络错误优先、Ethernet 及 Wi-Fi 特殊状态的实际优先级。实现前用行为基准测试固定这些规则，不依据名称重新推断优先级。

- 百分比约束为 `0...100`，进度为 `0...1`，点数约束为合法总数范围。
- RSSI 转为当前视觉等级，不保存精确 RSSI、SSID 或设备名称到图标场景。
- 音量点阵保存解析后的激活点数；弧线保留现有连续精度，不增加新的量化规则。
- 静音时仅底轨可见，隐藏的原始音量不应造成场景差异。
- `nil`、NaN、正负无穷不能进入可比较的进度。缺失／非有限输入采用现有“不可用、无有效填充”视觉；越界有限输入截断到合法范围。针对畸形输入固定确定性测试，不改变正常输入的产品行为。
- 蓝牙保存最终图标来源和有效颜色，不保存整个设备领域对象。

只要一个数据变化不能改变当前逻辑视觉，场景应相等。相同语义场景在相同渲染环境和相同帧下输出相同像素。

### 5.4 为未来保留的边界

图元命名及槽位契约不能硬编码“外环等于电池、中心等于网络、底部等于音量”。用设计示例检查：双设备环段、`中`／`EN` 中心文本、远程百分比和替代底部图元可以描述为展示状态。

这些示例不意味着本次渲染器已支持所有未来图元。以后可以添加状态变体及其绘制实现，同时保持 `scene + rendering environment` 的渲染入口和依赖边界；不承诺无需增加任何绘图代码。不加入无人生产的占位 enum 分支，也不以静默空白绘制伪装支持未来功能。

## 6. 发布、动画、缓存与无障碍

### 6.1 状态发布

共享所有者从真实领域快照和完整设置配置解析 canonical `scene`，并在发布前去重。既有充电测试模式仅用于 Menu Bar：同一个所有者通过同一个 Mapper 派生可选 `menuBarTestScene`，Menu Bar 消费该值或 canonical scene，Dock 始终消费 canonical scene。测试模式不建立第二个所有者或独立配置。沿用设置 publisher 从已投递值构造配置的方式：`@Published` 在字段写入前发送值，不能在 sink 中回读存储来拼出旧配置。

保持现有快速设置反馈及领域快照更新节流行为：共享所有者缓存最新已投递 snapshot／settings，领域更新使用 0.5 秒 trailing debounce，设置更新立即按最新 snapshot 解析。延迟调度可注入，stop 取消未执行工作，restart 以输入当前值刷新。调度／合并策略可留在 surface 层，但不能在那里再次解析领域视觉。初始渲染、显示器变化、外观变化、隐藏后恢复和停止后重启均消费共享所有者的最新完整值。

图标状态所有者无定时器和系统 I/O。启动／停止必须幂等，不重复订阅、不遗留任务或观察者，不引入额外高频 `@Published` churn。

### 6.2 动画

场景表达充电及心跳效果意图；`ChargingEffectPhase`、时钟、瞬态强度、帧索引均不进入场景。保留 `ChargingEffectClock`、Reduce Motion、显示器休眠、测试模式和现有 Menu Bar 动画行为。

Dock 在当前基准版本保持静态绘制策略；无需为本次重构新建 Dock 动画功能。surface 禁用动画不更改逻辑场景，只影响绘制策略。充电测试模式继续使用现有测试投影，仅改变 Menu Bar 测试展示，不改变 Dock 图片、真实领域快照或面板状态；测试开关不会触发 Dock 栅格渲染。

`StatusBarChargingFrameCache` 的整组帧 identity 包含场景、有效渲染环境和影响整组帧像素的效果参数（包括 heartbeat multiplier），排除每次 tick 的帧索引。单帧 identity 只在实际需要时包含 phase。保持预渲染帧复用及动画图层行为。

### 6.3 缓存

普通缓存键由场景和 surface 的实际栅格输入构成。Menu Bar 包含尺寸、backing scale 和有效外观；Dock 包含像素长度、背景和实际影响前景／颜色的环境。没有影响像素的领域数据或偏好不得进入键。

保留 Dock 有界图片缓存和预览尺寸隔离。渲染失败不能把未成功展示的键当作已成功缓存，恢复时需允许重试。无变化更新不调用栅格渲染；隐藏表面不产生新栅格；重新显示时使用最新状态。

### 6.4 本地化与无障碍

图标场景只包含实际可见的文本，不携带无关本地化字符串。面板 Mapper 可以产生本地化后的最终文案；语言变化刷新面板和无障碍展示，但不能因不可见语言信息使图标缓存失效。

无障碍使用单独的丰富输入／identity，保留精确音量、SSID、充满状态、设备信息等现有 VoiceOver 语义。不能把无障碍更新依赖于 `IconSceneState.removeDuplicates()`。将当前 `StatusPresentation` 中无障碍与面板格式化职责分开，但不额外重构监控层。

## 7. 面板展示与动作边界

### 7.1 各区域独立状态

`StatusPanelViewModel` 是面板展示所有者／协调入口，不是新的系统状态仓库。区域状态按各自需求表达标题、副标题、数值、可用性、设备行、权限提示、进行中／失败状态和稳定操作标识，不强制统一为通用 PanelNode。

| 区域 | 输入与必须保持的行为 |
|---|---|
| 电池 | `popupSnapshot`、电池详情状态；保留剩余时间、功率、详情开关及动作目标 |
| 网络 | `popupSnapshot`、名称解析、约束状态及现有 Wi-Fi／有线控制器；保留授权、扫描、连接、地址和详情导航 |
| VPN | 独立 `vpnStatus`；继续不驱动图标更新 |
| 蓝牙 | 现有设备／附近电量／听音模式控制器；保留设备稳定标识、授权、刷新、错误、表面持有及释放 |
| 音量 | `liveVolume`、设备与控制能力；保留滑块、滚动、静音、设备切换、操作结束及反馈 |
| 音频输入 | `liveInput` 与设置许可；保留输入设备切换、音量、静音和监控启停 |

`popupSnapshot` 的现有节流、实时音量与输入的快速反馈是不同契约；不改成单一大快照或对所有区域应用同一 debounce。面板保留不可操作状态的文案和禁用控制。

### 7.2 视图与控制器

音频输出排序及可见数量使用设置的已投递值作为窄配置输入；展示状态提供已解析的完整／收起行集合及展开文案，展开开关仍属于局部交互状态。视图负责布局、焦点和局部交互状态，不判断领域错误优先级、产品可用性或本地化规则。`PopupSection` 继续表示区域可见性和顺序，`popupSection(_:)` 可以保留为内建组合 switch。

`BatteryDetailsController`、`WiFiNetworkController`、`PrimaryLinkController`、`BluetoothDeviceController` 和听音模式控制器保持当前领域所有权与生命周期。展示状态可以从其已发布数据派生；UI 若需要出现／消失事件，应经协调接口转交，不把监控器直接塞入展示状态。

主要区域、设备列表和详情展示中的领域解释需迁入合适的展示辅助层。现有详情控制器无需重写，但不能只把解释逻辑从顶层视图挪到另一个 SwiftUI 子视图，便声称边界完成。

### 7.3 动作与失败

以明确方法或类型化动作表达领域意图：详情开关、权限请求、音量变更／结束、静音、输出／输入切换、设备操作及听音模式调整。允许保留已经清晰的闭包，不强迫所有动作进入一个巨大 enum。

动作携带稳定领域标识或必要参数；协调器解析当前领域对象并验证仍可操作，避免对已消失设备执行过期操作。失败、权限拒绝、不可用和异步进行中状态沿用当前反馈，不增加新错误 UI，不静默变成成功。

System Settings 路由独立于视觉映射，保留 Wi-Fi 自身 extension 优先、有线 Network pane 和原 fallback 顺序；不添加按 macOS 版本分支的路由判断。

### 7.4 生命周期和性能

ViewModel 可以与保留的 popover 内容同寿命，但不能因此持续启动扫描或硬件读取。显示、详情开关、Settings 表面 claim、蓝牙监听、输入许可等仍由现有领域机制控制；面板关闭时保留现有取消／释放和晚到结果处理。

按区域对有效展示输出去重，避免把设备列表刷新传播为所有区域重算／重绘。只有可见性需要的展示订阅可按需启停；不改变领域监控刷新节奏和休眠恢复规则。

## 8. 渐进迁移与退出条件

采用一个整体设计，分图标和面板两个顺序里程碑；不是一次性替换。详细文件修改、测试命令和提交拆分由后续实施计划给出。

| 阶段 | 交付 | 进入下一阶段的条件 |
|---|---|---|
| A：行为基准 | 输入／设置／优先级／像素／性能／生命周期覆盖矩阵 | 关键现有行为有可运行验证，缺口有明确补测目标 |
| B：状态与 Mapper | 视觉值类型、配置边界和纯映射 | 语义、归一化、视觉属性覆盖通过；尚不替换生产路径 |
| C：渲染适配 | scene 入口复用原绘图原语 | 同平台、同环境、同帧下旧新代表性输出一致 |
| D：共享图标生产链路 | 共享所有者、Menu Bar／Dock、缓存、动画、设置和所有预览 | 两端端到端同步及初始／恢复行为通过，临时适配器只承担迁移兼容 |
| E：面板展示与动作 | 按区域迁移状态与交互 | 布局、导航、实时控制、授权、按需监控和失败反馈一致 |
| F：清理与整体验收 | 删除旧像素入口、拆分辅助职责、架构文档及保护测试 | 无生产消费者走旧映射路径，全部本地及 CI 验证通过 |

阶段 D 内可以分提交迁移 Menu Bar 和 Dock，但每个可审阅提交都必须保持两端现有逻辑与像素一致，必要时用临时适配器桥接。不能引入只在一端生效的新设置或行为。预览用示例领域快照和同一 Mapper，不复制另一套优先级逻辑。

旧入口仅保留到对照测试和调用方迁移完成；删除前搜索全部调用方。`StatusIconAppearance` 可临时作为配置适配器，最终不再作为领域渲染入口。`MenuBarStatus` 如仍有无障碍等真实消费者可保留；不得为了删除名称制造无关改动。

每个阶段用独立、可回退的提交交付。每次清理只在必要回归通过后继续；不要合并成一个不可定位的巨型提交。

## 9. 验证与验收矩阵

### 9.1 测试层次

| 测试层 | 重点断言 |
|---|---|
| 纯 Mapper | 电池全部供电状态和开关；中心所有连接、替换和错误优先级；音量模式、边界、静音、缺失和颜色 |
| 状态语义 | 相等性、哈希一致性、有限范围、有效视觉属性；不可见原始噪声映射为相等场景 |
| 渲染对照 | 代表性旧新像素对比；几何、符号、外观、比例、线宽与效果帧 |
| 所有者与 surface 集成 | 单一共享实例、设置时序、去重、初始值、启停、隐藏恢复、缓存失败重试、动画独立性 |
| 面板与动作 | 文案、语言切换、实时控制、动作参数、稳定标识、禁用／失败状态、按需生命周期和路由 |

沿用各测试文件现有 XCTest／Swift Testing 风格，不批量转换框架。复用现有 `PixelBuffer` 和平台指纹规则；不随意更新指纹。纯架构重构的默认是像素不变，任何差异必须解释具体来源并重新审阅是否违反范围。

代表性像素覆盖至少包括：正常／临界／充电电池，顶部百分比／闪电／插头，强弱 Wi-Fi 和特殊连接，Ethernet，蓝牙分类与覆盖符号，中心百分比，音量点阵／弧线／静音及蓝牙颜色；同时覆盖不同有效外观、比例、线宽和渲染尺寸。

保留并更新现有 renderer、两端 cache、appearance publisher、Issue13IconParity、charging effects、previews／guide、settings、Bluetooth replacement、Wi-Fi 与 volume tests。结构保护优先使用编译边界及正常单元测试，只有已有合适先例时才增加源代码检查，不把字符串搜索作为架构唯一证明。

### 9.2 必须成立的架构断言

- Menu Bar 和 Dock 获取同一所有者的场景；预览使用同一 Mapper。
- 像素入口无直接领域模型或领域选项；优先级只在映射层决定。
- 相同场景、环境及帧产生相同像素；原始噪声不触发栅格渲染。
- 动画帧不发布为逻辑场景；关闭某表面动画不改变场景。
- 像素相同仍可独立刷新无障碍；语言变化刷新面板文案。
- 面板实时交互与监控 gate 不退化；关闭后无新增硬件读取或持续扫描。

### 9.3 本地与 CI 门槛

每次提交 Swift 变化之前运行：

```bash
swift test
swift build -c release
```

最终还必须运行 `git diff --check` 并审阅 diff；图标链路和面板里程碑执行相应集成／像素回归。测试通过后不做没有新风险依据的重复运行。

本次实施会触及 `@MainActor`、Combine、SwiftUI 绑定等，在合并前必须通过 `.github/workflows/release.yml` 的非发布 preflight。验收环境为 `macos-26`、Xcode `26.6`、Swift `6.3.3`，应用 SDK 至少 macOS 26；保留 `scripts/build-app.sh` 与 `scripts/verify-platform-version.sh` 的检查。

dispatch 前确认当前已发布与未发布版本信息，明确本次验证 version 和未使用且递增的 build，并准备 workflow 所需的本地化 notes（包括规定的标题占位符）。不得把当前推测的 build 写成固定实施常量。推送经验证的分支后以 `publish=false` 执行并等待完整 workflow 结果；本设计不包含 tag、Release 上传或 appcast 发布。

每个失败 Actions run 必须在 `docs/swift-ci-compatibility.md` 记录 run ID、失败阶段、根因、修复和验证结果后重试。遵守禁用 `isolated deinit`、禁用 `weak let`、actor 方法通过显式闭包传递和资源目录大小写兼容要求。编译器崩溃应缩减触发模式，不用实验标志掩盖。

本地较新编译器通过不能替代 CI 通过。仓库当前发布为 Ad-hoc 签名，不宣称 Developer ID 签名或 notarization。

## 10. 风险控制与文档交付

| 风险 | 控制措施 |
|---|---|
| 抽象丢失视觉细节 | 基准矩阵覆盖附件空隙、特殊图形、比例、线宽、颜色与效果；复用成熟绘图代码 |
| 发布时序造成旧值／半更新 | 使用 publisher 已投递值，交付一致的 scene 与 surface 配置，保留共享设置输入聚合 |
| 新缓存导致无谓刷新或漏刷新 | 完整有效视觉输入、表面环境及帧 identity；分别验证噪声去重与视觉变化 |
| 面板重构扩大硬件监控生命周期 | 保留现有控制器和表面 claim、可见性、许可、关闭取消及晚到结果测试 |
| 泛化失控或 CI 不兼容 | 只落地当前图元，未来以契约示例论证；阶段验证和指定工具链 preflight |

实施最终新增 `docs/presentation-state-architecture.md`，描述领域→映射→展示状态→渲染边界、组件依赖、生命周期、缓存、动画、无障碍及维护新设置的方法。明确记录：

> Menu Bar 和 Dock 共享逻辑状态；表面渲染及动画策略可以不同。

> 未来插件和自定义数据源是新增状态生产者，不获得 Core Graphics 或 SwiftUI 渲染权限。

未来示例 `Remote API → custom state → center text` 仅作为边界说明，明确标注未实现。

## 11. 审阅与实施计划交接

书面 spec 审阅通过后，使用 `writing-plans` 创建新的实施计划。计划必须给出真实文件路径、具体任务依赖、测试目标与命令、旧接口删除条件、可审阅提交边界及上述 CI 前置材料。

计划执行时遵循用户偏好，使用当前可用的最新 Luna 模型（现为 `gpt-6-luna`）；当前规划任务不启动实现代理。用户需审阅实施计划并选择执行方式后，才开始产品代码实施。
