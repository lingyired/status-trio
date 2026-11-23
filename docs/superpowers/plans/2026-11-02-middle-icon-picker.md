# Middle Icon Picker Implementation Plan

> **For agentic workers:** Execute inline with the current model using executing-plans. User explicitly requested a new branch/worktree and current-model execution; do not delegate implementation.

**Goal:** One middle-content selector in App Icon settings, explicit network/Bluetooth/input/battery/power sources, and one network-outage override for every source.
**Spec:** `docs/superpowers/specs/2026-11-02-middle-icon-picker-design.md` (approved).
**Architecture:** Keep shared IconSceneState and existing renderers. ConnectionIconOptions owns the exclusive source and outage priority. BluetoothAudioIconOptions owns only device glyph/scale/volume appearance. SettingsStore performs one-time migration, lifecycle subscriptions follow the exclusive source.
**Stack:** Swift 6, SwiftUI/AppKit, XCTest, macOS 13+.
**Base:** fa6064a491301824c26471bbbd53adbd75fb1e9f = origin/main at branch creation.

## Global constraints

- Work only in feature/middle-icon-picker linked worktree; do not copy other uncommitted main changes.
- Outage override applies to every source including pinned Bluetooth devices and power/battery. Existing battery/power users gain default true per approved design (intentional change).
- Preserve wired connectivity semantics with `StatusMappings.isNetworkOffline`; Wi-Fi off while Ethernet works is not offline.
- Missing input source falls back directly to network; missing Bluetooth output falls back to network; preserve power sample fallback.
- Demand owners must stop on disappearance/source change. Do not auto-request Bluetooth authorization on page appearance or source selection; explicit grant action only.
- Keep wifi and Bluetooth scaling controls in their existing pages per approved spec.
- All 12 localizations and affected docs/guide examples must match new paths.
- Run full local verification and icon alignment/parity/charging regressions; no release/merge.

## File structure

- Modify Models/ConnectionCenterSource.swift and ConnectionIconOptions.swift: explicit sources and one outage setting.
- Modify Models/BluetoothAudioIconOptions.swift and StatusMappings.swift: Bluetooth appearance and availability only; no competing source/priority flags.
- Modify Settings/SettingsStore.swift and +IconAppearance.swift: migration, persistence and atomic combined appearance delivery.
- Modify Store/SystemStatusStore.swift: selected-device demand follows exclusive source.
- Modify Presentation/Icon/IconPresentationMapper.swift: source switch, shared network fallback, outer outage override.
- Create UI/Settings/MiddleIconSettingsGroup.swift: selector + conditional Bluetooth child view with scoped demand, permission empty states and existing device/audio menus.
- Modify UI/Settings/AppIconSectionView.swift and SettingsView.swift: group and live input-source preview.
- Modify UI/Settings/NetworkSectionView.swift and BluetoothSectionView.swift: remove duplicate source controls.
- Modify UI/IconGuideView.swift and test-sheet fixtures: explicit scene source overrides.
- Modify Localization/LocalizationKey.swift and Resources/*.lproj/Localizable.strings: 12-language copy.
- Update affected XCTest fixtures, settings/lifecycle/publisher/render/guide tests, README text and docs where old setting path is described.

### Task 1: Exclusive source, storage migration, shared scene and demand

**Interfaces:** ConnectionCenterSource = network/bluetoothDevice/inputSource/batteryPercentage/power; ConnectionIconOptions.prioritizesNetworkErrors; SettingsStore.prioritizesNetworkErrors persisted key of same name. Remove legacy live store properties and Bluetooth source/priority options; keep old defaults constants only for migration.

- [ ] Add migration tests using raw persisted values, including old automatic+replacement, pinned device retention, old priority values, explicit numeric sources, invalid values and repeat launch after manual selection.
- [ ] Add real mapper tests that fail under current code: outage overrides power/battery, override off preserves value, wired+Wi-Fi-off remains numeric, input missing goes to network rather than hidden Bluetooth selection.
- [ ] Run focused tests via scripts/test.sh, observe red before implementation.
- [ ] Implement source switch, migration and unified publisher; convert Bluetooth demand to source equality and remove duplicate network priority logic.
- [ ] Update existing behavioral tests/fixtures to explicit source, preserving test intent and exact geometry fingerprints. Extend publisher tests to assert a single coherent update on source change.
- [ ] Run focused migration/presentation/publisher/lifecycle/renderer tests and resolve failures by root cause.
- [ ] Commit coherent model/presentation/lifecycle work (UI will be integrated before commit if compilation requires it).

### Task 2: Consolidated App Icon settings and localization

**Interfaces:** MiddleIconSettingsGroup(store:statusStore:); AppIconSectionView optional InputSourceController for live preview. Bluetooth child appears only for selected source, observes BluetoothDeviceController and holds/releases BluetoothSettingsDemandToken.

- [ ] Update settings UI tests to verify source controls live in App Icon and conditional device/audio options, outage option with numeric modes, denied/empty cases where feasible.
- [ ] Watch focused tests fail, then implement native grouped controls using existing SettingsGroup/MenuRow/ToggleRow.
- [ ] Move device source/audio UI out of Bluetooth page; use explicit grant button/denied system-settings action in the child. No automatic permission request.
- [ ] Pass input source controller to App Icon live preview.
- [ ] Add new App Icon localization keys, remove dead network/Bluetooth selector keys, translate 12 languages; update fixtures, guide source overrides and README setting paths.
- [ ] Run SettingsViewTests, localization regression, Bluetooth permission/demand and preview/guide suites.
- [ ] Commit UI/localization integration.

### Task 3: Final integrated verification and handoff

- [ ] Fetch origin/main and record current base/ahead status; inspect shared-file changes on original checkout without modifying them.
- [ ] Review complete diff for stale source flags, migrations, demand ownership, menu bar/Dock cache inputs and geometry preservation.
- [ ] Run bash scripts/verify-local.sh full on final integrated tree. Run explicit Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests|ChargingEffectRenderingTests if not already covered. Collect all outputs and report actual scope.
- [ ] For live UI validation use background-ui-testing skill/launcher and available instance-scoped CU only; if none connected record BLOCKED (no Computer Use provider), do not use global input. Runtime macOS13 remains NOT RUN unless performed.
- [ ] Perform whole-branch code review with current model (user current-model constraint); fix material findings with tests and rerun affected checks.
- [ ] Commit verification notes and final changes, leave branch/worktree available; do not merge or release.
