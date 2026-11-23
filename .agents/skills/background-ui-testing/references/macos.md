# macOS adapter

Assess macOS effects along the project's supplied CU route. This reference
does not choose tests, define functional acceptance, or require app refactoring.
Use existing project interfaces and public, supported APIs.

## Focus and presentation

Treat activation policy, ordering, key/main window, app activation, and input
routing as distinct effects. For the launch/attachment/input path in use,
check whether the app or tool requests any of them. For AppKit paths, calls such as
`NSApp.activate`, `makeKeyAndOrderFront`, and `orderFrontRegardless` deserve
explicit investigation. `open -g` alone does not constrain later app code.

An existing presentation route using `orderFront(nil)` may be a candidate;
it is not a universal solution. Nonactivating panels, accessory policy,
window levels, and screenshots alone do not establish safe background input.
Do not prescribe window/controller changes or extra functional tests.
If adaptation advice is requested, follow the
[integration boundary](project-adapter.md); implementation and production
verification remain with the project.

## Displays and observation

Use actual display identities, visible frames, coordinate systems, and scaling.
The leftmost display and array index zero need not be the physical main display.
Secondary displays can have negative coordinates and can disconnect. When
placement is requested, use a supported app or tool mechanism with assessed
effects and record fallback, clipping, and current topology.
Do not move unrelated windows or switch Spaces to arrange the test.

Prefer existing bounded diagnostics based on public foreground notifications,
running-app identity, and window observations. State which key-window, input,
pointer, or Space effects are not visible. Record the actual sampling gap;
zero sampled activations does not prove zero sub-sampling interference.
Stop run-owned observers at their deadline. If the target changes, end or
explicitly segment coverage rather than attributing one target's evidence
to another.

## Project boundaries

Read the current project's adapter for its launch route, supported providers,
identity checks, and known activating controls. Background test flags are
app-specific, not macOS or general harness features. Do not invent flags,
copy another app's Bundle ID, or weaken ownership checks to reuse its scripts.
Evaluate OS scripting and command-line wrappers by their actual targeting,
activation, and input behavior, subject to the project's tool restrictions.

When the existing workload reaches a menu-bar/Dock route or system dialog,
assess its activation and input effects rather than assuming earlier background
support applies. Do not add tests for these routes or reset onboarding to
complete this skill. Historical provider evidence is scoped to its app,
host, version, and operations, not every macOS app.
