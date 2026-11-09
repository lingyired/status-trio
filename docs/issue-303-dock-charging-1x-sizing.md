# Issue #303：Dock 充电动画在 1x 显示下的尺寸分析

## 现象

macOS 14.8.5 / App 1.9.4：Dock 中 Status Trio 的白色圆角底板明显小于相邻应用，
用户截图里视觉尺寸接近一半。原始 issue 未确认是启动即小还是运行中变小、是否在
充电动画期间、是否开启 Dock 放大、是否外接 1x 显示器。

## 代码里真实存在的问题

`DockChargingAnimationPresenter.ensureBase` 之前这样设置动画视图的大小：

```swift
tileContentSize = CGSize(
    width: CGFloat(key.pixelLength) / DockIconRenderer.scale,  // scale 恒为 2
    height: CGFloat(key.pixelLength) / DockIconRenderer.scale
)
```

而 `pixelLength` 是按**屏幕倍率**算出来的（`resolvedPixelLength`：`tileSize * displayScale`，
再按 64 像素分桶量化）。两者相除，视图点数就变成了 `tileSize * displayScale / 2`：

| 屏幕倍率 | Dock tile | 位图 | 旧视图点数 | 是否等于 tile |
| --- | --- | --- | --- | --- |
| 2x | 64 pt | 128 px | 64 pt | 是 |
| 1x | 64 pt | 64 px | **32 pt** | **否，只有一半** |

也就是说，视图大小被错误地耦合成“位图清晰度”的函数；只要 Dock 按视图 frame
来摆放内容，1x 下就会正好缩成一半，与截图一致。

另外，即使位图身份（`DockIconRenderKey`）没变，同一充电动画相位下 Dock 被拖动
调整图标大小时，旧逻辑会走“同一帧直接 return”的快速路径，视图不会跟着 tile 变化。

## 修复

- 视图点数改为直接跟随 `dockTile.size`（新增 `syncContentViewToTile()`）；屏幕倍率
  只决定位图像素数，即清晰度，不再影响显示尺寸。
- `present` 在每帧前同步一次尺寸；尺寸真的变化时即使相位相同也会重绘（返回
  `true` 并 `display()`），尺寸不变且相位相同时仍然保持零开销的 no-op。
- tile 尺寸异常（0/非有限）时回退到 256 pt，避免把视图设成 0。

## macOS 27 上的实测（与 Sonoma 的差异，必须单独看）

用临时 AppKit 小程序给 `NSDockTile.contentView` 设一个 32×32 pt 的视图后实测：

```
immediately: tile.size=(128.0, 128.0) view.frame=(0.0, 0.0, 128.0, 128.0)
after 1s:    tile.size=(128.0, 128.0) view.frame=(0.0, 0.0, 128.0, 128.0)
```

即当前系统（macOS 27.3）的 Dock **会把 `contentView` 强制撑到 tile 尺寸**，所以在这台
机器上无法复现“视图小 → 图标小”。这与 Apple 文档“view 应可宽高自适应”一致。

因此：

- 旧代码在 macOS 27 上不会表现为缩小（Dock 会纠正 frame），但 1x 下仍然是**错的契约**：
  它依赖“Dock 一定会纠正”这一未写进文档的行为，且位图分辨率与视图点数被绑死。
- 在 Dock 按视图 frame 摆放内容的系统上（包括用户报告的 macOS 14.8.5 这一代可能如此），
  1x 就会真的缩成一半。是否如此 **未在 14.8.5 实机验证**。

## 用户显示器信息的印证（2026-11-08）

用户补充的系统设置截图显示：

- 外接 **Mi Monitor** 被设为「**主显示器**」，分辨率选中 **3840 × 2160（原生）**，
  即这块 4K 屏以 **1x** 运行（未开 HiDPI 缩放）。
- 内建显示器为默认缩放（2x）。

`resolvedPixelLength` 取的是 `NSScreen.main?.backingScaleFactor`，而 `NSScreen.main`
是按「主显示器 / 菜单栏所在屏」解析的，**不是** Dock 所在屏。所以主屏一旦是 1x 的
Mi Monitor，倍率就恒为 1：

- 动画视图 = `tileSize * 1 / 2` = tile 的一半 → 外接屏缩小；
- 即使把 Dock 放回内建显示器，倍率仍取 1x 主屏，视图仍是一半 → **内建显示器也会小**。

这与用户「内建显示器也会」的反馈一致，且解释了为什么换屏无效。用户随后确认
「**只有充电的时候会变小**」，与这条路径完全对应：静态图标走 `applicationIconImage`，
NSImage 点尺寸固定 256 pt，不吃这个倍率，所以不充电时不缩小。两条现象互相印证，
可以排除静态图标路径。

## 自动化证据

新增于 `Tests/StatusTrioCoreTests/DockChargingAnimationTests.swift`（全部先失败后通过）：

- `contentViewUsesTilePointsRegardlessOfRasterScale`：1x/2x × tile 32/64/72/300 pt，
  断言视图 frame/bounds 恒等于 tile 点数。
- `resizingWithinOneRasterBucketUpdatesTheViewEvenForTheSamePhase`：同一相位下 tile 从
  64 变 72 pt，视图跟随、只多一次 `display()`；再喂同一相位则完全 no-op。
- `switchingFromRetinaToOneXChangesRasterResolutionWithoutResizingTheView`：倍率 2→1 时
  位图从 128 px 变 64 px，视图尺寸不变。

`bash scripts/test.sh 'DockChargingAnimation'` 24 个测试通过；
`bash scripts/verify-local.sh full` 结果见下（Swift 全量、Release 构建、App bundle、
platform/SDK 与 Helper 契约、native 检查、离线发布模拟）。

## 未验证 / NOT RUN

- macOS 14.8.5 实机：启动、插拔电源、动画开始/结束、Dock 图标大小拖动、Dock 放大开关、
  1x/2x 与外接屏下的实际视觉尺寸 —— **NOT RUN**（本机只有 macOS 27.3 内置 2x 屏）。
- Dock 放大开启时是否按同一比例放大内容视图 —— **NOT RUN**。
- 已知限制：`resolvedPixelLength` 取 `NSScreen.main` 的倍率，而非 Dock 所在屏幕的倍率；
  Dock 在 1x 外屏、主屏是 2x 时会拿到过大的位图（只是更模糊余量，不影响尺寸）。本次未改，
  避免在未验证前扩大改动面。
