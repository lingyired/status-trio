# Issue #263 — Dock volume coalescing

## What this change is (and is not)

The user authorized **方案 2 + 3**: while the volume value is adjusted
continuously, the **Dock** repaints at a bounded rate and merges changes that
are too small to see. The panel and the menu bar keep their existing realtime
feedback, and the final value always lands exactly.

This is **not** a CPU-measurement result. No `sample`/Activity Monitor sampling
exists for the volume-adjustment path yet, so this document makes no claim about
measured CPU improvement. The Dock is also **not** confirmed to be the hotspot.

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
- Runtime CPU improvement: **NOT RUN** — no sampling was performed.
