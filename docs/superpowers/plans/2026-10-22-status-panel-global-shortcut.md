# Status Panel Global Shortcut Implementation Plan

> **For agentic workers:** Use the executing-plans skill to implement these
> dependent tasks sequentially in the assigned worktree. Steps use checkbox
> syntax for tracking. The user explicitly selected DeepSeek execution.
> Do not recursively delegate or wait for another approval. Leave all changes
> uncommitted for the parent to review.

**Goal:** Let a user assign, modify, and clear a global keyboard shortcut in
General Settings that opens the existing status panel from any application.

**Architecture:** Use a small Carbon registration backend behind an injectable
main-actor controller. Persist a validated key-code/modifier value in
SettingsStore, record it through an AppKit control in the existing SwiftUI
General pane, and route activation through StatusBarController's existing
popover lifecycle.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Combine, Carbon, XCTest/Swift Testing.
No additional package.

**Spec:** `docs/superpowers/specs/2026-10-22-status-panel-global-shortcut-design.md`

## Global Constraints

- macOS 13 minimum; Swift 6 actor/concurrency rules and existing SDK guards.
- No change to icon rendering, scene source, appearance or placement options.
- No new permissions, background timers, global key logging, or telemetry.
- All 12 shipped localizations receive the added strings.
- No commit, push, merge, PR publication, release, tag, or online appcast change.
- Work only in `/Users/lingsmbp/.codex/worktrees/status-panel-global-shortcut/status-trio`,
  branch `codex/status-panel-global-shortcut`.
- Original base: `7071fbe90e1806ff757d630aaecbccf03b88a7d9`.
- Integrated base: `9c9968dd1df77427b485ead8b066a4d0befaabee`
  (`origin/main` on 2026-10-22). The feature branch was fast-forwarded after
  upstream advanced 17 commits; shortcut work was backed up and reapplied.
- Read `AGENTS.md`, `.agents/rules/performance.md`, and
  `.agents/rules/macos-compatibility.md` before product edits. If touching the
  rendering path, also read `.agents/rules/rendering.md`; avoid such changes.
- Use `bash scripts/test.sh [filter]` as the only Swift test entry point.
  Final delivery requires `bash scripts/verify-local.sh full`.
- Never weaken tests, hide a failure by retries, or classify simulation as
  real keyboard/window-system acceptance.

## Review Focus

1. A conflict when replacing a working shortcut must preserve the old value
   and registration; a stored binding that conflicts at launch shows an error.
2. An event already queued when stop/suspend/rebind occurs cannot invoke an
   obsolete callback or open the panel while recording.
3. Closing Settings or changing panes while recording removes capture and
   restores the stored shortcut; cancellation does not alter persistence.
4. Dock-only and inaccessible menu bar anchors still open the same popover
   on an available screen, without changing placement or mouse toggle behavior.
5. Corrupt defaults, non-Latin layouts, Caps Lock, unsupported modifier flags,
   and repeated key events have deterministic behavior without losing typing.

Each task below owns regression checks for the corresponding conditions.

## File responsibilities

- Create `Sources/StatusTrioCore/Settings/StatusPanelShortcut.swift`: value,
  modifier normalization, validation, Codable persistence payload.
- Create `Sources/StatusTrioCore/App/GlobalShortcutController.swift`: injectable
  registration interface, observable state, lifecycle, transactional changes.
- Create `Sources/StatusTrioCore/App/CarbonHotKeyBackend.swift`: Carbon resources,
  event IDs, callback delivery, teardown. Keep C callback code in this file.
- Create `Sources/StatusTrioCore/UI/Settings/ShortcutRecorder.swift`: native
  recording control and SwiftUI bridge; extract a small recording state
  reducer if necessary for meaningful tests.
- Create `Sources/StatusTrioCore/UI/Settings/ShortcutKeyLabel.swift`: readable,
  keyboard-layout-aware display for the value.
- Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`: stored optional
  shortcut, no transient OS error persisted.
- Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`: sole live controller
  ownership, construction, start/stop, settings window injection.
- Modify `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift`,
  `SettingsView.swift`, `GeneralSectionView.swift`: inject the same controller
  and add the row using existing SettingsGroup/SettingsRow styling.
- Modify `Sources/StatusTrioCore/UI/StatusBarController.swift`: explicit open
  entry point, shared presentation flow, fallback anchor ownership.
- Modify `Sources/StatusTrioCore/Localization/LocalizationKey.swift` and every
  `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`: UI copy.
- Create focused tests for each responsibility under
  `Tests/StatusTrioCoreTests/`; extend existing tests when more appropriate.
- Create `docs/status-panel-global-shortcut.md`: use, limitations, verification.

## Task 1: Validated preference and persistence

**Interfaces:** Produce `StatusPanelShortcut: Codable, Equatable, Sendable`,
with `keyCode: UInt32`, `modifiers: UInt32` using normalized Carbon modifier
bits, a failable validating initializer, and optional
`SettingsStore.statusPanelShortcut`. Expose a stable defaults key. Encapsulate
NSEvent-to-Carbon conversion so the recorder cannot persist unsupported flags.

- [ ] Write failing value and isolated-UserDefaults tests first. Cover missing,
  clear/reload, round-trip, invalid JSON/schema/range/modifier bits, modifier
  keys as primary keys, unmodified and Shift-only input. Avoid numeric casts
  that silently truncate corrupt values.

```swift
func testShortcutStartsUnassignedAndClearSurvivesReload() throws {
    let name = "StatusPanelShortcutTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = SettingsStore(defaults: defaults)
    XCTAssertNil(first.statusPanelShortcut)
    first.statusPanelShortcut = try XCTUnwrap(
        StatusPanelShortcut(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
    )
    XCTAssertEqual(SettingsStore(defaults: defaults).statusPanelShortcut,
                   first.statusPanelShortcut)
    first.statusPanelShortcut = nil
    XCTAssertNil(SettingsStore(defaults: defaults).statusPanelShortcut)
}
```

- [ ] Run `bash scripts/test.sh 'StatusPanelShortcutTests'` and capture the
  expected missing-type/property failure before implementation.
- [ ] Implement validation and persistence using the same store patterns as
  existing settings. Decode via validation, not unchecked synthesized Codable.
  Use the publisher's emitted value when observing `@Published`; it emits
  before the underlying property is changed.
- [ ] Run `bash scripts/test.sh 'StatusPanelShortcutTests|SettingsStoreTests'`.
  Record command, results, and any design deviation in the report.

## Task 2: Native registration with lifecycle and rollback

**Interfaces:** Produce an `@MainActor` registration protocol and injectable
controller. A representative boundary is:

```swift
@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID
    func unregister(_ token: UUID)
    func stop()
}
```

The concrete backend maps UUIDs to Carbon registrations and owned event IDs.
The controller exposes `start()`, `stop()`, `setShortcut(_:) -> Bool`,
`beginRecording()`, `endRecording()`, and observable localized-error state.
`setShortcut` persists only after successful registration, except clear always
persists nil and unregisters. `start()` uses the stored value. Recording and
registration errors stay observable without adding them to SettingsStore.

- [ ] Write a fake backend that records registration/removal and can throw
  on one candidate. Tests must invoke saved callbacks even after unregister
  to prove stale-event rejection. Cover duplicate start/stop, no-binding idle,
  same-value no-op, successful rebind, failed rebind, failed startup, clear,
  suspend/end, stop-then-start and repeated key events.

```swift
// Behavioral sequence for a fake backend test:
// start with A -> A registered
// beginRecording -> activation suspended
// fake.failNext = true; setShortcut(B) -> false
// endRecording -> A restored; settings still A; error observable
// fake.deliverObsoleteAction() -> no panel action
// stop twice -> no live tokens/handler
```

- [ ] Run `bash scripts/test.sh 'GlobalShortcutControllerTests'`, observe RED.
- [ ] Implement controller and backend. Install only one event handler, filter
  event signature/ID/kind, prevent repeat activation until key release, and
  never retain the controller through the callback. Keep backend resources
  valid through callback execution and clean up on stop.
- [ ] Inspect the installed SDK's `CarbonEvents.h` signatures, OSStatus error
  constants and handler ownership rather than guessing. Use safe main-actor
  isolation; do not enable experimental features or `isolated deinit`.
- [ ] Run `bash scripts/test.sh 'GlobalShortcutControllerTests|StatusPanelShortcutTests'`.

## Task 3: General Settings recorder and localization

**Interfaces:** Consume the shared observable GlobalShortcutController and
SettingsStore. Preserve existing callers/tests with optional injected
controller defaults, but production must always use the environment-owned
instance. Recorder returns a validated candidate or cancel/clear action.

- [ ] Write failing recorder behavior tests for valid recording, invalid input,
  Escape, Delete/Backspace, focus loss, pane removal and ordinary nonrecording
  input. Exercise actual native control event methods where possible rather
  than asserting source code substrings.
- [ ] Implement a first-responder AppKit control using `keyDown` and
  `performKeyEquivalent` only while recording. Handle Command combinations
  before the Settings menu consumes them. On invalid input remain recording
  with a message. Consume repeat events without duplicate commits. Preserve
  focus and restore registration on every exit path.
- [ ] Add the row after Launch at Login in General Settings, with record,
  current assignment/unassigned, clear, and inline feedback. Use localized
  labels and accessibility labels, existing SettingsRow geometry, and a
  compact control. No new Settings page or window.
- [ ] Add layout-aware key display using TIS/UCKeyTranslate only with a retained
  layout data owner; provide clear special-key names and a safe fallback.
  Handle keyboard layouts lacking Unicode data and layout changes without
  introducing always-on polling.
- [ ] Translate new keys in all 12 existing lproj files. Required concepts:
  Open status panel, record/change shortcut, not set, clear, recording
  instruction, invalid combination, shortcut unavailable, registration failed.
  Treat registration conflict and generic failure honestly.
- [ ] Run
  `bash scripts/test.sh 'ShortcutRecorderTests|ShortcutKeyLabelTests|SettingsViewTests|SettingsWindowControllerTests|LocalizationTests|LocalizationParityTests'`.

## Task 4: Existing panel routing, app ownership and final verification

**Interfaces:** Add `StatusBarController.openPopoverFromShortcut()`; consume
it in the environment-owned controller's action. Keep mouse and Dock toggles
unchanged. Share `presentPopover` with its refresh/visibility/content lifetime.

- [ ] Write failing presentation policy tests: already-open closes,
  menu bar uses its visible anchor, Dock-only uses a clamped fallback on the
  pointer's screen, missing/offscreen anchor uses fallback, screen boundaries
  and negative origins work. Existing Dock mouse toggle tests still pass.
  Prefer a pure anchor policy plus integration check; do not label pure
  geometry tests real multi-monitor/full-screen acceptance.
- [ ] Implement open/close toggle routing, fallback anchor
  creation/cleanup using the controller's existing owned invisible-window
  pattern. Ensure no orphan anchor window when the panel closes or is trimmed.
  Do not use Dock tile geometry for keyboard activation without a Dock click.
- [ ] Construct one global controller in AppEnvironment.live, inject it into
  SettingsWindowController/SettingsView/GeneralSectionView, and start/stop it
  with AppEnvironment. The callback weakly references the status controller.
- [ ] Run
  `bash scripts/test.sh 'GlobalShortcutControllerTests|StatusPanelShortcutTests|ShortcutRecorderTests|ShortcutKeyLabelTests|PopoverLifecycleTests|DockPopoverAnchorTests|SettingsViewTests|SettingsWindowControllerTests'`.
- [ ] Write `docs/status-panel-global-shortcut.md` with setup/clear instructions,
  toggle behavior, default unassigned, conflict limitations, and a manual
  acceptance matrix for another focused app, rebind, restart, cancel, clear,
  conflict, Dock-only, hidden menu bar, multiple screens, fullscreen, Ventura.
  Mark each native check NOT RUN until genuinely exercised.
- [ ] Fetch `origin/main`, record `git merge-base HEAD origin/main` and
  `git rev-list --left-right --count HEAD...origin/main`. If it advanced,
  report before integrating shared changes; do not rebase or overwrite work.
- [ ] Run `bash scripts/verify-local.sh full` on the final integrated tree,
  with logs in `.build/local-verification/`. Diagnose failures; do not bypass,
  relax, skip, blindly retry, or broaden product scope.
- [ ] Finish with `git diff --check`; report changed files, exact tests and
  counts, full-profile status, base/head/branch, native checks NOT RUN, known
  limitations, and the uncommitted diff ready for parent review.

## DeepSeek startup instruction

Implement this plan in the assigned worktree, sequentially and without further
approval. Read the linked spec and repository rules first. You own product code,
focused tests, local verification, and the usage/acceptance document; the parent
owns the plan/spec and final review. Use the executing-plans approach inline,
without spawning additional agents. Track progress and test evidence in
`/tmp/status-trio-global-shortcut-deepseek-report.md`, and send concise progress.
Do not commit, push, merge, release, change real user preferences, or install/
launch a build over the production app. Return the final diff and evidence.

## Execution record

- [x] DeepSeek V4.1 Flash (`auto/deepseek-v4.1-flash`, `max`) implemented Tasks
  1 through 4 in this worktree; all product changes remain uncommitted.
- [x] Original-base full verification passed. Its evidence applies to
  `7071fbe90e1806ff757d630aaecbccf03b88a7d9` plus the uncommitted shortcut work.
- [x] After upstream advanced, the feature branch was fast-forwarded to
  `9c9968dd1df77427b485ead8b066a4d0befaabee`; the saved changes reapplied
  without conflicts. Both overlapping files retained the upstream changes.
- [x] Integrated focused verification passed: 87 XCTest and 17 Swift Testing
  tests, including `StatusBarAccessibilityUpdateTests` and
  `StatusBarBackingScaleTests`.
- [x] Full verification on the integrated tree passed after the review fixes:
  15 PowerHelper plus 1,843 StatusTrioCore XCTest tests, 7 skipped, 0 failures;
  722 Swift Testing tests in 107 suites, 0 failures.
- [x] Independent read-only review found two Important findings and one Minor
  finding. All three fixes were re-reviewed and closed with no new findings;
  final scoped verdict: `Ready to merge: Yes`.
- [x] `origin/main` advanced after verification to
  `48f76bf8a1e0f7d50af99eef7e388ed8d0e8318a` by one test-only commit adding
  `BoundedProcessDrainTests.swift`. It does not overlap this feature. The
  feature branch remains uncommitted and unmerged because commit, merge, and
  push were not authorized.

Native global keyboard delivery, WindowServer focus, multiple displays,
full-screen Spaces, interactive layout switching, and macOS 13 runtime remain
NOT RUN. Caps Lock, relaunch persistence, and real conflict handling also
remain NOT RUN. Detailed execution evidence is in
`/tmp/status-trio-global-shortcut-deepseek-report.md`; the test bundle's
`.prohibited` activation policy is documented there rather than treated as a
passing real-focus test.
