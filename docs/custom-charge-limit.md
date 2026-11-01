# Managed charge limit

Issue #187 adds an optional charge-limit policy in Settings → Battery. The
default is **System Managed**: Status Trio does not take ownership of the
system's charge limit. This is separate from **Full ring level**, which only
changes how the battery icon is drawn.

## Choosing and restoring a limit

On a supported Mac, the charge-limit picker offers the values reported by
macOS, typically 80%, 85%, 90%, and 95%. These are native charge limits rather
than arbitrary percentages simulated by Status Trio. Choosing a value applies
it immediately and saves it for subsequent launches. The controller verifies
the resulting native limit before reporting it as active.

Before starting a managed period, Status Trio records the original system
limit. Changing between managed targets retains that original value. Choosing
**System Managed** restores the recorded value, including 100% when the system
previously had no lower cap, and ends Status Trio's managed policy. It does not
always mean “set to 100%.” With no managed period to end, the default selection
does not rewrite the system setting.

If a saved target is no longer reported as available, the picker keeps it
visible as an unavailable option. It cannot be applied again. Choose another
available value or System Managed; the app does not silently substitute a
different percentage. Restoring an original sub-100% limit also requires it
to remain available. If its options cannot be read, the restore fails without
discarding the recorded original value. An original 100% (no lower cap) can
still be restored when the options list is empty.

Before issuing a native write, the app saves the desired target and original
limit as a pending operation. If writing or verification fails, or the process
stops during the operation, that recovery record remains. A pending operation
can be confirmed by readback, but is never automatically retried against a
different current state. Choose a target again, Reapply, or System Managed to
recover explicitly.

Selecting System Managed also records its restoration intent before writing.
If the process stops after that write, relaunch verifies the original baseline
and clears ownership; it never interprets the interrupted opt-out as permission
to reactivate the old managed target.

A charge limit does not force the battery to discharge immediately when its
current charge is higher. macOS still controls charging and may occasionally
charge fully to maintain battery-level accuracy.

## Lifecycle and temporary full charging

Managing a limit is an explicit opt-in. While a custom target is selected,
Status Trio can reapply it at launch, after wake, or after power is reconnected.
The policy uses lifecycle and power-state events; it adds no periodic polling,
permanent timer, charging animation, or Helper process. Settings refreshes the
reported state when the group appears.

**Charge to Full Now** temporarily suspends the managed target. It does not
replace the saved target with 100%. Cancellation, reaching full charge, or
reconnecting power ends the temporary override and allows the managed target
to resume. This policy also respects a native temporary full-charge state that
the app detects. The existing panel action and its explicit-cancellation
workflow remain available.

An accepted override can take several seconds to appear in native readback.
The saved request time protects a stale active-target read for up to 15 seconds.
After that grace period, a confirmed native cancellation can end suspension.
This grace is evaluated only on existing events or Settings refresh, without a
timer.

Quitting Status Trio stops its lifecycle handling. The last applied native
limit remains in macOS, but the app cannot observe completion or reapply its
target while it is not running. A saved policy resumes on the next launch
after fresh state and capability checks. Quitting is not the same as selecting
System Managed.

If a different active limit below 100% is detected, Status Trio treats it as
an external change and pauses automatic application. It does not immediately
overwrite the other limit. Choose a limit or press **Reapply** to explicitly
resume management, or choose System Managed to restore the original recorded
limit. Failed operations show a localized status instead of reporting success
or entering a retry loop. Reapply performs a fresh validation and is unavailable
when the saved target is not currently offered.

## Compatibility and implementation boundary

The feature is restricted to supported Apple silicon Macs running macOS 26.4
or later. Availability depends on runtime capability and selector/ABI checks,
not just the OS version. Intel and Rosetta processes and unsupported systems
must remain on the existing battery-display path without loading this private
charging interface. The application's deployment target remains macOS 13.

Charge management uses the existing dynamically loaded PowerUI private API.
Apple does not provide a public compatibility guarantee for this interface;
future macOS changes may make the control unavailable. The app uses the
system-reported limits and verifies writes. It does not edit the charging
preferences plist, write SMC values, change Low Power Mode, request new
permissions, or introduce privileged Helper/XPC behavior.

The original [Charge to Full Now investigation](charge-to-full-now-poc.md)
records native one-shot behavior and its historical evidence. Its absence of
automatic restoration describes the legacy action with System Managed
selected. The opt-in policy described here deliberately adds event-based
restoration for an explicitly saved managed target. Historical experiments do
not prove this new policy's runtime behavior.

## Interaction with Charge to Full Now

The existing **Charge to Full Now** action and the managed policy share one
writer. When a managed limit is active it becomes the cancel/restore target, so
cancelling a temporary full charge resumes the managed limit rather than the
legacy **Restore limit** slider. That slider therefore only governs the
**System Managed** case; it is disabled and annotated while a managed limit is
selected.

Both actions persist their own session (`chargeToFullNow.session.v1` and
`managedChargeLimit.session.v1`). They are independent records with different
purposes and are not merged: the managed policy is the single source of truth
for the native limit, and Charge to Full Now reads it through one closure
(`managedRestoreLimit`). On relaunch each controller re-reads the live native
state before acting, so a completed, cancelled, or externally ended override is
reconciled rather than blindly replayed.

## Verification scope

Automated policy and bridge tests use fake clients. Local builds and tests do
not change a real battery charge limit. Record the final integrated local
profile separately; it is not evidence of actual charging or native UI state.

The following real-device checks remain **NOT RUN** for this feature until
performed and recorded for a specific Mac model and OS build:

- Applying and restoring each reported native limit, including an original
  100% setting and switching between managed targets.
- Launch, sleep/wake, and physical unplug/replug recovery.
- Product and native temporary full-charge actions, cancellation, full-charge
  completion, and restart during an override.
- External limit changes, unavailable options, read/write failures, and recovery
  through Reapply or System Managed.
- Quit/relaunch behavior and idle-power measurement with the policy enabled.
- Ventura and current-macOS runtime regression checks.

Any manual write requires explicit authorization for the tested charging
action. Follow the repository's isolated development-bundle and background UI
testing rules, and record functional charging behavior separately from focus
or non-activation evidence.
