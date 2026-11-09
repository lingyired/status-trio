# AirPods 快速展开/收缩修复（2026-11-05）

基线：最新 `origin/feat/airpods-inline-toggle`，
`0620ad3c671764a11fba8e66e7501d60e9b95c83`。
分支：`codex/fix-airpods-rapid-disclosure`。未提交、推送或合并。
本报告取代旧动画重构文档对快速点击和实窗覆盖的结论。

## 根因与修复

1. **折叠布局延后 170ms。** 原行等待卸载回调才开始收缩。
   用原行运行新实窗测试，折叠 40ms 后仍以 290pt 为目标，正确折叠高度是 98pt。
   现在逻辑展开状态、模型挂载、可交互性和实际占位分别管理；点击立即改变容器
   动画目标，start/stop 同步跟随用户意图。控件树和模型保留，容器连续缩到零并
   局部裁剪，没有卸载计时器或过期卸载意图，折叠时分隔线不会漏出。
2. **窗口提前丢弃反向目标。** 原窗口先做 frame 相等判断，可能遗漏运行中的新
   目标。现采用单驱动：`OutputDeviceRow` 的容器高度是唯一动画源；窗口只跟随
   实际中间布局测量，不再维护另一个动画目标。容器驱动先接受新目标，再判断
   是否可立即结束；回到当前展示高度会取消旧轨迹，即使尚未发生第一个 tick。
3. **固定最终高度使内容先跳位。** 原 retarget 固定整个 Hosting 到最终高度并
   同步强制布局。实窗曾测得窗口/父容器 207pt、Hosting 229.5pt 且 y=-22.5pt。
   移除整个 pin API、固定高度字段及补偿偏移，Hosting 只填实际原生容器。
   调查版仅靠窗口裁剪仍使 AirPods 下方内容瞬跳 192pt，新测试先失败，再改为
   动画驱动 AirPods 容器的真实布局占位。后续 sections 和 Footer 都随其移动。
4. **重建 cubic 造成速度断点。** 原反向约从 +3000 跳至 -3000pt/s。
   `StatusPanelResizeAnimation` 改为 position/velocity/target 临界阻尼轨迹。
   同一行只有一个有限期 timer，反向保留上次实际展示位置对应的速度；不混用
   旧位置和未展示时刻的未来速度。临近目标在首次到达时停止，不穿越后震荡。
   数学层保留小数，容器与窗口边界按实际 display/backing scale 对齐并去重。
   保留的行观察 displayScale 变化，驱动同步重新对齐运行中及已收尾目标。
5. **关闭与放置状态。** 关闭保留的 Hosting 树不保证触发 `onDisappear`。
   测试曾抓到关闭后 7 个监听残留，以及关闭后设备改名重新启动 7 个监听。
   面板用实例级可见性发布同步停止读取与动画，晚订阅可获得当前可见状态；
   名称/异步布局更新不能在隐藏时重启工作。锚定锁实际选中的 top/bottom/center，
   按该侧限高，放不下就滚动。屏幕/Space 环境变化先重新放置再锁定新侧，避免
   将旧 frame 误判为新锚点的翻转方向。

没有 debounce、禁用按钮、固定面板高度或延长动画时间。其他不带容器动画的
内容变化直接跟随测量；不再由窗口给所有高度变化额外套一层动画。

## 数据与布局路径

`用户点击 → expanded + 硬件需求 → 容器高度驱动 → SwiftUI 实际占位测量
→ 既有布局合并队列 → NSPanel frame`。

`StatusPanelScrollArea` 仅一棵稳定滚动树，实际 viewport 填当前原生宿主，Footer
在其下方。实际占位测量在 preference 回调中直接上报，不先等另一次 body 更新；
同样的测量在 metrics 层去重，一次主线程 turn 合并为最新值。
只有 `attachWindow` 绑定的真实 NSPanel 使用填满视口模式；独立 Settings/预览
继续按自然理想尺寸测量，不能让无界尺寸提案穿透为窗口高度。它上报的是唯一
容器驱动的中间高度，不是第二套窗口动画的中间反馈。`sizeThatFits` 的宿主回报
在有明确滚动内容测量时只复用该测量，不能把当前窗口视口当成新的自然目标。
窗口 frame 写入不请求同步 display；动画 tick 不强制 layout。

原 `StatusPanelResizeCoordinator` 现仅服务 SwiftUI 容器，没有 NSRect 放置回调、
window writer、pin 或 unpin。`cancel()` / `markSettled()` 清理 timer、轨迹及采样
时间；晚到的已失效 tick 不再工作。移除实窗测试里恒真的 window phase 断言。Debug 窗口诊断的 phase 描述窗口自身（始终
没有独立动画），不能用它证明行 timer 已停止；timer 收尾由驱动测试及实窗停止
后不再写 frame 的断言分别覆盖。

## 文件

| 文件（相对 `Sources/StatusTrioCore`） | 修改责任 |
| --- | --- |
| `UI/OutputDeviceRow.swift` | 即时意图、容器占位动画和局部裁剪、模型复用、硬件需求 |
| `UI/StatusPanelResizeAnimation.swift` | 连续位置与速度、非震荡轨迹 |
| `UI/StatusPanelResizeCoordinator.swift` | 每行单高度驱动、实际采样速度、物理像素及清理 |
| `UI/AnchoredStatusPanel.swift` | 删除窗口动画与内容 pin、跟随实际测量、选中侧与预算 |
| `UI/StatusPanelScrollArea.swift` | 中间占位测量直接上报、稳定视口和 Footer |
| `UI/StatusPanelLayoutMetrics.swift` | 测量去重、实例可见性当前状态 |
| `UI/StatusPopoverView.swift` | 测量和可见性接线 |
| `UI/AirPodsSystemControlsView.swift` | 可注入异步读取器，默认真实硬件路径不变 |

`controlsFactory` / `readSnapshot` 是局部依赖注入，没有全局测试替身进入默认
产品路径。保留既有列表稳定 `ForEach` / `VStack`；相同 ID 的行值刷新不会重建模型。
设备名是 backend 的真实验证依赖，改名仍会更换依赖，但保留展开意图。

## 真实窗口测试

`AirPodsDisclosureIntegrationTests` 使用生产 `AnchoredStatusPanel`、
`StatusPanelHostingController`、`StatusPanelScrollArea` 和 `OutputDeviceRow`。
AirPods 数据与 IO listener backend 是 synthetic，不依赖真实耳机。Footer 为
40pt 原生测量标记，测量生产滚动区的 Footer 插槽；AirPods 后另放原生标记，
检测容器下方内容是否提前重排。旧的仅 Coordinator 窗口模拟测试由这些实窗测试
替换；数学、timer 与取消规则继续由独立测试覆盖。

输入是测试进程内向指定窗口 `NSWindow.sendEvent(mouseDown/up)`，经过真实
SwiftUI 按钮手势，不直接调用 toggle 或 Coordinator。没有全局事件投递、鼠标
移动、剪贴板操作、激活再恢复。测试实例非激活且逐次断言不成为 key window；
有限期激活观察从夹具初始化前持续到清理。结束只关闭自身窗口并恢复进程策略。

覆盖：

- 20ms 折叠、50ms 折叠再 30ms 展开、100ms 折叠、收缩中反向，以及首 tick 前反向。
- 连续 30 次 20–80ms 点击，每次检查即时硬件需求；最终折叠后再展开，模型仅一个。
- 分批异步状态、受控暂停的在途第二批、折叠后释放晚到更新、同 ID 列表刷新。
- 收缩/展开中关闭、保留树重开、隐藏时设备名称变化、停止后 frame 不再改写。
- 超屏、靠近屏幕下缘、初始翻转、无动画路径、锚点环境更新，以及三种原生背景。另有保留行的 displayScale 环境 2→1 切换；真实 1x 屏仍未测。

frame 约每 4ms 采样；Footer/行标记在 native didUpdate 后观察。锚定边和 Footer
底部误差不超过 1pt；每步位移按实际采样时间与驱动上界检查，收尾实际内容高度
必须等于窗口高度或同侧屏幕预算，停止后无继续写入。`didUpdate` 并非原子化
compositor 快照，异步合并的窗口跟随允许一个已观测布局步的间隔，但不能保持
终点跳位或持续偏差，最终相对位置回到 1pt 内。这些几何观察不能替代逐帧屏幕
录像或用户对手感的验收。

## 验证结果

最终定向命令（显式允许自有窗口，不开放全局输入）：

```bash
STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1 \
STATUS_TRIO_UI_ARTIFACTS_DIR=/Users/lingsmbp/.codex/visualizations/2026/11/05/01a1a921-3fe7-7243-a252-32ca02ef0180/airpods-rapid-disclosure \
bash scripts/test.sh 'AirPodsDisclosureIntegrationTests|StatusPanelResizeAnimationTests|StatusPanelResizeCoordinatorTests|StatusPanelScrollAreaTests|StatusPanelContentResizeTests|StatusPanelHeightCapTests|AirPodsSpatialObservationTests|AirPodsInlineControlsTests|OutputDeviceListeningModeRowTests'
```

**65 tests / 0 failures**，其中 **16 个真实 NSPanel 测试方法**。三背景和多组
快速点击在方法内分别建立独立窗口。30 次点击记录 552/751 个采样，最大间隔
约 10.8/19.0ms，2x backing，目标进程激活为 0；每次按钮事件均未成为 key window。
最终折叠与再展开截图已检查，折叠后无旧分隔线残留。

首次 full 暴露 `StatusPanelHeightCapTests` 的 7 个方法失败：真实面板的填满模式
错误用于独立 host，产生无界高度。修复为显式窗口绑定后，上述 7 项全部通过；
保留原失败日志，没有跳过断言或改大容差。

最终 `bash scripts/verify-local.sh full` **PASS**：

- Helper XCTest：15 tests，0 failures。
- Core XCTest：2524 tests，87 skipped，0 failures。可见 UI 按项目默认边界跳过，
  已由上面的独立定向运行覆盖，不宣称 full 本身运行了所有窗口测试。
- Swift Testing：875 tests / 127 suites，0 failures。
- Release 编译、非 Universal 本地应用包、platform/SDK/MobileBattery/Helper 契约，
  以及 27 项原生/离线管线脚本全部通过。

full 中 `Published`、`accepted_and_stapled` 等字样来自临时目录和 fake 工具的
离线发布模拟，不是真实发布或公证。源文件 manifest 在 full 后重新核对一致。
复审处理后未发现新增 P1/P2，最终 `git diff --check` 通过。

证据目录：
`/Users/lingsmbp/.codex/visualizations/2026/11/05/01a1a921-3fe7-7243-a252-32ca02ef0180/airpods-rapid-disclosure/`。
含 final-focused.log、final-full.log、原行/容器/隐藏读取/跨 scale/重锚回归红灯日志、CSV、截图、
最终源文件 SHA-256 manifest。早期调查副本位于子目录，不属于最终实现。

独立只读审查最初提出的 side/cap、逐点击意图和取消 gate 问题均已处理；架构
切换后复审的跨 scale 更新与无效 phase 断言也已处理。

## 范围与限制

实窗环境：macOS 27.2（26B123）、Apple Silicon、2x backing，Xcode 27.0。
真实 WindowServer 窗口和生产 SwiftUI 行已运行，非纯数学模拟。观察目标进程
激活与 key window；未完整测量鼠标、剪贴板、全部 Spaces 副作用。

真实 AirPods、macOS 13 真机、Intel、非 HiDPI 显示器及正常生产激活行为的
人工验收仍未执行。无发布、DMG、Universal、正式签名或公证验证结论。

交付前重新 fetch：`origin/main=5ff0cff2d66b8117a58388a7382faf40a3b3a857`。
目标分支相对 main 有 31 个独有提交、落后 65 个提交，未将 main 合入。
`AnchoredStatusPanel.swift` 等共享文件需在后续整合时重新核对；本轮证据仅属于
指定 feature 基线加本补丁，不代表未产生的 main 合并树。

## 验收应用

已通过 `UNIVERSAL_BUILD=0 bash scripts/build-worktree.sh release no-open` 构建：

- 路径：`/Users/lingsmbp/.codex/worktrees/airpods-rapid-disclosure/status-trio/dist/StatusTrio.app`
- Bundle ID：`com.lingsmbp.StatusTrio.dev.fix-airpods-rapid-disclosure`
- 开发代号：`Fix Airpods Rapid Disclosure`

带开发身份的本地 arm64 应用，没有自动打开，没有覆盖或退出用户的生产应用。
构建日志为证据目录中的 `review-app-build.log`。真实耳机快速切换手感仍待用户验收。
