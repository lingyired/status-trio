# Dual-distribution product UI verification

Date: 2026-10-24 (Asia/Shanghai)

This record covers the Phase E product UI and action wiring only. It is focused
test evidence, not a full-suite, Store-build, signed-sandbox, hardware, or
visual UI acceptance result.

## Provenance

- Worktree:
  `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`
- Branch: `codex/dual-distribution-platform`
- Tested `HEAD`: `a4c9f34a1c9ade2c1116f02781ea549521eaa370`
- Worktree state at test time: dirty integration tree. The B/E policy fix is
  committed; later phase/documentation changes remain uncommitted.
- Toolchain: Xcode 27.0 (`27A266a`), Apple Swift 6.4
  (`swiftlang-6.4.0.34.1`), macOS 27.0.1 (`26A434`).

The dirty worktree is shared by the A-F integration effort. The tested SHA is
not the tested source state by itself; the focused command compiled the current
worktree.

## Focused command

```sh
bash scripts/test.sh 'DistributionCapabilityPolicyTests|DistributionCapabilityUIIntegrationTests|DistributionLocalizationTests|SettingsViewTests|AboutActionsLayoutTests|PanelActionRoutingTests|SettingsRowHitAreaTests|OutputDeviceListeningModeRowTests|PublicBluetoothPairedDeviceReaderTests|PublicAccessoryBatteryReaderTests|CoreWLANKnownNetworkProviderTests'
```

Result: exit `0`.

- Forbidden actor-isolated method-reference check: pass.
- XCTest: `43/43` passed in the final focused rerun (including 6 new policy
  regressions).
- Swift Testing: `33` tests in `4` suites passed.
- `PublicBluetoothPairedDeviceReaderTests`: pass.
- `PublicAccessoryBatteryReaderTests`: pass.
- `CoreWLANKnownNetworkProviderTests`: pass.
- `DistributionLocalizationTests`: pass across the 12 shipped languages.
- `SettingsViewTests`: `8/8` pass, including the two call sites that previously
  lacked the injected capability policy.

There were no public-reader failures. The earlier localization fixture drift
was resolved before this run; Phase E did not edit the translation files,
`LocalizationKey.swift`, or `DistributionLocalizationTests.swift`.

## Capability behavior

| Surface | Store behavior | Direct behavior |
| --- | --- | --- |
| Runtime default | `.runtimeDefault` resolves the compiled channel to `PlatformCapabilities.appStore`; it is not an empty-record fail-open default | Resolves to the explicit Direct capability contract |
| About | Low-emphasis compile-time channel identity plus repository link; no cross-channel download, paid, full-version, or purchase CTA | Retains the existing project link |
| General updates | System-managed update copy replaces the Sparkle toggle | Existing Sparkle controls remain |
| Privileged helper | Helper control hidden; Settings does not probe the helper on open | Existing helper lifecycle and refresh remain |
| Charge limit | Private system-reader action hidden; localized distribution reason shown; public threshold setting remains | Existing system charge-limit action remains |
| Bluetooth radio power | Private control hidden and action guarded | Existing control and confirmation remain |
| Apple listening mode | Private preview/control hidden; synthetic rows and preview task identity are suppressed at the ViewModel data source; action guarded | Existing preview/control remains |
| Internet Sharing icon option | Removed because the Store detector is unavailable | Existing option remains |
| Huawei listening mode | Remains runtime-driven and is not disabled by Apple capability state | Existing behavior remains |
| Mobile battery helper | Public Apple/IOBluetooth/BLE feature remains available; helper-backed background controls are hidden with a localized evidence reason | Existing helper-backed behavior remains |
| Public readers | `notVerified` remains evidence state, not `available`; UI does not globally disable public IOBluetooth, BLE, CoreWLAN, CoreAudio, or IPowerSources paths | Same evidence semantics |

`permissionRequired` and `temporarilyUnavailable` stay runtime gates. Public
`notVerified` capabilities do not masquerade as available and are not turned
into blanket distribution bans.

The Apple-devices master toggle is intentionally not globally disabled in the
Store build because it also controls public named-device and BLE discovery.
Only controls whose implementation is absent are removed. This keeps the public
candidate path available while preventing the helper action from becoming a
dead button.

## Action guards

`StatusPanelActions` receives the same policy as the UI.

- Bluetooth radio writes return before the command when the capability is
  blocked.
- Apple listening-mode writes are blocked; Huawei writes address their separate
  capability.
- Store builds do not synthesize Apple listening-mode preview devices from a
  persisted preview setting.
- The Direct policy still permits both synthetic preview creation and helper
  refresh; focused tests pin both sides.

`SettingsWindowController.show()` skips `helper.refresh()` when the privileged
helper capability is blocked.

## Focused regression tests

`DistributionCapabilityUIIntegrationTests` uses the real settings/action
composition and a recording helper facade. It verifies:

- a Store policy blocks synthetic Apple listening-mode preview before it reaches
  `BluetoothListeningModeController`;
- a Direct policy still produces the existing preview;
- opening Store Settings does not call the helper facade;
- opening Direct Settings still refreshes an available helper once.

`DistributionCapabilityPolicyTests` also pins the Store default to the populated
`PlatformCapabilities.appStore` contract, checks that private controls are
blocked, and checks that public Bluetooth readers and Huawei remain
runtime-driven.

## Relevant paths

- `Sources/StatusTrioCore/Distribution/DistributionCapabilityPolicy.swift`
- `Sources/StatusTrioCore/App/AppEnvironment.swift`
- `Sources/StatusTrioCore/Presentation/Panel/StatusPanelActions.swift`
- `Sources/StatusTrioCore/UI/StatusBarController.swift`
- `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`
- `Sources/StatusTrioCore/UI/Settings/AboutSectionView.swift`
- `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift`
- `Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift`
- `Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift`
- `Sources/StatusTrioCore/UI/Settings/SettingsView.swift`
- `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift`
- `Tests/StatusTrioCoreTests/DistributionCapabilityPolicyTests.swift`
- `Tests/StatusTrioCoreTests/DistributionCapabilityUIIntegrationTests.swift`

No renderer, menu-bar icon scene, or Dock icon scene was changed by this UI
slice.

## NOT RUN

- Full `bash scripts/verify-local.sh full` on the final integrated tree.
- App Store target compilation, archive, signing, bundle audit, and sandbox
  runtime from this Phase E change.
- Actual Direct and Store About, General, Battery, and Bluetooth panes at normal
  and compact window sizes.
- Bluetooth allow/deny/revoke, powered-off, sleep/wake, device removal, and
  offline states in a signed Store build.
- Real public IOBluetooth, BLE, CoreWLAN, CoreAudio, IOPS, or Huawei hardware.
- macOS 13 Ventura runtime and current-macOS interactive verification.
- Visual confirmation that disabled/hidden controls and localized reasons read
  correctly in all 12 languages.

These remain separate acceptance items and are not inferred from the focused
test run.
