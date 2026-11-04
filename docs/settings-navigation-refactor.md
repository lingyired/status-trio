# Settings navigation: two-level sidebar

This document records the information-architecture refactor of the Settings
window and the local regression evidence gathered while implementing it. The
change follows `status-trio-settings-navigation-refactor-plan.md`; global search
is intentionally **not** part of it and remains a separate task.

## Goal

Settings had grown to nine flat panes, and the three densest ones (Battery,
Audio, Bluetooth) plus App Icon buried related controls far down a single
scroll. The refactor keeps the visual style, the `SettingsStore` schema, the
window controller behaviour and macOS 13 support, and adds one optional second
sidebar level only for the categories that need it.

## Shape

Nine categories keep their existing order and titles:

```text
App Icon      → Placement & Size | Ring & Dock | Middle Icon
Battery       → Icon Display | Colors & Animation | Charge Management | Power & Energy
Network       (single pane)
Bluetooth     → Display & Preview | Devices & Battery | Panel & List
Audio         → Display & Interaction | Device Management | External Volume
Brightness    (single pane)
Status Panel  (single pane)
General       (single pane)
About         (single pane)
```

Interaction rules:

- Clicking a category expands it and opens its default (or last visited) leaf.
  Clicking another category collapses the previous one; only one category is
  expanded at a time.
- Only a leaf paints the selected pill. Its parent category keeps a medium-weight
  label as context, so two rows never compete for the highlight.
- Single-pane categories behave exactly as before.
- The sidebar scrolls on its own; the detail page keeps its own scroll and
  starts at the top when the leaf changes.
- Category and leaf rows are native buttons with `isSelected` accessibility
  semantics; the animation honours Reduce Motion.

## Code map

| Concern | File |
| --- | --- |
| Single selected route (category + leaf, defaults, remembered leaf, deep links) | `Sources/StatusTrioCore/UI/Settings/SettingsNavigationModel.swift` |
| Leaf identity, parent section, sidebar titles | `Sources/StatusTrioCore/UI/Settings/SettingsSubtopic.swift` |
| Sidebar + detail dispatch | `Sources/StatusTrioCore/UI/Settings/SettingsView.swift` |
| Leaf pages (each section view takes an optional `subtopic`) | `BatterySectionView.swift`, `AudioSectionView.swift`, `BluetoothSectionView.swift`, `AppIconSectionView.swift` |
| Deep-link API (`show(subtopic:)`, `show(section:subtopic:)`) | `SettingsWindowController.swift` |

Each section view keeps **one** set of group builders and renders a subset for a
leaf. There is no second implementation of the rows; the legacy full-pane layout
is still produced when `subtopic == nil` (used by tests and by any caller that
does not drive the two-level sidebar).

The new leaf labels live under `settings.subtopic.*` and are translated in all
twelve shipped languages (`en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `de`, `fr`,
`es`, `it`, `pt-BR`, `ru`, `ar`), covered by `LocalizationParityTests`.

## Invariants that must not drift

- **Store untouched.** No `SettingsStore` key, default, range or setter changed;
  the pages only move where the same bindings are shown.
- **Bluetooth listener lifetime.** The `beginBluetoothSettingsDemand()` /
  `endBluetoothSettingsDemand()` pair stays on the Bluetooth category container
  (a concrete stable `VStack`), never on a leaf. Switching Display/Devices/Panel
  must not tear down and rebuild the listener. `bluetoothDevices` and
  `appleDeviceDiscovery` stay observed by the container.
- **Audio refresh.** `statusStore.refreshAll()` stays on the Audio container and
  is not re-run when switching leaves.
- **Permission state.** The Bluetooth permission banner appears on the
  Display-and-Preview and Panel-and-List pages (the pages that depend on it);
  the Wi-Fi name-access notice stays on the Network pane.
- **Icon preview.** The pinned `StatusIconPreviewCard` is shown on the pages that
  configure how the icon is drawn; pages that are pure controls (charge
  management, power and energy, device management, external volume, device and
  battery, panel and list) reclaim that vertical space.
- **Conditional controls are unchanged.** `BatteryStatusColorsView` still allows
  editing saved colours while status colouring is off; the full-ring threshold
  moved to Icon Display while `chargeToFullRestoreLimit` stayed in Charge
  Management; the Charge Management page shows an explicit unavailable notice
  instead of an empty card when the platform has no override.
- **Scroll direction** remains owned by `PopoverSectionView`; it is not copied
  into Audio.
- **Deep links.** The old `show(section:)` still opens a category (now its
  default leaf). `show(subtopic:)` opens a specific leaf; a leaf belonging to a
  different category is ignored rather than rendering the wrong page.
- **Window controller untouched otherwise.** Activation policy, background UI
  testing, resurface-on-permission, preview resource observation and closing
  behaviour are unchanged.

## Local evidence

Commands are the repository entry points; no test was deleted, skipped or
weakened to make a run green.

```bash
bash scripts/test.sh                       # full Swift suite
bash scripts/test.sh 'SettingsViewTests'
bash scripts/test.sh 'SettingsNavigationModelTests|LocalizationParityTests'
bash scripts/verify-local.sh full
```

Results on this branch (`feat/settings-navigation-refactor`, based on
`origin/main` `5ff0cff2`):

- Full Swift suite after the refactor: 919 tests, 0 failures (visible AppKit UI
  suites skipped by their existing opt-in condition).
- `SettingsViewTests`: 16 tests, 0 failures, including the new leaf mapping,
  leaf-title localization, per-leaf render, two-level routing shape and
  Bluetooth-demand ownership tests.
- `SettingsNavigationModelTests`: 10 tests, 0 failures.
- `LocalizationParityTests`: all twelve languages agree with the English key set.
- `verify-local.sh full`: exit 0 (full Swift suite, Release build, non-Universal
  ad-hoc app bundle and native compatibility/dependency/release-pipeline
  contracts). This is local evidence only; runtime acceptance on macOS 13 and
  current macOS, signing, notarization, DMG and Universal packaging are not
  covered here.

## Follow-ups

- Global Settings search: separate task. It should index the stable leaf routes
  and control anchors introduced here rather than re-splitting pages later.
- A future hardware-monitoring category (CPU/GPU/temperature/fans) should be a
  new top-level category instead of extending Battery → Power & Energy.
