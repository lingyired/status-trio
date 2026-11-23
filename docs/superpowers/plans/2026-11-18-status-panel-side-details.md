# 状态面板详情并排显示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为全部状态面板详情提供可选的并排显示，并让同一开关控制两种模式的重开恢复行为。

**Architecture:** `StatusPanelViewModel` 保存路由和当前展示位置，`StatusBarController` 管理主窗、附属窗和共同的开关流程。SwiftUI 复用同一套详情内容，两个窗各自测量高度。纯定位和状态规则通过无窗口测试锁定。

**Tech Stack:** Swift、AppKit、SwiftUI、Combine、XCTest、Swift Testing。

**Spec:** [状态面板详情并排显示](../specs/2026-11-18-status-panel-side-details-design.md)（`9cfb74fa`）。工作分支 `status-panel-side-details` 基于 `feat/system-monitor-detail-pages` 的 `41c38b0e`。

## Global Constraints

- macOS 13+。继续使用现有窗口背景、减弱透明度回退、全屏 Space 和后台测试约束。
- 「并排显示详情」默认关闭。保留 `returnsToSummaryOnOpen` 的存储值、默认值、导入导出字段，设置界面反向绑定。
- 详情宽 330 pt，面板间隔 8 pt，屏幕边缘至少留 8 pt。只在主面板所在显示器的可用范围内摆放，计入自动隐藏 Dock 预留空间。
- 所有正常入口共用路由和窗口控制。详情内容及权限入口沿用现有行为。并排时摘要与当前详情共用已有采集服务。
- 测试走 `bash scripts/test.sh`。排序原生窗口或创建真实状态项的测试遵循仓库可见 UI 开关。改动前读性能和 macOS 兼容规则。交付前运行 `bash scripts/verify-local.sh full`。

## Review Focus

- 屏幕坐标出现负值或显示器贴在右边时，仍在主面板所在屏幕内找空间。任务 1。
- 从旧备份导入时，缺少并排字段会保留本机选择。任务 2。
- 正从 CPU 换到网络时，频率读数和高占用应用榜单随新详情切换，摘要采样继续。任务 3。
- 切换呈现位置时仍有打开的 Wi-Fi 展开区，只换宿主并保留路由与展开状态。任务 3–4。
- 在两个窗口、确认框、图标和空白间隙之间点击或转移焦点，按各自规则处理且一次图标点击只触发一次切换。任务 4。

---

### Task 1 — 同屏摆放规则

**Files**

- 修改 `Sources/StatusTrioCore/UI/StatusPanelPlacement.swift`，共用屏幕选择和 Dock 可用区域计算。
- 新建 `Sources/StatusTrioCore/UI/StatusPanelDetailPlacement.swift` 和 `Tests/StatusTrioCoreTests/StatusPanelDetailPlacementTests.swift`。

**Interfaces**

- 用 `StatusPanelPlacement.screenContaining(_:screens:)` 和 `usableFrame(_:dockInset:)`。若后者仍为私有，开放到模块内部。
- 提供 `StatusPanelDetailPlacement.frame(summaryFrame: NSRect, detailHeight: CGFloat, screens: [StatusPanelScreen], dockInset: NSEdgeInsets) -> Placement?`。`Placement` 提供 `side: Side`（`.left`、`.right`）、`frame: NSRect` 和 `maximumHeight: CGFloat`。

- [ ] 写无窗口测试，使用可用区域 `NSRect(x: 0, y: 0, width: 1000, height: 700)` 和主窗宽 330 pt。

```swift
#expect(place(summaryX: 324)?.frame.minX == 662)
#expect(place(summaryX: 0)?.side == .right)
#expect(place(summaryX: 600)?.frame.minX == 262)
#expect(place(summaryX: 325) == nil)
```

  将左侧边界锁定为 `place(summaryX: 346)?.frame.minX == 8`，`place(summaryX: 345) == nil`。另测主窗顶边 `650`、详情高 `200` 时详情顶边 `650`，详情高 `900` 时高度 `684` 且下边 `8`。将坐标平移到原点 `(-1600, 200)`，相对结果不变。主窗在该屏右缘时，即使相邻屏可放详情也选本屏左侧。主窗横坐标为 `324` 且右侧有 `20` pt Dock 预留时返回 `nil`。主窗横坐标为 `600` 且右侧有 `20` pt Dock 预留时仍选择左侧。没有屏幕或主窗中心不属于任何显示器时返回 `nil`。
- [ ] 运行 `bash scripts/test.sh 'StatusPanelDetailPlacementTests|StatusPanelPlacementTests'`，确认新类型未定义时失败。
- [ ] 实现定位函数。先在可用区域内扣除 8 pt 边距，再分别判断主窗右、左的完整 330 pt 余量。取主窗顶边作为详情顶边起点，按剩下的高度预算截断，并在可用区域内移动详情窗。先确认尺寸为正数、坐标有限且主窗所在屏幕有效，再计算可用区域。
- [ ] 运行同一过滤命令，确认新旧定位用例通过。
- [ ] 提交 `feat(panel): resolve adjacent detail placement`。

### Task 2 — 设置与文案

**Files**

- 修改 `Sources/StatusTrioCore/Settings/SettingsStore.swift`、`Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift`、`Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift`。
- 修改 `Sources/StatusTrioCore/Localization/LocalizationKey.swift` 和 `Sources/StatusTrioCore/Resources/*/Localizable.strings` 的 12 套语言。
- 测试 `Tests/StatusTrioCoreTests/SettingsPreferenceCatalogTests.swift`、`Tests/StatusTrioCoreTests/SettingsTransferTests.swift`、`Tests/StatusTrioCoreTests/SettingsViewTests.swift`。

**Interfaces**

- 提供 `SettingsStore.showsPanelDetailsAlongside: Bool`（`@Published`，默认 `false`）和 `restoresPanelDetailsOnOpen: Bool`（通过现有发布属性读写的反向计算属性）。导入导出使用 `showsPanelDetailsAlongside` 和已有的 `returnsToSummaryOnOpen` 两个键。
- 提供本地化键 `settingsPanelShowsDetailsAlongside`、`settingsPanelShowsDetailsAlongsideDescription`、`commonCloseDetail`。复用旧恢复开关的本地化键并更新其文案。

- [ ] 在现有短生命周期默认值和转移测试夹具中加入 `testDetailPresentationPreferencesRoundTrip`、`testLegacyImportPreservesSideDetailsAndReopenPolarity`、`testDetailReopenToggleInvertsLegacyPreference`。覆盖下列断言。

```swift
XCTAssertFalse(store.showsPanelDetailsAlongside)
XCTAssertTrue(store.restoresPanelDetailsOnOpen)
store.restoresPanelDetailsOnOpen = false
XCTAssertTrue(store.returnsToSummaryOnOpen)
XCTAssertFalse(store.restoresPanelDetailsOnOpen)
```

  往返保存后，新建的设置对象读取同样的两个布尔值。只应用 `["returnsToSummaryOnOpen": .bool(false)]` 时，之前为 `true` 的并排值仍为 `true`，恢复显示为开启。`SettingsPreferenceCatalog.prepare` 对并排字段的无效类型返回 `.bool(false)` 和警告。另在 `SettingsViewTests` 断言简体中文两行标签与设计一致。
- [ ] 运行 `bash scripts/test.sh 'SettingsPreferenceCatalogTests|SettingsTransferTests|SettingsViewTests|LocalizationParityTests'`，确认新属性或文案检查红灯。
- [ ] 接入持久化、目录及打开行为分组。简体中文使用「并排显示详情」「重新打开时恢复详情页」「关闭详情」。并排描述说明右侧放不下换左，恢复描述限定上次收起时仍开启。`PopoverSectionView` 先保留现有导航外观，由任务 4 接入并排功能时一并呈现新并排开关，避免中间提交出现无效控件。
- [ ] 用同一过滤命令确认通过。
- [ ] 提交 `feat(settings): store panel detail display preferences`。

### Task 3 — 路由、变更范围和采集

**Files**

- 修改 `Sources/StatusTrioCore/Presentation/Panel/StatusPanelRoute.swift`、`Sources/StatusTrioCore/Presentation/Panel/StatusPanelViewModel.swift`。复用 `Sources/StatusTrioCore/Monitoring/HardwareMetricsService.swift` 已有 API。
- 测试 `Tests/StatusTrioCoreTests/StatusPanelRouteTests.swift`、`Tests/StatusTrioCoreTests/HardwareMonitorPanelDemandTests.swift`、`Tests/StatusTrioCoreTests/TopAppsPanelDemandTests.swift`、`Tests/StatusTrioCoreTests/StatusPanelDemandTests.swift`。

**Interfaces**

- `StatusPanelDetailPresentation: Equatable` 的值为 `.inline`、`.alongside`，两者都可表达已选中的详情所在位置。当前有没有选中详情由 `route` 判断。
- ViewModel 提供 `detailPresentation: StatusPanelDetailPresentation`、`isSummaryVisible: Bool`（摘要路由或并排详情）、`setDetailPresentation(_ presentation: StatusPanelDetailPresentation)`。复用 `prepareForPresentation()`、`showSummaryPage()`、现有打开入口和失效检查。

- [ ] 增加 `testAllDetailRoutesUseOneSummaryVisibilityRule`、`testExplicitCloseClearsReopenRoute`、`testSwitchingHostKeepsWiFiDisclosure`、`testRepeatingCurrentWiFiRouteKeepsDisclosure`、`testAlongsideHardwareDemandUnionsMetricsAndDropsDetailOnlyWork`。用已有路由与 demand 夹具断言以下结果。

```swift
XCTAssertTrue(model.isSummaryVisible)
XCTAssertEqual(model.route, .wifi)
XCTAssertEqual(model.wifiDisclosure, WiFiPanelDisclosureState(showsDetails: true, showsMore: true))
XCTAssertEqual(metrics, HardwareMetricsService.hardwareSummaryMetricIDs
    .union(HardwareMetricsService.detailMetricIDs(for: .cpu)))
XCTAssertEqual(model.route, .summary)
```

  测试覆盖四个常规详情和 `HardwareDetailKind.allCases`。两种展示下分别验证恢复开关的开关组合、主动关闭、关闭后入口失效。打开 CPU 后视图切换到网络，需求变为摘要与网络指标的并集，CPU 专用采集停止，榜单请求改为网络。关闭详情后只保留摘要，整组关闭后首要断言详情需求为空，再按已有后台设置断言采样。切换宿主保持选中页、Wi-Fi 展开状态和详情生命周期计数。重复点击已选中入口也保留状态。
- [ ] 运行 `bash scripts/test.sh 'StatusPanelRouteTests|HardwareMonitorPanelDemandTests|TopAppsPanelDemandTests|StatusPanelDemandTests'`，确认新增行为未实现时失败。
- [ ] 实现展示位置与路由分离。宿主切换只更新 `detailPresentation`，整组收起释放活动内容，ViewModel 保留轻量路由。主动关闭走 `showSummaryPage()`。输入或电池等可用性检查沿用已有路由，并在模块或数据失效时清空路由。
- [ ] 将 `updateHardwareMetricsDemand` 里的 `.panel` 指标改为可见摘要与详情的集合并集，通过一次 `begin(.panel, metrics:)` 更新。继续只为当前详情设置专用 payload 和 Top Apps。内容宿主迁移期间，详情开关动作与立即采样都由稳定详情路由驱动。检查摘要的采集和 SwiftUI 可见性也以主界面实际显示为准。
- [ ] 跑同一过滤命令，确认通过。
- [ ] 提交 `refactor(panel): track summary and detail visibility separately`。

### Task 4 — 接入窗口、内容和交互

**Files**

- 新建 `Sources/StatusTrioCore/UI/StatusPanelDetailCoordinator.swift` 和 `Tests/StatusTrioCoreTests/StatusPanelDetailCoordinatorTests.swift`。
- 修改 `Sources/StatusTrioCore/UI/StatusBarController.swift`、`Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`、`Sources/StatusTrioCore/UI/StatusPopoverView.swift`、`Sources/StatusTrioCore/UI/PanelFocusDismissPolicy.swift`、`Sources/StatusTrioCore/UI/PopoverDismissalPolicy.swift`、`Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift`。
- 修改 `Sources/StatusTrioCore/UI/NavigationBackRow.swift` 共用标题控件。在共享控件和详情宿主传递环境值，现有五个视图在这个控件中统一切换返回／关闭样式。
- 扩展 `Tests/StatusTrioCoreTests/PanelFocusDismissPolicyTests.swift`、`Tests/StatusTrioCoreTests/StatusPanelLayoutIntegrationTests.swift`。

**Interfaces**

- 提供 `StatusPanelDetailCoordinator.update(route: StatusPanelRoute, enabled: Bool, summaryFrame: NSRect, screens: [StatusPanelScreen], dockInset: NSEdgeInsets) -> Decision`，`Decision` 为 `.hidden`、`.inline` 或 `.alongside(StatusPanelDetailPlacement.Placement)`。更新传入的 `summaryFrame` 是主界面正常布局时的窗口矩形。内容高度的变化适用独立的窗口测量，初次选择只需要定位所需的宽度。
- 在 `AnchoredStatusPanel` 增加 `onUnhandledEscape: (() -> Bool)?` 和支持受调用方定位的 `showAsDetail(in placement: StatusPanelDetailPlacement.Placement)`。`StatusPopoverView` 以 `Host`（`.primary`、`.detail`）决定主栏、面板内详情或附属详情的内容，由 `StatusBarController` 用同一套动作分别安装。
- `PopoverDismissalPolicy` 新增缺省为空的 `panelFrames: [NSRect]`。独立窗口的焦点判断将两块面板都标记为 `isPanel`。

- [ ] 新增 headless 测试 `testSwitchingRoutesKeepsSideUntilGeometryChanges`、`testFallbackReevaluatesOnScreenChange`、`testNoSideWindowWithoutActiveDetail`、`testPanelClicksAndGapHaveDifferentDismissal`、`testEscapePreservesInlineCloseAndClosesAlongsideFirst`。用可注入决策和回调测试窗口协调，带真实窗口的断言放到现有可见 UI 隔离边界。

```swift
#expect(!policy.shouldDismiss(at: NSPoint(x: 120, y: 20)))
#expect(policy.shouldDismiss(at: NSPoint(x: 104, y: 20)))
#expect(!policy.shouldDismiss(at: NSPoint(x: 100, y: 20)))
```

  上例主窗横跨 `0...100`，详情跨 `108...208`，测试高度内点。补测图标边界的一次点击切换、两窗互换焦点、详情弹出的确认框或菜单、设置保留开启／关闭、点击外部只关一次。恢复详情首次放到正确宿主，显示模式热切换和重新摆放保持现有路由与展开状态，主窗 frame 与摘要滚动位置稳定。并排设置开启后路由变回摘要，附属窗和观察者立即卸载。
- [ ] 运行 `bash scripts/test.sh 'StatusPanelDetailCoordinatorTests|PanelFocusDismissPolicyTests|StatusPanelLayoutIntegrationTests'`，确认新增接口或交互断言红灯。
- [ ] 接入现有窗口安装和定位。`presentPopover` 负责统一入口，依据主界面正常几何及时算出首帧模式，恢复并排时直接渲染摘要。挂接已有主窗尺寸和屏幕／Space 变化通知，横向可用区域变化时重算。Dock 入口复用已有自动隐藏预留，菜单栏与快捷键按主窗所在显示器解析该预留。详情自身尺寸变化只更新垂直位置。测量异步回调按窗口会话或测量 ID 丢弃过期结果。
- [ ] 设置附属窗的非激活属性、背景、独立高度和滚动预算、全屏与 Debug 下受控的显示行为。共用主窗详情 action 构建路径。`.detail` 时把共享顶部返回按钮换成「关闭详情」，提供本地化无障碍标签。接入焦点移交和关闭后回到触发入口，入口失效时回到主窗可用控件。
- [ ] 由主控制器协调外部点击、焦点切换和 Esc。保留图标已有防止鼠标按下收起后抬起又重开的路径。已打开的控件或确认窗先处理 Esc，之后通过 `onUnhandledEscape` 收起附属详情，再让原有处理收起整组。主动关详情清除路由并移除附属内容，整组收起先处理附属窗再执行现有主窗关闭清理，并保留可恢复路由。设置保留和后台测试豁免适用于整组。
- [ ] 在打开行为分组显示任务 2 的并排开关。观察该设置并合并过期回调，同步当前已选详情的宿主。确认主题变化同时应用到两窗。
- [ ] 用同一过滤命令验收后，另跑 `bash scripts/test.sh 'StatusPanel|PanelFocusDismissPolicyTests|HardwareMonitorPanelDemandTests|TopAppsPanelDemandTests|SettingsPreferenceCatalogTests|SettingsTransferTests|SettingsViewTests|LocalizationParityTests'`，确认通过。
- [ ] 提交 `feat(panel): show detail in an attached side panel`。

### Task 5 — 交付验证

- [ ] 刷新 `origin/main` 并记录当前分支 SHA、指定基线和与主线的分歧。检查与基线的 diff 及共享控制器、设置目录的交叉改动。按仓库顺序协调后续集成。
- [ ] 在最终提交运行 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=0 bash scripts/verify-local.sh full`。记录退出状态、跳过的可见 UI 和未覆盖项。
- [ ] 真机验证前读 `.agents/skills/background-ui-testing/SKILL.md`，按仓库方案绑定当前 worktree 的后台 Debug 实例。分别记录当前 macOS 与 Ventura 的鼠标、键盘、VoiceOver、菜单栏／Dock／快捷键、多屏、全屏、Dock 自动隐藏、设置窗口保留、聚焦与关闭结果。需要前台或实机授权的步骤按仓库规则留给相应验证环节。
- [ ] 给用户提供已验证的开发构建与复测场景，保留分支和 worktree 供验收。
