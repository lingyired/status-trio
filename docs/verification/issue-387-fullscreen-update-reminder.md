# Issue #387 — no update reminder while a game is full screen

Status: **fix implemented. The full-screen classification, the monitor's
full-screen → windowed transition, and the "schedule a background check only"
decision are covered by unit tests. The real Sparkle alert in a real
full-screen Space is `NOT RUN`: this repository's Debug and development-codename
builds never start the updater (`UpdaterManager.start` returns early), so the
reminder can only be exercised by a release candidate build on a real machine.**

Related: [#387 游戏时不应该弹出更新提醒](https://github.com/lingyired/status-trio/issues/387)

## Symptom

While a game (or any app) was running in full screen, Status Trio's automatic
update check found a new version and Sparkle's standard update alert appeared
over the game, interrupting play.

## Root cause

Status Trio is an `LSUIElement` (background) app. Sparkle's standard user driver
treats a scheduled check from a background app differently from a regular app:
for a regular app it waits until the app is active, but for a background app it
shows the alert right away, ordered behind other apps — and within a few seconds
of updater start it will even activate the app. Nothing consulted whether
another application currently owned the screen, so the alert could be shown on
top of (or steal focus from) a full-screen game. The app had no full-screen
awareness on the update path; only the status panel had Space handling
(issue #48 / #183).

## Fix

- `Sources/StatusTrioCore/App/FullScreenActivity.swift`
  - `FullScreenActivity.isActive(windows:displayBounds:ownPID:frontmostPID:)`:
    a pure classifier — a layer-0 window owned by the front-most application
    (and not our own process, not a system overlay, not transparent) whose
    bounds match an entire display counts as a full-screen app.
  - `FullScreenActivity.isActive()`: live probe. It reads only window
    geometry/owner/layer from the window server (no Screen Recording
    permission, no pixels) and compares window bounds against
    `CGGetActiveDisplayList` bounds so both use the same global coordinate
    space.
  - Requiring the covering window to belong to the front-most app avoids
    treating a background maximized window as full screen and avoids
    suppressing reminders while the user actively works on another display.
- `Sources/StatusTrioCore/App/FullScreenActivityMonitor.swift`
  - Observes `NSWorkspace.activeSpaceDidChange`, `didActivateApplication` and
    `NSApplication.didChangeScreenParameters`, then fires one debounced
    re-probe (no timer loop, so the app stays at rest). It reports only the
    full-screen → windowed transition.
- `Sources/StatusTrioCore/App/UpdaterManager.swift`
  - Implements `updater(_:mayPerform:)`. A **scheduled background** check is
    postponed while a full-screen app owns the screen; a user-initiated check
    (the user asked for it) is never postponed.
  - Throwing aborts the check before Sparkle fetches the appcast or shows any
    window. Sparkle suppresses updater errors raised before an update was
    presented, so the deferral is silent. The custom error domain is not in
    `UpdateSourceRetryPolicy`'s retry allowlist, so it does not advance the
    Gitee/proxy mirror chain.
  - When the monitor reports the full-screen session ended, the postponed check
    is re-run with `checkForUpdatesInBackground()` (guarded by
    `automaticallyChecksForUpdates` and `canCheckForUpdates`), so the reminder
    appears normally once the game is closed rather than waiting a full
    scheduled interval.

## Tests

- `Tests/StatusTrioCoreTests/FullScreenActivityTests.swift`: whole-display
  coverage, maximized-window false positive, own process, system overlay owners,
  non-zero layer / transparent windows, secondary display, partial coverage,
  no displays, and the front-most-app filter.
- `Tests/StatusTrioCoreTests/FullScreenActivityMonitorTests.swift`: initial
  state seeding and the true→false / false→true transition callback semantics.
- `Tests/StatusTrioCoreTests/UpdaterManagerFullScreenTests.swift`: only
  `.updatesInBackground` is deferred while full screen is active; `.updates`
  (user-initiated) is not.

## Not run / residual risk

- The live Sparkle alert over a real full-screen Space and the automatic
  re-check when the Space ends are `NOT RUN` locally because the updater never
  starts in Debug/dev-codename builds. Verify on a release candidate build.
- The window heuristic can be wrong in edge cases (auto-hidden menu bar plus a
  maximized foreground window). The front-most-app filter keeps the common case
  correct; it is a heuristic, not a public "this app is full screen" API.
