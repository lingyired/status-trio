# Issue #183 — status panel dismisses itself in another app's full-screen Space

Status: **fix implemented; the activation-gating behaviour is covered by
deterministic unit tests. The originating defect was reported on macOS 15.7.3,
which this checkout cannot run, so the live full-screen reproduction is
`NOT RUN`. A macOS 27 acceptance pass also found and fixed a Liquid Glass
detail-page resize jump in the same panel (see the follow-up section). The
macOS 27 `full` profile is blocked by a pre-existing, unrelated
rendering-fingerprint flake (see “Verification”, below).**

Related issues:

- [#183 [Bug] 全屏 App 中状态面板打开后，移动鼠标即自行收起](https://github.com/lingyired/status-trio/issues/183)
- [Issue #186 — arrowless status panel](issue-186-arrowless-status-panel.md) — the
  custom `NSPanel` this change fixes.
- [full-screen popover investigation](../fullscreen-popover-investigation.md) —
  issue #48, where the panel did not appear at all over a full-screen Space.

## Symptom

On macOS 15.7.3 with Status Trio 1.8.0 (46), opening the status panel from the
menu bar while another app (Kaku, WPS, ChatGPT, …) is in a full-screen Space
shows the panel briefly, then it dismisses itself as soon as the pointer moves
towards its controls. The same panel works normally on an ordinary desktop
Space, and other apps' popovers (Vorssaint) keep working in the same full-screen
Space.

## Decisive clue from the reporter

The reporter isolated the trigger by controlling the app's activation policy:

- With the Status Trio **Settings window open**, the Dock icon is visible and the
  app runs as `regular` (`policy=0`). Opening the panel from another app's
  full-screen Space then dismisses it. Log excerpt (UTC+8):

  ```
  14:53:11.522 Popover presented          policy=0 active=false key=false
  14:53:11.574 Application became active / window became key  active=true key=true
  14:53:11.755 Window resigned key / Application resigned active  active=false key=false
  14:53:12.245 Popover closed             event=9 (mouseExited)
  ```

- After **closing the Settings window** the Dock icon disappears, the app drops
  to `accessory` (`policy=1`), and the panel becomes key and stays open until a
  genuine interaction.

That is the whole difference: **the defect only reproduces while the app is
`regular`.** A regular app owns real windows on a desktop Space (the Settings or
first-run window); an accessory app owns none.

## Root cause

`StatusBarController.presentPopover` force-activated the application with
`NSApp.activate(ignoringOtherApps: true)` before showing the panel. For a
`regular` app that activation makes macOS reveal the app's other window — the
Settings window — which lives on a desktop Space. From another app's full-screen
Space that moves the WindowServer away from the full-screen Space; the app
becomes active and then immediately resigns, and `AnchoredStatusPanel` (which
closes on `NSApplication.didResignActiveNotification`, exactly like an
`NSPopover`) tears the panel down. The reporter's log shows that exact
became-active → resigned-active → closed sequence.

The code already knew this shape: the Dock-click path passes
`activatesApplication: false` with the comment “Re-activating can restore the
existing Settings window ahead of the transient popover.” The status-item and
shortcut paths did not apply the same guard.

## Fix

Withhold the forced activation while the app is regular. The panel is a
non-activating `NSPanel` (`.nonactivatingPanel`, `canBecomeKey == true`,
`.canJoinAllSpaces + .fullScreenAuxiliary`), so it still orders in over the
full-screen Space and becomes key without activating the app; the pointer and the
panel's own controls keep working, and no `didResignActive` is generated for the
panel to react to.

- `Sources/StatusTrioCore/UI/StatusBarController.swift`
  - new injected dependency `isApplicationRegular` (defaults to
    `NSApplication.shared.activationPolicy() == .regular`);
  - `presentPopover` computes
    `forcesApplicationActivation = activatesApplication && !isApplicationRegular()`
    and only calls `activatesApplicationForPopover()` when that is true;
  - the presentation log records `applicationActivation=withheld-regular` for the
    withheld case.
- Accessory apps and the Dock-click path are unchanged.

## Verification

### Automated (run on this branch)

- `Tests/StatusTrioCoreTests/StatusBarMemoryPressureTests.swift`
  - `testRegularApplicationPolicyWithholdsShortcutPresentationActivation` — with
    `isApplicationRegular == true`, `openPopoverFromShortcut()` shows the panel
    and does **not** call the activation probe.
  - `testShortcutPresentationStillForcesApplicationActivation` (pre-existing,
    extended harness) — with `isApplicationRegular == false`, activation still
    happens.
  - `testDockPresentationDoesNotForceApplicationActivation` (pre-existing) — the
    Dock path still never activates.
- Focused run: `bash scripts/test.sh StatusBarMemoryPressureTests` — **PASS**.

### Full local profile

`bash scripts/verify-local.sh full` runs the whole Swift suite first. On this
machine (macOS 27.2, 26B123, arm64e, Retina) it stops at a **pre-existing,
unrelated** failure:
`ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`
(the local system symbol raster gives a SHA-256, `55ad404d…`, that is not in the
two committed macOS-27 baselines). Evidence it is not caused by this change: the
same failure reproduces on a **clean `origin/main` checkout at `23e073d2`**, and
the test passes in isolation in both trees. It is an environment baseline /
parallel-run issue in the icon-rendering test, outside this change's scope.

Because `verify-local.sh full` aborts on that first failure, the remaining
`full` stages were run directly on this branch and recorded below.

| Stage | Result |
| --- | --- |
| Swift tests + forbidden patterns | 812/813 pass; the one failure is the pre-existing rendering fingerprint above (reproduced on clean `main`) |
| Release build (`swift build -c release`) | **PASS** |
| App bundle build (`build-app.sh release no-open`, non-Universal ad-hoc) | **PASS** |
| Platform / SDK contract (`13.0`, SDK 26 floor; built against `MacOSX27.0.sdk`) | **PASS** |
| Mobile battery bundle | **PASS** |
| Privileged helper bundle | **PASS** |
| Native checks (25 scripts: macOS 13 contracts, icon/appcast, mobile-battery, helper, release pipeline/recovery/notarization simulations, workflow policy) | **PASS** |

### Not proven here (recorded `NOT RUN`)

- Live reproduction on macOS 15.7.3 with a full-screen Space. This checkout runs
  macOS 27.2, where the maintainer already could not reproduce the original
  defect. Real acceptance needs the reporter's environment (or any macOS 15
  machine) with the Settings window open and another app in full screen.
- macOS 13 / Ventura runtime. The deployment target is unchanged; no runtime
  check was performed.
- Signing, notarization, DMG, Universal packaging, appcast, release.

## Acceptance for the reviewer

On a machine where the defect reproduces (macOS 15.7.3 or similar):

1. Open Status Trio → Settings and leave it open (Dock icon visible).
2. Switch to another app in full-screen mode.
3. Hover the top edge to reveal the menu bar, click the Status Trio icon.
4. Move the pointer into the panel and operate a control.

Expected: the panel stays open until an outside click / Escape / a panel action,
with no self-dismissal on pointer movement.

## Follow-up found during macOS 27 acceptance: detail-page resize jump

### Symptom

Opening the battery-detail or Wi-Fi-detail page moved the panel. For the tall
battery page the panel was pushed above the top of the screen so its Back
control could not be clicked; closing and reopening the panel showed the same
detail page at a normal position. Returning from a detail page moved the panel
again.

### Evidence

A `CGWindowListCopyWindowInfo` poll of the panel window (layer 25) while
reproducing on macOS 27.2 recorded the top edge and height oscillating:

```
Y= 34 H=418   (normal)
Y=-217 H=336  (above the screen top, Back unreachable)
Y= 34 H=318
Y=134 H=418
Y= 34 H=361
Y= 91 H=418
```

The X position stayed constant; only the vertical placement and height moved.

### Cause

On macOS 26+, `StatusPanelContentViewController` set
`NSGlassEffectView.contentView = hostingController.view` directly. The glass
view then treated the SwiftUI hosting view's intrinsic content size as its own
and resized/repositioned the panel window whenever the content height changed.
That fought `AnchoredStatusPanel.applyContentSize`, which had already computed
the correct anchored frame (top edge fixed). A probe that forced the pre-Tahoe
`NSVisualEffectView` path kept the top edge fixed at 1086 pt; the same probe on
the glass path reported 1148 pt after switching to the Wi-Fi page.

### Fix

`Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift` now puts a plain `NSView`
between the glass background and the hosting view and lets that container fill
`NSGlassEffectView.contentView`. The plain view has no intrinsic content size,
so the glass can no longer drive the window frame; the hosting view still fills
it through its autoresizing mask.

### Regression test

`Tests/StatusTrioCoreTests/StatusPanelContentResizeTests.swift` builds the real
`StatusPopoverView`, opens the Wi-Fi detail page and returns, and asserts the
menu-bar edge and X position stay fixed and the summary height is restored.

- Without the container: **FAIL** — top edge `1148` vs expected `1086`.
- With the container: **PASS**.

The pre-Tahoe `NSVisualEffectView` path was already stable; it is unchanged.


### Residual: summary clipped at the top after returning from battery details

macOS 27 acceptance after the container fix showed a second, intermittent
symptom: after leaving the battery detail page, the summary occasionally stayed
at the detail page's height, so the taller summary was clipped at the top and
its first rows were unreachable.

Two sizing paths are now hardened:

- `StatusPanelHostingController.viewDidLayout` measures
  `sizeThatFits(in: NSSize(width: panelWidth, height: .greatestFiniteMagnitude))`
  instead of `view.fittingSize`. The unbounded proposal returns the content's
  ideal height even while a route transition is still settling, so a stale
  detail-page height cannot be reported as the new summary height.
- `StatusPanelContentViewController.viewDidLayout` sizes the hosting view to its
  actual superview (`glassContent`), not to `glass.bounds`, so any
  `NSGlassEffectView` content inset cannot clip the top edge.

Coverage added in `StatusPanelContentTests` for the ideal-height measurement and
extended in `StatusPanelContentResizeTests` for summary → battery detail →
summary and summary → Wi-Fi detail → summary round trips.

### Appearance investigation and rejected root-glass experiment

A later experiment replaced the outer container with `NSGlassEffectView` and
assigned the hosting view directly to its content. Although the earlier test
passed, the maintainer observed the detail-page jump returning; the ABC keycap
and corner outline were unchanged. That experiment is rejected and the stable
container structure above is restored. The resize test now waits for natural
AppKit/SwiftUI layout without manually calling `viewDidLayout`.

The earlier claim that the wrapper caused the ABC colour difference was not
verified. A headless comparison found both the template icon and keycap using
`.primary` at roughly RGB 221 in dark mode. The filled keycap now uses explicit
white in dark appearance and black in light appearance, with a pixel test for
its ink and cut-out letter. This is a deliberate contrast adjustment, not a
claim about Liquid Glass internals.

The glass path previously rounded only the material itself; its outer backing
layer had radius 0 and `masksToBounds == false`. The root now clips descendants
to the panel's 16 pt curve, matching the pre-Tahoe root clipping contract. A
focused test fails on the old configuration and passes after the fix. The
WindowServer shadow is invalidated after frame changes so it can track the
current transparent silhouette. These contracts do not prove the user's
on-screen dark outline has disappeared; that remains a visual acceptance item.


### Text contrast: popover-material experiment (rejected)

The maintainer compared the custom panel with the 1.8.0 `NSPopover` and found
secondary text fainter. A headless appearance probe shows the difference is the
background class: `NSVisualEffectView(material: .popover)` resolves to
`NSAppearanceNameVibrantDark`, while `NSGlassEffectView` resolves to
`NSAppearanceNameDarkAqua`, so SwiftUI `.secondary` follows different values.

An experiment (dev build "Issue 183B") switched the panel to
`NSVisualEffectView(material: .popover)` on every macOS version. It matched the
old popover's text contrast but stopped using Liquid Glass, which the maintainer
noticed and rejected: the project keeps `NSGlassEffectView` on macOS 26+ as the
#186 design requires.

### Decision: keep system-native Liquid Glass

The maintainer chose to accept the system-native Liquid Glass appearance
(`NSGlassEffectView`) as-is. The slightly fainter secondary text is accepted as
the platform's own value for that material rather than compensated with a manual
colour override. The popover-material experiment is removed from the shipped
code.
