# Dual-distribution DDC isolation verification (2026-10-24)

## Scope

This record covers the DDC portion of the dual-distribution split. The shared
`VolumeMonitor` must compile without any Direct-only DDC implementation while
retaining its existing Huawei, public CoreAudio, and other non-DDC volume paths.

The shared boundary is `DDCVolumeCoordinating` plus
`DDCVolumeCoordinatorConfiguration`, `DDCVolumeCoordinatorFactory`, and
`DDCVolumeUpdate`. `VolumeMonitor` owns only the protocol and factory. Display
discovery, IOKit transport, resolver, read-profile, and coordinator
implementation stay behind the Direct factory. `DDCVolumeUpdate` moved from the
concrete coordinator into the shared boundary file without changing its fields.

## Store membership contract

The Store source closure must exclude these exact Direct-only paths:

```text
Sources/StatusTrioCore/Audio/DDCDisplayTransport.swift
Sources/StatusTrioCore/Audio/DDCReadProfile.swift
Sources/StatusTrioCore/Audio/DDCTargetResolver.swift
Sources/StatusTrioCore/Audio/DDCVolumeCoordinator.swift
Sources/StatusTrioCore/Platform/DirectDDCFactory.swift
```

These paths remain in the shared Store closure:

```text
Sources/StatusTrioCore/Platform/DDCVolumeCoordinating.swift
Sources/StatusTrioCore/Audio/DDCVolumeReply.swift
AppStore/Platform/StoreDDCFactory.swift
```

The canonical exclusion list is owned by the platform exclusions work. This
record does not edit it. The shared `VolumeMonitor` contains no concrete
`DDCDisplayTransport`, `DDCVolumeTransport`, `DDCVolumeCoordinator`,
`DDCTargetResolver`, or `DDCReadProfile` reference.

## Distribution behavior

- Direct supplies `DirectDDCFactory` through the existing
  `VolumeMonitor()` / `ddcTransport:` / `ddcCoordinator:` source surface.
- Store supplies `StoreDDCFactory`, whose coordinator is the shared
  `UnavailableDDCVolumeCoordinator`.
- The unavailable coordinator never invents a scalar, command ID, generation
  update, or capability. A Store build therefore leaves DDC volume unavailable
  rather than routing to private logic or pretending success.
- The shared initializer requires an injected factory. A target cannot
  accidentally compile shared `VolumeMonitor` with a concrete Direct default.
- The existing DDC reply validation, pending command-ID matching, generation
  checks, selection/topology/sleep invalidation, 150 ms debounce, final-drag
  flush, read watchdog, failure backoff, cancellation, and read-back
  verification remain in the Direct coordinator and its tests.

## Verification

Command:

```text
bash scripts/test.sh 'DDCVolumeIsolationTests|DDCVolumeCoordinatorTests|VolumeMonitorTests'
```

Result on 2026-10-24: exit `0`; `70/70` tests passed with no zero-match:

- `DDCVolumeIsolationTests`: 5
- `DDCVolumeCoordinatorTests`: 20
- `VolumeMonitorTests`: 45

The command built the SwiftPM debug targets before running the selected tests.
The only warning was an unrelated pre-existing `MemoryPressureMonitor.swift`
`nonisolated(unsafe)` warning.

## Not verified

- Store Xcode source-membership build: PASS on the final integrated archive;
  see `dual-distribution-store-build.md`.
- Full SwiftPM suite: PASS on the final integrated tree; see
  `2026-10-24-dual-distribution-final.md`.
- Sandboxed Store runtime and private API behavior: `NOT RUN`.
- Real DDC hardware, display compatibility, and hardware read-back: `NOT RUN`.

## Interface for integration

`VolumeMonitor` accepts:

```swift
ddcCoordinatorFactory: @escaping DDCVolumeCoordinatorFactory
```

The factory is called lazily with the update closure and a
`DDCVolumeCoordinatorConfiguration`. Direct compatibility initializers adapt
the old transport/coordinator injection points; Store uses
`StoreDDCFactory.makeCoordinator` and does not include any Direct DDC source.
