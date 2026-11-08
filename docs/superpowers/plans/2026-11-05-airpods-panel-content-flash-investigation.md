# AirPods 固定面板内整页瞬闪排查计划

> **For agentic workers:** 后续得到实施授权后，使用 `executing-plans` 逐项执行。本轮仅静态分析和编写计划，不修改源码、不启动应用、不运行测试、不提交。

**Goal:** 找出快速展开/收缩时，外框稳定但页面内容短暂上移或顶部消失的原因，以能捕获异常帧的回归测试约束最小修复。

**Architecture:** 保留现有 AirPods 容器高度驱动、窗口跟随测量的结构。先在生产配置和完整页面中同时观察滚动、宿主几何、内容身份和测量来源，确定哪个边界最先异常，再只修改该边界；不预设需要再次重构动画。

**Tech Stack:** SwiftUI、AppKit `NSPanel` / `NSHostingController` / `NSScrollView`、XCTest、现有 synthetic AirPods 和后台 UI 测试设施。

**Spec:** 本计划内的“现象与范围”及本会话用户 2026-11-05 最新要求；此前修复背景见 `docs/airpods-rapid-disclosure-fix.md`，此前通过结果不证明本次现象已解决。

## Global Constraints

- 本计划分析基于 `codex/fix-airpods-rapid-disclosure`，HEAD `0620ad3c671764a11fba8e66e7501d60e9b95c83` **加当前未提交修改**，不能仅凭 SHA 重建现场；执行前保存相关 diff、未跟踪文件清单及源码摘要。
- 保留所有既有未提交改动及旧报告；本轮只新增本文件。后续不自动提交、推送、合并或发布。
- macOS 13+；不 debounce、不限制点击、不延迟用户意图、不固定生产面板高度、不延长动画遮掩闪动。
- 后续实窗操作先读 `.agents/skills/background-ui-testing/SKILL.md`；可见窗口测试遵守 `VisibleUITestCase` 和显式 opt-in，opt-in 本身不代表后台安全。
- 节省预算：先一次有界观测，再单一假设验证和 focused 测试；最终代码冻结后才跑一次 `full`。不默认派发子代理，不循环重跑全套。

## Review Focus

- 外框和 Footer 稳定不代表顶部内容稳定；增加顶部两个不受 AirPods 高度影响的标记，分别检查位置和可见性。
- 正常用户滚动不能被“修复”重置；分别覆盖初始顶部、用户已滚动和内容从溢出变为可容纳。
- 生产宿主配置必须进入回归；特别是 macOS 14+ 的 `sizingOptions = [.preferredContentSize]`，不能继续用未配置的测试宿主代替。
- 异步设备状态更新不能替换整个页面或无故清空列表；检查稳定行 ID、顶部 section ID、host/document 身份与模型创建次数。
- 几何模型采样不等于合成后画面；若位置正常但图像闪失，应转查裁剪/绘制阶段，不放宽断言宣布成功。

## 现象与范围

用户慢放多次展开/收缩的录屏，发现偶发整页向上顶或顶部消失，随后快速恢复，面板外框看起来固定。所附单帧在 AirPods 下方有较大空白，不能单凭该帧判断是滚动、宿主错位、内容缺失，还是当时恰处于过渡布局。

本轮没有运行或复现，因此下面均区分“代码事实”和“待验证推断”。本轮也没有重新 fetch；远端是否变化不影响此次对当前 dirty tree 的只读分析。

## 静态发现与定位优先级

### 1. 宿主测量和生产配置存在未覆盖的组合

**代码事实：**

- `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`：
  `StatusPanelHostingController.viewDidLayout()` 每次用 `sizeThatFits(in:)`，提案高度为 `.greatestFiniteMagnitude`。
- `Sources/StatusTrioCore/UI/StatusPanelScrollArea.swift`：
  `fillsWindow == true` 时，`GeometryReader` 直接用收到的高度减 Footer 高度作为 ScrollView 高度，没有独立的理想高度。
- `Sources/StatusTrioCore/UI/StatusBarController.swift`：
  `installPopoverContentIfNeeded()` 在 macOS 14+ 启用 `.preferredContentSize`。
- `Tests/StatusTrioCoreTests/AirPodsDisclosureIntegrationTests.swift` 的 `Fixture` 没有设置该 sizing option。
- `installContent()` 虽优先采用 `layoutMetrics.contentHeight`，仍会执行上述无界查询；采用缓存后的结果不等于避免查询本身。

**待验证：** 无界理想尺寸查询与有限可视高度、自动 preferred sizing 是否形成多轮不一致布局，或影响 document/host 的短暂位置。代码只能证明这个组合存在，不能证明 `sizeThatFits` 必然改变显示几何。

**证伪条件：** 异常帧前后没有对应测量/宿主几何变化，且对照实验中仅改变测量路径或 sizing option 不改变异常。

### 2. ScrollView 在内容变化时可能调整可视起点

**代码事实：**

- ScrollView 身份稳定，但 `.scrollDisabled(!overflowsBudget)` 随内容测量和屏幕预算切换。
- live viewport 跟随实际 host 高度；内容高度则由 disclosure timer 和 SwiftUI 测量更新，两者经过异步窗口回报。
- `PanelScrollBridge` 读取 clip-view bounds 并发布滚动条偏移；它没有调用滚动定位 API，也没有保证 clip origin 稳定。
- `PanelScrollOffset.topOffset()` 会 clamp 到合法范围；仅记录这个值会掩盖原始 origin 的瞬时越界或回弹。

**待验证：** 内容/viewport 不同步、跨越可滚动阈值，或按钮焦点的可见性维护，是否让原生 scroll view 暂时改变 clip origin，使顶部全部内容一起上移。

**证伪条件：** 闪动期间原始 clip bounds、document frame 以及转换后的顶部标记位置均稳定。不能仅凭归一化 scrollOffset 为零排除此项。

### 3. 多来源测量、背景容器和页面身份作为后续分支

**代码事实：**

- content/footer preferences 分开存储、分开调用 `reportHeight`；每次上报可能组合“本次 content + 上次 footer”。
- 自然高度和 hosting `onLayout` 都能请求窗口尺寸；layout coordinator 只保留最后一次请求，不记录来源/测量代次。
- `StatusPanelContentViewController.viewDidLayout()` 每次把 host frame 设为直接父容器 bounds；Liquid Glass 多一层普通容器。
- `StatusPopoverView.summary` 使用 section 的稳定 `ForEach`；`OutputDeviceList` 使用普通 VStack 和稳定行 ID。没有发现 disclosure 点击直接重建整个 host 的调用。
- 设备列表仍有 skeleton/空列表/非空列表分支，真实异步更新可能经过这些路径，但本轮没有证据表明点击会触发它们。

**待验证：** 优先级低于前两项。只有观测到 Footer 测量突变、父容器偏移、host 替换或 rows 暂时清空，再进入对应分支；不因为“像刷新”就先搬迁所有展开状态。

## 文件与职责

| 文件 | 后续职责 |
| --- | --- |
| `Tests/StatusTrioCoreTests/AirPodsDisclosureIntegrationTests.swift` | 扩展真实窗口 fixture，保留现有断言，加入完整页面、生产 sizing 配置和异常帧观测 |
| `Tests/StatusTrioCoreTests/StatusPanelContentResizeTests.swift` | 复用实际 `StatusPopoverView` 的 store/控制器构造方式，验证 summary/detail sizing 不回归 |
| `Tests/StatusTrioCoreTests/StatusPanelScrollAreaTests.swift` | 只在确认 scroll/viewport 问题后补对应边界回归 |
| `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`、`StatusPanelScrollArea.swift`、`StatusPanelLayoutMetrics.swift` | 按证据选定测量、viewport 或 host 边界的最小修改；不默认全部改 |
| `Sources/StatusTrioCore/UI/StatusBarController.swift`、`StatusPopoverView.swift`、`OutputDeviceList.swift` | 生产对齐与身份调查入口；只有确认归因后修改 |

## Task 1：补齐生产现场并捕获第一个异常边界

**Interfaces:** 复用 `AnchoredStatusPanel.installContent(_:backgroundStyle:)`、`StatusPanelHostingController.onLayout`、`StatusPanelLayoutMetrics.measure(contentHeight:)` 和现有本窗口按钮事件。新增观测放在测试 target；确需生产测量来源时只加有限生命周期的 Debug hook，不做长期日志或轮询。

- [ ] 在现有 fixture 增加“生产 summary”模式：实际 `StatusPopoverView`、实际 Footer、系统代理/蓝牙/音量和至少五个输出设备，最后一个 synthetic AirPods；从 `StatusPanelContentResizeTests` 复用 fake store 组装方式，不读取真实耳机。
- [ ] 为 host 设置与生产相同的 availability 和 `.preferredContentSize`；确认 synthetic 分批更新经过实际 device list。确需注入 controlsFactory 时只增加默认无行为变化的窄测试入口，不另写一个外观类似的页面。
- [ ] 每条事件记录同一单调时间戳：用户意图、disclosure 高度、内容/Footer preference、窗口请求及应用高度；几何记录包括 window frame、各级 host/container frame/bounds、原始 clip bounds、document frame/bounds/isFlipped、顶部两个 marker 在窗口坐标中的矩形及可见交集、Footer 矩形。记录 host/document/section/row 身份和模型创建次数。测试退出同步解除观察。
- [ ] 一次有界观测先跑 30 次确定性间隔的交替点击（20–80ms，固定序列），同时覆盖 20ms 反向和 50ms/30ms 两次反向；页面分别选“始终容纳”“刚好跨溢出阈值”“展开收缩都超屏幕预算”。最后一项自然使窗口达到屏幕 cap，用来复现外框固定，不向生产引入固定高度。
- [ ] 先用实际 Liquid Glass，再用 solid 做单变量对照；后台捕获相关窗口的连续帧，保留异常前后短片段及同时间轴 CSV。若一轮未复现，报告未复现及覆盖范围，先检查与用户场景的差异，不开始猜测性修改。

**检查点：** 上述观测先回答：顶部节点是否仍存在？是 clip origin 先变，host/ancestor 先变，测量先失真，还是只有像素丢失？窗口 `didUpdate` 和定时采样只能辅助归因，不作为画面无闪动的充分条件。

## Task 2：按证据建立失败回归，只修首个异常边界

**Interfaces:** 复用 Task 1 的同时间轴样本和 production summary fixture；修复不新增几何动画驱动。

- [ ] 固化能复现的最短事件序列，添加 `testRapidDisclosurePreservesSummaryTopContent()`：无用户滚动、顶部锚定且顶部 sections 未变化时，顶部 marker 窗口坐标误差不超过一个实际显示像素；节点保持存在，画面不短暂被裁掉。允许合理移动的下方内容不能被混作顶部断言。
- [ ] 添加 `testProductionHostSizingKeepsFiniteViewport()`：验证已显示 host/viewport 的实际几何始终有限且符合窗口预算；单独标记理想尺寸查询提案，不能把合法的查询提案本身当失败。先确认失败发生在现有代码和同一 fixture。
- [ ] 每次只验证一个分支：若测量导致异常，避免窗口填充模式的无界 viewport 参与自然高度求值，并消除已证明竞争的 preferred sizing 路径；若 clip origin 导致异常，明确保持原有可视锚点的规则，只在确认的过渡点处理，并保留用户已滚动位置；若 host 或身份导致异常，则只修对应容器布局或列表状态转移。每个分支均要求 A/B 证据，不同时叠加。
- [ ] 若证实 content/footer 分代上报导致坏尺寸，在 `reportHeight` → metrics → coordinator 的边界保证同一次有效测量组合，验证不会多等一帧或丢最终目标；未证实时不改该路径。
- [ ] 运行匹配的新失败用例，确认修复后通过且异常画面消失；一次失败修复就检查假设，累计三次失败停止并写明哪个前提未成立，禁止继续堆补丁。

**分支限制：** 不默认每帧 `scrollTo(0)`、强制同步 layout、关闭全部滚动、移除所有自动尺寸能力或替换整个 ScrollView。静态分析尚不足以决定这些修改。

## Task 3：回归与交付

- [ ] 覆盖原要求的 20ms、50ms 后折叠再 30ms 展开、100ms 折叠、收缩途中反向、30 次交替、分批状态、途中关闭和超屏幕内容；加入顶部/中部已滚动状态，以及 summary→detail→summary。顶部稳定断言按锚定方向和滚动意图区分，不能禁止合理滚动。
- [ ] 用实际显示像素验证顶部和 Footer；继续验证最新意图、最终尺寸、固定锚边、停止后无 frame 写入、无过期工作及同 ID 模型不重建。保持已有测试严格程度，不用“一次布局步长”容忍整页突然上移。
- [ ] 先执行 `bash scripts/test.sh 'AirPodsDisclosureIntegrationTests|StatusPanelContentResizeTests|StatusPanelScrollAreaTests'`；真实窗口用例仅在已评估的隔离/后台会话设置 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1`。普通测试运行保留 UI skip，并单列说明。
- [ ] 最终改动冻结后按项目要求 fetch/记录对照基线，并串行执行一次 `bash scripts/verify-local.sh full`。执行前读对应 performance/compatibility 规则；不把构建或普通测试通过写成实窗通过。
- [ ] 将归因、修改文件、失败→通过证据及帧片段记入 `docs/airpods-rapid-disclosure-fix.md` 的独立补充段。分别报告当前 macOS synthetic 实窗、真实耳机、Ventura 和不同缩放的结果；未做项明确 `NOT RUN`，保留分支/worktree 供用户验收。

## 本轮交付边界

已完成：只读检查当前实现和测试差异，新增此排查计划。

未执行：源码修改、诊断 hook、测试、构建、应用启动、实时窗口观测和任何 Git 写操作。当前没有足够证据把候选原因中的任何一个认定为根因；后续实施需用户另行发出执行指令。

## 后续子任务执行状态

用户随后指定使用 `auto/deepseek-v4.1-flash` 子任务继续。上面的“本轮交付边界”
保留为最初只读分析时的记录，不代表后续执行状态。

已发现生产 preferred sizing 将显式测得的窗口高度覆写为 10pt 的竞争边界，
已移除该第二尺寸来源作为候选改动。一次 live 控制组触发进程 activation，
这条实窗路径已停止，候选改动后的实窗验证及用户瞬闪复现仍未完成。
Task 1/2 的实窗目标与 Task 3 的完整验收矩阵均不能勾为完成。

后续证据、候选修改和验证边界见
`docs/airpods-panel-content-flash-investigation.md`。

## 用户复测后的定位调整：人工验收失败

用户随后运行候选开发版，反馈“还是会”。本次只分析和更新计划，不修改源码、
不测试、不构建、不操作窗口。子任务继续使用 `auto/deepseek-v4.1-flash`。
移除 preferred sizing 不能解决整个症状；之前的 538→10pt 初始化证据仅作为
另一条尺寸竞争记录保留，不再作为本次固定外框瞬闪的根因结论。

### 新增静态发现

1. `StatusPanelScrollArea.swift:88-128` 中，可视区高度跟随实际 host proposal，
   而 `contentHeight` / `footerHeight` 来自不同 preference 回调；滚动开关依据
   自然内容是否超过屏幕预算决定。当前 viewport 的大小和预算不是同一个值，
   不能仅凭 `overflowsBudget == false` 断言此时 document 完全容纳于 viewport。
2. `PanelScrollBridge` 只观察原始 clip origin，并归一化成装饰滚动条 offset；
   不拥有实际滚动位置。归一化/clamp 后的 offset 不能用来排除原始 origin 异常。
   快速反向期间是否发生自动滚动或保留旧 origin，目前仍是假设。
3. `AnchoredStatusPanel.swift:658-680` 每次 `viewDidLayout()` 都先做一次
   `.greatestFiniteMagnitude` 高度的 `sizeThatFits` 查询，再判断是否需要回报。
   `installContent()` 已能使用有限的 metrics 高度；即使回报最终未采用无界结果，
   该查询依然发生。尚无证据证明查询会改变实际显示布局，必须单独验证。
4. `StatusPanelContentViewController.viewDidLayout()` 将 host frame 设为其直接
   父容器 bounds；Liquid Glass 路径多一个父容器。仅检查 window frame 无法
   排除父容器/host 在窗口内部短暂移动。
5. 现有实窗测试观察窗口、Footer 和 AirPods 下方 marker，没有同时覆盖真实
   顶部节点在 document/clip/window 坐标中的位置和可见交集，因而不能证明
   “固定外框内没有整页瞬闪”。

### Task 4：在真实页面抓第一处异常，不再先扩展 XCTest 页面

**Files:** 未来诊断仅考虑 `AnchoredStatusPanel.swift`、
`StatusPanelScrollArea.swift` 与 `StatusPopoverView.swift` 的有限 Debug 观测；
本次不修改这些文件。现有完整诊断 fixture 只作为归档参考，不直接恢复。

**Interfaces:** 分别观察 `StatusPanelHostingController.viewDidLayout()`、
`StatusPanelLayoutCoordinator.requestContentSize(_:)` / `flush()`、
原生 clip bounds 变更与实际 summary 顶部节点；所有数据使用同一单调时钟。
布局回调只存纯值，不遍历 AX、不查理想尺寸、不强制 layout 或离屏截图。

- [ ] 后续执行前先建立可用的安全观测路径。旧 XCTest 路径因 activation 已停止，
  不得直接重跑；可以由用户手动操作实际 Debug 开发包，工具仅记录该实例。
  记录单次 8 秒，关闭面板、超时或进程退出即停止，禁止常驻日志/轮询。
- [ ] 第一轮只记录：用户点击与 disclosure 展示高度；window frame；
  wrapper/glass parent/host 的 frame、bounds；scroll viewport 的 frame、
  原始 clip bounds、document frame/bounds；真实顶部节点在 document、clip 和
  window 中的矩形及可见交集；content/footer/预算与滚动开关；尺寸请求来源。
  完整观测放在独立安全边界，几何在途样本与完成更新样本分开标记。
- [ ] 只取最短反向序列（展开→20ms 收缩、展开→50ms 收缩→30ms 展开）。
  若 clip origin 变化而顶部节点 document 坐标不变，进入滚动分支；
  若 clip origin 不变而 host/ancestor 或节点 document 坐标变化，进入宿主/
  内容布局分支。两者不变但画面闪失时，检查 viewport 裁剪或绘制，不能继续猜滚动。
- [ ] 只有得到对应证据才做一个 A/B：滚动分支只验证自动滚动/原可视锚点的作用；
  宿主分支只验证面板处于稳定显示阶段时额外无界理想尺寸查询的作用。
  不同时改滚动开关、host 测量和动画。A/B 必须保留合法用户滚动，不以
  `scrollTo(0)`、固定生产面板高度、同步强制布局或按钮限制取得通过。
- [ ] 有效异常时序拿到后才补最小失败回归。用真实 summary 和 Footer：
  “始终容纳”场景无滚动；“固定外框”场景在 AirPods 之后添加足够内容，
  使展开和收缩都自然超过屏幕 cap，同时顶部及 disclosure 按钮保持可见。
  禁止准备阶段滚动到 AirPods 后还声称顶部可见。断言顶部在实际可见更新中的
  坐标、可见交集、原始 clip origin、有限 viewport 和锚边，精度为
  `1 / backingScaleFactor`；保留异步布局在途记录，不将其冒充合成器画面。

**验收门槛：** 用户复测仍出现即为失败；没有抓到异常或没有安全实窗路径时，
只报告证据缺口，不再用全量测试通过、10pt 初始化修复或 Footer 稳定代替验收。
