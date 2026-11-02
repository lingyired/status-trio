# Background Computer Use testing

## Scope and current decision

The reusable procedure is
[`background-ui-testing`](../.agents/skills/background-ui-testing/SKILL.md).
Its non-interference contract applies to every agent and harness. This document
is Status Trio's project adapter: Debug launch flags, supported presentation,
verified controls, provider support, diagnostics, and rollback. The reusable
skill neither requires nor authorizes installing a provider; it supplies the
capability gate this project applies to every provider.

Functional and background acceptance are separate. A manual menu-bar/Dock
click that opens an activating popover can pass functional acceptance while
failing a non-activation criterion. A recording that expires before an action
does not cover it; inspect action timestamps before citing zero activations.
No skill or instruction file enforces behavior in a harness that did not
actually load it.

This is an opt-in **Debug Settings and first-run guide mode**, first tested with
Codex native Computer Use. It is not a separate input session. Spaces, displays
and applications still share foreground and keyboard focus.

The Phase 1 feasibility gate passed on October 31, 2026: the throwaway
accessory-window probe supported setting changes, sidebar navigation and
window screenshots in five consecutive rounds, without an observed foreground
transition. This justified implementing the injected configuration and optional
display placement. A later integrated test connected a secondary display and
passed the first-run guide gate: native attachment, Next, Back, a verified
preview control, screenshot capture and the transition to Settings all operated
without the target app becoming active. The rest of the runtime acceptance
matrix remains incomplete.

No claim here extends the successful AX button interactions to text input,
coordinate clicks, menus, permission dialogs, shortcut recording or every
SwiftUI control. Those steps must stop if they require activation.

Two specific Settings controls remain foreground-only: enabling Bluetooth's
"Show in status panel" on the Bluetooth page, and enabling Bluetooth in the
status-panel page's section visibility list. Their existing bindings explicitly
call `NSApp.activate`, even with authorization already granted. **Do not click
these controls during a background test.** Leave their actual tests `NOT RUN`
or run them in an explicitly foreground session. This change does not broaden
the permission behavior to make them appear supported.

## Computer Use provider support

The project accepts any Computer Use provider that passes the background
capability gate in
[harness-adapters.md](../.agents/skills/background-ui-testing/references/harness-adapters.md);
Codex native Computer Use is not the only permitted provider. First-class
providers are Codex native Computer Use, `kimi-cu` MCP, and `agent-desktop`.
Any other instance-scoped AX/DOM/window provider is allowed under the same gate.
Foreground/global keyboard or pointer input is never allowed, whether it comes
from a provider, `osascript`/System Events, `CGEventPost`, `cliclick`, or a
per-pixel pointer loop.

Selection order:

1. A CU tool explicitly named in the project `AGENTS.md` or the user-level
   `AGENTS.md` / harness instruction file (for example, a user rule that
   prefers `kimi-cu` MCP), when the current session actually exposes it.
2. Otherwise, any available provider that passes the per-run capability record
   (target selection, launch/attach, observation, input, interference trace,
   lifecycle) without a foreground transition.
3. If no provider is available, report the affected steps as
   `BLOCKED (no Computer Use provider)`, name the providers checked, and say
   what connecting one would unlock. A provider that is installed but not
   connected to the current harness counts as unavailable.

| Provider | Exposed as | Status on this project |
| --- | --- | --- |
| Codex native Computer Use | native CU service exposed to Codex | Phase 1 gate and first-run guide gate passed (see below) |
| `kimi-cu` MCP | MCP server (Apple-silicon app at `/Applications/KimiCU.app`) | capability gate required; not yet verified here |
| `agent-desktop` | CLI (global npm, e.g. `agent-desktop@1.0.2`) | installed on this host; default is AX press / headless, `--headed` permits physical input; capability gate required, not yet verified here |

An unverified provider reaches `PASS` only for actions actually exercised under
this gate; unexercised click, menu, text-input or permission actions stay
`NOT RUN` with the reason recorded. Do not claim another provider inherits
Codex's results.

## Launch and fallback

From the isolated development branch/worktree:

```bash
bash scripts/launch-computer-use.sh
bash scripts/launch-computer-use.sh --display secondary
```

The script always builds with `bash scripts/build-worktree.sh debug no-open`.
It validates the branch-specific Bundle ID, executable, development codename,
Debug capability marker and source HEAD. The final JSON reports path, PID,
source SHA, whether the source tree was dirty, and requested/connected displays.
A dirty build is **HEAD plus local changes**, not a clean build of that SHA.
The executable digest is printed separately.

The script checks instances before building. It can gracefully terminate only
a process with this exact Bundle ID, bundle/executable path and
`--background-ui-testing` argument. A non-test instance, another checkout using
the same ID, a failed graceful exit or a new instance appearing during the build
stops the launcher. It does not use `pkill`, `open -n` or attempt to append
arguments to a running app.

A per-worktree directory lock covers preflight, build and launch, preventing
two instances of this launcher from assembling the same bundle concurrently.
A unique process argument is checked after launch so another process cannot
be mistaken for the requested launch. LaunchServices is not an atomic
compare-and-start API: a manual launch or a different build command racing
this script remains outside its lock. Serialize such commands; the token
detects misidentification but cannot retract an already delivered reopen.

The app receives immutable launch configuration from `AppEnvironment.live()`:

- `--background-ui-testing` opts in only when compiled with `DEBUG`.
- `--test-display=secondary` requires that opt-in. With no secondary display,
  presentation falls back to the physical main display.
- Malformed or duplicate reserved arguments disable the mode and produce
  Debug diagnostics in the existing `DockActivation` log category. Other
  arguments are left alone. Release ignores both testing flags.

Background startup preserves the normal first-run guide policy. If the guide is
due, it stays on the same first-run path and renders without requesting
temporary regular policy, setting the key window, forcing ordering or
activating the app. If no guide is due, startup opens Settings through the same
background presentation. Choosing "Customize" (`调整外观…`) closes the guide and
opens the already verified background Settings window. A native Computer Use
reopen received while the guide is visible is ignored so attachment cannot
open a second Settings window over it. Settings also uses `orderFront(nil)` and
does not resurface after permission recovery. A persistent Dock preference
still owns its normal policy.

Window visibility, preview ownership, tab notifications, shortcut cleanup and
close/recreate semantics use the existing controller. Background windows do not
set a frame autosave name, so normal `SettingsWindow.Sidebar.v1` is preserved.
Positioning uses `CGMainDisplayID`, screen display IDs and `visibleFrame`; it
re-evaluates on each presentation. No display observer, timer, permission,
floating panel or private API was added to the app.

To return to normal behavior, quit this test instance and launch the dev app
without flags. To rebuild the usual development bundle:

```bash
bash scripts/build-worktree.sh debug open
```

Normal Settings presentation retains temporary regular mode,
`makeKeyAndOrderFront`, `orderFrontRegardless` and `NSApp.activate`.
Normal onboarding, permission recovery, status-panel and Dock routes are
preserved. The one Debug exception is a reopen from the observed exact native
service ID `com.openai.sky.CUAService`: background mode routes it to Settings
for every placement, avoiding a key popover when Dock/Both is selected.
Physical Dock events, unknown senders, similarly prefixed service IDs and all
Release/normal-mode events retain the existing route. A future native service
identity must be observed and retested before assuming the same support.
Do not use activate-then-restore as a background workaround.

## Phase 0: baseline and attribution

Source base: `98fc8a10879ca9ed4244626e8b44682d7b54a7bc`, fetched from
`origin/main` before creating `codex/background-computer-use-testing`.
Worktree:
`/Users/lingsmbp/.codex/worktrees/background-computer-use-testing/status-trio`.

Host: macOS 27.2 (`26B123`), Xcode 27.0 (`27A266a`), SDK 27.0,
Codex app `26.1021.31345`, CLI `0.166.0`. One display, ID `1`,
1728 x 1117 points, scale 2, visible frame `{{0, 0}, {1728, 1084}}`.
The actual foreground app during the unlocked experiment was BlueStacks,
Bundle ID `com.now.gg.BlueStacks`, PID `81860`; browser/IDE foreground trials
were not run. No other running Status Trio instance was terminated.

The isolated dev preferences set `hasCompletedIconGuideOnboarding.v1=true`
before the baseline to exclude onboarding activation. Placement was Menu Bar
Only. Production preferences and permission state were not reset.

| Trigger / component | Observed evidence | Foreground result / status |
| --- | --- | --- |
| Cold `open -g`, normal dev build | PID `83200`, accessory policy, no Settings window during approximately the first 18 seconds | 0 observed switches before Computer Use; PASS for launch only |
| First native `cua.getApp(appPath)` | Native service sent a reopen from `com.openai.sky.CUAService`, PID `3798`; Menu Bar Only routed to `Settings.show existing=false` | 1 observed switch to PID `83200`; FAIL for background use, expected normal behavior |
| Normal Settings show | Regular policy and key-window/active-app logs followed the reopen | Combined activation path reproduced; individual calls are not uniquely attributed |
| Temporary regular policy alone | Probe avoided it and remained accessory | Isolated transition NOT RUN; no claim that it alone activates |
| `makeKeyAndOrderFront` / `orderFrontRegardless` / `NSApp.activate` individually | Existing call sequence confirmed in source; probe removed the group | Individual A/B attribution NOT RUN |
| Settings Bluetooth permission recovery | Source calls `resurface` after undetermined permission changes, unless popover is visible | Real system decision NOT RUN; unit regressions cover recovery/suppression |
| Menu-bar/shortcut status panel | Source explicitly activates and makes its popover key | Physical interaction NOT RUN; retained foreground path |
| Dock reopen | Source routes by sender and persistent placement; Dock path skips redundant activation | Physical Dock click NOT RUN; native service reopen is not a Dock click |
| First-run icon guide | Source requests regular policy, key window and activation | Excluded from the original baseline; later injected background presentation verified separately below |

The actual native reopen is an additional trigger, not evidence that the
Computer Use service itself necessarily activates the app independently of its
reopen handler. Removing the Settings activation group allowed the same native
attachment to remain in the background.

## Phase 1: feasibility evidence

The small, discarded probe changed only Debug Settings presentation: skip the
regular request, use `orderFront`, suppress permission resurfacing and disable
frame autosave. It did not change AppDelegate, the Dock resolver or popovers.
Its patch is retained in the ignored evidence directory, and was reversed
before implementing the injected configuration.

Probe PID `85789`, binary SHA-256:
`cdf5e4ecc639acb759d97ef107540cdbfb9be57830eff3deb1a4e9b569dc933d`.

| Operation | Successful repetitions | Focus evidence | Result |
| --- | --- | --- | --- |
| Native attachment creates an accessory Settings window | 1/1 | Foreground stays PID `81860` | PASS |
| Sidebar to General and back to App Icon | 5/5 | Foreground stays PID `81860` | PASS |
| Ring thickness Normal/Thin selection actually changes | 5/5 | Selected state verified after each click; ends at Normal | PASS |
| Window screenshots | 10/10 across 5 rounds | Valid images, approximately 156-190 KB, one visually inspected | PASS |
| Read an already opened window | Multiple AX observations | No activation logged | PASS within this probe |
| Close/recreate, text input, shortcut recording | Not exercised on probe | No evidence | NOT RUN |

Two bounded recordings, 90 seconds and 120 seconds, contained respectively
2532 and 3312 samples: **0 foreground PID changes and 0 workspace activation
events in both**. Requested interval was 25 ms; maximum observed sample gaps
were 56.33 ms and 55.86 ms. The first 90-second app log also contained no
key-window/application-activation event; the later recording relies on samples
and workspace events rather than a complete second app-log stream.
No visible flash was observed, but sampling
cannot prove absence of a shorter transient, and there was no continuous
screen/Space recording.

### First-run guide gate

The isolated development defaults were reset for only
`com.lingsmbp.StatusTrio.dev.background-computer-use-testing` so the real guide
policy ran; production defaults and permissions were not changed. Two displays
were connected: main ID `5` at `2048 x 1152` points and secondary ID `1` at
`1728 x 1117`, to the left at negative coordinates.

PID `45396` launched through the normal launcher with
`--background-ui-testing --test-display=secondary`. The guide appeared at
`{{-1184, 260}, {640, 700}}`. After choosing Customize, Settings appeared at
`{{-1224, 345}, {720, 530}}`. Both windows were on the secondary display and
the app stayed accessory/inactive.

| Operation | Repetitions | Focus evidence | Result |
| --- | --- | --- | --- |
| First-run guide shown instead of Settings | 1/1 | Guide window on secondary display; Settings absent until Customize | PASS |
| Native AX attachment to the guide | 1/1 | Target remained inactive | PASS |
| Guide Next and Back | 3 transitions across 2 attempts | Actual page content changed; target remained inactive | PASS |
| Dark/light preview selection | 2/2 | Accessibility value changed and was restored to dark | PASS |
| Guide screenshot | 2/2 | Valid guide images inspected | PASS |
| Customize -> Settings | 1/1 | Settings opened on the secondary display; no target activation | PASS |
| Text input, menu-bar help, system links/dialogs | 0 | Not exercised | NOT RUN |

The controlled 90-second recording contained 2619 samples and four unrelated
foreground changes among other apps. It contained **0 activation events for the
target** and **0 samples where the target was active**. Requested sampling was
25 ms; the maximum observed gap was 53.60 ms. This supports the tested AX
actions, not sub-sampling proof of zero transient focus or every control.

### Single-display guide and Settings follow-up

After the dual-display run, the guide and Settings path was repeated with only
the physical main display connected: ID `5`, `2048 x 1152` points, visible
frame `{{0, 0}, {2048, 1122}}`. The launcher requested
`--test-display=secondary`; the configuration correctly fell back to the sole
main display. Production preferences and permission state were not changed.

The isolated development preference domain was backed up and reset so the real
first-run policy ran again. The guide appeared on the sole display. Native
Computer Use selected Next, observed the second page, selected `调整外观…`, and
reached Settings without the target becoming active. Settings appeared at
`{{664, 178}, {720, 530}}` in WindowServer coordinates and remained fully on
the display.

A complete repeated Settings sequence under the second recorder selected
General, returned to App Icon, changed ring thickness from Normal to Thin,
verified the selected state, captured a screenshot, restored Normal, and
captured another screenshot. The checked time window contained 126 samples,
foreground remained Microsoft Edge throughout, and there were **0 foreground
transitions and 0 samples where the target was active**.

The two bounded recordings for this test contained 3545 samples over 120
seconds and 2350 samples over 90 seconds. They recorded **0 activation events
for the target** and **0 samples where the target was active**. The complete
session did contain 11 foreground transitions among other applications, so the
whole run is not described as globally transition-free. The initial recorder
ended before its final screenshot/restore calls; those calls were repeated
under the second recorder rather than counting incomplete coverage as a pass.
The maximum observed sample gaps were 57.90 ms and 62.50 ms. These results do
not prove absence of a transient shorter than that interval.

## Integrated build and remaining runtime matrix

The launcher successfully built and started PID `21498` with both testing
flags. It reported the correct dev ID and `sourceDirty=true`. The only
connected display remained ID `1`, and its window was on-screen at
`{{504, 172}, {720, 530}}` in WindowServer coordinates. Native attachment
read the existing Settings controls.

That intermediate integrated executable was SHA-256
`e29b76285b820da14f3893c618948a581d0cefd53ba28ecab77c008e9e07a233`.
It precedes the additional event-time screen diagnostic; it is not claimed as
the final verified executable.

During the first repeated interaction attempt, native Computer Use returned:
"The Mac is locked and automatic unlock could not unlock it." No completed
rounds were reported. The 120-second recording contained one foreground
transition at 54.63 seconds to `com.apple.loginwindow`, PID `623`, and none to
Status Trio. This external lock transition is not counted as a zero-transition
run or as an app regression. The test instance was then gracefully terminated.

| Scenario | Single display | Secondary display | Evidence / next requirement |
| --- | --- | --- | --- |
| Integrated Debug startup, secondary requested without a secondary display | PASS (1 run) | PASS (guide) | Earlier fallback PASS; guide appeared on an actual negative-coordinate secondary |
| Native read/attach to integrated Settings | PASS (1 run) | PASS (guide/Settings transition) | Guide and Settings AX trees returned; no complete repeated Settings gate |
| First-run guide Next -> Settings | PASS (fresh isolated preference) | PASS (controlled) | Single display observed both pages, Customize and Settings; dual display additionally covered Back, preview and guide screenshots |
| Integrated sidebar + setting change + screenshot, one complete sequence | PASS | BLOCKED | Single display covered General/App Icon, Normal -> Thin -> Normal and two screenshots; dual-display attempt was interrupted by the Mac lock |
| Five consecutive integrated Settings rounds | NOT RUN | BLOCKED | The discarded probe passed five rounds, but that is separate evidence |
| Settings close/reopen and existing window behind browser/IDE | NOT RUN | BLOCKED | Automated lifecycle tests pass; native runtime remains unverified |
| Menu bar -> Settings | NOT RUN | BLOCKED | Need native menu-bar interaction; popover may intentionally activate |
| Real Dock click / reopen | NOT RUN | BLOCKED | Native service reopen cannot substitute for Dock |
| Real Bluetooth decision, recovery and system prompt | NOT RUN | BLOCKED | No TCC reset or permission changes performed |
| Text input / shortcut recording | NOT RUN | BLOCKED | No safe supported background claim; stop if key focus required |
| Secondary placement | NOT RUN | PASS | Guide and Settings rendered on the left-hand secondary display |
| Secondary unplug, main-display swap, wake | NOT RUN | NOT RUN | No topology transition was performed |
| Normal mode / Release actual GUI behavior | NOT RUN | NOT RUN | Source paths retained; Release flag contract checked independently |
| Launcher rejects production ID / another worktree's ID | PASS | NOT RUN | Live helper refused both; protected PIDs unchanged |
| Launcher safe restart / refuses this path's non-test process | PASS (process boundary) | NOT RUN | PIDs `53864` -> `55062`; non-test PID `55079` refused before rebuild |

## Automated verification and evidence

Focused development command:

```bash
bash scripts/test.sh 'BackgroundUITestingTests|SettingsWindowControllerTests|GuideWindowLifecycleTests|DockActivationActionTests'
```

The added tests were first observed failing because the configuration and
presentation injection did not exist. The onboarding-focused run passed seven
XCTest tests; the combined Swift Testing route suite passed seven tests. It
covers configuration validation, guide first-run presentation and skip policy,
normal activation retention, window close/rebuild/preview ownership, permission
suppression, preserved normal presentation/autosave, activation-policy and Dock
routing regressions, and synthetic screen layouts (negative coordinates, screen
above main, exchanged main ID, disconnected secondary and a screen smaller than
the fixed window). These tests use the existing application-policy spy; they do
not set the process-global activation policy.

`scripts/test-background-ui-configuration.sh` compiles the actual configuration
source both with `DEBUG` and optimized without `DEBUG`; Release flags must
produce exactly `.disabled`. `scripts/test-launch-computer-use.sh` uses offline
fixtures for ten launch argument, lock, capability, identity and ordering cases,
including paths containing spaces. The full local profile includes both.
No real launch is made by those offline fixtures.

An earlier full profile passed 2153 XCTest tests (8 existing skips), 794 Swift
Testing tests in 116 suites, the Release build, local app/Helper contracts and
the new offline checks, then failed in `test-verify-local-bundle.sh`. Its nested
temporary repository omitted the two newly registered check scripts. The
fixture now includes them and asserts that both run; no assertion was loosened.
Final full verification after the onboarding gate: **PASS** on base
`98fc8a10879ca9ed4244626e8b44682d7b54a7bc` plus the recorded working-tree changes.
It passed 2156 XCTest tests (8 existing skips), 797 Swift Testing tests in 116
suites, Release compilation, the non-Universal local ad-hoc app bundle and
platform/MobileBattery/Helper contracts, and all offline checks. The status
file was empty and the script exited successfully. This is local evidence,
not release, signing/notarization, Universal or hardware acceptance.

Independent static review identified the Dock/Both native-reopen bypass,
concurrent launcher bundle assembly, and two activating Bluetooth bindings.
The exact native sender now has a Debug background Settings route with
regressions covering all placements, normal mode, physical Dock, unknown or
prefixed senders, and non-reopen events. The launcher now holds a worktree lock
and validates a unique launch token. Both new regressions were observed failing
before their fixes. Bluetooth bindings are explicitly excluded from background
testing instead of changing permission behavior without native evidence.
The post-review focused route run passed seven XCTest and seven Swift Testing
tests.
The manual-launch race described above and unsupported controls remain limits.

The live instance helper separately refused a production Bundle ID and a
collision with another running worktree (PID `55357`). Three other running
Status Trio PIDs were unchanged before/after these refusal tests. This is
process-boundary evidence, not GUI or permission acceptance.

The final launcher was also exercised live: it gracefully stopped test PID
`53864` before starting PID `55062`, with a different per-launch token. Both
requested display variants reported only connected display ID `1`. A deliberate
normal-mode fixture, PID `55079`, caused the launcher to refuse before building;
the PID, executable digest and executable mtime were unchanged by the refusal.
Only those fixtures created by this investigation were then terminated.
The executable used for that process-boundary run was SHA-256
`df94d4d7ceb6989164134f6e2714d13961fce72c5cca4ee26d96b806e3961b78`.

After the final full pass, the final source was rebuilt and launched again as
PID `56765`, requesting a secondary display. The exact executable SHA-256 was
`36c6a766108997730ac6d79f44a130c3aaf1ecb5473d678a9f79742541e91995`.
Native `cua.getApp(appPath)` again returned the locked-Mac error, so **the final
integrated GUI acceptance remains BLOCKED**, including the post-review CUA
Dock/Both route. PID `56765` was gracefully terminated afterward; the final
test instance is not left running. No unlock workaround was attempted.

Local evidence is under `.build/background-computer-use/`; full-profile
evidence is under `.build/local-verification/`. This ignored directory contains
baseline/probe/build logs, foreground JSONL recordings, native app event logs,
the discarded probe patch and source/binary provenance. Computer Use action
results and the inspected screenshot are also in the Codex chat.

The read-only diagnostic can be run for at most 120 seconds:

```bash
swift scripts/measure-ui-focus.swift com.lingsmbp.StatusTrio.dev.background-computer-use-testing 30 > /tmp/status-trio-ui-focus.jsonl
```

It samples foreground identity, target process policy/activity and on-screen
target window bounds, and subscribes to workspace activation notifications.
It records physical display IDs, actual sample gaps and transition counts.
It cannot read another process's `NSWindow.isKeyWindow`; correlate with the
existing `DockActivation` key-window logs. It never requests Accessibility or
screen recording access, injects input, changes focus or remains resident.

Signing/notarization, Universal packaging, privileged Helper runtime, macOS 13
runtime, publication and release CI are NOT RUN.
