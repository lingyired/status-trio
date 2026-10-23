# Menu-bar charging animation CPU optimization

## Result

The animation's incremental CPU cost fell from **12.30 points to 0.41 points**
on the same machine, build configuration, display, and synthetic charging input:

- Before: 12.26 / 12.40 / 12.25% mean CPU with animation on over three 60 s runs,
  against 0.01–0.02% with it off.
- After: 0.41 / 0.41 / 0.44% mean CPU with animation on in the first post-change
  run, then 0.40 / 0.34 / 0.32% after the final failure-path edits, against
  0.00–0.02% with the animation off.
- Peak CPU fell from 15.70–16.30% to 0.50–0.90%. RSS stayed at 19–23 MB in the
  final runs.

The optimization keeps 20 FPS, the 1.8 s steady cycle, the 0.6 s plug-in burst,
the level-change heartbeat burst, Reduce Motion, display sleep, template
re-tinting, and the static Dock. The steady tick now reuses cached `CGImage`
frames and writes only the overlay layer's contents; it no longer rasterizes the
template or reassigns `NSStatusBarButton.image`.

## Environment and method

- Date: 2026-10-19, Asia/Shanghai.
- Machine: Mac15,9, arm64, 128 GB, macOS 27.0.1 (26A434). Built-in display at
  2x; one menu bar item for the development bundle.
- Toolchain: Xcode 27.0 (27A266a), Swift 6.4. The project CI toolchain is Xcode
  26.6 / Swift 6.3.3; this measurement used the local toolchain and does not
  replace a CI preflight.
- App: release bundle from `bash scripts/build-worktree.sh release no-open`
  (`com.lingsmbp.StatusTrio.dev.charging-animation-cpu-optimization`), identical
  bundle and settings for every run.
- Baseline: the recorded `main` tree `af765c63` before any optimization, built
  with the same command and copied to `/tmp/status-trio-baseline/`.
- Optimized: this branch built after Tasks 1–4, copied to
  `/tmp/status-trio-optimized/`.
- Charging input: `STATUS_TRIO_FORCE_CHARGING_INPUT=1`, a development-only launch
  switch that feeds the synthetic charging status without enabling the
  animation. The machine was on AC at 80% but held, so real charging was not
  available; both variants use the same synthetic input. The switch is ignored
  outside `.dev.` bundles.
- On/off comparison: the only difference between a pair is the persisted
  `showsChargingEffect` setting. Both runs have the same synthetic charging
  state, Settings window closed, Dock static, and no preview visible.
- Sampling: 15 s settle, then 60 one-second samples per run with
  `top -l 61 -s 1 -pid <PID> -stats pid,command,cpu,mem`. Three on/off pairs
  were run consecutively for each build through
  `scripts/measure-menu-bar-charging-cpu.sh`. Mean and peak are the arithmetic
  mean and maximum of the 61 per-process `%CPU` samples.
- Raw logs: [`artifacts/menu-bar-charging-cpu/`](artifacts/menu-bar-charging-cpu/).
  Every `*.summary.txt` is generated from its adjacent `*.top.txt`.

## CPU results

| Build | Pair | Animation | Mean CPU | Peak CPU | RSS |
|---|---:|---|---:|---:|---:|
| Baseline | 1 | On | 12.26% | 16.10% | 22 MB |
| Baseline | 1 | Off | 0.01% | 0.20% | 20 MB |
| Baseline | 2 | On | 12.40% | 16.30% | 22 MB |
| Baseline | 2 | Off | 0.01% | 0.30% | 20 MB |
| Baseline | 3 | On | 12.25% | 15.70% | 22 MB |
| Baseline | 3 | Off | 0.02% | 0.20% | 20 MB |
| Optimized (first build) | 1 | On | 0.41% | 0.80% | 23 MB |
| Optimized | 1 | Off | 0.01% | 0.20% | 20 MB |
| Optimized (first build) | 2 | On | 0.41% | 0.90% | 21–22 MB |
| Optimized | 2 | Off | 0.02% | 0.30% | 46 MB* |
| Optimized (first build) | 3 | On | 0.44% | 0.70% | 23 MB |
| Optimized | 3 | Off | 0.01% | 0.10% | 20 MB |
| Final build | 4 | On | 0.40% | 0.70% | 20–21 MB |
| Final build | 4 | Off | 0.01% | 0.20% | 20 MB |
| Final build | 5 | On | 0.34% | 0.60% | 21 MB |
| Final build | 5 | Off | 0.01% | 0.20% | 19–20 MB |
| Final build | 6 | On | 0.32% | 0.50% | 21 MB |
| Final build | 6 | Off | 0.00% | 0.10% | 20 MB |

\* One first-build off run reported 46 MB for every sample. The on and other off
runs started from the same fresh launch pattern at 20–23 MB; this sample is
retained as collected and excluded from the RSS comparison. The final-build
pair 4 on sample was re-collected after its first raw log was moved out of the
artifact directory; the table contains the retained run.

| Metric | Baseline | Optimized | Change |
|---|---:|---:|---:|
| Mean animation-on CPU (3-run mean) | 12.30% | 0.35% (final build) | −11.95 points |
| Mean animation-off CPU (3-run mean) | 0.01% | 0.01% | ~0 |
| Incremental CPU (on − off) | 12.29 points | 0.34 points | −11.95 points |
| Peak animation-on CPU | 15.70–16.30% | 0.50–0.70% | −15.0 to −15.8 points |
| RSS (animation on) | 22 MB | 20–21 MB | −1 to −2 MB |

The optimized incremental cost is 0.34 points, inside the plan's 1-point target.
This is a real paired measurement on this machine, not a projection. It is not a
hardware acceptance run: the charging state was synthetic because the machine
would not charge, and WindowServer and Dock CPU were not sampled.

## Instruments Time Profiler

Both builds were attached for a 15 s Time Profiler recording after the same
12 s settle and synthetic charging launch. Raw traces and exported tables are
under [`artifacts/menu-bar-charging-cpu/profiles/`](artifacts/menu-bar-charging-cpu/profiles/).

| | Baseline | Optimized |
|---|---:|---:|
| Sampled CPU in 15 s | 1,996 ms | 92 ms |
| Main-thread samples | 1,950 ms | 56 ms |
| `NSStatusBarButtonCell` drawing (inclusive) | 718 ms | not present |
| `NSImage` best-representation / CGImage conversion | 755 / 603 ms | not present |
| `StatusIconRenderer.render` (inclusive) | 477 ms | not present as a steady cost |
| `presentMenuBar` (inclusive) | — | 28 ms |
| `presentOverlayFrame` (inclusive) | — | 20 ms |
| `CA::Render::prepare/copy_image` | — | 3 / 2 ms |

The pre-change profile is dominated by drawing through the button image: every
20-Hz phase rebuilt template and chromatic artwork, then AppKit converted and
drew the new image. The optimized profile's main-thread time is the clock
publication and the overlay layer contents commit; the template and symbol
rendering paths no longer appear in steady samples.

## What changed

1. **Static/animation split (P0).** `StatusBarController` now has one
   phase-free static key. The template base and resting overlay are rebuilt only
   when that key changes. Ticks go straight to `presentAnimationPhase`.
2. **Independent overlay renderer.** `StatusIconRenderer.menuBarTemplateBase` and
   `menuBarChromaticImage` expose the two halves of the previous
   `menuBarLayers`, so an animation tick never draws the template.
3. **`CGImage` frame cache (P0).** `StatusBarChargingFrameCache` stores 36
   `CGImage`s, removes the `CGImage -> NSImage -> CGImage` round-trip, and keeps
   at most two heartbeat variants (1.0 and 1.35) with LRU eviction.
4. **Layer write suppression (P1).** `StatusBarAnimationLayerPresenter` compares
   the requested frame, backing scale, and image identity, and updates only what
   changed. A repeated frame does not submit a CALayer transaction.
5. **Consumer-driven clock (P1).** `ChargingEffectClock` requires an animation
   surface: a visible menu bar or a live settings preview claim. Hidden menu bar
   with no preview stops the 20-Hz loop; a resumed view continues from the real
   battery state without replaying a plug-in burst.
6. **Measurement support.** The development-only launch switch and
   `scripts/measure-menu-bar-charging-cpu.sh` make paired runs reproducible.
   Tests expose bounded render counters instead of per-tick logging.

## Preserved behavior

- Menu bar: template base plus chromatic layer; the system keeps re-tinting the
  template during a Space switch (#112).
- 20 FPS; 1.8 s steady; 0.6 s plug-in burst; 0.3 s level-advance burst; heartbeat
  boost at 1.35; bolt scaling and tint.
- Reduce Motion, display sleep/wake, unplug/stop, level changes, Settings toggle,
  and the settings preview's `TimelineView`.
- Dock stays static and never subscribes to clock phases.
- `swift test` (600 tests), the targeted 110-test filter, and
  `Issue30WiFiAlignmentTests` (6 tests) pass; `swift build -c release` passes;
  the SDK check reports macOS SDK 26.0 in the app bundle.

## Visual check

The optimized release bundle was launched twice (animation on, then off) with the
same synthetic charging input. Full menu-bar captures at three time points show
the same status-item footprint, template glyphs, and ring geometry. In the on
runs the animated highlight moves along the ring (for example, the colored arc
head at x≈3260 varies between frames); in the off runs the ring stays static.
The zoomed status-item captures are in
[`verification/optimized/`](artifacts/menu-bar-charging-cpu/verification/optimized/).

This is a screenshot comparison on the built-in display, not a real-hardware
Space-switch, multi-display, or WindowServer acceptance run.

## Rejected or deferred

- **Core Animation `CAKeyframeAnimation` playback (Task 5):** not implemented.
  After Tasks 1–4 the remaining sampled cost is the 20-Hz publication and one
  layer contents commit per changed frame, at 0.41 points total. There is no
  measured hotspot left that justifies a second animation architecture.
- **Sub-region animated caching:** not implemented. The steady frame cache is
  already hit on every tick; splitting the ring from other chromatic regions
  would add layering complexity without measured benefit.
- **Unbounded per-multiplier caches:** rejected. The cache holds only the two
  multipliers the clock emits and evicts anything else.
- **Lower frame rate:** rejected. Frame rate and animation semantics are
  unchanged.

## Residual risks and unfinished items

- The real charging state was unavailable; both variants used
  `STATUS_TRIO_FORCE_CHARGING_INPUT=1`. A real plug-in/unplug and level-advance
  hardware check remains open.
- WindowServer and Dock CPU were not sampled; the report only compares Status
  Trio's process CPU.
- The Dock-only placement path is unit-tested at the clock-claim level, but the
  settings window's visible-preview claim was not exercised by a UI automation
  run.
- The local toolchain is Xcode 27.0 / Swift 6.4. The project CI preflight is
  Xcode 26.6 / Swift 6.3.3; no non-publishing `release.yml` run has been made
  yet because it needs a version/build choice.
- No merge, tag, GitHub Release, DMG, or appcast publication was performed.
