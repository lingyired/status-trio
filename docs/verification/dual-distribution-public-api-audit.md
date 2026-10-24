# Dual Distribution Public API Readiness Audit

Date: 2026-10-23
Baseline: `HEAD` `b9b7961f7eb34ed555ca791f5769883cbf3b1b78`
Scope: source/static readiness for the shared Direct/App Store product. This is
not an App Store submission review, a sandbox runtime pass, or hardware
evidence.

## Evidence

All source evidence below was read with
`git show b9b7961f7eb34ed555ca791f5769883cbf3b1b78:<path>`, not from
parallel-agent working-tree changes. Line numbers refer to that baseline.

Classification used here:

- **Public candidate**: uses a public Apple framework or documented process API;
  still requires Store/Sandbox runtime verification.
- **Direct-only/private**: uses an undocumented ABI, private symbol, private file,
  root helper, or an update framework excluded from the Store graph.
- **Verification required**: available implementation, but its Store behavior
  (subprocess, entitlement, TCC, container, or device access) is not yet proven.
- **Not verified** is not the same as unsupported. No Store capability below is
  declared unavailable merely because sandbox testing has not run.

The Store graph must compile and link only the selected closure. A binary scan
alone cannot prove that no numeric Apple-private HAL selector is present; the
source-closure manifest and its exclusion audit remain mandatory evidence.

## Public Provider Retention

The following are the current public candidates to preserve in the shared
product without assuming that every action already works under App Sandbox.

| Capability | Current provider evidence | Retention decision | Store evidence needed |
| --- | --- | --- | --- |
| Battery percentage, power source, charging, Low Power read | IOPS battery read at `Monitoring/BatteryMonitor.swift:38-78`; IOPS and power-state notifications at `:153-180` | Public candidate | None intrinsic; verify sandbox read and notification delivery |
| Battery details | Public IOPS adapter data and IORegistry `AppleSmartBattery` read at `Monitoring/BatteryDetailsReader.swift:58-78` | Public candidate; keep registry fields best-effort | Verify unavailable/partial values do not become fake failure states |
| Wi-Fi status and interface | CoreWLAN/SystemConfiguration reader at `Monitoring/WiFiStatusReader.swift:21-63`; monitor at `Monitoring/WiFiMonitor.swift:289+` | Public candidate | Verify reads under sandbox and with location permission denied |
| Wi-Fi scan and radio power | CoreWLAN scan/power at `Monitoring/WiFiNetworkController.swift:55-116`; user power/refresh at `:304-350` | Public candidate, action remains gated until available | Verify scan, SSID visibility, and radio write; keep read-only state on failure |
| Wi-Fi name permission | Core Location authorization request at `Monitoring/WiFiNameAuthorizer.swift:19-68`; request path at `Monitoring/WiFiMonitor.swift:418-427` | Public candidate | Verify TCC allow/deny/revoke and Settings route |
| Network service/address resolution | Public `SCDynamicStore` snapshot and resolver at `Monitoring/NetworkServiceResolver.swift:37-67`; wired interface/read at `Monitoring/PrimaryLinkController.swift:43-103` | Public candidate | Verify dynamic-store reads and container restrictions |
| VPN and proxy status | Public SystemConfiguration VPN services at `Monitoring/VPNProbe.swift:114-162`; proxy reader begins at `:171` | Public candidate, read-only | Verify service names may be hidden for non-admin users; absence must stay nonfatal |
| Local IP | Public `getifaddrs` plus `SCDynamicStore` at `Monitoring/LocalIPController.swift:24-113` | Public candidate | Verify interfaces/addresses remain readable and no broader permissions are requested |
| Bluetooth paired/connection status | Public IOBluetooth paired-device actions at `Monitoring/BluetoothDeviceActionPerformer.swift:39-64`; connection notifications at `Monitoring/BluetoothConnectionEventMonitor.swift:33-120` | Public candidate, but connection/action verification is separate | Verify connect/disconnect and notification delivery; do not infer from compilation |
| Bluetooth authorization/adapter state | Public CoreBluetooth state monitor at `Monitoring/BluetoothDeviceController.swift:257-312` | Public candidate | Verify TCC allow/deny/revoke and powered-off behavior |
| Nearby BLE battery scan | Public CoreBluetooth scanner boundary at `Monitoring/BluetoothLEBatteryScanner.swift:1-17` and implementation below it | Public candidate | Verify scan, per-device access, cancellation, and idle-stop behavior |
| Huawei listening-mode transport | Public IOBluetooth RFCOMM/SPP transport at `Audio/HuaweiListeningModeTransport.swift:81-123` | Separate candidate, not grouped with Apple private HAL | Verify sandbox and real third-party hardware; currently NOT RUN |
| CoreAudio output read/write | Public CoreAudio device, volume, mute, and default-output paths at `Audio/CoreAudioOutputController.swift:7-110`; monitor at `Monitoring/VolumeMonitor.swift:111-157` | Public candidate | Verify device enumeration and writes under sandbox |
| Carbon input-source read/switch | Public TIS read at `InputSource/InputSourceReading.swift:18-60`; selection at `InputSource/InputSourceSwitching.swift:12-29` | Public candidate | Verify container/SEATBELT behavior; do not add key simulation |
| Carbon global hotkey | Public Carbon `RegisterEventHotKey` at `App/CarbonHotKeyBackend.swift:55-91` | Public candidate | Verify registration and conflict handling in Store runtime |

### Explicitly separate sources

- `Monitoring/WiFiMonitor.swift:253-286` reads the undocumented
  `com.apple.nat` dynamic-store key for Internet Sharing. Treat it as a
  **verification-required** source, independent of the public CoreWLAN Wi-Fi
  status/scan candidate. Do not delete CoreWLAN support because this detector is
  unverified.
- `Monitoring/BatteryDetailsReader.swift:58-78` combines public IOPS and
  IORegistry data with `SystemPowerReader`. The SMC portion is Direct-only; the
  rest remains a public candidate.
- IOBluetooth/CoreBluetooth/IOKit/CoreAudio imports are not private by
  themselves. A private result depends on the exact symbol, selector, file, or
  component used.

## Direct-Only And Private Providers

| Capability | Baseline evidence | Store policy |
| --- | --- | --- |
| Bluetooth radio total power write/read | `dlopen` plus `dlsym` of `IOBluetoothPreference*` at `Monitoring/IOBluetoothRadioPowerBackend.swift:12-79`; controller default factory at `Monitoring/BluetoothRadioPowerController.swift:136-152` | Exclude. Keep the control unavailable/gated in Store; public device connect/disconnect is a separate candidate |
| Apple listening-mode HAL | Numeric selectors `iaap`, `lstm`, `lsms` at `Audio/BluetoothListeningModeHAL.swift:11-27`; HAL access begins at `:59-70` | Exclude Apple HAL path. Do not classify Huawei SPP with it |
| System total power | `AppleSMC` service and private 80-byte ABI at `Monitoring/SystemPowerReader.swift:14-69` | Exclude |
| Private charge limit | `/Library/Preferences/com.apple.powerd.charging.plist` at `Monitoring/SystemChargeLimitReader.swift:30-47`; `NSKeyedUnarchiver` private layout at `:52-84` | Exclude. Keep user-entered battery threshold only |
| iOS/mobile battery helper | Executes bundled `StatusTrioMobileBatteryHelper` at `Monitoring/MobileBatteryHelperReader.swift:17-39` | Do not ship by default. Requires independent usbmuxd/library/signing/sandbox/license verification |
| Root power helper | XPC service, LaunchDaemon registration, and fixed Direct identity at `PowerHelperProtocol/PowerHelperProtocol.swift:6-35`; manager at `App/PrivilegedHelperManager.swift:44-103` | Exclude binary, plist, XPC surface, and registration from Store |
| Sparkle updater | Direct package dependency at `Package.swift:12-23`; updater singleton at `App/UpdaterManager.swift`; shared UI entry points cited below | Exclude dependency, framework, updater keys/configuration, and update actions from Store |
| DDC private API | Direct package dependency and CoreDisplay link at `Package.swift:19-34` | Exclude `DDCPrivateAPI`, `Sparkle.framework`, `CoreDisplay.framework`, and any DDC dependency from Store |

The current default `SystemStatusStore` composition still constructs several of
these Direct-only services (`Store/SystemStatusStore.swift:211-216`), and
`AppEnvironment.makeStore()` supplies `PmsetAccessoryBatteryWorker`,
IOBluetooth notifications, and CoreBluetooth scanning at
`App/AppEnvironment.swift:367-397`. Composition-root injection is therefore
required before the Store target can claim a clean closure.

## External Commands

Only these command sites were found in the baseline search:

| Command | Baseline call site | Store baseline |
| --- | --- | --- |
| `/usr/sbin/system_profiler -json SPBluetoothDataType` | `Monitoring/BluetoothDeviceController.swift:102-119` | **Verification required**. Keep behind a provider; Store must not require it for basic status |
| `/usr/bin/pmset -g accps -xml` | `Monitoring/BluetoothAccessoryBatteryReader.swift:98-178` | **Verification required**. Accessory enrichment only; failure must keep base battery/device UI usable |
| `/usr/sbin/networksetup` preferred networks | `Monitoring/WiFiKnownNetworkProvider.swift:37-71` | **Verification required**. Known-network enrichment only; no password reads; scan must degrade to CoreWLAN results |
| `/usr/bin/pmset` in root helper | `PowerHelperProtocol/LowPowerModeCommand.swift:8-20`; `StatusTrioPowerHelper/PowerModeService.swift:33-90` | **Direct-only**. Exclude helper and command from Store graph |

Recommended Store baseline: keep each command behind its existing protocol or
worker seam and inject a Store-safe implementation from the Store composition
root. The baseline product must remain useful if `system_profiler`, `pmset`,
and `networksetup` all fail. A successful subprocess test alone is not proof of
App Store acceptance or sandbox policy.

## Coinstall, Defaults, Lock, Login, And Helper Identity

| Identity boundary | Baseline fact | Readiness implication |
| --- | --- | --- |
| User defaults | Settings and localization default to `UserDefaults.standard` (`Settings/SettingsStore.swift:1150`, `Localization/Localization.swift:34-41`, `Audio/VolumeFeedback.swift:33,92`) | Sandboxed `UserDefaults.standard` is container-backed. Do not share a suite or container with Direct; verify migration never reads another channel's data |
| Single-instance lock path | Home-derived `~/Library/Application Support/StatusTrio` plus a filename keyed by actual bundle ID at `App/SingleInstanceGuard.swift:37-56` | Bundle-ID suffix prevents the same filename, but sandbox home redirection and two-channel simultaneous launch are **NOT RUN** |
| Lock primitive | `open`, `flock(LOCK_EX|LOCK_NB)`, `close` at `App/SingleInstanceGuard.swift:62-120` | App Sandbox may restrict the path/primitive; do not claim coinstall behavior until runtime-tested |
| Lock timing | Acquired before environment setup at `App/AppDelegate.swift:19-33` | Preserve fail-closed single-instance semantics; provide a Store-safe path/strategy only after test evidence |
| Login item | `SMAppService.mainApp` at `App/LaunchAtLoginManager.swift:31-66` | Main-app login item is a candidate; approval/login behavior is NOT RUN. Never register Direct and Store against one identity |
| Store settings identity | Direct identity is in `Support/Info.plist:11-12`; `SettingsStore` does not currently receive a distribution policy | Inject channel/capability policy from composition, not from receipt guessing or arbitrary defaults |
| Root helper identity | Fixed `com.lingsmbp.StatusTrio.PowerHelper` service, plist, client ID, and team at `PowerHelperProtocol/PowerHelperProtocol.swift:6-35`; support check at `App/PrivilegedHelperManager.swift:44-67` | Store cannot reuse this identity; exclude registration and helper UI path |
| Root daemon URL | `Contents/Helpers/StatusTrioPowerHelper` at `App/PrivilegedHelperManager.swift:64-67` | Bundle auditor must reject it; no Store entitlement or UI may imply it exists |

Do not force production Store ID in a development build merely to fix a lock or
defaults problem. The runtime identity should be the generated Store ID; only
the production candidate is fixed to `com.lingsmbp.StatusTrio.AppStore`.

## Shared UI Capability Gaps

The following shared controls currently call Direct-coupled services or expose a
capability without a Store availability input. This table is a gap inventory,
not a product redesign.

| UI surface | Current action/coupling | Required capability behavior |
| --- | --- | --- |
| Popover Low Power toggle in battery summary/details | `UI/StatusPopoverView.swift:51-54,139-142` gates only on helper readiness; toggle writes at `UI/BatteryStatusView.swift:94-119` and `UI/BatteryDetailsView.swift:72-92` | Store: hide/disable write as `unsupported` or `notVerified`; retain read-only Low Power state |
| Settings Low Power group | `UI/Settings/BatterySectionView.swift:279-347` observes `PrivilegedHelperManager.shared`; `SettingsWindowController.swift:83-93` refreshes it on show | Gate the group by distribution capability; no helper singleton access in Store composition |
| Private charge-limit link | `UI/Settings/BatterySectionView.swift:221-275` calls `applySystemChargeLimit()` and displays a private-source availability warning | Store: hide the private link; keep the editable user threshold |
| About update action | `UI/Settings/AboutSectionView.swift:4-56,104-110` observes `UpdaterManager.shared` | Gate by updater capability; Store shows no Sparkle update action |
| General update/analytics UI | `UI/Settings/GeneralSectionView.swift:4-20,144-177`; login singleton at `:7-8` and action at `:53-91` | Updates gated by policy; analytics must stay ineligible unless separately approved; login remains a separate runtime candidate |
| Menu update action | `UI/StatusBarController.swift:1193-1196` directly calls `UpdaterManager.shared`; wiring at `:1363-1371` | Inject a capability-aware command; Store command must be unavailable |
| Wi-Fi power/refresh | `UI/WiFiNetworkListView.swift:22-27,68-73`; routed through `UI/StatusPopoverView.swift:55-70,154-158` | Keep public CoreWLAN candidate; disable writes when `.permissionRequired`, `.temporarilyUnavailable`, `unsupported`, or `notVerified`, while preserving reads |
| Wi-Fi name permission | `UI/StatusBarController.swift:1198-1204` and popover request closures | Route explicit request to Core Location; update state on grant/deny/revoke; no background prompt loop |
| Bluetooth authorization and list visibility | `UI/Settings/PopoverSectionView.swift:58-71`; `UI/Settings/BluetoothSectionView.swift:526-549,621-635`; popover request at `UI/StatusBarController.swift:1206-1209` | Gate request/enable transitions and show permission-required state; never treat denied as unsupported |
| Bluetooth connect/disconnect | `UI/BluetoothStatusView.swift:52-70,400-418`; row tap at `UI/BluetoothDeviceRow.swift:67-100`; action routes at `Presentation/Panel/StatusPanelActions.swift:272-303` | Public candidate; disable until authorization and device action are verified; read-only rows remain visible |
| Bluetooth refresh | `UI/BluetoothStatusView.swift:299-314` starts paired and mobile-battery refresh paths | Gate command adapters; a failed/large `system_profiler` or helper must not remove basic status |
| Bluetooth total radio power | `UI/BluetoothStatusView.swift:327-355`; controller at `Monitoring/BluetoothRadioPowerController.swift:136-166` | Store: unavailable because backend is private Direct-only; hide/disable the control |
| Apple listening mode in device/output rows | `UI/BluetoothDeviceRow.swift:55-63`; `UI/OutputDeviceList.swift:71-80`; `UI/OutputDeviceRow.swift:9-20`; action at `UI/BluetoothListeningModeControl.swift:37-85` | Gate Apple HAL presentation/action separately from Huawei SPP; no private selector execution in Store |
| Output-device selection, volume, mute | `UI/VolumeControlsView.swift:13-65`; row selection at `UI/OutputDeviceRow.swift:23-53`; routes at `Presentation/Panel/StatusPanelActions.swift:226-243` | Public candidate until sandbox test; gate only when runtime evidence requires it |
| Input-device selection, input volume/mute | `UI/AudioInputControlsView.swift:130-215,234-297`; routes at `Presentation/Panel/StatusPanelActions.swift:246-260` | Public candidate; gate writes if Store device access fails, preserve read-only rows |
| Input-source switching | `UI/InputSourceListView.swift:50-55`; routed at `UI/StatusPopoverView.swift:82-88` and `Presentation/Panel/StatusPanelActions.swift:270` | Public Carbon candidate; gate on `TISSelectInputSource` runtime result |
| Global shortcut recorder | `UI/Settings/GeneralSectionView.swift:95-103`; `UI/Settings/ShortcutRecorder.swift:278-345`; registration at `App/GlobalShortcutController.swift:64-121` | Public carbon candidate; disable/store State as unsupported only if runtime registration fails |
| Ethernet settings and Internet Sharing links | `UI/EthernetLinkView.swift:28-35`; Wi-Fi sharing links at `UI/WiFiNetworkListView.swift:47-54` | Settings links are separate from the unverified `com.apple.nat` read; do not claim sharing status from a link |

`UI/StatusPopoverView.swift:162-182` directly injects `store.bluetoothPower` and
`store.mobileBattery`, while `StatusPanelActions` routes several public and
private actions through one store. The smallest safe change is a policy input on
these views/actions, not a second UI tree.

## Minimal Implementation Recommendation

1. Add a distribution-capability policy at the composition boundary with
   `available`, `permissionRequired`, `unsupported`, `temporarilyUnavailable`,
   and `notVerified` states.
2. Inject the policy into `AppEnvironment`, `StatusPanelActions`, the popover,
   battery/settings views, Bluetooth views, and updater-facing views. Default
   Direct composition keeps current behavior; Store composition supplies the
   explicit private/resource decisions.
3. Make every write/command guard on `.available`. Preserve read-only rows when
   an action is unavailable. `notVerified` may render an explanatory state but
   must never execute and must not be described as unsupported.
4. Gate, at minimum: Sparkle checks, root Helper Low Power writes, private charge
   limit, Bluetooth total radio power, Apple private listening-mode HAL,
   `system_profiler`, accessory `pmset`, `networksetup`, and mobile battery
   helper.
5. Keep CoreWLAN, IOPS/IOKit, IOBluetooth, CoreBluetooth, CoreAudio,
   SystemConfiguration, and Carbon TIS candidates in the capability model until
   Store sandbox/device tests provide contrary evidence.
6. Keep public providers behind their existing protocols. Store composition
   should use no-op or read-only adapters where an unverified action is not
   enabled; it must not silently reuse Direct singletons.

### Focused Tests To Add With D

- A gated UI action never invokes its service when the capability is not
  `available`.
- A `.permissionRequired` path requests permission only on explicit user action.
- A Direct command adapter executes only when `.available`; `notVerified`,
  temporary failure, and tool failure perform no write.
- Read-only status remains visible while actions are gated.
- Store composition excludes `UpdaterManager`, `PrivilegedHelperManager`,
  `IOBluetoothRadioPowerBackend`, Apple HAL selectors, the mobile helper, and
  Direct command adapters.
- `CoreDisplay.framework` and all private/Direct components are absent from the
  Store source-closure and bundle graph; public frameworks are not blanket
  banned.
- Identity tests prove the Store channel's runtime bundle ID, defaults domain,
  lock namespace, and login-item identity are isolated from Direct.

## Bundle Audit Coupling

The companion bundle auditor must enforce the executable closure, not only the
main binary: recursively inspect every Mach-O, nested bundle, framework,
helper, XPC service, and symlink; reject `Sparkle.framework`,
`DDCPrivateAPI`, `StatusTrioPowerHelper` and its LaunchDaemon registration,
`CoreDisplay.framework`, and the mobile battery helper. It must reject
`spawn`/execute-adjacent private strings and public/private HAL names where
present, but it must not blanket-ban public IOBluetooth, CoreBluetooth, IOKit, or
CoreAudio imports.

The binary audit must inspect `otool -L`, undefined/all `nm` symbols, ObjC
symbol strings, raw Mach-O strings, and `dlsym` string literals. It must not
claim to detect a private HAL selector encoded numerically, or any private code
that has no string/symbol evidence. Source-closure exclusion is the required
complement.

## Explicit NOT RUN

- Signed or notarized App Store build and App Store Connect upload.
- App Sandbox runtime behavior for every provider and command adapter.
- TCC allow, deny, revoke, and relaunch flows for Wi-Fi/location and Bluetooth.
- Real hardware tests for Wi-Fi scan/power, Bluetooth connect/disconnect,
  CoreAudio/HAL, Huawei SPP, and battery telemetry.
- Two-channel simultaneous launch, container/defaults isolation, and lock
  behavior under sandboxed home redirection.
- Login-item registration/approval/removal in a Store build.
- Root helper coexistence, removal, and XPC denial in a Store build (helper is
  intentionally excluded; this remains unverified by design).
- Numeric private-HAL source closure proof from a binary alone.

These gaps mean **readiness to implement**, not **Store submission ready**.
