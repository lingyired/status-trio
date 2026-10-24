# Public Provider Verification

Date: 2026-10-24

Scope: the three App Store/provider additions in
`Sources/StatusTrioCore/Monitoring/PublicBluetoothPairedDeviceReader.swift`,
`Sources/StatusTrioCore/Monitoring/PublicAccessoryBatteryReader.swift`, and
`Sources/StatusTrioCore/Monitoring/CoreWLANKnownNetworkProvider.swift`. This is
source and offline-fixture evidence for the shared D provider slice. It is not
Store composition, sandbox-runtime, TCC, or hardware evidence.

## Public API Evidence

The implementations use only the following SDK declarations:

| Provider | Public API | SDK evidence |
| --- | --- | --- |
| Paired-device enumeration | `IOBluetoothHostController.defaultController`, `powerState` | `IOBluetoothHostController.h:48-60` |
| Paired-device records | `IOBluetoothDevice.pairedDevices`; `addressString`, `nameOrAddress`, `deviceClassMajor`, `deviceClassMinor`, `isConnected` | `IOBluetoothDevice.h:412`, `:424`, `:450`, `:479`, `:565`, `:872-882` |
| Bluetooth class numbers | Public `BluetoothAssignedNumbers.h` class constants | `BluetoothAssignedNumbers.h:332-344`, `:364-370`, `:428-445`, `:456-477` |
| Accessory power sources | `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription` | `IOPowerSources.h:273`, `:287`, `:305` |
| Accessory power-source keys | `kIOPSTypeKey`, `kIOPSNameKey`, `kIOPSVendorIDKey`, `kIOPSProductIDKey`, `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSIsPresentKey` | `IOPSKeys.h:329`, `:343`, `:446`, `:497`, `:511`, `:541`, `:554` |
| Known Wi-Fi interface | `CWWiFiClient.interface(withName:)` | `CWWiFiClient.h:257-270` |
| Preferred-network configuration | `CWInterface.configuration()` | `CWInterface.h:273-278` |
| Preferred-network profiles | `CWConfiguration.networkProfiles` | `CWConfiguration.h:44-54` |
| Profile SSID | `CWNetworkProfile.ssid` | `CWNetworkProfile.h:114-122` |

The IOBluetooth header documents that `pairedDevices` returns `nil` when there
are no paired devices. The reader therefore maps `nil` to the successful empty
list; it does not call that answer unavailable. A missing controller is
`unavailable`, a non-ON controller state is `poweredOff` or `unavailable`, and a
non-device payload is `failed`.

The paired reader takes one public snapshot per requested read, converts the
Objective-C objects to Sendable value snapshots immediately, and never asks for
battery data through KVC, a private selector, or a private framework. Missing
battery/model/vendor metadata stays absent. Connected records sort first,
normalized addresses are deduplicated, and nil, empty, or invalid identity
metadata is skipped instead of inventing a device.

The accessory reader uses one public IOPS snapshot and reduces each description
dictionary before publishing it. Internal battery and UPS sources are excluded.
A missing or invalid capacity is omitted rather than displayed as 0%; a missing
IOPS handle or list is unavailable, while a malformed description or known-value
type is failed. An empty public source list remains a successful empty list.
Known numeric fields require a non-floating-point `CFNumber`; a `CFBoolean`,
floating-point number, or other value is rejected as malformed. `Is Present`
requires the actual `CFBoolean` type, so numeric `NSNumber` values are not
silently interpreted as `true` or `false`.
The existing optional accessory protocol cannot preserve the difference between
unavailable and failed, so both are honestly exposed to consumers as `nil`.

Both public providers bound uncancellable API calls to two outstanding reads.
A third request while both are wedged completes immediately as `.unavailable`
for Bluetooth and `nil` for accessories, without creating another queue or
provider call. `shutdown()` closes the lifecycle latch, and deinitialization
also closes it. This is a stop path for new work, not a fabricated cancellation
of an IOBluetooth or IOPS call already blocked in the system framework. The old
"a third read always runs on another queue" contract was intentionally removed
because it had no upper bound.

The CoreWLAN reader obtains the named public `CWInterface`, reads its public
`configuration()`, and projects each public `CWNetworkProfile.ssid`. The
snapshot keeps `.profiles([])` distinct from `.unavailable`; the existing
`WiFiKnownNetworkProviding` contract has no failure state, so both map to an
empty enrichment set. `configuration()` returning nil may mean no interface,
permission/sandbox restriction, or a transient CoreWLAN error. It is not
evidence that the public API is unsupported. The provider neither requests TCC
nor polls.

Composition remains B-owned. This change does not replace the Direct default or
edit the Store factory; the Store composition can inject
`CoreWLANKnownNetworkProvider()` where it currently uses an always-unavailable
known-network provider.

## Not-Verified Metadata

The SDK headers expose no public enum constant for `"Accessory Source"`, no
public `"Part Identifier"` key, and no public `"Group Identifier"` key. The
provider therefore does not interpret those strings to split a device into left,
right, or case channels:

- `BluetoothAccessoryBatteryLevel.part` remains `nil` for public-provider
  readings.
- Vendor and product IDs remain `nil` when the public dictionary omits them.
- No accessory battery is synthesized from an unknown source.

This is a declared metadata limitation, not a claim that the hardware lacks the
capability. Resolving those fields requires independently public evidence that
the Store build may rely on.

## Offline Tests

Three focused Swift Testing files contain the injected snapshot fixtures:

- `Tests/StatusTrioCoreTests/PublicBluetoothPairedDeviceReaderTests.swift`
- `Tests/StatusTrioCoreTests/PublicAccessoryBatteryReaderTests.swift`
- `Tests/StatusTrioCoreTests/CoreWLANKnownNetworkProviderTests.swift`

The tests cover public metadata/class mapping, connected-first identity dedupe,
invalid metadata omission, distinct successful-empty/unavailable/failed states,
accessory capacity validation, absent sources, unknown accessory metadata,
malformed IOPS payloads including raw Boolean/non-integer numeric dictionaries,
one provider call per read, the two-read blocked-call bound, shutdown rejection
without cancellation claims, CoreWLAN profile projection, nil-versus-empty
snapshots, interface forwarding, and SSID deduplication. Tests inject value
snapshots and do not call IOBluetooth, IOPS, CoreWLAN, TCC, a subprocess, or
hardware.

Pre-fix focused execution on 2026-10-24:

```text
bash scripts/test.sh 'PublicBluetoothPairedDeviceReaderTests|PublicAccessoryBatteryReaderTests|CoreWLANKnownNetworkProviderTests'
```

The command exits 0. Swift Testing reports 20 tests in 3 suites passed; the
parameterized class-mapping test expands those declarations to 33 executed cases.
Compile red points were fixed before the green runs: the paired snapshot was
declared as a `struct` containing enum cases, a local `devices` binding shadowed
the mapping function, and CoreWLAN imports its ordered-set elements as `Any`
until explicitly converted to `CWNetworkProfile`.

The CoreWLAN test file was first added without the provider and failed to compile
with `cannot find 'CoreWLANKnownNetworkProvider' in scope` (RED). The provider
implementation then passed all four focused tests (GREEN).

Fix-round-1 changed the public-reader lifecycle and added malformed-IOPS
coverage. Its focused run is pending: the `StatusTrioCore` source target
compiled, but the test target was blocked by concurrent Settings UI changes in
`SettingsViewTests.swift` that did not yet pass the new `capabilityPolicy`
argument. That unrelated compile failure is not a reader test result. The old
20-test count is therefore evidence for the pre-fix implementation only.

## Source Boundary Checks

Static scans after the final provider edit passed:

- No `system_profiler`, `pmset`, or `networksetup` invocation is present in the
  three provider files.
- No KVC (`value(forKey:)`, `value(forKeyPath:)`) or Objective-C runtime
  selector lookup is present in them.
- No TCC request or polling was added. Each call reads one snapshot; scheduling
  and retry ownership remain with the existing controller lifecycle.
- Direct profiler naming/classification files are unchanged; the new class
  mapping is local to the public paired-device reader.

## Explicit NOT RUN

- Pre-fix focused SwiftPM compile/tests: **PASS** on 2026-10-24.
- Fix-round-1 focused SwiftPM tests: **BLOCKED** by the concurrent Settings UI
  test compile error above; no new count is claimed.
- App Store composition/factory injection and sandbox entitlement runtime.
- Bluetooth TCC allow, deny, revoke, powered-off, and relaunch behavior.
- Real paired-device enumeration, connected-state changes, and accessory IOPS
  source delivery on macOS 13 and current macOS.
- Real CoreWLAN preferred-profile reads, including nil under sandbox/TCC denial,
  on macOS 13 and current macOS.
- App Store bundle audit against a real signed Store build.
