# Issue #188: menu-bar colour baseline

Base: `origin/main` at `e3477268e794f6794decaa7ac3b2a03968d512a0`.
Branch: `menubar-status-colors` (from `6630ee951805e833e242596b0674ba41a3d6da10`).

This document records the new baseline. It does not rewrite
`issue-165-template-image-view.md`, whose frozen `.powered` / `.lowPower`
constants were `#1F8F3D` / `#C99700` on a light background and `#34C759` /
`#F2B900` on a dark background.

## What changes

- The template ink is now opaque black `(0,0,0,1)` on a light menu bar and
  opaque white `(1,1,1,1)` on a dark one. The previous `labelColor` carried
  alpha ≈ 0.847, which caps the drawn mask at roughly 216/255.
  **This is a measured alpha difference. Whether it is the user-visible cause
  of the reported grey icon is still an acceptance hypothesis, not a proven
  root cause; the honest confirmation needs the manual comparison below.**
- `.powered` → `NSColor.systemGreen`, `.lowPower` → `NSColor.systemYellow`,
  `.critical` → `NSColor.systemRed`, each resolved once per render against the
  real `NSAppearance` (including the accessibility high-contrast variants).
  These are **semantic starting points**, not a promise that they equal the
  system battery icon pixel for pixel.
- No region classification changes: `templateRegions` / `chromaticRegions`, the
  #112 template/overlay split and the #165 presenter are untouched.

## #165 two-layer architecture (kept)

For coloured scenes the button keeps a transparent non-template footprint, the
monochrome chrome remains an independent template `NSImageView`, and the colour
primitives stay in a `CALayer` above it. The maintainer reported on the local
two-display setup that this I+ arrangement passed both the #112 slow Space-drag
check and an unfocused-display visual check, with the colour ring appearing
dimmed and desaturated on the inactive display. Those are **maintainer-observed
probe results, not automated Space-gesture or dimming tests**; no gesture video
or exhaustive OS/appearance matrix was captured. This baseline commit adds no
focus detector, dimming compensation, opacity heuristic, settings or permission;
the #193 commit on top adds only the per-role colour settings.

## Automated verification

- `BatteryStatusColorBaselineTests`: literal opaque black on aqua and
  high-contrast aqua, literal opaque white on dark aqua and high-contrast dark
  aqua; the three semantic baselines resolve to the appearance's
  `systemGreen` / `systemYellow` / `systemRed`.
- `StatusIconRendererTests.testMenuBarTemplateInkIsOpaqueInBothAppearances`:
  drawn template alpha peaks at 255 in both appearances.
- `StatusIconRendererTests` semantic-colour assertions resolve the expected
  system colour per appearance rather than pinning a hand-tuned triple.
- `DockIconRendererTests`: light tile draws the light-appearance semantic
  green; a dark tile draws the dark-appearance semantic red (three-role
  semantic parity, intentional and documented).
- `IconMenuBarTemplateTests`, `IconSceneRegionTests`,
  `IconSceneRendererParityTests`, `ChargingEffectRenderingTests`,
  `Issue30WiFiAlignmentTests`, `IconSurfaceIntegrationTests`,
  `StatusBarTemplateImagePresenterTests`, `StatusBarChargingAnimationTickTests`
  pass unchanged. The static charging fingerprint test was not loosened; one
  concurrent full-suite run produced an unexplained `55ad…` variant that
  differed only inside the Wi-Fi glyph (ring and volume pixels identical, the
  ink-offset measurement and symbol bounds unchanged). No new hash was approved
  and no tolerance was widened; the final full run passed without it. It stays
  a documented finding rather than a fixed cause.
- `ChargingEffectFrameCacheTests` builds its expected pixels from the same
  opaque-ink environment instead of the previous translucent `labelColor`, and
  `Support/AppIcon.icon/Assets/AppIcon-{light,dark}.png` were regenerated from
  the renderer so the committed bundle artwork matches the new semantic green.
  The AppIcon fingerprint table was re-recorded for this local environment; the
  prior CI/headless pair is not claimed and must be re-recorded on that
  hardware (NOT RUN here).

Commands (all run locally on the tested worktree):

```bash
bash scripts/test.sh 'StatusIconRendererTests|IconMenuBarTemplateTests|IconSceneRegionTests|IconSceneRendererParityTests|ChargingEffectRenderingTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests|DockIconRendererTests|StatusBarTemplateImagePresenterTests|StatusBarChargingAnimationTickTests|BatteryStatusColorBaselineTests'
bash scripts/verify-local.sh full
```

## Still manual / NOT RUN

- Real Ventura (macOS 13) and current-macOS runtime: NOT RUN.
- Slow Space-drag gesture and unfocused two-display dimming for the new
  baseline: NOT RUN this round (maintainer-observed for the prior #165 probe).
- Whether the opaque ink removes the user-visible grey icon: needs a human
  before/after comparison; NOT RUN.
- Exact RGB agreement with the built-in system battery icon: not asserted.
