# macOS adapter

These are investigation points, not instructions to refactor another app.
Read the project's existing implementation and use public, supported APIs.

## Focus and presentation

Treat activation policy, ordering, key/main window, app activation, and input
routing as distinct effects. Inspect show/reopen handlers, Settings, onboarding,
permission recovery, popovers, status items, and Dock routes. Calls such as
`NSApp.activate`, `makeKeyAndOrderFront`, and `orderFrontRegardless` deserve
explicit investigation. `open -g` alone does not constrain later app code.

An app-supported presentation using `orderFront(nil)` may be a candidate; it
is not a universal solution. Establish whether the actual controls can operate
without key-window or keyboard focus. Nonactivating panels, accessory policy,
window levels, and screenshots alone do not establish safe background input.
Do not change the user's normal app behavior merely to pass a test.

For a codebase that needs support, propose a minimal opt-in development-only
probe before a full window rewrite. Preserve normal/Release activation,
permissions, lifecycle, and frame autosave. Do not modify app code unless
development is within the user's authorized scope.

## Displays and observation

Use actual display identities, visible frames, coordinate systems, and scaling.
The leftmost display and array index zero need not be the physical main display.
Secondary displays can have negative coordinates and can disconnect. Use the
app's placement mechanism and record fallback, clipping, and current topology.
Do not move unrelated windows or switch Spaces to arrange the test.

Prefer existing bounded diagnostics based on public foreground notifications,
running-app identity, and window observations. State which key-window, input,
pointer, or Space effects are not visible. Record the actual sampling gap;
zero sampled activations does not prove zero sub-sampling interference.
Stop observers at their deadline and before replacing the test instance.

## Project boundaries

Read the current project's adapter for its launch route, supported providers,
identity checks, and known activating controls. Background test flags are
app-specific, not macOS or general harness features. Do not invent flags,
copy another app's Bundle ID, or weaken ownership checks to reuse its scripts.

Menu-bar/Dock behavior and system dialogs need separate acceptance; an app's
intentional foreground interaction is not a background automation PASS.
First-run preferences must follow the project's real policy; resetting a
guide requires an explicitly scoped test fixture and restoration of that
test domain. Historical results for a provider are scoped to the recorded
app, host, version, and controls, not every macOS app.
