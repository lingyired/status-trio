# Dock activation routing

The live Dock tile routes reopen events using the persistent
`SettingsStore.appIconPlacement.showsDockIcon` preference. Pointer position is
used only by the existing popover anchor geometry.

## Confirmed causes and remaining uncertainty

The old resolver opened Settings whenever the pointer was outside an inferred
Dock strip. Its regression test reproduces that wrong decision without a real
Dock process. The old delegate also used `isRegularApp`, which includes the
temporary Dock tile owned by Settings, instead of the user's placement choice.

A separate native-window regression reproduces an application-owned focus
path: with an existing Settings window, opening the status panel can publish
the first Bluetooth authorization read. The permission observer calls
`resurface()` and brings Settings forward. Resurfacing now yields while the
status panel is visible. The existing permission-dialog recovery still works
when the panel is closed; closed Settings windows are never recreated by it.

The status bar then forced `NSApp.activate(ignoringOtherApps:)` even on the Dock
path. A real Dock tile click has already activated the app before delivering
reopen, so this redundant request could restore the ordinary Settings window
ahead of the transient popover. Dock-origin presentation now skips that call;
menu-bar and shortcut presentation still force activation. `DockActivation`
logs record whether activation was forced or skipped, alongside explicit
`Settings.show` / `Settings.resurface`, a Settings key-window notification, and
the later popover close. No timer, poll, window hiding, or repeated ordering
workaround is added.

## Decision table

Only an explicit `aevt/rapp` event is routed:

| Resolved sender | Dock Only / Both | Menu Bar Only |
| --- | --- | --- |
| Dock (`com.apple.dock`) | Toggle status popover | Show Settings |
| Finder (`com.apple.finder`) | Show Settings | Show Settings |
| Spotlight (`com.apple.Spotlight`) | Show Settings | Show Settings |
| Apps launcher (`com.apple.apps.launcher`) | Show Settings | Show Settings |
| Other Bundle ID | Toggle status popover | Show Settings |
| Unknown / missing PID or Bundle ID | Toggle status popover | Show Settings |
| Explicit non-reopen event | None | None |
| Missing current event, including a delegate call without a descriptor | None | None |

The missing-event case retains the old conservative behavior. A delegate
callback alone is not promoted to a reopen: cold/login launch must not open a
status panel accidentally. Real callback observations must be reported
separately from synthetic nil-descriptor tests.

Launchpad or a launcher that sends as Dock is indistinguishable from a tile
click. The live Dock tile takes priority. Additional launchers require verified,
exact Bundle IDs; arbitrary or prefixed names are not treated as settings
entrypoints.

## Sender metadata

`AppleEventSenderResolver.currentActivation()` reads the manager synchronously
in `applicationShouldHandleReopen`. It accepts `keySenderPIDAttr` as an
exactly four-byte `typeSInt32` or `typeUInt32` integer that fits a positive
`pid_t`, copies its bytes into aligned storage, and resolves the running
application's Bundle ID. An exited process,
missing identity, wrong type, or wrong length degrades to Unknown.

Native Finder verification on macOS 27.0.1 exposed an SDK/runtime difference:
the SDK annotates `keySenderPIDAttr` as `typeSInt32` (`long`), but the actual
received attribute was `typeUInt32` (`magn`), length four, containing the
running Finder PID. The initial signed-only implementation rejected it and
routed Finder as Unknown. A regression reproduces the resulting wrong
Popover route; both explicit integer types are now supported, with zero,
negative and unsigned values above `Int32.max` rejected before process lookup.
This is observed sender metadata, not a target-address or pointer heuristic.

`keySenderPIDAttr` is read-only: setting it on a synthetic event silently leaves
it absent. Tests inject the descriptor reader and process identity lookup,
then exercise the production validation and routing. They do not depend on a
running Dock process or claim live sender availability.

`keyAddressAttr` is not used as a fallback: the public Apple Event creation API
defines it from the target address. A valid PID descriptor there does not by
itself establish the sender. See the SDK's `AEDataModel.h` (`keySenderPIDAttr`,
`AECreateAppleEvent`) and `AEMach.h`. The parsing approach was compared with
[Lunar's AppDelegate](https://github.com/alin23/Lunar/blob/master/Lunar/AppDelegate.swift);
its routing, process-path lookup, coercion, and unaligned load are not copied.

Finder, Dock, Spotlight and Apps identities were checked against the installed
system bundles on the macOS 27 test host. Sender metadata remains evidence of a
process, not proof of a particular click or user intent.

## Changed files

| File | Change |
| --- | --- |
| `Sources/StatusTrioCore/App/AppleEventSenderResolver.swift` | Synchronous event snapshot, validated sender PID and exact Bundle ID classification |
| `Sources/StatusTrioCore/App/DockActivationAction.swift` | Pure routing by reopen, sender and persistent Dock preference |
| `Sources/StatusTrioCore/App/AppDelegate.swift` | Resolve and log synchronously, route once, keep mouse location only for anchoring |
| `Sources/StatusTrioCore/App/DockActivationLog.swift` | Shared event-driven `DockActivation` logger |
| `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift` | Yield permission resurfacing to an active status panel; log explicit and native activation |
| `Sources/StatusTrioCore/UI/StatusBarController.swift` | Skip redundant app activation for Dock-triggered presentation; retain it for menu-bar/shortcut; log presentation state and close |
| `Tests/StatusTrioCoreTests/AppleEventSenderResolverTests.swift` | Valid, absent, malformed and non-reopen metadata tests |
| `Tests/StatusTrioCoreTests/DockActivationActionTests.swift` | Sender/placement matrix, non-reopen and temporary-regular regression |
| `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift` | Existing Settings cannot resurface over a status-panel permission refresh |
| `Tests/StatusTrioCoreTests/StatusBarMemoryPressureTests.swift` | Dock presentation skips activation while shortcut presentation retains it |
| `docs/dock-activation-routing.md` | Rationale, limitations, verification evidence and tester handoff |

No renderer, icon scene, cache, Dock anchor geometry, activation-policy
implementation, user preference schema, entitlement, or permission is changed.

## Isolated build and feedback checklist

Build from the `codex/dock-activation-routing-fix` worktree:

```bash
bash scripts/build-worktree.sh release no-open
open dist/StatusTrio.app
```

The development Bundle ID is
`com.lingsmbp.StatusTrio.dev.dock-activation-routing-fix`; the displayed name is
`Status Trio (Dock Activation Routing Fix)`. This is an ad hoc local build,
not a notarized, Universal, or published release.

1. In the development app, choose Dock Only or Both. Close Settings and click
   the development Dock tile five times, allowing each toggle to finish.
2. Open Settings, then put another app in front. Click the development tile;
   verify the panel appears, retains focus, and Settings is not the only UI.
3. Repeat with Settings already in front, then with Settings closed. Test
   Finder opening this exact development bundle while it is running.
4. Test Spotlight/Apps only if their result identifies this development build.
   Record launch source, placement, window state, Dock orientation/autohide,
   display configuration, macOS version, and expected/actual result.
5. If it fails, collect only this build's event logs using the command below.
   Include the reopen line and adjacent Settings/Popover lines.

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.lingsmbp.StatusTrio" AND category == "DockActivation" AND process == "StatusTrio"'
```

The subsystem is shared with other local copies. For parallel instances,
replace the final predicate with `processIdentifier == PID`, using the
development process's PID. Logs contain event IDs, sender identity/PID,
placement, actual activation policy, visible-window diagnostics, Settings
window state, and selected action; they do not contain user paths or telemetry.

## Verification record (2026-10-22)

Base: `0474ae45865e3aefa15af29261e47bac98e329ad` from `origin/main`.
The implementation changes were uncommitted throughout verification.

The baseline targeted run passed 12 XCTest and 21 Swift Testing cases.
Both root-cause regression tests failed against the original implementation.
The expanded targeted run passed 21 XCTest and 29 Swift Testing cases.

The first `full` attempt passed 1,898 XCTest cases (7 existing skips), 748 Swift
Testing cases, and the Release build. Bundle creation then failed when the
OpenSSL partial clone lost its connection (`RPC failed`, `early EOF`).
The local dependency cache was copied into this worktree only after checking
all six clean source checkouts against the manifest pins and matching the
manifest/SDK/clang build key. The incomplete download was preserved separately.
No dependency check or build step was bypassed. Final complete-profile and
native runtime results:

- `bash scripts/verify-local.sh full`: PASS, including 1,898 XCTest cases
  (7 existing skips), 750 Swift Testing cases, Release build, local bundle,
  native contracts, and offline workflow/release simulations.
- Focused verification for the activation split: PASS, 17 XCTest and 12 Swift
  Testing cases. The final `full` run passed after that change as well.
- `bash scripts/build-worktree.sh release no-open`: PASS. Verified the branch
  Bundle ID/display name, ad hoc signature, arm64 slice, minimum macOS 13.0,
  SDK 27.0, and both bundled Helpers. The app was not launched.
- `git diff --check`: PASS. Xcode 27.0 / Swift 6.4 / SDK 27.0. No new Swift
  warnings in the changed files; the existing `LowPowerModeClient` Sendable
  capture and `MemoryPressureMonitor` unnecessary isolation warnings were also
  present in baseline compilation. The existing weak-variable test warning is
  unrelated.
- `origin/main` was fetched again before commit and advanced from this branch
  base to `40685c4dcbcd929324367470e6f0838aa1e1b122`; no changed file overlaps
  this branch's 11 files. The commit remains based on the recorded base and is
  not merged with that advance. The four unrelated dirty files in the primary
  checkout were preserved.
- Read-only senior review: no Critical or Important static findings. A direct
  delegate-dispatch integration test remains a coverage gap; the resolver,
  route matrix and native Settings regression are covered separately. No
  unverified legacy Launchpad Bundle ID was added.

Evidence is preserved under `.build/dock-activation-routing-verification/`,
including the failing original regressions, successful focused/full logs,
the initial dependency-download failure, the development build log, and a
`record.json` with source-file and built-binary digests.

The rebuilt development app was launched on macOS 27.0.1. A real Finder reopen
of the running development bundle produced
`sender=com.apple.finder senderPID=55710 placement=dock action=Settings`.
The first raw event inspection found `keySenderPIDAttr` as four-byte
`typeUInt32` (`magn`), while the initial implementation accepted only
`typeSInt32`; the signed-only regression failed and was corrected. A second
Finder reopen logged `settingsExists=true settingsVisible=true
settingsKey=true action=Settings` and `Settings.show existing=true`, then kept
the same key window. Both Dock and Both placements selected Settings.

The automated GUI service triggered reopen callbacks with sender
`com.openai.sky.CUAService`. In Dock placement they opened a key popover; in
Menu Bar Only placement they opened Settings. That unknown-sender routing is
useful diagnostic evidence, but it is not a real menu bar icon click and is not
claimed as one. After temporarily selecting Menu Bar Only, the persistent
preference read back `menuBar`, and the temporary Dock tile disappeared while
the menu bar icon remained. The settings window's custom close control did not
accept the Computer Use accessibility click, so it was closed by quitting the
development app; that control was not used as routing evidence.

Computer Use could not attach to the windowless system Dock by Bundle ID or
name (two `-10005` timeouts), so the maintainer performed the live tile clicks.
Across development PIDs `49653` and `69399`, there were 23 real reopen
callbacks from `com.apple.dock`, all from Dock PID `51518`: every one selected
`action=Popover` and none selected Settings. Twenty-two were in Both placement
and one in Dock placement. A separate real Finder reopen selected Settings and
reused the existing window, so the replacement sender classifier passed both
the Dock and Finder paths.

An isolated live test with Settings already frontmost produced
`sender=com.apple.dock ... action=Popover` and immediately logged
`Popover presented shown=true key=true`. It then logged
`Settings became key popoverVisible=true` about 2.3 seconds later and
`Popover closed` 0.3 seconds after that. With Settings deliberately behind
Finder, the same routing and immediate `shown=true key=true` occurred; Settings
became key about 9.2 seconds later and the popover closed about 0.6 seconds
after that. Neither transition logged an application `Settings.show` or
`Settings.resurface` call. The first was also associated with a visible request
to inspect the app in Computer Use, so it is not counted as a clean
no-interaction result. The second is a real residual focus-reclaim defect.

The earlier PID `34553` run established the remaining focus behavior: the
popover initially became key, but an existing Settings window later reclaimed
key without an application `Settings.show` or `Settings.resurface` call. The
permission-refresh regression now covers the identified application-owned
path, and the Dock presentation no longer invokes the redundant application
activation. This is an event-driven fix; there is no delayed refronting.

The final physical-Dock rerun used development PID `97358` and binary SHA-256
`58710252250b0896de3de3437b45827622678458b693fb7a895d477b279495b7`.
At `23:54:47`, Settings was closed and a
`com.apple.dock` reopen selected `action=Popover`; the popover became key with
no follow-up Settings activation. At `23:54:54`, Settings was opened from the
popover and then another app was brought forward. At `23:54:56`, a second
physical Dock reopen logged
`sender=com.apple.dock settingsExists=true settingsVisible=true settingsKey=true
action=Popover`. Settings resigned key 33 ms later, the popover became key, and
it retained key until a deliberate user click at `23:56:01`
(`pressedMouseButtons=1`). No application `Settings.show` or
`Settings.resurface` occurred after the reopen.

Across all development builds, 44 real `com.apple.dock` reopen callbacks from
Dock PID `51518` selected `action=Popover`; none selected Settings. Twenty-one
of those callbacks came from the activation-skip builds. This includes the
Settings-present and Settings-key cases above. The final focused run passed 17
XCTest and 12 Swift Testing cases. The final complete local profile passed
1,900 XCTest cases (7 existing skips), 750 Swift Testing cases, the Release
build, the local app bundle, native contracts, and offline workflow/release
simulations.

The final rebuilt development binary is SHA-256
`0f7c60d5cd72fbd2d416af7c8d96b0999f19e18c2ffd568fae0baf734da96594`.
Its only change from the physically tested binary is marking the existing
`applicationActivation=forced|skipped` value public in the diagnostic log; the
routing and focus code are identical.

One explicit `Settings.show existing=false` appeared at `22:00:42.800` while
the user was testing. The user believes it was their own click on the panel's
Settings button, and its timing matches that action. It had no preceding
reopen callback, so it is not counted as a Dock routing pass. A real menu bar
icon click later opened the status panel without a reopen callback, as expected.
Spotlight, Apps launcher, login-item launch, left/right Dock, external display,
and macOS 26 remain NOT RUN. A relaunch after onboarding did not show onboarding
again or open a window by itself; that is cold-launch continuity evidence, not a
login-item test. The current system Dock is bottom-aligned with autohide
enabled; those preferences were only read and were not changed.

| Runtime scenario | macOS 27.0.1 | macOS 26 |
| --- | --- | --- |
| Bottom Dock tile, Settings closed | PASS (44/44 real callbacks selected Popover) | NOT RUN |
| Settings behind another app | PASS (real Dock reopen replaced Settings with a key popover; no automatic reclaim for 65 seconds) | NOT RUN |
| Settings already in front | PASS at the delegate boundary (`settingsKey=true`, `action=Popover`; final key window was the popover) | NOT RUN |
| Repeated tile toggle | PASS (44 real callbacks, all Popover) | NOT RUN |
| Finder opens running development build | PASS | NOT RUN |
| Finder reopen reuses Settings | PASS | NOT RUN |
| Menu bar icon opens status popover | PASS (user click; outside the reopen logger) | NOT RUN |
| Unknown sender follows persistent placement | PASS (automation sender) | NOT RUN |
| Menu Bar Only hides temporary Dock tile | PASS (on close) | NOT RUN |
| Actual sender PID / Bundle ID | PASS (`com.apple.finder`, PID `55710`) | NOT RUN |
| Spotlight / Apps | NOT RUN | NOT RUN |
| Relaunch after onboarding, no new onboarding | PASS | NOT RUN |
| Login-item launch | NOT RUN | NOT RUN |
| Left / right Dock | NOT RUN | NOT RUN |
| Auto-hidden Dock | NOT RUN (GUI tool cannot attach to Dock) | NOT RUN |
| External display / switching displays | NOT RUN | NOT RUN |

Ventura runtime, signing/notarization, Universal packaging, privileged Helper
runtime, release CI, and publication are outside this local verification.
The requested Dock routing and Settings-focus acceptance is PASS on macOS 27.
The remaining NOT RUN matrix items above still require separate verification.
