# 电池详情页交互与功耗图连接 — 验收记录（#281 / #282，2026-11-06）

分支 `overnight-panel-color-refresh`，基线 `origin/main=d4598847`。
本记录只覆盖 Task 1（#281 电池页底部两行整行交互、#282 功耗图卡片与流带连接）。

## 结论

**本地自动化：PASS。人工视觉/交互验收：NOT RUN（需人工或后台 UI 流程）。**
未 commit / merge / push，未启动真实前台 GUI，未启用 `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS`。

## 变更边界

本任务仅改动下列文件；未触碰 `SettingsStore`、`localization`、任何 controller、`#275`/`#255` 相关文件。

| 文件 | 变更 |
| --- | --- |
| `Sources/StatusTrioCore/UI/PowerFlowCardShape.swift` | 新增：单侧圆角 `Shape`/`InsettableShape`、连接判断 `PowerFlowCardConnections`、共用 fill/stroke 的卡片表面 modifier（含 1pt 搭接） |
| `Sources/StatusTrioCore/UI/BatterySettingsLinkStyle.swift` | 新增：仅这两行使用的 `ButtonStyle` 与整行 `BatterySettingsLinkRow` |
| `Sources/StatusTrioCore/UI/BatteryDetailsView.swift` | 两行改为整行 `BatterySettingsLinkRow` + 各自 `onHover` 状态（+10 / −4） |
| `Sources/StatusTrioCore/UI/BatteryPowerFlowView.swift` | 卡片改用 `powerFlowCardSurface`；一次快照解析 live ribbons 与连接（+31 / −23） |
| `Tests/StatusTrioCoreTests/PowerFlowCardShapeTests.swift` | 新增：真实 `Path` 几何 + 连接判断回归（6 例） |
| `Tests/StatusTrioCoreTests/BatterySettingsLinkTests.swift` | 新增：离屏渲染整行 hover / 独立高亮回归（2 例） |
| `Tests/StatusTrioCoreTests/BatteryPowerFlowTests.swift` | 新增：离屏渲染接线测试 `testInputCardSquaresOnlyItsRibbonSideCorners`（1 例） |

保留的接口：`BatteryDetailsView` 的 `onOpenBatterySettings` / `onOpenAppBatterySettings` 回调签名不变；卡片尺寸、布局、颜色、功率分支比例算法、无动画时钟均未改。

## Red / Green

所有命令在 worktree 根目录执行，日志在 `/tmp`。

| 阶段 | 命令 | 结果 |
| --- | --- | --- |
| Red | `bash scripts/test.sh 'PowerFlowCardShapeTests\|BatterySettingsLinkTests'` | **FAIL（预期）** — 新增测试引用尚未实现的生产类型，编译失败：`cannot find 'PowerFlowCardShape' in scope`（16 处）、`cannot find 'PowerFlowCardConnections' in scope`（8 处）。日志 `/tmp/st-red-battery.log`。 |
| Green（focused） | `bash scripts/test.sh 'PowerFlowCardShapeTests\|BatterySettingsLinkTests'` | **PASS** — `Test run with 8 tests in 2 suites passed`，EXIT=0。日志 `/tmp/st-green-battery.log`。 |
| 回归 | `bash scripts/test.sh 'BatteryDetailsLayoutTests\|BatteryPowerFlowTests'` | **PASS** — `Executed 13 tests, with 0 failures`（BatteryDetailsLayoutTests 7 + BatteryPowerFlowTests 6，含新增接线测试）。EXIT=0。日志 `/tmp/st-regress-battery.log`。 |

诚实说明：Red 阶段的失败是「新类型缺失」的编译级红，而非行为断言红；同一次编译还有其它并行任务当时未完成的改动导致的编译错误，因此该日志不是本任务的孤立行为红证据。真正的行为守卫是下面的几何与渲染断言（实现后为绿）。

`scripts/test.sh` 自带的 forbidden-patterns 检查通过（`No forbidden actor-isolated method references`）。

## 断言覆盖（真实几何 / 离屏渲染，非源码字符串）

`PowerFlowCardShapeTests`（`Path.contains` 真实几何，角点取距角 1pt 的内点：12pt 圆角处该点在形外，直角处该点在形内）：

- `isolatedCardKeepsAllFourCornersRounded`：`.none` 四角都圆、边界框等于卡片矩形。
- `trailingConnectionSquaresTheRightCorners`：右侧两角直角命中、左侧两角仍圆（输入卡连接右侧）。
- `leadingConnectionSquaresTheLeftCorners`：左侧两角直角命中、右侧两角仍圆（分支卡连接左侧）。
- `insetRimStaysConcentricAndKeepsTheConnectionSquare`：`inset(by:)` 后边界为内缩矩形且连接侧仍直角（strokeBorder 与 fill 同轮廓）。
- `onlyEdgesWithALiveRibbonAreConnected`：只有厚度 > 0.5pt 的流带才判为连接；0 / 0.5 / 0.49 不连；无输入卡时输入边不连；空分支为空。
- `inputConnectsOnTrailingAndBranchOnLeading`：输入卡接右侧、分支卡接左侧的映射。

`BatterySettingsLinkTests`（`NSHostingView` 离屏截图，窗口不上屏）：

- `hoveredRowReachesTheRightEdgeWhileIdleRowStaysAtItsLabel`：同一容器两行，hovered 行的高亮到达 ≥95% 行宽（右侧空白属于按钮），idle 行只有标签墨迹 <80% 行宽 —— 即整行命中 + 独立 hover。
- `aSingleHoveredRowPaintsFullWidthAndAnIdleOneDoesNot`：单行对照，hovered 满宽、idle 不满宽。

`BatteryPowerFlowTests.testInputCardSquaresOnlyItsRibbonSideCorners`（离屏截图）：输入卡（62×84）连接侧上/下角有填充（直角），外侧上/下角为背景（圆角）——验证视图确实把连接判断接到了 shape，而不只是 shape 单元测试通过。

## 待人工 / 未覆盖验证

- **视觉未跑**：hover 高亮的具体观感与鼠标移出恢复、两侧空白点击的手感、1pt 搭接在抗锯齿下的接缝是否完全消失、深色模式与 Liquid Glass 透明度/彩度下的对比，以及细分支端点是否露缝/溢出，均需后台 UI 或人工确认（本次未启动 GUI）。
- **真实鼠标/键盘**：自动化只证明「渲染出的高亮/hit 宽度 = 整行宽」，未做真实点击与 Return/空格激活；按政策 `VisibleUITestCase` 默认跳过，未启用。
- **macOS 13 运行时**：几何用纯 `Path`，未使用 macOS 14+ API（`onHover`、`InsettableShape`、`Path.addArc(tangent1End:tangent2End:)` 均 macOS 13 可用）；但仅本机 SDK 编译，未在真实 Ventura 上运行验证。
- **圆角风格微调**：输入卡原来用 `.continuous` 圆角，单侧圆角自定义 `Shape` 使用圆形 12pt 弧；圆角半径与尺寸不变，仅曲率连续性与原实现略有差异，属视觉层，建议人工对照。
- 未新增轮询、动画或后台工作；卡片功率比例、颜色、布局算法与采样时钟保持不变。
