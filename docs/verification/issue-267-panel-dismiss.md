# Issue #267 — clicking the Settings window did not dismiss the status panel

Status: **fix implemented. The dismissal decision and the window-notification
wiring are covered by unit tests (headless policy tests plus synthetic
notification-wiring tests). The real key-window handoff / real click is
`NOT RUN`: the only available local session was screen-locked, so no click-driven
acceptance was performed. The Debug background-testing panel route deliberately
disables focus-loss dismissal and therefore cannot prove this behaviour.**

Related:

- [#267 [Bug] 点击设置窗口时状态面板不消失](https://github.com/lingyired/status-trio/issues/267)
- [Issue #186 — arrowless status panel](issue-186-arrowless-status-panel.md) —
  the custom `NSPanel` that has to reproduce popover dismissal itself.
- [Issue #224 — status-item single-click toggle](issue-224-status-item-toggle.md)
  — the global outside-click monitor and its status-item exception.
- [Issue #183 — full-screen Space dismissal](issue-183-fullscreen-panel-dismiss.md)
  — the activation gating that must not regress.

## Symptom

Open the app's Settings window first, then open the status panel from the
menu-bar item, then click the Settings window. The panel stayed on top of the
Settings window instead of closing the way clicking another app's window does.

## Root cause

The panel is a custom borderless `NSPanel` (`AnchoredStatusPanel`), not an
`NSPopover`, so it has no built-in "close when another window is clicked"
behaviour. Outside clicks are handled by
`StatusBarController.installPopoverDismissMonitor()`, which uses
`NSEvent.addGlobalMonitorForEvents` — that monitor only sees events delivered to
*other* applications. A click on the app's own Settings window is an in-process
event the monitor never receives. The panel's `NSWindow.didResignKeyNotification`
observer only wrote a log line; nothing closed the panel on an in-app focus
handoff.

## Fix

- New pure policy `Sources/StatusTrioCore/UI/PanelFocusDismissPolicy.swift`.
  Given the window that just became key/main it dismisses only when that window
  is not the panel itself, is visible, is at `NSWindow.Level.normal`, has no
  `sheetParent` and no `parent`. This keeps internal interactions (panel
  controls, pop-up menus, confirmation sheets/alerts) from closing the panel.
- `StatusBarController.observeAppWindowFrontmostChanges()` observes
  `NSWindow.didBecomeKeyNotification` and `NSWindow.didBecomeMainNotification`
  and closes the panel when the policy allows it. The notifications are handled
  synchronously (AppKit posts window notifications on the main thread) so a
  run-loop hop cannot deliver a stale key change after the panel re-keyed
  itself.
- The Debug background-testing route keeps its contract: while
  `disablesDismissOnResignForTesting` is set (the `--panel` launcher route), the
  new dismissal logic does not run.
- Existing paths are unchanged: the footer's Settings action still closes the
  panel explicitly before opening the window (no double close), and clicking
  another app / switching Spaces / full-screen Spaces keeps the #183/#224
  behaviour.

## Verification

| Check | Result |
| --- | --- |
| `PanelFocusDismissPolicyTests` (headless decision boundaries) | PASS |
| `swift test --filter 'StatusBarController\|Panel'` | PASS (80 tests / 13 suites on the fix commit) |
| `scripts/verify-local.sh full` (non-Universal local bundle, native contracts, offline release simulations) | PASS (927 tests / 129 suites) |
| Notification wiring via synthetic `NSWindow.didBecomeKey/MainNotification` posts | PASS (visible-UI suite, skipped by default; only proves the observer runs) |
| **Real key handoff: Settings key → panel opens and takes key → Settings key → panel closes** | **NOT RUN** — requires an authorized visible session; the available session was screen-locked |
| **Real click acceptance: open Settings → open panel → click Settings window** | **NOT RUN** — same reason |
| Debug background-testing route (`launch-computer-use.sh --panel`) | NOT APPLICABLE — `disablesDismissOnResignForTesting` bypasses the new logic by design |

### What is actually proven

- The decision table (what may/may not dismiss) is exhaustively unit-tested.
- The controller registers both window notifications and closes the panel when
  the policy allows; this is exercised with synthesized notifications.
- The full local profile builds and passes.

### What is not proven

- A real macOS key/main handoff from the panel back to the Settings window.
  `isKeyWindow` only becomes meaningful in an active app, and the visible-UI
  test that asserts it (`testRealKeyHandoffFromPanelBackToSettingsClosesPanel`)
  is skipped by default.
- Real click routing on the Settings window (the original bug report path).
- macOS 13 / current-macOS runtime acceptance; only the static contract and the
  local build were checked.

The Debug background-testing route must not be cited as evidence here: it opens
the panel without key status and with focus-loss dismissal disabled, which is
the opposite of the behaviour #267 changes.

## Next step

Run the visible-UI suite in an authorized, unlocked session:

```sh
STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1 bash scripts/test.sh 'StatusBarController|Panel'
```

plus the manual steps from the issue, and record the result before claiming a
live-click pass.
