# Icon Designer Legacy Behavior and Demand Baseline

Date: 2026-10-09 (recorded from the local XCTest environment).
Source revision: `2ec5b81ce1f4731dca4d1f2ed61bfdbbb53e426e`.
Purpose: pin observable Classic composition before changing the icon configuration and settings UI.

## Composition behavior pinned by tests

`IconLegacyCompatibilityTests` records these existing `IconPresentationMapper` outputs as fixed expected values:

- A present battery percentage in Center wins before pinned Bluetooth replacement and a Wi-Fi no-internet state.
- A configured Bluetooth symbol override remains visible when the current output device is absent (the pinned-symbol legacy behavior).
- Ethernet defaults to the wired-port primitive; Wi-Fi off maps to `wifi.slash`.
- Existing battery and volume stroke settings independently affect Outer Ring and Footer.
- Classic battery output keeps charging bolt, connected-full plug, critical battery percentage, absent-battery 100% behavior, and low-power semantic color. Classic volume output is four dots; arc remains supported.
- Hotspot, temporary connection, and shared connection retain their respective personal-hotspot, screen-wedge, and arrow-wedge center mappings.

These tests assert concrete `IconSceneState` values, not only equality between two mapper executions.

## Existing data-demand ownership observed in source

- `SystemStatusStore.bindMobileBatterySettings` gates Apple/mobile battery reading on `showsBluetoothBatteryLevels`, `showsAppleDevicesAndBattery`, and `showsBluetoothDeviceList`; actual background refresh additionally follows the explicit refresh preference and interval.
- The same store configures nearby BLE selection/visibility and background refresh from explicit settings, selected IDs, visibility, and the configured refresh interval. No icon Designer demand exists at this baseline.
- `BluetoothDeviceController.requestBatteryLevels(_:)` and `releaseBatteryLevels(_:)` maintain tokenized claims. Read/event ownership starts on the first claim and is cleared/stopped after the last claim is released.
- The currently visible Bluetooth status view and panel actions are explicit battery-level claim owners. No claim is inferred from constructing an icon presentation model.
- `IconPresentationViewModel` remains the existing production presentation path; this baseline does not add a parallel status stream or polling loop.

## Measurements and manual validation

- Release idle CPU and wakeups over a five-minute interval: **not measured** in this task; no zero-overhead claim is made.
- Bluetooth scan/reader activity on physical hardware: **not measured** in this task.
- macOS 13 UI, VoiceOver, appearance variants, and hardware states: **not manually validated** in this task.
- The behavior tests verify the pure mapping contract; they do not claim renderer pixel parity or hardware lifecycle validation.

## Verification

- `swift test --filter IconLegacyCompatibilityTests` — 6 tests passed, 0 failures.
- Full `swift test` and `swift build -c release` are recorded in the execution ledger after completion.
