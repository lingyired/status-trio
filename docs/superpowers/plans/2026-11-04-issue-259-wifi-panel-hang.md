# Issue #259：Wi-Fi 详情页高 CPU 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让打开 Wi-Fi 详情页后的窗口尺寸更新能够收敛，消除持续高 CPU / 无响应，并保留面板限高、滚动与锚定行为。

**Architecture:** 先按最终可放置 frame 判断是否需要写窗口，再拆开内容尺寸变化、自身 resize、屏幕预算变化三种事件。布局期间只提交请求，由每个拥有者的单个待处理操作合并最新值；滚动偏移采用相同调度机制但独立拥有生命周期。每阶段单独验证，不将“改成异步”当作收敛证明。

**Tech Stack:** Swift、AppKit、SwiftUI、Combine、XCTest / Swift Testing；沿用 SwiftPM 与项目本地验证脚本。

**Spec:** [采样复核与整改方案](../../issue-259-wifi-hang-analysis.md)。先阅读该文档，特别是证据边界；`406` 是采样次数，不是递归深度，ProgressView 抖动尚未证实。

## Global Constraints

- 在现有分支 `fix/issue-259-wifi-cpu-hang`、worktree `/Users/lingsmbp/Documents/aiwork/status-trio-issue-259` 实施；分支起点为 `004cc56a7fadcd6a8492f889dfe7c317fd472012`，已有分析提交 `1064bf4394a84f3e416485d88efa474512720558`。保留当前未提交的分析更正。
- macOS 最低版本保持 **13**，SDK 下限保持 **26**；不使用 `isolated deinit`，不将 actor-isolated 方法直接作为函数值。
- 实施前读取仓库 `AGENTS.md`、`.agents/rules/performance.md`、`.agents/rules/macos-compatibility.md`、`.agents/rules/network.md`。
- 不修改 CoreWLAN 扫描策略、定位权限、扫描频率或 Wi-Fi 文案；不为该修复固定 ProgressView 高度，不重写整个滚动容器。
- 不添加轮询、无限重试或常驻诊断日志；临时观测只记录尺寸、来源与次数，不记录 SSID。
- 保留单滚动容器、固定 footer、短内容贴合、长内容限高、菜单栏 / Dock 锚定边及三种背景。
- 不放宽既有尺寸、位置或布局断言。新增纯逻辑与离屏测试保持无窗口展示；真实窗口用例继续遵守 `VisibleUITestCase` 边界。
- Swift 测试仅通过 `bash scripts/test.sh [filter]`；交付前运行 `bash scripts/verify-local.sh full`，Visible UI 默认跳过须单列。
- 本计划不授权发布或提前合并；用户验收后再合并 / 推送，issue 随正式发布统一核对关闭。

## Review Focus

1. **最终尺寸与中间尺寸不同：** 小数高度上限及屏幕限宽后，重复请求不应继续写 frame；任务1覆盖。
2. **事件相互反馈：** 自身 resize 不得恢复旧内容尺寸，菜单栏顶边 / Dock 底边仍正确；任务2覆盖。
3. **预算变化与缓存：** 同一内容预算由300缩为200再恢复300，不能永久停在200；任务2与4覆盖。
4. **在途操作跨生命周期：** 关闭再打开、更换内容、滚动桥 detach / rebind 后，旧操作不得写入新实例或旧 Binding；任务2与3覆盖。
5. **扫描状态与真实集成：** 扫描中 / 扫描结束、短 / 长列表、三种背景须使用窗口实际共享的 metrics 验证；任务4覆盖。

## 文件与责任

| 文件 | 责任 |
| --- | --- |
| `Sources/StatusTrioCore/UI/StatusPanelPlacement.swift` | 增加最终 frame 更新决策，复用既有放置、翻转、限幅数学 |
| `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift` | 分离三类事件、统一写 frame、失效旧请求及重新测量 |
| 新建 `Sources/StatusTrioCore/UI/StatusPanelLayoutUpdateScheduler.swift` | 主线程单操作合并；只做调度和失效，不负责布局数学 |
| `Sources/StatusTrioCore/UI/StatusPanelScrollArea.swift` | 滚动偏移延后发布、更新 Binding、解绑时失效 |
| 新建 `Tests/StatusTrioCoreTests/StatusPanelFrameUpdateTests.swift` | 最终 frame 判重、限幅与收敛行为 |
| 新建 `Tests/StatusTrioCoreTests/StatusPanelLayoutUpdateSchedulerTests.swift` | 合并、失效、重入、释放的确定性测试 |
| 新建 `Tests/StatusTrioCoreTests/StatusPanelScrollBridgeTests.swift` | 离屏滚动桥发布时机和生命周期 |
| `Tests/StatusTrioCoreTests/StatusPanelContentResizeTests.swift` | 真实面板与内容共享 metrics，窗口反馈及锚定回归 |
| `Tests/StatusTrioCoreTests/StatusPanelHeightCapTests.swift`、`StatusPanelScrollAreaTests.swift` | 同一实例预算恢复、扫描状态布局回归 |
| `docs/issue-259-wifi-hang-analysis.md` | 记录最终根因证据、版本、验证结果与未测项 |

任务按 **1 → 2 → 3 → 4** 串行执行；任务2和3共用调度接口。不要安排多个实现者同时编辑面板或滚动容器。

---

## Task 1：最终目标 frame 判重

**Files:** 修改 `StatusPanelPlacement.swift`、`AnchoredStatusPanel.swift:202–225`；新建 `StatusPanelFrameUpdateTests.swift`；回归 `StatusPanelPlacementTests.swift`。

**Interfaces:** 新增纯函数：

```swift
static func contentFrameUpdate(
    from currentFrame: NSRect,
    contentSize: NSSize,
    maximumHeight: CGFloat?,
    anchor: StatusPanelAnchor?,
    screens: [StatusPanelScreen],
    dockInset: NSEdgeInsets
) -> NSRect?
```

返回 `nil` 表示无须写入；否则返回最终可放置 frame。无 anchor 时保持当前 origin。尺寸须为正且有限；无效测量返回 `nil`。沿用现有 ceil 意图及 placement 限幅，比较必须发生在全部限幅之后；保留尺寸差 `>= 0.5pt`、位置变化精确比较的既有边界，不新增更宽容差。

- [ ] **Step 1：写失败回归。** 固定屏幕 / anchor 数据，使最终高度上限为 `200.25`；当前高度 `200.25`、内容高度400时 `XCTAssertNil(update)`。屏幕宽316、左右margin各8、当前宽300、请求宽330也断言nil。另覆盖高度从120变160、仅origin变化、0 / NaN / infinity测量。先将旧决策原样提取到函数并接入生产调用，使失败来自旧行为，而非仅缺少符号。
- [ ] **Step 2：运行红测。** `bash scripts/test.sh 'StatusPanelFrameUpdateTests|StatusPanelPlacementTests'`；确认小数预算或限宽用例失败，记录旧判断拿中间size比较的证据。
- [ ] **Step 3：最小修复。** 先得到最终placement frame，再判重；`applyInitialContentSize()` 与 `applyContentSize(_:)` 复用该决策。保持屏幕翻转、Dock inset与原点规则；不要以“上次请求一样”永久屏蔽更新。
- [ ] **Step 4：验证收敛。** 模拟实际写入：第一次更新后令current等于返回frame，再重复同一输入100次，`XCTAssertEqual(frameWrites, 1)`；稳定状态再请求新内容高度应仍产生更新。重复Step 2命令，要求新旧回归均通过。
- [ ] **Step 5：提交本任务。** 只暂存本任务源码和测试；建议subject：`fix(panel): compare the final placed frame before resizing`。

## Task 2：分离事件职责，合并布局请求

**Files:** 新建调度器及其测试；修改 `AnchoredStatusPanel.swift:87–99, 173–185, 238–269, 301–371`；扩展 `StatusPanelFrameUpdateTests.swift` 与真实resize回归。

**Interfaces:** 新增 `@MainActor final class StatusPanelLayoutUpdateScheduler`：

```swift
typealias Schedule = (@escaping @MainActor () -> Void) -> Void
init(schedule: @escaping Schedule)
func enqueue(_ operation: @escaping @MainActor () -> Void)
func invalidate()
```

生产端用显式闭包把operation送到主队列，测试端把operation放进可手动drain的队列。每个拥有者各持一个scheduler，不做全局共享。新增面板私有入口 `scheduleContentSize(_ size: NSSize)`、`handleWindowResize()`、`handlePlacementEnvironmentChange()`、`flushPendingLayout()`，以及host的 `invalidateSizeMeasurement()`。面板保存 `pendingMeasuredContentSize: NSSize?` 和 `needsContentMeasurement: Bool`；排队operation统一调用flush并读取这些最新字段，不能让后来的content请求覆盖尚未执行的environment重新测量意图。

- [ ] **Step 1：补调度与反馈测试。** 100次enqueue在drain前应满足 `XCTAssertEqual(pendingCallbacks.count, 1)`；drain后只执行最新operation。invalidate后旧callback执行次数为0；invalidate后重新enqueue能执行新请求；operation内enqueue下一项时保留该项。另覆盖scheduler释放后队列不强持面板。
- [ ] **Step 2：补面板行为红测。** 固定旧测量400、当前窗口200、预算300，自身resize处理后高度必须仍200，禁止恢复到300；随后真实内容请求260应增长至260。连续100次自身resize后，记录写frame次数不再增加。environment请求后、drain前插入旧content请求，仍须执行重新测量，不得以旧高度结算。真实窗口版本放进 `VisibleUITestCase`；纯决策不依赖orderFront。新决策应由生产入口复用，避免在测试中重写一份算法。
- [ ] **Step 3：运行红测。** `bash scripts/test.sh 'StatusPanelLayoutUpdateSchedulerTests|StatusPanelFrameUpdateTests'`；新类型尚不存在时的编译失败可用于调度器API红测；面板反馈问题另须在旧行为下失败。
- [ ] **Step 4：实现调度器。** 单个pending callback加最新operation，flush前清除pending状态；invalidate清除operation并增加代次，旧callback不得清掉新代次pending。排队闭包弱持拥有者。不用sleep、每事件一个Task或固定时长debounce。
- [ ] **Step 5：实现三类事件。** 内容变化记录 `lastMeasuredContentSize` 并合并应用；该缓存只表示host测量，不再称“自然文档高度”。自身resize以当前窗口尺寸校正放置，允许必要屏幕限幅，但不重放旧测量来放大窗口。屏幕 / Space变化重算预算后请求host重新测量，不以旧限高测量冒充自然高度。
- [ ] **Step 6：统一窗口写入。** 增加私有 `applyFrameIfNeeded(_ target: NSRect)` 作为尺寸 / 定位写入入口，最终判重后 `setFrame(target, display: false)` 并按需更新阴影。host布局回调只提交尺寸，不同步改窗口；初次show与透明reveal仍保留既有顺序。
- [ ] **Step 7：接好生命周期与重测。** installContent、close、旧host回调各有代次校验；隐藏期间不持续排队写窗口，重开时重新测量。`invalidateSizeMeasurement()` 重置host上次报告缓存并标记needsLayout，在安全的延后操作中触发必要布局，不在viewDidLayout内强制重入。使用弱引用保存重测入口，避免面板—host循环引用。
- [ ] **Step 8：绿测与提交。** 重跑Step 3及 `bash scripts/test.sh 'StatusPanelHeightCapTests|StatusPanelPlacementTests'`。通过后提交调度、面板和相关测试，建议subject：`fix(panel): separate resize placement from content sizing`。

## Task 3：滚动桥延后写回，解绑失效

**Files:** 修改 `StatusPanelScrollArea.swift:212–312`；新建 `StatusPanelScrollBridgeTests.swift`；复用任务2调度器。

**Interfaces:** 保持 `PanelScrollBridge` 的View行为；为离屏测试将其访问级别由private收窄调整为模块内可见。Coordinator保留 `bind(to:)`、`detach()`，新增 `updateBinding(_ binding: Binding<CGFloat>)`；构造时允许注入任务2的scheduler。所有publish来源统一走合并入口。

- [ ] **Step 1：写时机红测。** 用setter计数的Binding及离屏NSScrollView：bind / 重复bind / updateNSView返回前 `XCTAssertEqual(bindingWrites, 0)`；drain后偏移符合 `PanelScrollOffset.topOffset`。100次bounds通知合并为一次最新偏移发布；不得人为展示窗口。
- [ ] **Step 2：写生命周期红测。** bind A后排队，再detach，drain不得写Binding；改绑B后drain只读取B。更新Binding后旧Binding写入次数为0、新Binding拿到最新偏移。偏移变化 `<= 0.5pt` 不发布，沿用现有阈值。
- [ ] **Step 3：运行红测。** `bash scripts/test.sh 'StatusPanelScrollBridgeTests|StatusPanelScrollAreaTests'`；确认旧同步publish触发新增时机断言。
- [ ] **Step 4：最小修改。** 首次bind、重复bind、bounds通知都只排一次发布，flush时读取当前scrollView和当前Binding；updateNSView更新Binding；detach移除observer并invalidate。保持隐藏原生scroller及4pt指示条的既有行为。
- [ ] **Step 5：绿测并独立提交。** 重跑Step 3；建议subject：`fix(panel): defer scroll offset publication outside layout`。报告该修改为独立状态更新问题，不宣称已单独解释本次hang。

## Task 4：真实反馈回归与性能验收

**Files:** 修改 `StatusPanelContentResizeTests.swift`、`StatusPanelHeightCapTests.swift`、`StatusPanelScrollAreaTests.swift`；更新分析文档。诊断只作有界Debug观测，不建立常驻监控子系统。

**Interfaces:** 根视图使用同一个 `panel.layoutMetrics`。任务2的窗口写入入口是观察写入次数的位置；若需测试计数钩子，只在Debug / 测试配置启用，不新增Release日志或轮询。

- [ ] **Step 1：修正fixture并补失败集成。** 现有ResizeTests传入独立metrics，改为先创建panel，再把 `panel.layoutMetrics` 交给根视图。新增同一实例cap `300 → 200 → 300` 用例；对内容600 + footer40，断言总高依次为300、200、300（沿用既有accuracy 1），document仍比viewport高，footer始终不在document内。
- [ ] **Step 2：补扫描状态与锚定覆盖。** 同一root在扫描中 / 结束、空列表 / 长列表之间转换；检查窗口不超过budget、只有一个scrollView、主线程测试续体可继续执行。菜单栏顶边与Dock底边稳定沿用 `accuracy: 0.5`；三种背景都覆盖。静止fixture在settle后继续处理100次resize，frame写入次数增量为0；尺寸或预算真实改变后允许新写入。
- [ ] **Step 3：运行聚焦验证。** `bash scripts/test.sh 'StatusPanelFrameUpdateTests|StatusPanelLayoutUpdateSchedulerTests|StatusPanelScrollBridgeTests|StatusPanelPlacementTests|StatusPanelHeightCapTests|StatusPanelScrollAreaTests|WiFiNetwork|StatusMenuBuilderTests'`；要求退出0且实际匹配测试。Visible UI用例默认跳过，不能将跳过写成通过，也不能为了覆盖而直接设置UI opt-in。
- [ ] **Step 4：采集修复前后运行证据。** live测试前加载 `.agents/skills/background-ui-testing/SKILL.md` 及所需引用；优先复用同worktree仍属本次所有的Debug实例，使用 `bash scripts/launch-computer-use.sh --reuse`，需要构建再按项目launcher流程。身份冲突先停止该路线，不关闭其他人的实例。无可用实例限定输入能力时标记 `BLOCKED (no Computer Use provider)`，安排用户手测；不抢前台或改定位权限。
- [ ] **Step 5：限定诊断范围。** 临时观测记录来源（content / resize / environment）、测量、cap、当前 / 最终frame、resize数与写入数；每次会话最多200条明细、最多60秒，满额停止明细但保留会话计数，面板关闭全部停止。记录设备、macOS、SDK、分支、SHA、dirty差异、实例PID与背景类型。若无原始baseline，只能报告修复版观测，不伪造前后对比。
- [ ] **Step 6：执行10分钟验收。** 扫描完成且列表稳定后，Debug frame写入计数在后续60秒窗口内不再增加；CPU记录整段及最后60秒，主线程能处理返回 / 关闭，重新sample不再由同一通知—setFrame链长期主导。正常扫描/列表变化期间允许合理尺寸更新，不把spinner正常动画当作零CPU失败。另跑无权限已有状态、空网络、长列表、预算变化和三种背景短测，不自动切换系统权限。真实环境无法覆盖的项明确NOT RUN。
- [ ] **Step 7：定位未收敛分支。** 若任务1–3后仍高CPU，依据实际frame序列区分通知回环、host测量震荡与桥接写回，不继续盲叠去抖。如果必须重写内容测量或改扫描策略，先更新分析与计划，当前候选修复不得标为完成。
- [ ] **Step 8：交付验证。** fetch最新 `origin/main`，记录base与差异；有共享文件变化先处理冲突，再在最终集成树执行 `bash scripts/verify-local.sh full`。full报告保留Visible UI跳过、macOS 13真机NOT RUN以及签名/公证等未覆盖项；full通过不等于性能验收通过。
- [ ] **Step 9：提交报告与交付。** 更新分析文档，分开写“已证实根因 / 修复 / 自动测试 / 实测 / 未测”；纳入当前分析更正，建议subject：`test(panel): cover resize convergence and budget recovery`。保留分支与worktree，交给用户验收；验收前不合并、不推送、不关闭issue。

## 执行方式与完成定义

建议主执行者在当前会话按任务顺序实施，每任务完成一个红绿测试周期并作小提交；最终请独立审查者检查整分支的收敛与生命周期逻辑。四个任务依赖同一套窗口 / 调度接口，不适合并行改共享文件。

只有最终frame幂等、旧操作失效、预算恢复、锚定 / 滚动回归全部通过，且现场高CPU症状得到运行时验证，才可称issue修复已确认；无法取得现场复现时应标“候选修复，待用户验收”。本计划的编写和检查本身不代表已执行修复或测试。
