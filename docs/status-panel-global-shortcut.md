# Status panel global shortcut

Status Trio can open its existing status panel with one configurable global
keyboard shortcut. The shortcut is unassigned by default.

## Set up or change the shortcut

1. Open **Settings > General**.
2. Choose the record control next to **Open status panel**.
3. Press a key together with Command, Control, or Option. Shift may also be
   held. Escape cancels; Delete or Forward Delete clears the assignment.
4. Press the shortcut from another app to open the same status panel.
   Press it again, or click the menu bar item, to close the panel.

The assignment is saved immediately after Carbon accepts it. It is restored
after relaunch. Use the explicit clear control to disable keyboard opening.

While recording, the saved shortcut is temporarily unregistered so pressing it
does not open the panel instead of entering the recorder. Cancel, focus loss,
pane removal, or closing Settings ends recording and restores the saved
registration. If a replacement conflicts, the previous assignment remains
stored; it is registered again when recording ends.

Recording fails without replacing the saved shortcut when the input is
structurally invalid, Carbon reports an exclusive conflict, or Status Trio
recognizes a known system/input-method combination. The recorder stays active
and shows localized feedback. `Option-Space` is currently rejected as a known
input-method conflict because input methods such as WeType can consume it
before Carbon receives it, even though Carbon registration succeeds.

Exhaustive preflight detection is not possible. macOS provides no public API
that enumerates every shortcut owned by the system, input methods, or
third-party applications, and some owners intercept keys after Carbon
registration. A combination that registers successfully can therefore still
be consumed by another component. Status Trio reports failures it can establish
reliably instead of claiming that every unsupported combination was detected.

## Behavior and limitations

- Shortcut activation toggles the panel. If it is already open, the same
  shortcut closes it. Mouse and Dock click behavior remains a toggle.
- With a usable menu bar item, the shortcut uses that item as the popover
  anchor. In Dock-only mode, or when the menu bar item has no on-screen frame,
  the pointer selects the target screen and a clamped top-center fallback
  anchor is used. Dock tile geometry is not used for keyboard activation.
- Registration uses Carbon `RegisterEventHotKey` with
  `kEventHotKeyExclusive`. No Accessibility, Input Monitoring, event tap, new
  package, polling loop, or key logging is added.
- Carbon reports `eventHotKeyExistsErr` when another exclusive Carbon owner
  already has the combination. It cannot detect every shortcut implemented by
  macOS, an input method, a non-Carbon framework, or another application's
  private mechanism. Such an owner may still receive or override the
  combination after registration succeeds.
- A shortcut saved by an older build that is now recognized as an input-method
  conflict is not registered at launch. Settings reports the conflict while
  retaining the assigned value so the user can replace or clear it.
- The displayed key name follows the active keyboard layout where layout Unicode
  data is available. Special keys use fixed names or symbols, and unknown key
  codes have a safe fallback.

## Verification

The automated coverage is local evidence for validation, persistence,
transactional replacement and rollback, stale-event rejection, recording
cancellation, window focus loss, localization parity, anchor selection, and
closing an already-open panel. It is not native keyboard, WindowServer,
multi-display, or OS-compatibility acceptance.

The implementation started from `7071fbe90e1806ff757d630aaecbccf03b88a7d9`
and was integrated with `origin/main` at
`9c9968dd1df77427b485ead8b066a4d0befaabee`. The integrated focused check also
includes the upstream status-bar accessibility and backing-scale regressions.

Run the focused tests with:

```bash
bash scripts/test.sh 'StatusBarAccessibilityUpdateTests|StatusBarBackingScaleTests|GlobalShortcutControllerTests|HotKeyActivationGateTests|StatusPanelShortcutTests|ShortcutRecorderTests|ShortcutKeyLabelTests|StatusPanelShortcutPresentationPolicyTests|StatusBarMemoryPressureTests|AppEnvironmentTelemetryLifecycleTests|PopoverToggleGateTests|PopoverContentRetentionTests|DockPopoverAnchorTests|SettingsViewTests|SettingsWindowControllerTests|LocalizationTests|LocalizationParityTests'
```

### Manual acceptance matrix

Every row remains **NOT RUN** until exercised on a built, non-production test
bundle with the named host and input.

| Environment | Action | Expected result | Status |
| --- | --- | --- | --- |
| Current macOS, another app focused | Press an assigned shortcut | The existing Status Trio panel opens in front | NOT RUN |
| Current macOS | Press the shortcut while the panel is open | The panel closes | NOT RUN |
| Current macOS | Rebind while another app is focused | The old combination stops and the new one opens the panel | NOT RUN |
| Current macOS | Relaunch the app | The saved assignment is active without re-recording | NOT RUN |
| Current macOS | Escape, click another app, switch panes, or close Settings while recording | Recording ends and the saved combination works again | NOT RUN |
| Current macOS | Choose clear, then relaunch | No shortcut is registered and no panel opens from the old key | NOT RUN |
| Current macOS | Assign an exclusively owned shortcut | The previous assignment stays, and localized conflict feedback appears | NOT RUN |
| Current macOS | Launch with a saved conflicting shortcut | The app remains usable and reports the unavailable shortcut | NOT RUN |
| Current macOS with WeType or another input method that owns `Option-Space` | Record `Option-Space` | Recording stays active and localized input-method conflict feedback appears; the previous assignment remains | NOT RUN |
| Current macOS | Repeatedly toggle with the shortcut from another app | The panel follows the menu bar anchor and never moves to the bottom-left | NOT RUN |
| Dock-only placement | Press the shortcut from another app | The same panel opens on the pointer screen | NOT RUN |
| Auto-hidden or unavailable menu bar | Press the shortcut | The fallback anchor opens the panel on a visible screen | NOT RUN |
| Two displays with negative or mixed origins | Move the pointer and press the shortcut | The panel opens on the pointer display and remains clamped on-screen | NOT RUN |
| Current macOS full-screen Space | Press the shortcut | The panel appears on the active Space as designed | NOT RUN |
| Non-Latin and layout-switch scenarios | Record, change layout, and activate | The label refreshes without polling and the stored key code still works | NOT RUN |
| Caps Lock on | Record and activate | Caps Lock does not alter the stored combination | NOT RUN |
| macOS 13 Ventura | Repeat the current-macOS rows | The feature behaves the same on the minimum supported OS | NOT RUN |

Do not infer these runtime results from XCTest, Swift Testing, source
inspection, or a successful release build.
