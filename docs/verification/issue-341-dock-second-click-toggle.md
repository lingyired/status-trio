# Issue #341 — second Dock tile click did not hide the panel

Related: [#341](https://github.com/lingyired/status-trio/issues/341),
[#224](https://github.com/lingyired/status-trio/issues/224) (same close–reopen
pair on the status item), [#321](https://github.com/lingyired/status-trio/issues/321)
(Dock activation routing).

## Symptom

Opening the status panel by clicking the app's Dock tile worked, but clicking
the same Dock tile again did not hide it. The menu-bar item already toggled
closed; the Dock path only re-opened.

## Root cause

A Dock tile click produces the same two-step pair that #224 hit on the status
item:

1. **mouse-down** — the global `popoverDismissMonitor` treats the Dock click as
   an outside click, records `reopenSuppression.recordClose(..., mouseButtonDown:
   true)` and calls `performClose`, so the panel is already closed.
2. **reopen** — the Dock click continues as an application reopen and routes to
   `StatusBarController.togglePopover(anchoredAtScreenPoint:)`. It sees
   `popover.isShown == false` and presents the panel again.

`togglePopover()` (menu bar) guards exactly this with
`reopenSuppression.shouldSuppressReopen(at:)`; the Dock overload did not.

## Fix

`togglePopover(anchoredAtScreenPoint:)` now applies the same guard **before**
consuming the toggle gate:

```swift
if !popover.isShown, reopenSuppression.shouldSuppressReopen(at: Date()) {
    return
}
guard popoverToggleGate.shouldAccept(at: Date()) else { return }
```

Ordering matters: checking first means the suppressed click never refreshes the
0.25 s `PopoverToggleGate` lockout, so the following click is accepted promptly
instead of being swallowed a second time. `PopoverReopenSuppression` still
consumes its record, so a third click is independent. Dock anchors, placement
geometry, activation withholding, and the menu-bar/shortcut paths are unchanged.

## Verification

- `PopoverReopenSuppressionTests` (headless): pins that the Dock entry checks the
  suppression before the toggle gate, and that a close-then-reopen pair is
  suppressed once while the next click is accepted. Both failed before the guard
  (the ordering test) and pass after it.
- Regression neighbours: `PopoverToggleGateTests`, `PopoverDismissalPolicyTests`,
  `DockPlacementTests` — pass.
- Full local profile: recorded in the delivery log.
- Real Dock-tile double click on a live macOS session: **NOT RUN** in this
  checkout — the Dock tile belongs to Finder, so it needs an authorized manual
  pass (blocked for instance-scoped background UI testing).
- macOS 13 runtime: **NOT RUN** separately.
