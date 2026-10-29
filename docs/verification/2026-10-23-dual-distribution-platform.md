# Dual-distribution platform boundary verification (2026-10-24)

## Scope

This record covers Phase B platform injection and Store-safe source membership.
It does not claim the Store application target, sandbox runtime, hardware
support, signing, or packaging exists yet; those belong to Phases C/D/F.

The canonical Store exclusion list is:

```text
AppStore/direct-only-sources.txt
```

The Direct entry remains the existing SwiftPM `StatusTrioCore` and
`StatusTrio` targets. `Package.swift` is unchanged. Store is expected to compile
the same shared source directory into an independent `StatusTrioCore` framework
while removing every path in that list.

## Platform interfaces

### Updates

- `UpdateServicing`, `UpdateControlState`, and observable `UpdateStateFacade`
  are shared and contain no Sparkle import.
- Direct injects `UpdaterManager.shared`. The Direct factory explicitly
  configures it with the same `AppActivationPolicy` used by manual update
  presentation, the Settings window, and Dock activation.
- Store injects `SystemManagedUpdateService`; it exposes no manual check,
  automatic-update binding, download, or install action.
- `UpdaterManager`, Sparkle fallback delivery, fallback user driver, and manual
  update presentation remain Direct-only.

### Privileged helper and private power

- Shared UI observes `PrivilegedHelperFacade`, not
  `PrivilegedHelperManager.shared`.
- `AppEnvironment` injects the helper facade into startup synchronization,
  Status Bar/menu actions, the popover, and the Settings window.
- Direct injects the full `PrivilegedHelperManager`. Store injects
  `UnsupportedPrivilegedHelperService`.
- Root registration, `PowerHelperProtocol`, XPC, and private mach lookup are
  excluded from the Store source closure.
- Public low-power state remains in the shared battery snapshot. Store can
  display that read state but cannot invoke the privileged write path.

### Hardware readers

- `SystemPowerReading` and `SystemChargeLimitProviding` are shared protocols.
- `UnavailableSystemPowerReader` and `UnavailableSystemChargeLimitProvider` are
  Store-safe defaults.
- AppleSMC `SystemPowerReader`, powerd charge-limit parsing, MobileBattery helper
  execution, and bounded subprocess execution are Direct-only.
- Public IOKit battery and charging models remain shared.
- Direct composition explicitly injects
  `AppleDeviceDiscoveryController(reader: mobileBatteryReader())`; Store uses
  `UnavailableMobileBatteryReader` and neither packages nor launches the
  MobileBattery helper as a baseline dependency.
- Public IOBluetooth/CoreBluetooth connection paths and the Huawei RFCOMM/SPP
  vendor transport remain shared. Huawei support is marked `notVerified` for
  Store rather than removed or treated as an Apple-private API.
- Apple private IOBluetooth radio symbols, private CoreAudio HAL selectors,
  endpoint/listener discovery, and the network-sharing detector are Direct-only.
- Direct Wi-Fi composition explicitly re-injects
  `SystemInternetSharingDetector`; safe defaults use `nil`.
- Public CoreWLAN status, scan, and power paths remain shared. `networksetup`
  known-network enrichment is Direct-only.
- `system_profiler`, `pmset`, and `networksetup` readers are Direct-only. They
  are not Store baseline dependencies.

### DDC

The DDC boundary is owned by the parallel DDC slice and recorded separately in
`docs/verification/dual-distribution-ddc.md`.

The shared volume monitor depends only on `DDCVolumeCoordinating` and the
coordinator factory. Direct supplies the private transport factory; Store
supplies `UnavailableDDCVolumeCoordinator`. Public CoreAudio output volume and
device selection remain available in both compositions.

### Composition and resources

- Direct composition lives in
  `Sources/StatusTrioCore/Platform/DirectAppEnvironment.swift` and is excluded
  from Store.
- Store composition lives in
  `AppStore/Platform/StoreAppEnvironment.swift` and does not fall through to
  Direct factories.
- Shared `AppEnvironment.makeLive` owns start/stop and UI/controller lifecycle,
  but receives updater, helper, capabilities, settings, and stores from the
  distribution root.
- Store resource lookup lives in
  `AppStore/Platform/StoreResourceBundle.swift`. Its `Bundle.module` equivalent
  anchors to `StatusTrioResourceBundleAnchor` in the Store Core framework; it
  does not copy localized resources.

## Store default behavior

| Capability | Store source behavior | Runtime result |
| --- | --- | --- |
| Updates | `SystemManagedUpdateService` | No Sparkle check or preference |
| Privileged helper | `UnsupportedPrivilegedHelperService` | Unavailable, no registration or XPC |
| Charge limit | `UnavailableSystemChargeLimitProvider` | No private powerd plist read |
| System power detail | `UnavailableSystemPowerReader` | No AppleSMC access |
| Mobile battery helper | `UnavailableMobileBatteryReader` | Not launched or packaged |
| Apple listening modes | unavailable HAL/endpoint/listener | No private 4CC access |
| Bluetooth radio write | unavailable backend | Read-only/public paths remain |
| DDC | unavailable coordinator | Public CoreAudio volume remains |
| Wi-Fi sharing detector | `nil` | CoreWLAN status remains |
| Known networks | empty provider by default | CoreWLAN scan remains |
| Bluetooth device/battery | fail-closed readers by default | D will inject public readers |

`PlatformCapabilities.appStore` uses stable reason identifiers only:

```text
distribution.system-managed-updates
distribution.private-ddc
distribution.private-hal
distribution.private-bluetooth
distribution.privileged-helper
distribution.private-power
distribution.undocumented-detector
distribution.helper-not-packaged
distribution.public-vendor-transport
distribution.provider-pending
```

UI localization remains an E responsibility; the platform model contains no
hard-coded English unavailable message.

## Direct preservation

`DirectPlatformFactory` explicitly retains:

- `SystemChargeLimitReader`
- `SystemInternetSharingDetector`
- `NetworksetupWiFiKnownNetworkProvider`
- `SystemProfilerBluetoothPairedDeviceWorker`
- `SystemProfilerBluetoothBatteryWorker`
- `PmsetAccessoryBatteryWorker`
- `SystemPowerReader`
- `MobileBatteryHelperReader`
- `AppleDeviceDiscoveryController(reader: mobileBatteryReader())`
- `IOBluetoothRadioPowerBackend`
- concrete private listening-mode HAL, endpoint, and listener backends
- `XPCPrivilegedHelperClient`
- `UpdaterManager.shared`
- `PrivilegedHelperManager.shared`

`PlatformCompositionTests` asserts the concrete reader wiring, Direct
MobileBattery discovery, the Direct Internet Sharing detector, the two
shared-manager facades, and fail-closed safe defaults.

## Verification evidence

Final B tree: `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`, branch
`codex/dual-distribution-platform-work`, with the Phase A files still staged
and the B delta unstaged.

Toolchain: Xcode 27.0 (`27A266a`), Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), macOS SDK 27.0. The Swift target was
`arm64e-apple-macos14.0`; the built app and helpers retained `minos 13.0`.

Focused command:

```bash
bash scripts/test.sh 'PlatformServiceFacadeTests|PlatformCompositionTests|UpdaterManagerTests|PrivilegedHelperManagerTests|LowPowerModeControlSynchronizerTests|SettingsStoreTests|WiFiClassifierTests|BluetoothListeningModeHALTests|NearbyBLEControllerDemandTests'
```

Result: `294` XCTest and `2` Swift Testing tests passed, with zero failures.
This covers asynchronous Helper readiness/approval/error publication, the
system-managed update facade, Direct update activation-policy propagation,
Direct MobileBattery discovery, Direct Internet Sharing detection, Huawei HAL
routing, safe Store defaults, and BLE request-permit behavior.

Full command:

```bash
bash scripts/verify-local.sh full
```

Result: passed.

- Power-helper tests: `15/15`.
- `StatusTrioCore` XCTest: `1938` executed, `7` skipped, zero failures.
- Swift Testing: `751` tests in `112` suites, zero failures.
- Release build passed.
- Non-Universal ad-hoc `dist/StatusTrio.app` bundle build passed with bundle ID
  `com.lingsmbp.StatusTrio.dev.verify-local`.
- macOS 13 deployment and SDK 26-or-newer contracts passed at `minos 13.0`,
  `sdk 27.0`.
- MobileBattery and privileged-helper bundle/rpath contracts passed.
- Offline release, notarization, workflow, appcast, and recovery simulations
  passed.
- `git diff --check` passed.

The Release build emitted two non-fatal concurrency warnings:

- `Sources/StatusTrioCore/App/MemoryPressureMonitor.swift:47` marks an already
  `Sendable` dispatch source as `nonisolated(unsafe)`.
- `Sources/StatusTrioCore/Platform/DirectPrivilegedPowerClient.swift:72`
  captures a non-`Sendable` operation closure in a `@Sendable` XPC reply
  closure.

Both are recorded for review; neither failed compilation or the test suite.

Not run on the final B tree:

- Store Xcode source-membership build: `NOT RUN`; Phase C owns the generated
  project and exact build command.
- Store link-graph and artifact audit: `NOT RUN`; Phase C must prove the Store
  Core does not link Sparkle, `DDCPrivateAPI`, `PowerHelperProtocol`, or the
  Direct SwiftPM Core product.
- Store sandbox runtime, Bluetooth/Wi-Fi/power permissions, Huawei RFCOMM
  operation, and hardware reads: `NOT RUN`.
- Real manual-update presentation and Dock/activation-policy interaction:
  `NOT RUN`; unit coverage passed, but no native-window exercise is claimed.
- Signing, notarization, DMG, Universal packaging, release publication, and
  appcast publication: `NOT RUN`.

DDC has separate focused evidence in
`docs/verification/dual-distribution-ddc.md`. A filter pass is not a full-suite
pass, and the full profile above is not Store or hardware acceptance.

## Integration interfaces

### Phase C

Use `AppStore/direct-only-sources.txt` as the exact source-exclusion input.
Include `AppStore/Platform/*.swift` in the independent `StatusTrioCore`
framework. Compile the shared sources with `STATUS_TRIO_APP_STORE`, deployment
target macOS 13, SDK 26 or newer, and Swift 6. Do not link Sparkle,
`DDCPrivateAPI`, `PowerHelperProtocol`, or the Direct SwiftPM Core product.

### Phase D

Store composition currently uses fail-closed readers. D should inject the
public in-process readers through the existing protocols:

```swift
BluetoothPairedDeviceReading
BluetoothBatteryReading
BluetoothAccessoryBatteryReading
```

No shared controller change is required. Keep `system_profiler`, `pmset`, and
`networksetup` out of the Store baseline. Update the
`bluetooth.public-readers` and Huawei capabilities from `notVerified` only
after sandbox/device evidence exists.

### Phase E

Consume `PlatformCapabilities.appStore` reason identifiers and
`CapabilityAvailability` in shared UI. Keep unavailable controls hidden or
disabled with localized explanation; do not infer availability from a missing
provider. Huawei remains `notVerified` until Store hardware evidence exists.
