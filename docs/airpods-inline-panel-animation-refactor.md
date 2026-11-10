# AirPods 行展开/折叠抖动与动画重构

> 本文为上一轮历史记录。快速点击仍存在的问题、后续修复与真实 NSPanel 测试，
> 见 [2026-11-05 修复记录](airpods-rapid-disclosure-fix.md)；不要将下文的数学
> Coordinator 测试误作实际按钮/窗口集成验证。

分支：`feat/airpods-inline-toggle`
基线提交：`b0a3d6f7`
本文记录根因、改动、验收与遗留项。

## 1. 已确认的根因与触发顺序

原始实现（`AnchoredStatusPanel`）用一套**不在状态机里**的动画：

1. `StatusPanelHostingController.viewDidLayout` 每次布局都调用 `sizeThatFits` 上报尺寸。
2. `applyContentFrame` 收到上报后，如果是高度变化就用一个 120 Hz `Timer` 逐帧插值。
3. 这个 Timer 的起点是 `resizeStartHeight` / `resizeStartTime`，**在动画进行中再次触发时**从存储的起点重算，而不是从当前显示高度接续。
4. 动画开始时 `pinContentHeight(target)` 把内容钉在目标高度，结束时 `pinContentHeight(nil)` 再 `layoutSubtreeIfNeeded()`，这会**再次触发 `viewDidLayout` 上报**，形成"测量 → 改 frame → 再测量"的反馈环。
5. 每次上报的尺寸只要与 `lastReportedSize` 不严格相等（浮点亚像素差异也算）就会重新进入这条链路。
6. `pinContentHeight` 永远**顶部对齐**，底部 Dock 锚定或向下增长时 Footer 会被窗口底边裁掉。
7. `OutputDeviceRow` 用 `if expanded` 直接增删控件，收起瞬间内容消失、窗口还没缩，然后窗口再单独缩——"内容先没、面板仍然很高"。
8. `AirPodsSystemControls.read()` 分阶段 `onUpdate`（空间音频 → 对话感知 → 完整），每阶段行数变化都会真实改变自然高度。
9. `OutputDeviceList` 用 `LazyVStack`，行被回收时展开状态与其 controls model 被销毁，重新出现时重新读取。

**触发顺序**：展开 → `expanded` 变 true → 控件整体插入（高度一步到位）→ 上报 → Timer 动画逐帧改 frame → 动画中内容再次布局 → 再上报（亚像素差）→ retarget/重启曲线 → 尾部修正；同时异步 read 的分阶段发布继续改变行数。抖动是"窗口动画"和"内容测量"两套独立逻辑互相触发的叠加。

## 2. 修改文件与目的

| 文件 | 目的 |
| --- | --- |
| `UI/StatusPanelResizeAnimation.swift`（新） | 纯数学：缓动曲线、从当前高度重定向、整点吸附、到达判定。无 AppKit，可直接单测。 |
| `UI/StatusPanelResizeCoordinator.swift`（新） | 单一尺寸动画驱动器：`idle/expanding/collapsing/settling` 状态机、单 tick 源、retarget 从实时高度接续、pin/unpin、cancel 完整清理。 |
| `UI/StatusPanelResizeDiagnostics.swift`（新，DEBUG） | 隐私安全的诊断快照：阶段、高度、锚定边、写入/重定向/钉住计数。不含设备名/UID/地址。 |
| `UI/AnchoredStatusPanel.swift` | 移除旧 Timer 与 `isAnimatingContentSize` 等散落状态，改由 Coordinator 统一驱动；动画期间**锁定锚定边**（中间高度不会翻转方向）；pin 按锚定边对齐（菜单栏向下增长对齐顶部、底部 Dock 向上增长对齐底部、左右 Dock 居中）；`pinContentHeight` 支持 `edge`；宿主测量加入**显示器像素容差**，亚像素重测不再上报；屏幕/Dock/Space 真实变化时取消锁定并重新测量。 |
| `UI/OutputDeviceRow.swift` | 拆分 `expanded`（逻辑意图）/ `shouldMountControls`（是否保留视图）/ `contentVisible`（是否完全显示）。展开先建立布局再淡入（opacity+5pt 位移，约 170ms）；收起先淡出再卸载，窗口收缩与内容退出连续。遵守 Reduce Motion。 |
| `UI/AirPodsSystemControlsView.swift` | 加载中的区段用与最终行数等高的**骨架占位行**（空间音频 3 行、对话感知 2 行），异步发布只替换内容、不改变布局高度；真正不支持/错误时才允许一次真实尺寸调整。 |
| `UI/OutputDeviceList.swift` | `LazyVStack` → `VStack`（设备列表很小），避免行被回收导致展开状态与 controls model 重建、重新读取。 |
| `Tests/.../StatusPanelResizeAnimationTests.swift` | 曲线/重定向/整点吸附单测。 |
| `Tests/.../StatusPanelResizeCoordinatorTests.swift` | 状态机：单一驱动、retarget、pin/unpin、cancel、立即 settle。 |
| `Tests/.../AirPodsInlineWindowTransitionTests.swift` | 完整窗口过渡：静态展开、渐进加载、快速反复、几何验收。 |

## 3. 窗口高度/位置诊断（自动化）

`AirPodsInlineWindowTransitionTests` 在 1440×900（visibleFrame 875）屏幕上以 330pt 宽、菜单栏锚定验证：

- 展开 400→640pt：每一帧 `maxY` 与初始偏差 ≤ 0.5pt；宽度不变；高度单调递增；settle 后追加 frame 写入 = 0；Timer 已销毁。
- 渐进发布（520→600→640 在动画中）：`startCount == 1`（没有第二个驱动器），`retargetCount == 2`。
- 连续 20 次快速切换：最终收敛到最后目标，无残留 Timer、无 settle 后写入。
- 动画中 cancel：驱动器停止，之后无任何 frame 写入。
- 目标超过屏幕预算：所有帧 ≤ `maximumPanelHeight`。
- 底部 Dock 锚定：`minY` 偏差 ≤ 0.5pt，向上增长。
- 收起 640→400：单调递减，回到原高度。

> 注：上述是 headless 几何验证。真实窗口的像素级肉眼验收需要在有 AirPods 与显示器的手动会话中完成（见第 5 节）。

## 4. 自动化测试结果

- 完整 Swift 套件：`bash scripts/test.sh` → **875 tests / 127 suites，0 failures**。
- 新增/相关过滤全部通过：
  - `StatusPanelResizeAnimationTests`（5）
  - `StatusPanelResizeCoordinatorTests`（5）+ `StatusPanelResizeDiagnosticsTests`（1）
  - `AirPodsInlineWindowTransitionTests`（8）
  - `StatusPanelScrollAreaTests` / `StatusPanelPlacementTests` / `StatusPanelHeightCapTests` / `AirPodsInlineControlsSizingTests` 等回归通过。
- `bash scripts/verify-local.sh full`：**通过（exit 0）**，`head=f7b9d06b`，full 档包含完整 Swift 套件、Release 构建、本地 ad hoc app bundle 与平台/原生契约检查；不含签名、公证、DMG、Universal 打包。
- 可见 UI 测试（`StatusPanelContentResizeTests`）按仓库规则默认跳过，未在本会话启用。

## 5. 仍需硬件/人工实测的项目

以下**无法**在无头环境证明，仍需手动会话：

1. 真实 AirPods 的渐进式异步加载（空间音频 → 对话感知 → 自适应）在真实硬件上的展开/收起观感。
2. macOS 13 Ventura 真机；Intel 与 Apple Silicon 真机。
3. Retina 与非 HiDPI 外接显示器。
4. 菜单栏、底部 Dock、左右 Dock 三种锚定的真实视觉验收。
5. `.liquidGlass`（macOS 26+）、`.classicMaterial`、`.solid` 三种背景。
6. Reduce Motion 开启时的无动画路径。
7. 内容超过屏幕高度后的滚动与 Footer 始终可见。
8. 空载 `NSGlassEffectView` 的尺寸传播是否仍与 Coordinator 竞争（需在 macOS 26 真机确认）。

## 6. 与 main 的合并风险

- `feat/airpods-inline-toggle` 基线 `b0a3d6f7`，**落后当前 `origin/main`（`5ff0cff2`）65 个提交**。
- 交集文件：`AnchoredStatusPanel.swift` 在 main 上有 `e6d9d093`（后台测试打开面板，新增 `disablesDismissOnResignForTesting` / `disablesKeyWindowForTesting` 等），本分支改的是内容尺寸动画区域，**语义不冲突但同文件会文本冲突**，需人工合并。
- 其余改动文件（`OutputDeviceRow` / `OutputDeviceList` / `AirPodsSystemControlsView`）main 未触及，风险低。
- 合并后必须重新跑 `bash scripts/verify-local.sh full`，并重跑 `AirPodsInlineWindowTransitionTests` 与 `StatusPanelContentResizeTests`。
- 本分支新增的 `StatusPanelResizeAnimation/Coordinator/Diagnostics` 是独立新文件，不与其他面板修复争用。

## 7. 未做/刻意不做的部分

- 没有为了"看起来顺滑"而固定整个面板高度、统一改动画时长或隐藏问题。
- 评估过 `NSAnimationContext`（原生窗口动画），但它在锚定边界与可取消性上不如自绘逐帧稳定，保留手动驱动并收敛为单一状态机。
- 未改 AirPods 私有协议、Helper、音频设备识别或本地化数据。
