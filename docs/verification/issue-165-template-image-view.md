# Issue #165: independent template image view

Base: `origin/main` at `d3b7ac241533afda385a1bf95e4df43778a81ce6`.
Branch: `codex/issue-165-template-image-view`.

## Accepted probe

The maintainer reported that I and B passed both the slow Space-drag test
(#112) and unfocused-display visual testing on the local two-display setup.
I uses a template NSImageView alongside a non-template button image. B uses a
second button instead of the image view. N and T were not selected.

I+ then retained the template NSImageView but moved the coloured ring into a
CALayer over a transparent non-template button image. The maintainer reported
that I+ also passed both checks. These are maintainer-observed probe results,
not automated Space-gesture tests or whole-application acceptance. No gesture
video or exhaustive OS/appearance matrix was captured.

## Integration

- Keep the shared scene, renderer, geometry, all palettes and animation policy.
- Keep the existing CALayer presenter and pre-rendered charging-frame cache.
- For chromatic scenes only, put the template base in a non-interactive
  NSImageView; the button's transparent non-template image reserves its size.
- Keep the chromatic layer above the template view, so ring fill covers track.
- Retain the original direct template image for entirely monochrome scenes.
- Clear the template view for hiding, switching to monochrome, or full-raster
  fallback. Restore it with the same cached footprint after recovery.

No settings, permissions, dependencies, timers, focus detectors, opacity
heuristics, Dock palette changes, or release operations are added.

The palette remains main's original `.powered` constants: dark menu-bar
background `#34C759`, light menu-bar background `#1F8F3D`. The probe's `#009A2A`
and the earlier green-only branch are not incorporated. These are the RGB
constants in the existing renderer, not claims about screenshot-encoded RGB.
Charging highlights, particles and trails still derive from the same arc
colour through ChargingEffectPalette.

## Automated verification

The new controller regression first failed against the original implementation:
the button image remained template and nontransparent. It then passed with
independent template presentation. Presenter tests cover centering/resizing,
click-through, accessibility, rehosting, release, and the colour-over-track
stacking order.

The existing tick tests enforce one static base, no button-image assignments
during burst/steady ticks, one cached 36-frame set, fallback recovery, and no
duplicate layers. New failure-boundary regressions keep the last readable
template after a hidden item's first redraw fails, and avoid recreating the
template view while overlay rendering fails repeatedly. Existing geometry,
scene-composite, Dock parity, and charging fingerprints remain unchanged.

Commands:

```bash
bash scripts/test.sh \
  'StatusBarTemplateImagePresenterTests|StatusBarChargingAnimationTickTests|StatusBarAnimationLayerPresenterTests|StatusBarControllerVisibilityTests|IconSceneRegionTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests|IconSceneRendererParityTests|DockIconRendererTests|ChargingEffectRenderingTests'
bash scripts/verify-local.sh full
bash scripts/build-worktree.sh release no-open
```

The full-profile result and tested SHA are recorded in
`.build/local-verification/log.txt`; `status.txt` is written only on failure.
A build or test count is not evidence for WindowServer compositing or a native
Space gesture.

## Runtime acceptance boundary

- Standalone I+ two-display appearance and #112: maintainer-observed PASS.
- Development app with this integration: built and launched from this worktree;
  the charging arc changed across captured frames on the focused display, and
  the ring appeared dimmed and desaturated on the unfocused display without a
  duplicate template underlay.
- Full-app #112 Space dragging, popover interaction, low/critical/Bluetooth
  scenes, sleep/wake, and other display arrangements: NOT RUN.
- Real macOS 13 runtime, Universal package, Developer ID signing, notarization,
  publication: NOT RUN.
