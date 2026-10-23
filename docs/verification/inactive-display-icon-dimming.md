# 非焦点显示器：彩色菜单栏图标未随系统灰化

状态：**真实双屏实验已完成；A0/A1/A3 均不能继承系统灰化，A2 能灰化但会
回归 #112 与 20 fps 预算，正式修复暂不实施**。生产代码未改动，只记录证据与
可复现边界；若后续要修，需要先找到能区分每个屏幕副本的公开系统信号，或接受
A2 的已知退化。

## 现象

多显示器时 macOS 会把非焦点显示器的菜单栏整体调暗。Status Trio 的模板部分
（圆环底轨、电量数字、Wi-Fi 等）会跟着变暗，但 AirPods 蓝色、供电绿色、
低电量黄色、临界电量红色这些彩色区域保持原来的亮度。

## 实测环境

| 项目 | 值 |
| --- | --- |
| 机器 | MacBook Pro，Apple M3 Max，macOS 27.0.1（26A434） |
| 焦点屏 | 内建 Liquid Retina XDR，3456×2234 @2x；切换后两台屏幕各做过一次焦点屏 |
| 非焦点屏 | XV272U，4096×2304 物理像素 / 2048×1152 @2x，144 Hz |
| Space | `spans-displays = 0`，两屏各自独立菜单栏 |
| 复现 | `screencapture -x -D 1` / `-D 2` 抓两屏后裁剪菜单栏逐像素对比 |

焦点屏上 Status Trio 图标：环为明亮的绿色，AirPods 为明亮的蓝色。
非焦点屏上同一图标：数字 `80` 降到约 1/4 亮度，而环和 AirPods 仍是高饱和的
绿色和蓝色。两屏的直接对照见本目录的
`inactive-display-menubar-compare.png`（上：焦点屏；下：非焦点屏）。阶段 A 的
六种承载策略对照见 `inactive-display-strategy-compare.png`。

## 代码侧已确认的事实

- `IconSceneState.chromaticRegions` 把 `critical`、`lowPower`、`powered`、
  `bluetooth` 以及充电动画区域划为彩色区域，其余进 `templateRegions`。
- `StatusIconRenderer.menuBarLayers` 把模板区域渲染成 `isTemplate = true` 的
  `button.image`，把彩色区域渲染成单独的 `CGImage`。
- `StatusBarAnimationLayerPresenter` 把该 `CGImage` 作为 `CALayer.contents`
  直接挂到 `NSStatusBarButton.layer` 上，之后每帧只换 `contents`。
- `StatusBarRenderKey` 不含任何屏幕焦点状态，`screenParametersCancellable`
  只在屏幕数量/分辨率变化时重绘。

AppKit 头文件对 `NSStatusBarButton` 的说明是：只有模板图片会拿到“正确的菜单栏
样式”；`NSStatusItem.view` 也被标注为次选方案，因为 button 才能自动调整外观。

## 阶段 A：最小实验（未完成）

独立 AppKit 探针（临时文件，未入库），每个 item 都同时包含一条模板横条和一个
彩色圆，一次对比多种承载方式：

| 策略 | 呈现方式 | 真实非焦点屏结论 |
| --- | --- | --- |
| A0 | 模板 `button.image` + 彩色 `CALayer`（现网做法） | **彩色不变暗，模板部分变暗** |
| A1 | 模板 `button.image` + layer-backed 子视图承载彩色 | **彩色不变暗**，与 A0 相同 |
| A2 | 一整张非模板 `button.image` | **彩色与模板横条一起变暗** |
| A3 | 模板 `button.image` + 自绘 `NSView` | **彩色不变暗**，与 A0 相同 |

探针在真实双屏上用同一组 6 个 status item 验证：每个 item 都有同一条模板横条，
横条上方的色块分别是纯模板、A3 自绘子视图、A2 整张非模板图、A1 layer-backed
子视图、A0 直接挂 layer，以及第二个模板参照。来回切换前台 app 让外接屏在焦点/
非焦点之间切换，再抓取两块屏的菜单栏逐像素对比。

- 非焦点屏上，A0/A1/A3 的模板横条按系统规则变暗（横条亮度从约 0.94 降到
  0.69–0.76），但彩色子视图没有跟随，仍是接近原色的高饱和值。
- A2 的彩色块与它自带的白色横条一起变暗；它是唯一能让彩色内容继承系统
  非焦点外观的承载方式。
- 结果与是否先启动探针、两块屏幕的先后顺序无关；切换焦点后重复抓取得到同一
  结论。

本机合盖时曾用私有 `CGVirtualDisplay` 造第二块屏，系统只在该屏画自己的菜单项，
**不镜像任何第三方 status item**：真实 Status Trio 和独立探针都没有出现在虚拟屏
上，抓到的是一份停止更新的菜单栏快照。因此虚拟屏上的结果全部作废，不作为双屏
验收；下面的结论全部来自真实内建屏 + XV272U。

## 外部项目证据

- Stats #2131 的修复（`11b34498c4`）只针对**完全没有设置 image** 的自定义
  `NSStatusItem.view`：补一个空 `NSImage()` 让系统把它纳入菜单栏合成。
- Status Trio 的 `button.image` 一直非空，Stats 那个空图片修复不适用。
- 与本问题同源的报告（AlDente #1322 等）把彩色菜单栏图标不灰化归为
  Sequoia 起的系统行为差异，而非单个 app 的 bug。

## 为什么尚未改生产代码

计划要求“只有候选在真实双屏上确认彩色区域能与系统一致灰化，才推广”。
A1/A3 已在真实双屏上确认无效；A2 虽然能灰化，但必须把整张彩色图交给
`NSStatusBarButton.image`。这既会在每帧更新时重新赋值 `button.image`，也会
拿走现在由模板图层承担的 Space 拖动实时重着色路径（#112），与 20 fps 的现有
约束冲突。计划明确把 A2 排除在正式动画方案之外，因此本轮没有可推广的最小修改。

现有公开 API 里没有“当前菜单栏是否处于非焦点显示器”的查询：
`NSApp.isActive` 表示 app 是否前台，`NSScreen.main` 表示键盘焦点屏幕，
`NSStatusBarButton.effectiveAppearance` 只在 Space 切换提交后更新，三者都不能
可靠推出系统针对**每个屏幕副本**的灰化状态。按计划，不能用鼠标位置或
`NSApp.isActive` 猜一个全局布尔值去调暗彩色层——同一 status item 在不同屏幕上
由系统分别合成，一个全局值会把焦点屏也调暗。

## 可选下一步

1. **系统信号优先**：继续查找能区分“当前 status item 的这个屏幕副本是否非焦点”
   的公开 API。AppKit 的 `NSStatusBarButton` 没有该属性，`NSApp.isActive`、
   `NSScreen.main` 和按钮所在窗口都不能代表活跃菜单栏屏幕；这次实测中切换前台
   app 后，按钮窗口归属和 `effectiveAppearance` 都没有变化。
2. 如果只能二选一：A2 可以修复灰化但不是合格的生产方案；常驻
   `layer.opacity`、按 `NSApp.isActive`/`NSScreen.main` 调暗、整图改 Template
   都属于计划明确禁止的假修复。
3. 在找到系统信号之前，保留本文件与 `docs/known-limitations.md` 的说明，不建议
   用每次前台 app 切换都重绘整张图的方式换取“看起来更灰”的结果。

## 回归边界

本次没有生产改动。已在当前 worktree 运行：

- `swift test --filter Issue30WiFiAlignmentTests`：6 tests，0 failures
- `swift test`：587 tests，0 failures
- `swift build -c release`：通过

因为生产代码未变，Issue #30、Dock 与充电动画的最终行为与改动前一致；真实双屏
灰度结论来自独立 AppKit 探针，不代表 Status Trio 的彩色 layer 已被修复。
