# Issue #30 — Wi-Fi icon not centred (regression analysis)

Reported: <https://github.com/lingyired/status-trio/issues/30>
Status: **not a reverted fix** — the original fix is still in the shipped build; the fix itself was wrong.

## Question asked

> Previously fixed, but recently it came back — was the earlier fix's code replaced?

## Answer

No. The fix is intact in source and in the shipped v1.3.3 binary. It never
addressed the real cause.

Evidence:

```bash
git show v1.3.3:Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift | grep -n wifiSymbolCenter
# 8:    private static let wifiSymbolCenter = CGPoint(
# 9:        x: StatusIconGeometry.canvas.midX,
# 121:            x: -(wifiSymbolCenter.x - 28.0),
# 941:        let pivot = wifiSymbolCenter
# 1006:        center: CGPoint = wifiSymbolCenter,
```

The only later change to the fix was the test tolerance, not the code:

```
e48cd70 test: tolerate macOS 15 icon rasterization
-            accuracy: 0.25,
+            accuracy: 0.45,
```

## Real root cause

The original fix (32f5a43) replaced the hardcoded `59.5` with
`StatusIconGeometry.canvas.midX`. Those are **not the same number**:

| Element | x centre |
| --- | --- |
| `canvas.midX` (what the SF Symbol is anchored to) | **60.0** |
| `batteryCenter.x` | 59.5 |
| `wifiOuterCenter.x` | 59.5 |
| `batteryChargingBoltPivot.x` | 59.5 |
| `wifiDot` bbox midpoint | 59.5 |
| `noInternetOverlay` stem | 59.5 |

The artwork is designed on a 119-unit-wide box centred at **59.5** — the source
`status-menubar.svg` battery arc runs from `x=15.5` to `x=103.5`
(`(15.5 + 103.5) / 2 = 59.5`). `canvas` is 120 wide, so `canvas.midX = 60`.

So the "fix" moved the SF Symbol **+0.5 units to the right** of every
hand-drawn element, instead of aligning it. Measured against the artwork, the
symbol sits 0.5 units right; a circle drawn around it would sit 0.5 left of the
symbol's ink — which is what the reporter sees.

## Why the test passes anyway

`Issue30WiFiAlignmentTests` asserts the *ink centroid* against
`canvas.midX` with `accuracy: 0.45`. Two problems:

1. It measures a 60x38 window (`x: 30, y: 40`) that mixes the hand-drawn Wi-Fi
   dot (centred at 59.5) with the SF Symbol, so the two errors partly cancel.
2. The tolerance (0.45) is the same order as the defect it is meant to catch
   (0.5). It was widened from 0.25 in `e48cd70` — the commit that let the bug
   through. A 0.5-unit error can never fail a 0.45 tolerance reliably.

Measured symbol ink anchor, `wifiSymbolCenter.x` fixed at 60.0:

| `wifiScale` | point size | symbol box | off vs art centre (59.5) |
| --- | --- | --- | --- |
| 1.00 | 38.0 | 50x39 | +0.500 |
| 1.25 | 47.5 | 63x48 | +0.500 |
| 1.50 | 57.0 | 76x58 | +0.000 (lucky rounding) |
| **1.60 (shipped default)** | 60.8 | 81x62 | **+0.500** |
| 1.70 | 64.6 | 85x65 | +0.500 |
| 1.80 | 68.4 | 91x69 | +0.000 (lucky rounding) |

The default `wifiSymbolScale` is **1.6** (`defaultWifiSymbolScale =
defaultStatusCenterSymbolScale = 1.6`, range `1.0...1.8`), so most users are in
the +0.5 case. The defect only vanishes at scales whose symbol box width happens
to be odd (57.0pt and 68.4pt), which is why it looks intermittent.

## Proposed fix direction (not yet implemented)

Give the icon one authoritative centre instead of two, and anchor to the
artwork rather than the bitmap:

- Add `StatusIconGeometry.artworkCenterX: CGFloat = 59.5` (derived from the SVG
  battery arc, documented as such).
- Point `wifiSymbolCenter.x`, and the `59.5` literals in `batteryCenter`,
  `wifiOuterCenter`, `batteryValueBaseline`, `batteryChargingBoltPivot` and the
  hand-drawn paths at it, so one constant governs the whole icon.
- Tighten the regression test: assert against `artworkCenterX` with a tolerance
  below 0.25, measure the SF Symbol ink in isolation (not a window that also
  contains the hand-drawn dot), and cover the shipped default scale 1.6 as well
  as the range endpoints.

## 2026-10-09 recurrence after the icon-presentation refactor

The issue reopened on v1.5.1. The `artworkCenterX` fix was still in the source,
so the earlier 59.5-vs-60 analysis was not the whole cause.

The remaining error is inside the SF Symbol itself. `NSImage.size` reports a
layout box, and the glyph's visible ink is not centred in that box:

| symbol | point size | layout box | ink bbox centre vs box centre |
| --- | --- | --- | --- |
| `wifi` | 38.0 | 50x39 | **-0.438** |
| `wifi` | 60.8 (default) | 81x62 | **-0.344** |
| `wifi` | 68.4 | 91x69 | **-0.375** |
| `wifi.slash` | 60.8 | 81x75 | **-0.344** |
| `wifi.exclamationmark` | 60.8 | 81x74 | **-0.344** |
| `headphones` | 60.8 | 78x76 | **-0.344** |

Anchoring that box at 59.5 therefore put the visible `wifi` ink at about
59.16, still left of the hand-drawn ring. The 2.0 scene renderer kept the same
box-centring call, so the UI refactor did not introduce a new anchor; it carried
the incomplete fix forward.

`StatusIconRenderer.drawOfficialSymbol` now measures the alpha bbox of the
configured symbol and applies the horizontal bearing before drawing. The
measurement is cached per symbol name, variable value, and point size, so
animation frames do not re-rasterise it. On the local macOS 27 toolchain the
reported ink centre moves from 59.125 to 59.500 for `wifi`, `wifi.slash`,
`wifi.exclamationmark`, and `headphones`.

Regression coverage:

- `Issue30WiFiAlignmentTests.testCenterSymbolInkLandsOnTheArtworkCenterLine`
  renders only the centre symbol and pins its alpha bbox against
  `artworkCenterX`; removing the compensation fails all six cases.
- `Issue30WiFiAlignmentTests.testWiFiGlyphIsHorizontallyCenteredInMenuBarIcon`
  keeps the full-composite check.
- `ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`
  is re-recorded because `staticSnapshot` draws `wifi.slash` through the same
  compensation.

## Toolchain note

Shipped v1.3.3 is built with `sdk 26.0`, `minos 15.0`, satisfying the macOS 26
SDK requirement in AGENTS.md.
