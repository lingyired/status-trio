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
