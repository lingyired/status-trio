# BetterDisplay external-display volume integration

This document covers the user-facing setup and the evidence boundary for the
per-output BetterDisplay volume backend. It does not instruct Status Trio to
launch BetterDisplay or change BetterDisplay settings or preferences.
Native writable Core Audio always takes precedence; BetterDisplay is only the
fallback for outputs without native macOS volume control.

## Setup

1. Connect the external display and make its audio output the current macOS
   output device.
2. Open Status Trio Settings > Audio > External Display Volume.
3. If the output has no native writable macOS volume control, choose
   `BetterDisplay` under Control Method.
4. Discovery starts automatically. Status Trio links the current audio output
   when its EDID identity and framebuffer registry path uniquely identify a
   BetterDisplay display. In this case there is no `Linked Display` picker.
   When an exact association is unavailable or ambiguous, select the matching
   display manually under `Linked Display`. The manual picker is hidden until
   discovery finishes, so setup does not flash an empty picker.
   Status Trio then checks its reported volume automatically.
   `Connected. Volume control is available.` appears only after a valid volume
   read for this output and display. No manual refresh is needed for setup.
   The picker stores the full display UUID, not its friendly label.
5. If BetterDisplay is not running or is unresponsive, open or restart it and
   choose `Detect Again`. A hint at the bottom explains the required integration
   settings. Explicit detection permits one bounded discovery
   attempt without launching the app.
6. Use the status-panel volume and mute controls. They remain bound to the
   current audio output and its saved BetterDisplay display UUID.

Selecting `BetterDisplay` without a display UUID is valid. The preference stays
selected while the catalog is discovered. Status Trio uses only the unique
EDID-to-registry-path mapping for automatic association; it never guesses from
names, model, serial, display ID, tag ID or enumeration order.
Existing saved UUIDs are preserved. Direct DDC is suspended until a
display UUID is associated. The current audio output is shown above the controls,
and its configuration follows it when outputs change.

With native writable volume control, the settings show that macOS is already
controlling the output. BetterDisplay connection controls are hidden and no
BetterDisplay discovery starts. In Standard mode, all BetterDisplay connection
controls and help are hidden.

## Return to existing behavior

Choose `Standard (Default)` in the same group. This stores the direct-DDC
default configuration for the current audio-output UID and clears the
BetterDisplay display association.

## Status messages

The UI keeps actionable failure reasons distinct:

- `BetterDisplay is not running`: open it, then refresh.
- `BetterDisplay is not responding`: restart it, then refresh.
- `BetterDisplay returned an invalid response`: refresh and retry.
- `BetterDisplay could not complete the request`: retry.
- `Choose a BetterDisplay display`: the backend is selected but unassociated.
- A volume-change confirmation failure with a `Detect Again` recovery action: the
  reported readback did not match the requested value.

The same distinctions are present in all twelve shipped localizations.

## Requirements

- BetterDisplay with CLI access enabled.
- BetterDisplay notification-based integration enabled.
- A current audio output with a stable, non-empty Core Audio UID.
- An explicit display UUID for associated volume and mute operations.

Status Trio does not change BetterDisplay settings, does not launch BetterDisplay,
and does not write BetterDisplay preferences.

## Runtime ownership

The direct-DDC default starts no BetterDisplay notification observer, catalog
request, process, or reconciliation timer. When BetterDisplay is explicitly
selected and associated, one notification client owns the request/response
traffic. Reconciliation is bounded to 2 seconds while audio details are visible
and 10 seconds while hidden, and stops during sleep, topology invalidation,
backend changes, app termination, or status-monitor shutdown.
Framebuffer identity is read on a utility task only when a BetterDisplay
catalog request succeeds. It adds no observer or polling timer. The association
is persisted by the status store, so it also works with Settings closed.

## Verification evidence

### Automatic setup flow, October 29, 2026

The final product-flow tree passed `bash scripts/verify-local.sh full` on
macOS 27.2 with Xcode 27 / Swift 6.4 / SDK 27:

- 2118 core XCTest cases, zero failures, 8 existing skips.
- 15 Helper XCTest cases, zero failures.
- 787 Swift Testing cases in 115 suites, zero failures.
- Release build, non-Universal local ad-hoc bundle, platform/dependency/Helper
  contracts, and offline release simulations.

The branch and base were both
`d3b7ac241533afda385a1bf95e4df43778a81ce6`; verification includes the
uncommitted worktree changes, not just that base commit. The preserved log is
`.build/local-verification/issue115-product-full-20261029.log`.

New regressions cover automatic unbound discovery, choosing a display without
manual refresh or volume writes, cached reselection updating the settings
status, connection readiness waiting for valid readback, snapshot/output
identity mismatch, unknown versus confirmed missing displays, duplicate
friendly names, native priority, and re-enabling after a connection timeout.
Discovery enumerates the catalog without a UUID filter so another display
remains selectable after relaunch; actual volume/mute requests still target
only the chosen UUID. Optimistic volume and mute updates preserve the actual
control source for native, BetterDisplay and direct DDC.

The readiness, unbound discovery, cached reselection, retry, catalog selection,
and optimistic-source regressions were observed failing before their fixes.
No assertions were weakened or skipped to obtain this result.

This is local automated evidence. Physical audio changes, real multi-display
targeting, macOS 13 runtime and comparative CPU/memory measurements remain
separate acceptance items.

The final development bundle was built and launched with
`bash scripts/build-worktree.sh release open`. Its bundle ID is
`com.lingsmbp.StatusTrio.dev.issue-115-betterdisplay-volume` and embedded
codename is `Issue 115 Betterdisplay Volume`. The main executable SHA-256 is
`e440acfd1d71716032e34c5a25cff0875fdc52ae110b446da838dc8fe693310b`.
The final fetch still matched the branch base to `origin/main`.

Final native click-through: **BLOCKED** because the Mac was locked when the
UI automation attempted to inspect the relaunched app. The tool reported that
automatic unlock was unavailable; no further unlock or bypass was attempted.
The development process was confirmed running and its existing
XV272U UUID association was preserved; the production process remained running
from `/Applications/Status Trio.app`. The real-window layout regression passed
in the automated suite, but the earlier layout-only manual check below does
not establish that the final automatic setup flow has been manually exercised.
No volume or mute writes were sent during this final runtime check.

### Earlier focused integration checks

Focused local verification:

```text
bash scripts/test.sh 'BetterDisplay|VolumeMonitor|DDCVolume|SettingsStoreTests|VolumeDetailsDemand|AudioPanelMapper|MacOS13UICompatibility|Localization|PopupVolumeScroll'
```

Result: PASS on October 28, 2026. 355 filtered XCTest cases passed with zero
failures; 17 Swift Testing cases in 2 suites also passed. The forbidden-pattern
preflight passed.

The focused suite covers UUID selection and normalization, unassociated
BetterDisplay persistence, distinct availability copy, explicit user slider
ownership, stale identity/capability invalidation, unknown-mute gating, mapper
identity propagation, overlapping volume/mute readback confirmation, stale
queued writes across topology and selection changes, scroll-target identity and
mute-state changes, the zero-request direct-DDC default, and all twelve
localized string sets.

The focused result above is task-scope evidence only. The whole-repository log
for the layout fix is preserved in
`.build/local-verification/issue115-layout-full-20261029.log`; the delivery
report distinguishes the full local profile from runtime checks.

### Audio settings layout regression

Refreshing the catalog used to size the display picker to its longest option,
including the full UUID. At the settings pane's 530-point width, the picker grew
from 86.5 to 383 points and squeezed the description into a narrow column. The
page grew from 851 to 1483 points, causing the apparent blank/clipped layout.
The closed picker now has a bounded width and truncates long labels; menu
options show friendly names and use a short UUID suffix to distinguish duplicate
names. The full selected UUID remains available as a tooltip.

`BetterDisplaySettingsLayoutTests` hosts the real audio pane in an AppKit
window and exercises catalog refresh, selecting a display, long display names,
and an unavailable saved display. Its height regression failed before the fix
and passes with the bounded picker. The focused layout, settings-view,
BetterDisplay UI, and pinned-header run passed 29 XCTest cases on October 29,
2026:

```text
bash scripts/test.sh 'BetterDisplaySettingsLayoutTests|BetterDisplayVolumeUITests|SettingsPagePinningTests|SettingsViewTests'
```

The full local profile also passed on October 29, 2026: 2111 core XCTest cases
(8 existing skips), 15 Helper XCTest cases, and 781 Swift Testing cases, plus
the Release build, app-bundle contracts, and offline release simulations.

Native UI check: **PASS** on macOS 27.2 using the worktree development bundle
`com.lingsmbp.StatusTrio.dev.issue-115-betterdisplay-volume`, built with
`bash scripts/build-worktree.sh release open`. Three refreshes, including one
with XV272U selected, kept the settings card and output list visible. The menu
still exposed complete UUIDs, and switching away from Audio and back preserved
the layout. The original unassociated selection was restored afterward. This
check did not send volume or mute writes.

## Result boundary

BetterDisplay readback confirms the value BetterDisplay reports. It is not
independent proof of the physical DDC value, the display OSD, or audible
output. Native writable Core Audio wins and bypasses BetterDisplay, so the
fallback setup affects only outputs without native macOS volume control.

The following remain **NOT RUN** for this task:

- Sending a real BetterDisplay volume or mute set.
- Hearing an audible change or visually checking the display OSD.
- Sleep, reconnect, dual-display, or VDD hardware validation.
- macOS 13 Ventura runtime and full current-macOS acceptance beyond the audio
  settings layout check above.
- CPU and memory measurements.
