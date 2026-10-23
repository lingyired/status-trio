# Configurable Global Shortcut for the Status Panel

## Intent and execution authority

The user requested a global shortcut that quickly opens the status panel, can
be modified in Settings, and is implemented by DeepSeek after a written plan
in a new branch and worktree. Execute that handoff directly. The choices below
are conservative implementation defaults, not additional user requirements.

## Product behavior

- Add an "Open status panel" shortcut row in Settings > General.
- Start unassigned. Recording a valid combination assigns it immediately.
  Clearing disables it and persists that choice. Restart restores the choice.
- Activating the shortcut while another app is focused opens the existing
  status popover. Activating it when the panel is already open closes it.
  Existing mouse and Dock toggle semantics remain intact.
- Accept a non-modifier key plus Command, Control, or Option (Shift may be
  added). Reject modifier-only and unmodified/Shift-only combinations.
  Escape cancels recording; Delete/Backspace clears during recording.
  Ordinary typing and standard navigation outside recording stay unchanged.
- Show the current combination, an accessible record button, an explicit
  clear button, recording instructions, and a localized validation/conflict
  message. Failed replacement retains the previous working shortcut.
- Recording temporarily suspends shortcut activation so the old combination
  cannot unexpectedly open the panel. Ending recording, losing focus,
  switching sections, or closing Settings restores the registration.
- Use the menu bar anchor when visible and usable. For Dock-only mode or an
  unavailable/offscreen menu bar anchor, position the same popover at a stable
  point on the screen containing the pointer, clamped inside its visible frame.
  Do not change placement preferences or create another status panel.

## Architecture

Use the already-linked Carbon framework for `RegisterEventHotKey`,
`UnregisterEventHotKey`, and a single application event handler. Avoid a new
package for this one binding. Do not install a global key event monitor, event
tap, accessibility request, input monitoring request, or polling loop.

Separate these responsibilities:

1. A validated, serializable shortcut value and keyboard label formatting.
2. A main-actor controller with an injectable registration backend, published
   runtime error/recording state, and explicit start/stop ownership.
3. A small AppKit recorder wrapped in SwiftUI, present only in the General pane.
4. Existing `SettingsStore` persistence, `AppEnvironment` lifecycle, and
   `StatusBarController` presentation integration.

Keep persisted preference separate from transient registration state. Carbon
callbacks must hop safely to the main actor, identify the owned event ID, and
ignore events after stop or during recording. Replacement must be transactional:
register a candidate before removing the old registration; if that cannot be
done because recording suspended it, restore the old registration on failure
and report a restoration failure explicitly. Every registration and handler
has exactly one owner and an idempotent cleanup path.

Use layout-aware labels for printable keys where the active keyboard layout
has Unicode data, and readable names for Return, Tab, Space, arrows, function
keys and other supported special keys. Fall back safely for unknown codes.
Never assume a pointer obtained from a temporary layout object outlives it.

## Constraints and non-goals

- macOS 13 minimum; Swift 6 actor/concurrency rules and existing SDK guards.
- No change to icon rendering, scene source, appearance or placement options.
- No new permissions, background timers, global key logging, or telemetry.
- All 12 shipped localizations receive the added strings.
- No commit, push, merge, PR publication, release, tag, or online appcast change
  is authorized by this implementation request.
- Detect registration failures that Carbon reports. Do not promise detection
  of every macOS or third-party shortcut; document this practical limitation.

## Acceptance and evidence

Automated tests cover persistence and malformed data; modifier validation;
start/stop, replacement/rollback, suspension and stale callbacks; recorder
cancel/clear/focus loss; and selecting a valid popover anchor in menu bar and
Dock-only modes. Use fake backends for tests instead of reserving real system
shortcuts in the test process. Keep existing mouse/Dock behavior regressions.

Run focused tests while developing and `bash scripts/verify-local.sh full` on
the final tree. Fetch `origin/main`, record the base and final comparison, and
preserve unrelated work. Report native keyboard operation, multi-display,
full-screen Spaces, Ventura, and current macOS runtime as NOT RUN unless
actually exercised. Unit tests are not manual runtime acceptance.
