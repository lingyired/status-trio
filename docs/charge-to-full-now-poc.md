# Charge to Full Now: research and implementation

## Decision

**IMPLEMENTED as a native-equivalent override with explicit cancellation.**

The authorized experiments proved that `temporarilyDisableMCL:` is the same
private path used by the native `Charge to Full Now` action. On macOS 27.2 it
started charging without a permission or administrator prompt. It also left the
persistent manual charge limit at `100` after charging completed and after a
physical unplug/replug cycle; the native UI showed the same result. The user
manually restored the limit to `80`.

The user reviewed that evidence and explicitly chose to replicate the native
button's behavior, including its lack of automatic recovery. Status Trio stores
the valid pre-request limit as a fallback, persists the operation session, and
offers an explicit "Cancel Charge to Full" action. It never restores the limit
automatically, watches the battery in the background, or runs a periodic task.

Research started October 27, 2026; regression verification continued October 28,
2026, Asia/Shanghai. Both authorized write experiments ran on October 28, 2026.

- Initial baseline: `origin/main`, `a9ee5cab352b6464d3a6b5a2a4cb51a5bd6c99b9`.
- Latest fetched baseline for the final rebase: `origin/main`,
  `58b195f8ae9efa8010dff37f900fe41935d2cd1e`.
- Branch: `codex/charge-to-full-now`, research commit
  `29577226dad404e2a8a4eddfa402807d2e9a5647`, rebased onto the latest
  `origin/main`; final research documentation is at `4f100926`.
- Isolated worktree: `/Users/lingsmbp/.codex/worktrees/charge-to-full-now/status-trio`.
- Write experiment host: Apple Silicon, macOS 27.0.1 (26A434), Xcode 27.0
  (27A266a).
- Current revalidation host: Apple Silicon, macOS 27.2 (26B123), Xcode 27.0
  (27A266a).
- Two authorized charging requests total, one per OS build. No new permissions,
  authorization requests, Helper changes, or SMC writes occurred. No explicit
  persistent-limit write was declared, but the macOS 27.2 request changed the
  native persistent setting as described below.

## Reproduce the read-only experiment

From this worktree:

```bash
bash scripts/probe-charge-to-full-now.sh --self-test
bash scripts/probe-charge-to-full-now.sh --inspect
```

The first command uses local fake Objective-C classes; it does not load PowerUI
or contact a charging service. The second explicitly loads the system's
PowerUI framework in a short-lived command-line process and reads state.
No arguments, unknown arguments, Intel/Rosetta processes, or macOS before 26.4
stop before loading PowerUI. The inspection child has a 20-second timeout.
Private Objective-C classes are kept loaded until process exit.

The tool is outside `Sources`, is not a Swift package target, and is not
called by the app, settings, popover, or tests in `scripts/test.sh`.
The product bridge does not acquire an additional query or background task.
There is deliberately no write flag, declared write method, privileged
service, or charge-limit setter in the tool.

The probe checks class, selector, return type, argument count, and out-pointer
encodings before initializing the client or sending state queries.
`temporarilyDisableMCL:` is inspected as metadata only.

## Observed ABI and state

These encodings were read from the running macOS 27.0.1 arm64 process and
rechecked against the running macOS 27.2 arm64 process:

| Selector | Encoding | Interpretation |
| --- | --- | --- |
| `initWithClientName:` | `@24@0:8@16` | Object argument and object result |
| `isMCLSupported` | `B16@0:8` | `BOOL` |
| `isMCLCurrentlyEnabled:` | `Q24@0:8^@16` | `NSUInteger`, **not BOOL**; `NSError **` |
| `getMCLLimitWithError:` | `C24@0:8^@16` | `unsigned char`, **not NSUInteger**; `NSError **` |
| `availableChargeLimitsWithError:` | `@24@0:8^@16` | `NSArray *`; `NSError **`; optional at runtime |
| `smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:` | `B48@0:8^Q16^Q24^B32^@40` | `BOOL`; two `NSUInteger *`, `BOOL *`, `NSError **` |
| `temporarilyDisableMCL:` | `B24@0:8^@16` | `BOOL`; `NSError **`; invoked exactly once after authorization |
| `enableMCL:` | `B24@0:8^@16` | `BOOL`; `NSError **` |
| `setMCLLimit:error:` | `B28@0:8C16^@20` | `BOOL`; `unsigned char`, `NSError **` |

The Objective-C implementation is independent and uses checked typed messages,
not unchecked function-pointer casts or statically linked private frameworks.
It does not copy JuiceLeft source, comments, or tests.

Observed on the development machine:

| Reading | Value |
| --- | --- |
| Internal battery present / external power | `true` / `true` |
| Battery percentage / currently charging / fully charged | `80` / `false` / `false` |
| MCL supported | `true` |
| MCL enabled raw result | `1`, no error |
| MCL limit / UI limit | `80` / `80`, no error |
| UI state raw result / query success | `14` / `true`, no error |
| `chargingOverrideAllowed` | **`false`** |
| Charging write requested | **`false` before the authorized experiment** |

Both private enum results remain raw. Their meanings have not been verified
against native UI and must not become production enum cases or boolean
assumptions. The applicability of the override-allowed signal to MCL, as
distinct from Optimized Battery Charging, still needs verification.

The false signal does not prove entitlement denial, permanently unsupported
hardware, or that native Charge to Full Now is unavailable. The successful
experiment below confirms that it is not a universal MCL gate. No Accessibility,
Automation, or other authorization was requested.

The user manually confirmed that native Charge to Full Now was visible and
clickable. The automated Control Center inspection had timed out, so this is
user-observed UI evidence rather than an automated accessibility-tree result.

Raw output and temporary exploratory tools are in the ignored
`.build/charge-to-full-now-poc/` directory. Re-running inspection replaces the
machine observation and may produce different state.

## Authorized write experiment

After the manual native-menu confirmation, the user explicitly authorized one
real private-API experiment. The one-shot research executable was outside
`Sources`, is not linked into Status Trio, and had no argument guard.

Sequence and evidence:

1. At 12:58:18, the first executable stopped at the ABI self-check because its
   argument-count assertion used `+3` instead of `+2`. No write was sent.
2. A corrected executable was built at 12:58:23.
3. It was accidentally launched with `--help`. Because the executable ignored
   arguments, that invocation sent one write request. Its return value and
   `NSError` were printed but not retained. No second request was sent.
4. The executable was immediately made non-executable after this was
   discovered.
5. Ten seconds after the request, `pmset` still reported not charging, while
   private MCL state had changed from raw `1` to `3`, MCL limit from `80` to
   `100`, and UI state from raw `14` to `13`.
6. At 30 seconds, `pmset` reported charging and IOKit reported
   `IsCharging=1` with positive current. No permission prompt, administrator
   request, Helper, SMC write, or explicit persistent-limit write was observed.
7. At 13:02:17, the battery was at 82% and still charging. PowerUI still
   reported UI limit `80`, while `getMCLLimitWithError:` reported `100`.

During the override, `/Library/Preferences/com.apple.powerd.charging.plist` was
360 bytes and its `policies` value decoded to an empty keyed archive. The
battery continued to 100%, reached `charged` at 13:51:26, and no second charging
request was sent.

The host was then updated and rebooted to macOS 27.2 (26B123). A fresh read-only
check at 15:46:11 showed:

| Reading | Recovered value |
| --- | --- |
| Battery percentage / external power | `80` / `true` |
| Battery charging state | `not charging` |
| MCL enabled raw result | `1`, no error |
| MCL limit / UI limit | `80` / `80`, no error |
| UI state raw result / query success | `14` / `true`, no error |
| `powerd` policy archive | `558` bytes, populated |

This was natural recovery for the tested macOS 27.0.1 build: charging reached
full, the internal and UI limits returned to `80`, the temporary `100` override
did not survive the system update/reboot, and no recovery write or permission
request occurred. The current host is macOS 27.2, so the effect and recovery
were repeated there rather than inferred from this older build.

Do not run the ignored one-shot executable again. Its current mode is `0644`.

## macOS 27.2 revalidation and native behavior

After renewed explicit authorization, a protected one-shot tool was built for
macOS 27.2. It required an exact confirmation argument, validated the arm64/OS
precondition and every selector ABI before initialization, and sent only when
the tested state was present: 80%, AC connected, not charging, not charged, MCL
raw `1`, MCL limit `80`, UI success, UI limit `80`, and UI raw state `14`.

Exactly one request was sent at approximately 15:48:

| Reading | Before | After |
| --- | --- | --- |
| Write attempts / result | `0` / not called | `1` / `true` |
| Write error | none | `null` |
| MCL enabled raw result | `1` | `3` |
| MCL limit | `80` | `100` |
| UI state raw result | `14` | `13` |
| UI limit | `80` | `80` |

Within 30 seconds, `pmset` reported charging and IOKit reported
`IsCharging=1` with positive battery power. No permission prompt,
administrator request, Helper, LaunchDaemon, SMC write, or `pmset` write
occurred.

The battery reached the native `charged` state at 16:44:00. It remained at
100% while plugged in, but MCL still reported raw `3` and limit `100`.
After the user physically unplugged and replugged the power adapter, read-only
checks every 30 seconds for five minutes continued to report raw `3` and limit
`100`.

The native System Settings UI then showed a Charge Limit of **100%**. PowerUI's
`uiLimit` output still reported `80` during the same period, so that field
cannot be treated as the persistent user setting or as proof of recovery.

The user manually restored Charge Limit to `80%`. A subsequent read-only check
reported:

| Reading | Restored value |
| --- | --- |
| Battery percentage / state | `100%` / `charged` |
| MCL enabled raw result | `1`, no error |
| MCL limit / UI limit | `80` / `80` |
| UI state raw result / query success | `16` / `true` |
| `powerd` policy archive | `558` bytes, populated |

This confirms recovery after manual user action, not automatic one-shot
cleanup. The native button and the private request both changed the persistent
setting and neither restored it after unplugging. The user reviewed this
behavior, explicitly accepted it as the native-equivalent outcome, and
requested this exact action in Status Trio. The later explicit-cancel
requirement adds a saved operation snapshot for user-triggered restoration;
product code still performs no automatic restoration.

## Relationship to the native action

A read-only binary inspection shows that the macOS 27.2 Control Center
`Charge to Full Now` implementation is on the same private path:

- `ControlCenter` contains the localized `Charge to Full Now` action and imports
  `PowerUISmartChargeClient`.
- Its arm64e code at `0x1005b45b8` calls the Objective-C message stub at
  `0x1006c3280`, whose selector reference is `temporarilyDisableMCL:`.
- `PowerPreferences` invokes the same selector from the Swift path at
  `0x100060cfc`; its adjacent error log is
  `Could not temporarily disable charge limit`.

The static call chain was then confirmed with a direct native-UI comparison.
After the user restored the native limit to `80%`, a read-only monitor recorded
this sequence:

| Native menu click | Battery | Charging | MCL raw | MCL limit | UI limit |
| --- | --- | --- | --- | --- | --- |
| Before, 81% | present, AC connected | `false` | `1` | `80` | `80` |
| At 18:02:00, after click | present, AC connected | `false` initially | `3` | `100` | `80` |
| Within 40 seconds | present, AC connected | `true` | `3` | `100` | `80` |

No process from Status Trio sent a write request. The user then restored the
native setting to `80%`; after 45 seconds `pmset` returned to
`AC attached; not charging`, and PowerUI reported MCL raw `1`, limit `80`, UI
limit `80`, and UI raw state `16`. The monitor log is
`.build/charge-to-full-now-poc/native-button-20261028-180146.log`.

This directly confirms that `temporarilyDisableMCL:` is the native action's
underlying private call, not an invented simulation. It is still a private
implementation detail with no compatibility or behavioral guarantee across
macOS releases. The persistent limit changing from `80` to `100` is native
behavior, not a Status Trio-specific cleanup failure.

## Architecture audit and plan corrections

The audited baseline supports the proposed layout, with these corrections:

1. The repository ships **12** languages, not the plan's 13.
2. `BatteryStatusView` consumes `PanelSummaryState`; it must remain a
   presentation view. Future state belongs in the existing store/panel
   architecture, with actions through `StatusPanelActions`.
3. Popover content can survive closure. Future PowerUI demand must follow
   explicit panel lifecycle, setting enablement, and battery-section visibility
   in `StatusPanelViewModel`/`SystemStatusStore`, with release on closure.
   View disappearance alone is insufficient.
4. `BatteryMonitor` stays read-only. Neither its existing cadence nor
   `SystemChargeLimitReader`'s cached plist proves override eligibility.
   `batteryFullThreshold` remains an icon-display threshold.
5. Existing trailing leaf/chevron/gear geometry, home-row navigation, and the
   330-point width must remain intact. A future action is a sibling below the
   home battery row, with layout/VoiceOver tests across all 12 languages.

The product implementation follows this audit:

- `PowerUIPrivateAPI` dynamically validates and calls the private Objective-C
  client without static framework linkage.
- `ChargeToFullNowController` owns capability, live state, duplicate-request
  protection, the persisted operation session, cancellation, final-state
  verification, and error presentation behind an injectable protocol.
- Restore prefers a valid `getMCLLimitWithError:` result, then the pre-request
  snapshot, then `80`. An error in a different state query does not discard a
  successfully read limit. Cancellation always tries `enableMCL:` first and
  reads the enabled state and limit again. Only a successful call with a
  verifiable non-target state can fall back once to `setMCLLimit:error:`,
  then `enableMCL:`, followed by another verification read. Errors or a
  different restored sub-100 limit stop the operation without more writes.
- A valid active limit from the user or another app supersedes the saved
  session without a restore write. A session restored after relaunch, a
  potentially external `100%` state, a state-read error, or a fallback requires a
  second explicit confirmation before writing.
- A brief same-limit read immediately after an accepted override does not
  discard the session. A 15-second grace period is evaluated only when the
  panel or user action requests a read; it has no timer or polling. An
  observed override or a changed valid limit ends that ambiguity immediately.
  Cancel during that ambiguity retains the session and asks the user to retry.
  A read error retains a cancel/retry action instead of hiding it.
- `SettingsStore.showsChargeToFullNowButton` is default-on and persisted.
- `BatterySectionView` shows the setting only when capability is available.
- `StatusPanelViewModel` supplies demand only while the popover and battery
  section are both visible; closing the popover clears that demand.
- `BatteryStatusView` draws the action below the home battery summary, never in
  the detail page, in all 12 shipped languages.

The implementation does not alter the battery monitor, low-power mode,
charging animation, menu-bar icon, or Dock icon.

## Verification matrix

| Scope | Result |
| --- | --- |
| Native arm64 fake ABI/platform checks | PASS: 17 checks, 0 failures; no PowerUI load |
| Universal PoC and fake-test compilation | PASS: `arm64` and `x86_64`, macOS 13 deployment target |
| Fake ABI/platform tests under Rosetta | PASS: 17 checks, 0 failures |
| Rosetta inspection fallback | PASS: exit 2, unsupported, no PowerUI load, no write |
| Missing/unknown/extra command arguments | PASS: exit 2 before compiling or loading the probe |
| Live arm64 class/selector/ABI and state reads | PASS on macOS 27.0.1; read-only recheck PASS on macOS 27.2 |
| Existing focused battery/panel tests | PASS: 5 XCTest tests and 8 Swift Testing tests |
| Complete repository local profile | PASS: `bash scripts/verify-local.sh full`, exit 0; see provenance below |
| Updated-main DDC regression | PASS: 14 tests, 0 failures after rebasing onto `27ef4ca2` |
| Independent four-file safety review | PASS: no remaining Critical or Important findings |
| Native system menu comparison | PASS: user confirmed visible and clickable; automated UI inspection timed out |
| Native action call chain | PASS for macOS 27.2 static inspection: Control Center and PowerPreferences reference `temporarilyDisableMCL:` |
| Native menu click compared with private call | PASS: native click produced MCL raw `1 → 3`, limit `80 → 100`, then charging within 40 seconds |
| 80% override request and actual continued charging | PASS for this OS build: charging began within 30 seconds |
| Permission or authorization prompt during request | PASS: none observed |
| Private write return value and `NSError` on macOS 27.0.1 | NOT CAPTURED: accidental invocation discarded stdout |
| Private write return value and `NSError` on macOS 27.2 | PASS: returned `true`, no error |
| PowerUI UI limit during override | PASS: remained `80` immediately before and after the request |
| Persistent limit behavior matches native action | PASS: both native click and private request changed Charge Limit from `80` to `100`; accepted product behavior |
| Unplug/replug automatic restoration | VERIFIED ABSENT on macOS 27.2; native-equivalent behavior is retained |
| Manual restoration and read-only confirmation | PASS: user restored native `80`; MCL and UI limit report `80` |
| macOS 27.0.1 restoration after system update/reboot | PASS: MCL and UI limits returned to `80`; policy populated |
| Settings default, persistence, and capability visibility | PASS: focused XCTest |
| Controller duplicate-write prevention, revalidation, failure, and teardown | PASS: focused XCTest |
| Cancel target selection for `80`, `85`, `90`, `95`, `100`, read failure, snapshot, and fallback | PASS: focused XCTest |
| Cancel confirmation, verification mismatch, retry, external change, and relaunch session | PASS: focused XCTest |
| Native restore ordering, state-read failure, NSError, external-change guard, and final verification | PASS: 15 fake-client cases; real PowerUI loading aborts the test |
| Popover setting/section/visibility demand lifecycle | PASS: focused integration XCTest |
| All 12 localization layouts at fixed 330-point width | PASS: focused SwiftUI layout XCTest |
| 90%, limit 100%, unplugged, already charging/full, thermal/power restriction | NOT RUN |
| Legacy OBC override | NOT RUN; outside supported scope |
| Physical Intel, macOS 13-26.3, macOS 26.4, sleep/wake | NOT RUN; fake/version and Rosetta checks are not hardware coverage |
| Product-button manual charge write and cancel restore | PARTIAL: user reported the limit restored to its prior `80%` after the product cancel button on the current test Mac; selector branch and broader hardware coverage remain unverified |
| VoiceOver and full interactive UI acceptance | NOT RUN |

### Local verification environment

The first `bash scripts/verify-local.sh full` run passed 15 Helper XCTest
tests, 1,928 app XCTest tests (8 existing skips), 763 Swift Testing tests in
112 suites, and the Release build. It failed at `App bundle build`, exit 128,
because GitHub returned HTTP 403 while cloning the existing `libplist`
dependency. This was a source-download failure, not a feature or test failure.

All six dependency commit pins were verified in the main checkout's existing
local source cache. The absent repositories were cloned locally into this
worktree's ignored build directory, without hardlinks or changes to the
source cache, and their origins restored to the manifest URLs. No dependency
pins, build scripts, tests, or assertions were changed. The complete profile
was then run again with these pinned source inputs available and passed
(exit 0) on October 28, 2026.

During the research, `origin/main` advanced to
`27ef4ca27217f09cdd3ee9efa4f5e1ad59209f89` with an unrelated DDC test and
compatibility-document change. The branch was rebased onto that commit, the
14 affected DDC tests passed, and `bash scripts/verify-local.sh full` passed
again with exit 0 at research commit
`29577226dad404e2a8a4eddfa402807d2e9a5647`.

The successful final run reported 15 Helper XCTest tests, 1,928 app XCTest
tests (8 existing skips), and 763 Swift Testing tests in 112 suites, with zero
failures. Release compilation, the local non-Universal Ad-hoc app bundle,
platform/SDK and Helper contracts, native compatibility checks, and offline
release simulations all passed. Existing Swift concurrency warnings in the
unchanged Low Power Mode sources remain baseline warnings.

These results validate the existing app with the research files present. The
final product implementation is verified separately by the focused and full
local profiles recorded below. Neither result validates a physical Intel Mac,
the Ventura runtime, Universal app packaging, Developer ID signing,
notarization, or publication.

The initial failure log is retained at
`.build/charge-to-full-now-poc/full-verification-initial-failure.log`;
the subsequent run is at
`.build/charge-to-full-now-poc/full-verification-console.log` (first complete,
pre-rebase run) and `.build/charge-to-full-now-poc/full-verification-final.log`
(final post-rebase run).
The repository's canonical current report is
`.build/local-verification/log.txt`. Its `status.txt` records a failing step
when applicable; it is empty on this successful run. The saved initial status
is `.build/charge-to-full-now-poc/full-verification-initial-status.txt`.

## Implementation boundary

The user accepted the measured native behavior and authorized the explicit
override/cancel implementation. Status Trio therefore adds the controller,
default-on setting, home-panel action, session persistence, state/error
presentation, tests, and 12 translations.

The product still does not request permissions, use administrator authorization,
add a Helper/XPC service/LaunchDaemon, write SMC, rewrite the charging plist,
run a permanent timer, or substitute a different charging mechanism. Charging
writes remain limited to the explicit user action:

1. `temporarilyDisableMCL:` starts the native-equivalent override.
2. `enableMCL:` is tried first. A fresh enabled/limit read can finish the
   cancellation without a setting write.
3. Only if that successful call leaves a verifiable non-target state does
   `setMCLLimit:error:` apply the validated target before one more
   `enableMCL:`. A newly observed different sub-100 limit stops the fallback.
4. The bridge re-reads PowerUI and reports success only when the limit is active
   at the requested value.

Manual product acceptance remains separate from the automated suite: set the
native limit to `80%`, open the built Status Trio development app, enable the
setting, and click its `Charge to Full Now` button. After the temporary override
is visible, click `Cancel Charge to Full` and record PowerUI and System Settings
before, during, and after both writes. Do not perform either write in an
automated test.

The `enableMCL:`-only result and the fallback order are verified with a fake
client, not with real battery-control writes. The user later reported that the
charge limit returned to its prior `80%` after clicking the product's cancel
button on the current test Mac. That is manual acceptance of the reported
restoration only: the exact native selector branch was not captured, and other
limits, actual charging behavior, sleep/wake, and other OS or hardware
combinations remain **NOT RUN**.

### Manual cancellation acceptance

Use the development bundle from `bash scripts/build-worktree.sh release no-open`
and keep System Settings open beside it. Repeat for each supported native
limit (`80`, `85`, `90`, `95`); record the exact OS build and Mac model.

1. Set the native limit and confirm the Status Trio setting is enabled. Record
   the baseline before clicking its home-panel Charge to Full Now button.
2. Click Charge to Full Now manually. Reopen the panel if needed; record
   whether the stored MCL limit still equals the baseline or becomes `100`.
3. Click Cancel Charge to Full manually. If confirmation is shown, verify the
   displayed target before the second click.
4. Record the enabled state and stored limit after `enableMCL:`, and after
   `setMCLLimit:error:` plus `enableMCL:` if fallback was needed. Compare the
   final value with System Settings and the actual charging state.
5. Test one external limit change and one application relaunch. The external
   valid limit must survive; the relaunched session must require confirmation.

| Stage | MCL enabled raw | Stored MCL limit | Battery % / charging | System Settings limit |
| --- | --- | --- | --- | --- |
| Before request | Record | Record | Record | Record |
| After `temporarilyDisableMCL:` | Record | Record | Record | Record |
| After first `enableMCL:` | Record | Record | Record | Record |
| After fallback, if used | Record | Record | Record | Record |

A battery already above the restored limit need not discharge immediately.
Do not force discharge or invoke the old exploratory write executable. Capture
intermediate selector results with an attached debugger during the manual
button action if needed; automated tests must continue to use fake clients.

## Sources and provenance

- Apple's [About Optimized Battery Charging and Charge Limit on Mac](https://support.apple.com/en-us/102338),
  published April 6, 2026, describes Charge Limit on Apple Silicon and macOS
  26.4+, and the native Charge to Full Now menu action. Retrieved October 27,
  2026. It does not document this private programming interface.
- Apple's installed framework runtime metadata and live read-only results
  above are the ABI/state evidence. They are version-specific.
- The user's supplied `StatusTrio_ChargeToFullNow_Codex_Plan.md` provided
  candidate Apple API names. JuiceLeft's license was inspected to confirm
  its restricted terms; its implementation was not read or reused.
