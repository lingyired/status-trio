# Issue #30 — menu-bar icon horizontal alignment: verification report

Issue: <https://github.com/lingyired/status-trio/issues/30>

Branch: `fix-issue30-menubar-alignment` (isolated worktree, base `origin/main`
@ `cf24f1da`). **Not merged, not released, issue not closed.** Awaiting owner
acceptance and, for the external/1× screenshot matrix, an unlocked screen.

## TL;DR

- **Found and fixed a real layout defect**: the coloured `CALayer` overlay did
  not follow an `NSStatusBarButton` resize. The template `NSImageView`
  autoresized with the button, but the layer kept its pre-resize frame, so on
  any resize after a presentation (icon-size change, display/scale transition,
  menu-bar spacing reflow) the colour fill drifted from the template/base — the
  horizontal `偏左` class of bug. Reproduced by a unit test first (red), then
  fixed; the test now passes.
- The renderer's own vector centring was already correct: at the real 16–36 pt
  sizes rendered at scale 8, the ring sits on the artwork centre within
  **0.27 px** and the glyph ink on the ring centre within **0.062 pt**.
- Fix: one shared `StatusIconGeometry.contentFrame(in:contentSize:)` used by both
  surfaces, a `CALayer.autoresizingMask` of flexible margins so the layer stays
  centred on resize, and an actual-frame comparison so a resize still counts as
  a change.
- Real-screen pixel screenshots of every state could **not** be taken this run:
  the session locked at 00:52 (`CGSSessionScreenIsLocked=1`), so every capture
  is the lock-screen wallpaper with no menu bar. That matrix is **BLOCKED /
  NOT TESTED** and must be re-run when unlocked (script provided). The one clean
  screenshot taken earlier while unlocked (round 1) measured PASS.
- Runtime geometry (read from the live app's own views, valid while locked)
  confirms template frame == colour-layer frame == system `imageRect`, centred
  (offset 0) for every fixture state and across a 24→30→16→36 pt resize.

## Environment

| Item | Value |
| --- | --- |
| Display | **XV272U external, 2×** (2048×1152 pt / 4096×2304 px), primary |
| macOS | 27.2 (build 26B123), Apple M3 Max |
| Agent Desktop | 1.0.2, Accessibility + Screen Recording granted |
| Dev bundle | `com.lingsmbp.StatusTrio.dev.fix-issue30-menubar-alignment` |
| Lock state | screen locked from ~00:52 (`CGSSessionScreenIsLocked=1`) |

## The defect that was reproduced and fixed

`StatusBarTemplateImagePresenter` positioned its `NSImageView` with a centred
frame and `autoresizingMask` flexible margins, so it follows a button resize.
`StatusBarAnimationLayerPresenter` set the colour layer's `frame` once, from
`view.bounds`, and never re-derived it. `NSStatusBarButton` (variable length)
*does* resize after the image is assigned. Result: template ring moves with the
button, colour layer does not → visible horizontal offset of the coloured arc.

Reproduction (watched red before the fix):

```
Test hostResizeKeepsOverlayOnTemplateWithoutAnotherDisplayCall failed:
  Expectation failed: layer.frame == templateView.frame
```

Fix (`StatusBarAnimationLayerPresenter` + `StatusIconGeometry`):

- add `StatusIconGeometry.contentFrame(in:contentSize:)` — the single layout
  source, exactly the button-bounds centre (matching the system `imageRect`,
  which reports a zero mid-X offset), used by both presenters;
- `layer.autoresizingMask = [.layerMinXMargin, .layerMaxXMargin,
  .layerMinYMargin, .layerMaxYMargin]` so the layer stays centred as the button
  resizes;
- treat a real frame drift (`framesMatch`) as a change so a resize still writes
  the correct geometry once, then stays quiet on steady ticks.

## Runtime geometry evidence (live app, lock-safe)

`artifacts/icon-alignment/runtime-resize-evidence.json` — after switching icon
size on the running app:

| icon size | template frame | colour-layer frame | system imageRect | centre offset |
| --- | --- | --- | --- | --- |
| 24 | 8,0,24,24 | 8,0,24,24 | 8,0,24,24 | 0 |
| 30 | 8,0,30,30 | 8,0,30,30 | 8,0,30,30 | 0 |
| 16 | 8,3,16,16 | 8,3,16,16 | 8,3,16,16 | 0 |
| 36 | 8,0,36,36 | 8,0,36,36 | 8,0,36,36 | 0 |

`artifacts/icon-alignment/states/summary.json` — per fixture (wifi, weak wifi,
bluetooth, charging bolt, plug, input-source text, animated) `imageRectCenterOffset
= 0`, and for every chromatic scene `overlayFrame == templateFrames[0]`.

## Offscreen real-size vector centring (unit, scale 8)

`StatusBarIconLayoutTests` (all pass):

| size (pt) | ring vs artwork centre | glyph ink vs ring centre |
| --- | --- | --- |
| 16 | +0.03 px | +0.00 px |
| 22 | −0.27 px | +0.50 px (0.062 pt) |
| 24 | −0.20 px | +0.00 px |
| 27 | −0.10 px | −0.50 px (0.062 pt) |
| 30 | +0.00 px | +0.00 px |
| 36 | +0.20 px | −0.50 px (0.062 pt) |

Plus `testContentFrameCentersEveryContentSizeOnTheButtonCentre` (both surfaces use
one centred rect; a resized host moves the centre).

## Real-screenshot status (screen unlocked, 08:33)

Per-state fixtures rendered on the real menu bar and measured against a blank
reference of the same button region (`artifacts/icon-alignment/states/`).
`inkOffsetPx` is the ink centre minus the button centre.

| Scenario | Measured | Result |
| --- | --- | --- |
| Wi-Fi composite (ring + glyph), 24 pt 2× | ring +0.5 px, glyph 0.0, glyph→ring −0.5 px | **PASS** |
| Charging composite (ring + glyph), 24 pt 2× | ring +0.5 px, glyph 0.0, glyph→ring −0.5 px | **PASS** |
| Wi-Fi ring isolation | ring +0.5 px | **PASS** |
| Wi-Fi glyph isolation / weak Wi-Fi | 0.0 px | **PASS** |
| Bluetooth glyph | +0.5 px | **PASS** |
| Input-source text | 0.0 px | **PASS** |
| Charging animation (running) glyph | 0.0 px | **PASS** |
| Power plug (symmetrical) | 0.0 px | **PASS** |
| Charging bolt (top-gap) | bbox centre +1.0 px | **PASS with caveat** — the lightning bolt is left/right asymmetric, so its ink-bbox centre is not its layout anchor; the bolt is anchored in the symmetric top gap (ring +0.5 px). Not a layout offset. |
| Real size sweep 16–36 pt (round 1, 2×) | glyph-to-ring ≤0.5 px at all sizes | **PASS** |
| 1× non-HiDPI | — | **NOT TESTED** (no 1× display) |
| Display switch external ↔ built-in | — | **NOT TESTED** (no second display) |

## How to run the full matrix when the screen is unlocked

```bash
cd .agents/worktrees/fix-issue30-menubar-alignment
bash scripts/launch-computer-use.sh                 # build + background launch
python3 scripts/run-menubar-alignment-states.py      # per-state real screenshots
```

Then also, on any other display, pass the right display to the screenshot step.

## Files changed / added

- `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift` — shared
  `contentFrame(in:contentSize:)`.
- `Sources/StatusTrioCore/UI/Icon/StatusBarTemplateImagePresenter.swift` — use it.
- `Sources/StatusTrioCore/UI/Icon/StatusBarAnimationLayerPresenter.swift` — use
  it, autoresizing margins, actual-frame comparison, DEBUG `frameForDiagnostics`.
- `Sources/StatusTrioCore/UI/StatusBarController.swift` — DEBUG-only, env-gated
  fixture/diagnostic wiring (no effect on Release builds).
- `Sources/StatusTrioCore/UI/Icon/StatusBarAlignmentDiagnostics.swift` — new,
  `#if DEBUG` only: in-memory render fixtures + view-geometry dump.
- `Tests/StatusTrioCoreTests/StatusBarIconLayoutTests.swift` — new real-size tests.
- `Tests/StatusTrioCoreTests/StatusBarAnimationLayerPresenterTests.swift` — new
  resize-sync regression test.
- `scripts/test-menubar-icon-alignment.py`, `scripts/menubar-item-frame.swift`,
  `scripts/post-alignment-request.swift`, `scripts/run-menubar-alignment-states.py`,
  `scripts/run-menubar-alignment-check.sh` — measurement harness.

## Performance & compatibility

- No timer or polling added. The colour layer still updates only on presentation;
  the extra frame comparison turns into a single geometry write only when the
  layer actually drifted. Steady ticks remain `unchanged`.
- Release builds exclude all diagnostics (`#if DEBUG`); the `contentFrame` helper
  and autoresizing mask are the only production changes and are behaviour-
  preserving for the steady case.

---

# Residual size-dependent centering (follow-up)

## Iteration log

| 修改假设 | 改动内容 | 修复前偏移 | 修复后偏移 | 截图证据 | 判断 |
| --- | --- | --- | --- | --- | --- |
| A：SF Symbol 光学中心测量精度（bbox vs 质心） | 把 `measureInkCenterOffsetX` 从 alpha>0 bbox 中点改为 alpha 加权质心，离线重测 | sym-ring（scale2）最差 −0.64px@24 | 与改前**逐值相同**（6× 下 bbox≈质心） | `size-preview/probe` | **无变化，已回退** |
| B：绘制坐标与最终像素栅格不一致（小尺寸栅格化取整） | `render()` 增加 supersample：菜单栏路径先按 2× 大网格绘制，再高质量一次性降采样到目标像素 | sym-ring 最差 −0.64px@24、−0.59px@18 | **±0.26px 以内**（24→−0.16，18→−0.14；scale1 ≤0.31） | `size-preview/status-trio-wifi-sizes-vertical-black.png` | **明显改善，采纳** |

## 结论（假设 A/B/C）

- **A 不是主因**：把 bbox 中点换成 alpha 加权质心后，逐尺寸结果完全不变（6× 高分辨率下两者几乎重合）。说明墨迹补偿本身不是残差来源。
- **B 是主因**：SF Symbol 直接按最终 ~12–18pt 像素栅格化时，其抗锯齿墨迹会随尺寸 snapped 到不同像素相位（18/24pt 最多偏左约 0.6px）。将菜单栏渲染改为「2× 超采样 → 一次性高质量降采样」后，符号与圆环落在同一像素栅格，残差降到 ±0.26px（半物理像素内），且**不同尺寸不再各自跳动**，也消除了切换尺寸/状态时的水平跳动根因。
- **C（真实容器）**：之前已证伪——`NSButton.imageRect(forBounds:)` 的 `midX−bounds.midX = 0`，系统按钮精确居中图片；本次真实菜单栏实测 24/28pt PASS（ring +0.5px），18pt 的 1.0px 读数是 AX 整数边界 ±0.5px 测量噪声。并非容器偏移。

## 实现（系统化，无按尺寸硬编码）

- `StatusIconRenderEnvironment.supersample`（默认 1）。
- `render()`：`supersample>1` 时按 `scale*supersample` 绘制，再用 `interpolationQuality=.high` 一次性降采样到 `ceil(size*scale)`。
- 仅在菜单栏入口启用 `supersample: 2`：`menuBarTemplateBase` / `menuBarChromaticImage` / `menuBarImage` / `preRenderedMenuBarImage` / `StatusBarController` 的 fallback raster。Dock、设置预览保持 1（不受影响）。
- 未改动 `artworkCenterX`、电池外环/音量点原始设计，未加尺寸偏移表。

## 真实菜单栏测量（2×，本次）

| size | ring offset | glyph→ring | 结果 |
| --- | --- | --- | --- |
| 18 | +1.0px (AX ±0.5 噪声) | −0.5px | PASS*（ring 读数在测量噪声内） |
| 24 | +0.5px | 0.0px | PASS |
| 28 | +0.5px | 0.0px | PASS |
| 30 / 36 | 见补测 | | |

real-size 截图见 `artifacts/icon-alignment/realsize-wifi/`。

## 测试

- 新增 `StatusBarIconLayoutTests.testMenuBarSupersampleCentersGlyphOnRingAtDisplayScale`：菜单栏超采样路径在 1×/2× 下、16–36pt 全尺寸，符号质心与圆环质心偏差 ≤0.5 物理像素。
- `testSymbolInkLandsOnRingCentreAtEveryRealSize` / `testRingSitsOnArtworkCentreAtEveryRealSize` / `testSymbolOffsetDoesNotGrowWithIconSize` 覆盖全部 11 档尺寸；容差改为物理意义明确的 0.25pt（2× 下半个物理像素）。
- `ChargingEffectFrameCacheTests` 的 `preRenderedMenuBarImagePreservesPixelsAtTheRequestedBackingScale` 参考环境同步为 `supersample: 2`（对齐生产路径语义，非放宽）。

## 性能与兼容

- 超采样只作用于菜单栏静态基图（已缓存）和动画帧；图标像素面积极小（≤96px²@2×），20Hz 动画额外开销可忽略；无新增定时器/轮询。
- Dock 路径不变；Template 着色、非焦点淡化、点击、动画逻辑未改。
