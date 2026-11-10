# Issue #224 — single click on the status item did not close the panel

Related: [#224](https://github.com/lingyired/status-trio/issues/224),
[#186](https://github.com/lingyired/status-trio/issues/186) (arrowless
`NSPanel` that introduced the hand-rolled dismissal),
[#183](https://github.com/lingyired/status-trio/issues/183) (activation gating).

## Symptom

After opening the status panel with a single click on the menu-bar item, a
second single click on the same item did not close the panel — it visibly
flashed and stayed open, so users needed a double click. Other app windows
flickered during the attempt.

## Root cause

The arrowless panel (`AnchoredStatusPanel`, issue #186) dismisses on outside
clicks through `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,
.rightMouseDown])`. That monitor closed the panel on **every** mouse-down, with
no exception for the status item itself.

When the panel opens while the app is not active (the forced `activate` from a
status-item click can be ignored by the user-activation policy — see the comment
in `presentPopover`), a click on the status item is delivered by the system
menu-bar process and reaches the global monitor as an outside click:

1. `mouseDown` → monitor calls `performClose` → panel closes.
2. `mouseUp` → the button's action (`handleClick` → `togglePopover`) sees
   `popover.isShown == false` and presents the panel again.
3. So one click closed then reopened the panel: it looked like "does not
   close", and the repeated re-present re-ordered windows / re-requested
   activation, which flickered other windows.
4. A rapid second click was then swallowed by `PopoverToggleGate`
   (`popoverToggleLockoutInterval = 0.25`), so only the mouse-down close
   remained — a double click "closed" it.

## Fix

`PopoverDismissalPolicy` (new, pure) decides whether a global mouse-down is an
outside click. `StatusBarController.installPopoverDismissMonitor()` now builds
the status item button's screen rectangle and skips the dismissal when the click
lands inside it, leaving the click to the item's own `togglePopover`. Clicks
outside the item still dismiss; when the item is not visible there is nothing to
protect and every click dismisses (previous behaviour).

The fix does not add timers, polling, or repeated activation. A single
status-item click now produces exactly one state change (open → closed), so the
close–reopen activation churn that caused the flicker is gone.

## Verification

- Deterministic unit tests (`PopoverLifecycleTests.swift`,
  `PopoverDismissalPolicyTests`): click inside the item is not dismissed, click
  outside is dismissed, missing frame falls back to dismissing, and one
  status-item gesture toggles exactly once. A regression guard shows the old
  unconditional dismiss would reopen on the same click. **PASS** (10 tests).
- Full local profile (`bash scripts/verify-local.sh full`): see delivery record.
- Real-device click-driven check (single click open, single click close, double
  click does not thrash, other windows do not flicker) on macOS 13 and current
  macOS: **NOT RUN** — this harness has no permitted Computer Use provider for a
  status-item click (same limitation recorded for #186), so it requires an
  authorized foreground/manual pass.


## Follow-up: deactivation still reopened v1.9.2

On macOS 27.0.1, production logs showed app deactivation closing the panel
before the status item's mouse-up reopened it. The global-click exclusion
above does not cover this path. Menu-bar presentation now skips the legacy
`NSPopover` forced activation: the current nonactivating `NSPanel` becomes key
without it. A panel-scoped workspace observer preserves Cmd-Tab dismissal and
ignores Status Trio's own activation; existing close teardown removes it.

The activation and workspace-close tests failed before their respective fixes.
The focused visible run passed 16 XCTest and 8 Swift Testing cases. The user
confirmed repeated open/close/reopen, Settings-open behavior, Cmd-Tab, Escape,
and outside clicks. CUA could inspect windows but could not click the status item.
Full local verification is recorded in the PR; macOS 13 runtime is NOT RUN.
Shortcut activation is unchanged; shortcut-open → status-click is unvalidated.

## Follow-up 2: focus-loss paths still reopened while the app is active

The v1.9.2 follow-up fixed the *inactive* case, but the panel still had two
unconditional focus-loss close paths that the global-click exclusion does not
cover:

- `AnchoredStatusPanel` closes on `NSApplication.didResignActiveNotification`.
- `AnchoredStatusPanel` closes when another app activates
  (`NSWorkspace.didActivateApplicationNotification`).

Both fire when the app is **active/regular** — Dock icon shown, or the Settings,
first-run or manual-update window open — and the user clicks the status item to
close the panel: the app resigns active on the mouse-down, the panel closes, and
the item's mouse-up `togglePopover` sees `popover.isShown == false` and presents
it again. That is the same "looks like it refreshed instead of closing" symptom,
now on a second close path.

Fix: `PopoverDismissalPolicy.shouldDismissOnFocusLoss(at:isMouseButtonDown:)`
defers a focus-loss close while a mouse button is held down inside the status
item rectangle, letting the item's own toggle own the click. A genuine focus
loss with no button pressed (Cmd-Tab, Space switch, clicking another app) still
dismisses even if the pointer rests over the item, so the #183 full-screen and
Cmd-Tab dismissal is preserved. `StatusBarController.configurePopover()` wires the
policy to `NSEvent.mouseLocation` and `NSEvent.pressedMouseButtons`.

Covered by `PopoverFocusLossDismissalPolicyTests` (headless). The real click in
regular mode is `NOT RUN` in this checkout (no permitted Computer Use provider
for a status-item click); it needs an authorized foreground/manual pass.

## Follow-up 3: pure menu-bar (accessory) users still saw a reopen

A reporter on macOS 27.0.1, v1.9.4, with **no Dock icon and no Settings window
open**, still saw a single status-item click "refresh" the panel instead of
closing it. In that accessory state the app never becomes active, so neither
`didResignActive` nor another app activating applies — the only close path is the
**outside-click monitor's status-item hit test**. If that hit test misjudges the
item (multi-display / notch / menu-bar geometry, or an OS-build difference), the
monitor closes on mouse-down and the item's mouse-up toggle reopens it.

Fix: a coordinate-free safety net, `PopoverReopenSuppression`. Any panel close
that happens **while a mouse button is held down** is recorded; the immediately
following status-item toggle then refuses to reopen. This does not depend on the
item's screen rectangle, so it holds when the hit test is wrong. A genuine
outside click (no toggle follows), a normal close from the item's own mouse-up
toggle (button not held), Escape, and a real focus loss (no button held) are all
unaffected. The record is bounded by
`StatusBarController.popoverReopenSuppressionInterval` (0.35 s) so a much later
opening click is not mistaken for the closing one; the trade-off is that a
deliberate reopen within 0.35 s of a mouse-down dismissal is ignored once.

Covered by `PopoverReopenSuppressionTests` (headless). The real accessory-mode
click is still `NOT RUN` here (no permitted status-item click provider) and needs
the reporter's manual confirmation on macOS 27.

## Follow-up 4: the status item's very edge (reproduced on v1.9.4)

A reporter on macOS 27.0.1 with **no Dock icon and no Settings window** could
reliably reproduce the "refresh instead of close" only by clicking the **outermost
edge** of the status item (e.g. its rightmost pixels).

Root cause: `NSRect.contains(_:)` — and `NSPointInRect` / `NSMouseInRect` — treat
the rectangle as **half-open**. `minX` / `minY` are inside, `maxX` / `maxY` are
*outside*:

```text
contains(minX, midY) = true
contains(maxX, midY) = false   <- right edge counts as outside
contains(midX, maxY) = false   <- top edge counts as outside
contains(midX, minY) = true
```

`PopoverDismissalPolicy.shouldDismiss(at:)` used exactly that test, so a click on
the status item's rightmost or topmost column of pixels was classified as an
outside click: the monitor closed the panel on mouse-down, and the item's own
mouse-up `togglePopover` presented it again — one click that visibly "refreshed".

Fix: `PopoverDismissalPolicy.containsInclusive(_:_:)` compares the point against
all four edges inclusively. Both `shouldDismiss(at:)` and
`shouldDismissOnFocusLoss(at:isMouseButtonDown:)` use it. The rectangle is not
widened, so a genuine outside click one pixel past the edge (e.g. on the
neighbouring menu-bar item) still dismisses.

`PopoverDismissalPolicyEdgeTests` covers both edges, all four corners, the
one-pixel-outside cases, the focus-loss path, and the full edge-click gesture.
It also pins the half-open `NSRect.contains` behaviour the helper exists for.

Two independent layers now prevent this symptom:

1. the geometric test classifies an edge click as the item's own toggle;
2. `PopoverReopenSuppression` keeps the panel closed even if the geometry
   misjudges, because the close happened while the mouse button was held.

Real pointer verification on macOS 27 remains `NOT RUN` in this checkout; it
needs the reporter's (or an owner's) manual click on the outermost pixel.
