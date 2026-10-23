# Dock charging animation CPU optimization

## Result

The `NSDockTile.contentView` approach (方案 A) costs **2.12 points of app CPU**
and **7.70 points of Dock CPU** at 20 FPS, measured as the mean of three
interleaved on/off pairs. The rejected `applicationIconImage` prototype
(方案 B) costs **12.23 points of app CPU** over two runs.

A is the chosen implementation: the app cost is roughly one fifth of B, and the
Dock cost is within one point of B. This machine's WindowServer baseline moves
by several points between runs, so the combined figure is not stable enough to
source implementation decisions.

| Placement | Frames | App mean | Dock mean | WindowServer mean |
|---|---:|---:|---:|---:|
| Dock only, animation Off | — | 0.02% | 0.04% | 48.39% |
| Dock only, 方案 A On | 20 FPS | 2.12% | 7.70% | 47.14% |
| Dock only, 方案 B On | 20 FPS | 12.23% | 6.88% | 50.04% |
| Menu bar only, On | 20 FPS | 0.48% | 0.07% | 45.52% |
| Both surfaces, 方案 A On | 20 FPS | 2.04% | 7.01% | 52.00% |

The plan's first-stage targets were `<= 1.0` app points and `<= 2.0` combined
points. **The measured A result misses both.** The Dock redraw alone moves the
cost onto the Dock process, and this WindowServer runs a steady 43-52% whether
or not a tile animates, so the combined delta is dominated by unrelated
baseline movement. That is a miss, not a pass; the report keeps the numbers as
collected.

## Environment and method

- Date: 2026-10-19, Asia/Shanghai.
- Machine: Mac15,9, arm64, 128 GB, macOS 27.0.1 (26A434). One built-in display
  at 4096 × 2304, 2048 × 1152 points, 2x. Dock at 62 pt, magnification off,
  auto-hide off, bottom placement, light system appearance, `.system` background.
- Toolchain: local Xcode 27.0 / Swift 6.4. The CI acceptance toolchain is Xcode
  26.6 / Swift 6.3.3; this run does not replace the CI preflight.
- App: release bundle from `bash scripts/build-worktree.sh release no-open`
  (`com.lingsmbp.StatusTrio.dev.charging-animation-cpu-optimization`).
- Source: branch `codex/charging-animation-cpu-optimization` at `1a68f0e4`
  plus the uncommitted Dock-charging worktree changes. The benchmark and final
  verification do not share a committed source SHA; this report does not imply
  one.
- Charging input: `STATUS_TRIO_FORCE_CHARGING_INPUT=1`, a development-only
  launch switch. The machine was on AC at 80% but not charging, so every On and
  Off run used the same synthetic state.
- Pairs: 15 s settle, then 61 one-second `top` samples. Three dock pairs
  (`on / off / on / off / on / off`), two prototype pairs, one menu-bar pair,
  and one `both` run. The app, Dock and WindowServer were sampled concurrently,
  not serially, so the numbers describe the same wall-clock window.
- On/off differs only in the persisted per-surface charging-effect switches:
  `showsMenuBarChargingEffect` for the menu-bar pair and
  `showsDockChargingEffect` for the Dock and both-surface pairs. Placement and
  synthetic charging input are identical within each pair. The measurements
  above predate the split switches, so they are retained as historical
  benchmark evidence rather than remeasured under the new on/off controls.
- Script: `scripts/measure-dock-charging-cpu.sh <dock|menuBar|both> <on|off>
  <prefix>`. It refuses an `on` run whose call graph never enters
  `ChargingEffectClock.start()`, so a silent no-op cannot be reported as a
  zero-cost animation.
- Raw logs were collected under `/tmp/bench-*`, `/tmp/ab-B-*`, and
  `/tmp/pilot-dock-on2.*`, but those files are no longer present in this
  session. Only the per-run means below were preserved, so the paired
  measurements cannot be re-audited from raw samples on this branch.

### Raw per-run means

| Run | App mean | App peak | Dock mean | WindowServer mean |
|---|---:|---:|---:|---:|
| A dock on 1 | 2.39% | 3.30% | 8.03% | 43.29% |
| A dock on 2 | 2.07% | 3.10% | 7.55% | 49.76% |
| A dock on 3 | 1.90% | 2.60% | 7.52% | 48.37% |
| Off 1 | 0.02% | 0.30% | 0.11% | 47.66% |
| Off 2 | 0.02% | 0.60% | 0.01% | 47.36% |
| Off 3 | 0.02% | 0.30% | 0.01% | 50.14% |
| B dock on 1 | 12.28% | 15.80% | 6.51% | 52.42% |
| B dock on 2 | 12.18% | 16.00% | 7.24% | 47.65% |
| Menu bar on | 0.48% | 0.70% | 0.07% | 45.52% |
| Menu bar off | 0.01% | 0.10% | 0.03% | 49.25% |
| Both on (A) | 2.04% | 2.70% | 7.01% | 52.00% |

## Chosen approach: `dockTile.contentView` with a split raster

The presenter owns one `DockChargingContentView` and hands it two cached
rasters:

1. A static base: the whole tile with the animating regions omitted.
2. A cropped effect slice: the charging ring effect, heartbeat halo and bolt,
   bounded to the battery arc's ink box.

A tick changes only the effect slice and asks `dockTile.display()` to present
it. Repeated phases, repeated rail rasters and a frame-cache hit do not call
`display()`.

Cache limits:

- 36 steady frames per heartbeat variant; at most 2 variants.
- Hard ceiling of 24 MiB of raw frame pixels. A 512-px set is about 18 MiB, so
  only one variant remains resident at that size; the 128-256 px tiles the Dock
  actually draws keep both the 1.0 and 1.35 heartbeat sets.
- The effect slice measured 202 × 168 px at a 256-px tile, not a full-tile
  bitmap. A failed base or effect raster falls back to the existing static
  `applicationIconImage` path.
- Six reusable scratch contexts, keyed by width and height, for the base and
  effect renders.

`AppIconController` remains the single owner of Dock visuals. While the
presenter owns the content view, it suppresses `applicationIconImage` writes;
clearing the animation restores the static icon.

## Why方案 B was rejected

方案 B caches whole-tile `NSImage`s and assigns `applicationIconImage` for each
phase. It produced 12.18–12.28% app CPU, close to the pre-optimization menu-bar
baseline. Each assignment makes the Dock replace and rescale a complete icon;
A assigns no app-owned image and redraws only a small effect slice inside a
texture the Dock already owns.

The prototype stays behind a development-only switch
(`STATUS_TRIO_DOCK_ANIMATION_RENDERER=applicationIcon`). It is not reachable from
a shipped bundle. It exists so the comparison can be repeated.

## What changed

1. `ChargingEffectClock` gained an idempotent Dock surface claim. The existing
   20 FPS loop and timeline remain the only timer.
2. `DockIconRenderer` can render the animation base, the cropped effect slice,
   and the effect's tile-space rect from the same transform as the full tile.
3. `DockChargingFrameCache` caches the 36 steady frames per state and heartbeat
   multiplier with an explicit byte ceiling.
4. `DockChargingContentView` and `DockChargingAnimationPresenter` present the
   base plus overlay and suppress duplicate Dock displays.
5. `AppIconController` exposes the animation scene and eligibility, suppresses
   static image writes while the animation is active, and restores the static
   image when the claim ends.
6. `AppEnvironment` wires the one clock to both surfaces, consumes delivered
   `@Published` inputs rather than re-reading the store during `willSet`, and
   keeps the Dock idle unless the user's own placement has a tile.
7. `DockVisibilityMonitor` pauses a Dock-only animation while the Dock window
   is hidden and resumes it when the Dock reappears. It uses the CoreGraphics
   window list because macOS has no public Dock visibility notification.

## Hidden Dock handling

The monitor runs only while the Dock effect is enabled, the app really owns a
Dock tile, and the battery is otherwise eligible to animate. It has no timer of
its own: it reuses the existing `SystemIconAppearanceMonitor` poll, now shared at
1 s, and performs two metadata-only window queries:

1. The all-window list confirms the Dock process still has a Dock-level window.
2. The on-screen list confirms that window is currently composited.

If the Dock window metadata is unavailable, the monitor fails open rather than
silently disabling the effect. While hidden, the presenter restores the static
Dock icon and the shared clock releases the Dock surface. A menu-bar animation
on the same clock continues unaffected. Reappearance does not replay the
plug-in burst; it resumes the steady timeline within roughly one poll interval.

## Preserved behavior

- 20 FPS, 1.8 s steady cycle, 0.6 s plug-in burst, level-advance burst,
  heartbeat 1.35 boost, bolt scaling and tint.
- Menu bar: the existing static base plus chromatic overlay path is untouched
  apart from the one fewer blank line. Its measured on cost remains 0.48%.
- Reduce Motion, display sleep, unplugging, charge completion, hidden menu bar,
  and the settings preview's clock claim all still stop or start the one clock
  through `ChargingEffectPolicy`.
- A temporary `.regular` activation for Settings does not claim the Dock unless
  the persisted placement is `.dock` or `.both`.

## Verification

- `swift test`: 1,657 XCTest (7 skipped) and 647 Swift Testing tests in 99
  suites pass, with 0 failures.
- `swift test --filter Issue30WiFiAlignmentTests`: 6 tests pass.
- `swift build -c release`: pass.
- `bash scripts/check-forbidden-patterns.sh`: pass.
- Release bundle: `dist/StatusTrio.app`, bundle id
  `com.lingsmbp.StatusTrio.dev.charging-animation-cpu-optimization`, macOS SDK
  26.0 check pass, rebuilt 2026-10-20 00:05:37 CST from this source state.
- Real-process check: enabling 测试充电动画 made `ChargingEffectClock.start`,
  `DockChargingAnimationPresenter.present` and `NSDockTile.display` appear in a
  `sample`; two screenshots 220 ms apart changed in the Dock icon's columns but
  not in its unchanged left neighbor. The saved placement was `both`, charging
  effects and the development test input were enabled, and the Settings window
  was open. This is a built-in-display screenshot check, not hardware charging
  acceptance.

## Residual risks and unfinished items

- The app-only target was missed. The animation costs about 2.1 app points and
  7.7 Dock points on this machine; the plan's first-stage target was 1.0 app
  points and 2.0 combined points.
- WindowServer on this machine is 43-52% with or without the animation, so the
  combined figure is not a clean attribution. The per-process numbers are the
  usable evidence.
- The charging state is synthetic; a real plug-in, unplug, charge-limit hold,
  and level-advance run remain open.
- Visual acceptance covered one display, bottom Dock, 62 pt, no magnification,
  light system appearance, `.system` background. Left/right Dock, magnification,
  dark and clear backgrounds, multi-display, Spaces, Mission Control, sleep/wake,
  and Reduce Motion remain manual checks.
- The current machine's auto-hidden Dock was checked with the development
  process: synthetic charging plus Dock-only animation produced no
  `ChargingEffectClock.start` or `DockChargingAnimationPresenter.present`
  samples while hidden. Revealing the Dock produced no clock or presenter
  sample, while the shared poll still ran. Resume was separately exercised by
  the injected-monitor integration tests and by the previous 250 ms build's
  real-process transition; this exact 1 s build's live resume remains a manual
  UI check.
- Under `.both`, a Settings window that makes the app regular does not steal the
  Dock claim; it remains visible while Settings is open. That is intended, but
  it has not been UI-automated.
- No non-publishing `release.yml` preflight, merge, tag, DMG, GitHub Release, or
  appcast publication has been run.


## 2026-10-20 memory optimization follow-up

The memory branch preserves 20 Hz and the existing frame geometry. Cropped Dock
frames now use a ring/effect/background/size identity independent of center and
footer. A large variant retires the old group after its first stride probe,
before constructing the remaining 35 frames. Real 512 px renderer tests retain
19,488,960 bytes and reach a cache/build peak of 20,030,320 bytes, excluding the
presenter's current image, scratch, and system copies. The original two-full-set
construction was about 37.17 MiB. Pressure keeps the active group.

The first three Release menuBar/off A/B pairs measured app CPU means of
0.01/0.03%, 0.01/0.02%, and 0.02/0.00% (main/optimized). These are idle measurements,
not charging-animation CPU acceptance. Raw files and the retained memory outlier
are documented in memory-audit-2026-10-20.md.

The Dock/on run did not observe ChargingEffectClock in the existing sampling
gate. The tool rejected the run; the remaining five attempts are not_run. No
new live Dock-animation CPU conclusion is available, and earlier evidence above
remains historical rather than being overwritten. Hardware, visibility, and
Swift 6.3.3 non-publishing CI checks remain open.

A second three-pair menuBar/off confirmation explicitly suppressed onboarding
and consent UI on each launch. App CPU averaged 0.02% / 0.01%
(main/optimized), with no pair above the 0.5 percentage-point threshold. All six
processes had 82–83 passive window observations and no observed visible window.
This does not establish live Dock charging performance. Raw confirmation files:
`/Users/lingsmbp/Documents/aiwork/status-trio-memory-measurements/2026-10-20/task7-confirm-20261020T0444/`.
