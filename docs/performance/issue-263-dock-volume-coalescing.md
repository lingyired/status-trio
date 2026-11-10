# Issue #263 — Dock volume coalescing

## What this change is (and is not)

The user authorized **方案 2 + 3**: while the volume value is adjusted
continuously, the **Dock** repaints at a bounded rate and merges changes that
are too small to see. The panel and the menu bar keep their existing realtime
feedback, and the final value always lands exactly.

This change is a bounded-rate safeguard on the Dock path. Real runtime sampling
now exists; see the **Runtime sampling (2026-11-04)** section below for what it
found on this machine. The Dock is **not** confirmed to be the hotspot — and on
the sampled machine it was **not** a hotspot.

## Code evidence checked before changing anything

- **No volume CPU sampling exists.** `scripts/measure-dock-charging-cpu.sh` and
  `scripts/measure-menu-bar-charging-cpu.sh` only sample the **charging
  animation**; neither script mentions volume.
- **The Dock is already deduplicated.** `AppIconController` subscribes to
  `iconPresentation.$output` with `.removeDuplicates()` and only rasterizes when
  `DockIconRenderCache.needsRender(key)` says the `{scene, background, size}`
  key changed. A repeated scene never repaints.
- **The default volume style is discrete.** `VolumeIconOptions.standard` is
  `.dots`, and `StatusMappings.volumeSteps` maps the scalar to five buckets
  (0–4). Most tiny volume deltas therefore change no scene at all in the
  default style; only `.arc` carries a continuous progress value.
- **The shared scene is already debounced.** `IconPresentationViewModel`
  applies a 500 ms trailing debounce to snapshots, so in today's build the Dock
  rarely sees more than one volume-only scene per burst. The Dock coalescer is
  therefore a bounded-rate safeguard rather than a measured hot-path fix.

## The change

- `IconSceneState.isVolumeValueChange(from:)` classifies a change as a
  continuous volume **value** change only when the ring, centre and per-role
  colours are unchanged and the footer kept its kind, colour and stroke. A
  dots↔arc switch, a stroke/colour change, or any ring/centre change is a
  settings or device change.
- `DockVolumeRenderCoalescer` (Dock only) rate-limits volume-value changes to
  10 Hz and merges arc progress deltas below `0.002` into the trailing repaint.
  The newest request is always the trailing repaint, so the final value is
  exact.
- `AppIconController` routes volume-value changes through that coalescer and
  every other change through the existing `IconRenderCoalescer` (or the
  immediate settings path). A non-volume change cancels a pending volume
  repaint so it cannot delay or resurrect it.
- `stop()` cancels the volume coalescer, so no trailing task outlives the
  controller.

The scene source, the Dock graphic style (dots or arc as configured), the menu
bar path and the panel path are untouched.

## Verification

- Focused: `bash scripts/test.sh 'DockVolumeRenderCoalescerTests|AppIconControllerTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests|PresentationArchitectureTests'`.
- Delivery: `bash scripts/verify-local.sh full` on the final tree.

## Runtime sampling (2026-11-04)

Real `sample` capture of the running build while continuously dragging the
volume slider on this machine (arm64, macOS 27.2). The app was the worktree's
development bundle (`com.lingsmbp.StatusTrio.dev.fix-issue-263-volume-cpu`),
Dock tile visible, default `.dots` volume style. A 12 s capture while the user
dragged the slider in the panel.

Result:

- **No Dock repaint hotspot.** No `DockIconRenderer`/`DockIcon` samples appear in
  the drag window. Discrete `.dots` + `removeDuplicates` + the Dock cache mean a
  continuous drag does not re-raster the Dock.
- **Menu bar icon is not a hotspot.** `StatusIconRenderer` samples are sporadic
  and tiny (≤ ~8 samples).
- The visible busy frames are the **panel sliding control itself**: AppKit
  `layoutIfNeeded`/`_layoutViewTree` (≈140 samples) and SwiftUI
  `DisplayList.ViewUpdater` updates; the main thread otherwise sits in the event
  loop. `SystemStatusStore.setVolume` is called at drag cadence but a single
  CoreAudio write is cheap.
- Net: on **this** machine and configuration, dragging volume does not produce a
  standout CPU spike in StatusTrio. The change is therefore a defensive
  bound-rate guard; any residual high CPU on the reporter's machine is more
  likely the panel layout / SwiftUI, a `.arc` continuous configuration, or a
  BetterDisplay / DDC volume write path, which this change does not touch.
