# BetterDisplay Volume Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read and change the current external output's volume through an explicitly selected BetterDisplay backend.

**Architecture:** A typed notification client feeds a generation-scoped volume coordinator. VolumeMonitor selects one read/write backend, publishes the existing shared VolumeStatus, and preserves native Core Audio priority. Audio settings persist per-output choices and explicit display bindings.

**Tech Stack:** Swift 6, AppKit, Combine, SwiftUI, DistributedNotificationCenter, XCTest/Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-22-betterdisplay-volume-control-design.md`

**Branch:** `codex/issue-115-betterdisplay-volume`

**Base:** `origin/main` at `d3b7ac241533afda385a1bf95e4df43778a81ce6`

## Global Constraints

- Work only in the isolated branch/worktree created for Issue #115.
- User explicitly requested DeepSeek implementation; use `auto/deepseek-v4.1-flash` with `max` reasoning for implementers and fixes.
- The user's latest instruction authorizes implementation of the presented design; execution method is DeepSeek delegation. Do not ask again for routine local implementation.
- Deployment target remains macOS 13; no new dependencies, permissions, audio drivers, private APIs, or changes to BetterDisplay preferences.
- Keep writable Core Audio as the first choice.
- Persist selection per audio output UID, not per brand.
- Every command targets one explicit BetterDisplay display identity.
- When BetterDisplay is selected, suspend Status Trio's direct DDC work for that output.
- No automatic retry of a timed-out mutation is allowed.
- Start with a 3-second request deadline, one mutation in flight and at most one coalesced refresh.
- Coalesce repeated input with a 150 ms maximum send rate and one latest pending value.
- Reconciliation intervals: 2 seconds with audio details visible and 10 seconds otherwise; stop while absent, asleep, disabled or unselected.
- Menu Bar, Dock and panel consume the existing shared VolumeStatus.
- Localize new user-facing strings in every shipped language.
- Do not commit, push, merge, create a PR, publish, install or start an application. Leave reviewed changes in this worktree.
- Run focused tests only through `bash scripts/test.sh [filter]`; parent owns final `bash scripts/verify-local.sh full`.
- Do not weaken tests, add arbitrary retries, or change unrelated files.

## Review Focus

1. Repeated keyboard/slider changes must not starve writes or let late reads restore an older value.
2. A -> B -> A and reconnect with a reused display ID must reject old responses and never guess the target.
3. Distributed notifications use JSON in `object`; null parameters must remain present in the encoded request.
4. A successful request with missing/malformed payload or a mismatched readback must not look verified.
5. A programmatic slider update, unknown mute state, or read-only capability must not cause a write.

## File Structure and Ownership

Task 1 owns only new notification transport/protocol files and their tests.
Task 2 consumes that transport and owns coordinator, settings persistence,
monitor/store integration and their regressions.
Task 3 consumes Task 2's runtime/settings APIs and owns UI interactions,
localized copy and usage/verification documentation.
Tasks execute sequentially. Parent writes this plan and the private progress
ledger, and performs review/verification; parent does not compete for source
ownership with an implementer.

### Task 1: Typed BetterDisplay notification transport

**Files:**
- Create: `Sources/StatusTrioCore/Audio/BetterDisplayIntegrationProtocol.swift`
- Create: `Sources/StatusTrioCore/Audio/BetterDisplayIntegrationClient.swift`
- Create: `Tests/StatusTrioCoreTests/BetterDisplayIntegrationClientTests.swift`

**Interfaces:**

```swift
enum BetterDisplayEvent: Equatable, Sendable {
    case launched
    case terminated
    case audioChanged
}

@MainActor
protocol BetterDisplayRequesting: AnyObject {
    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void)
    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String?
    func stop()
}
```

The concrete client implements this interface; operation-specific numeric and
device parsing belongs to Task 2. Keep bridge and scheduling seams internal and
injectable. Do not change production settings or instantiate a running-app probe
in a transport unit test.

- [ ] **Step 1: Read primary protocol and write failing tests.**
  Read the spec's transport section and
  `https://betterdisplay.pro/guide/integration/third-party-apps/`.
  Add deterministic tests for exact request shape (including
  `["volume": nil, "UUID": "display-a"]`), observer-before-post behavior,
  matching and unmatched UUID responses, failure Boolean/missing result,
  success without payload, malformed JSON, deadlines, cancellation, stop,
  pending-request bounds and valid audio/lifecycle notifications. Treat OSD
  events as refresh hints, not values or target identities.

  The encoded request must preserve null rather than remove its parameter:

  ```swift
  let parameters: [String: String?] = ["UUID": "display-a", "volume": nil]
  let object = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(parameters)
  ) as! [String: Any]
  XCTAssertTrue(object["volume"] is NSNull)
  XCTAssertEqual(object["UUID"] as? String, "display-a")
  ```

- [ ] **Step 2: Run the red tests.**
  Run `bash scripts/test.sh BetterDisplayIntegrationClientTests`.
  Record the actual failure before implementation in the task report.

- [ ] **Step 3: Implement the client.**
  Use the modern `pro.betterdisplay.BetterDisplay` prefix, `object` JSON,
  response UUID matching, a bounded pending map and a 3-second injected
  deadline. Observer callbacks transfer decoded Sendable values to MainActor.
  Release observers and pending continuations on stop and deallocation;
  restarting must be safe. Use no isolated deinit, weak let or actor-isolated
  method passed directly as a function value.

  The request envelope has exactly these field names:

  ```swift
  struct BetterDisplayRequestEnvelope: Encodable {
      let uuid: String
      let commands: [String]
      let parameters: [String: String?]
  }
  ```

- [ ] **Step 4: Run green tests and self-review.**
  Run the same focused command. Verify no real notification is posted from
  fake-transport tests, no unknown UUID can resolve a request and no observer
  survives teardown. Report edited paths, red/green evidence and exact public
  signatures. Do not commit. Parent then runs a task-scoped code review.

### Task 2: Volume coordinator and shared backend integration

**Files:**
- Create: `Sources/StatusTrioCore/Audio/BetterDisplayVolumeModels.swift`
- Create: `Sources/StatusTrioCore/Audio/BetterDisplayVolumeCoordinator.swift`
- Create: `Sources/StatusTrioCore/Models/ExternalVolumeConfiguration.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift` for default-compatible configuration and catalog hooks
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift` to bind external-volume settings at startup
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify: `Sources/StatusTrioCore/Models/StatusSnapshot.swift` only if unknown mute requires explicit state
- Create: `Tests/StatusTrioCoreTests/BetterDisplayVolumeCoordinatorTests.swift`
- Create: `Tests/StatusTrioCoreTests/BetterDisplayVolumeIntegrationTests.swift`
- Extend: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`

**Consumes:** Task 1's BetterDisplayRequesting and BetterDisplayEvent.

**Produces:** these stable setting types, plus runtime APIs for Task 3:

```swift
enum ExternalVolumeBackend: String, Codable, CaseIterable, Sendable {
    case directDDC
    case betterDisplay
}

struct ExternalVolumeConfiguration: Codable, Equatable, Sendable {
    var backend: ExternalVolumeBackend
    var betterDisplayUUID: String?
    static let `default` = Self(backend: .directDDC, betterDisplayUUID: nil)
}
```

SettingsStore exposes `externalVolumeConfiguration(for uid: String)` and
`setExternalVolumeConfiguration(_:for:)`, backed by published per-UID
configurations. SystemStatusStore exposes a published device catalog,
availability/failure enum, and `refreshBetterDisplayDevices()` for Audio settings.
The task report pins their final exact signatures for the next implementer.

- [ ] **Step 1: Add red coordinator, routing and persistence tests.**
  Use a fake BetterDisplayRequesting client and injected clock/sleep. Detect
  BetterDisplay readiness through request/response transport, not process
  inspection: a successful identifiers request means ready; a lifecycle launch
  event triggers discovery; timeout means unavailable/unresponsive. Cover an
  explicit selector on every volume/mute write/read, non-100 ranges,
  malformed/non-finite values, Display-only catalog filtering, duplicate
  identity rejection, missing/unknown mute, readback mismatch and timeouts.
  Test manual binding independently of DDC service discovery. Use official
  device-list and scalar payload examples; do not invent a success format.

  Regression cases include:

  ```swift
  // Each is a separate deterministic test with observable I/O assertions:
  // native writable -> zero BetterDisplay requests and zero DDC calls
  // BetterDisplay selected -> zero direct DDC calls, even on request failure
  // A -> B -> A -> a response from generation A1 cannot publish into A2
  // slider 0.2, 0.4, 0.8 -> bounded writes and final confirmed value 0.8
  // timed-out set -> no retry of that mutation
  // readback mismatch -> actual returned scalar, never requested scalar
  // app absent / sleep / stop -> no reconciliation polling or observers
  ```

  Persistence tests must use isolated UserDefaults, default to directDDC,
  round-trip per-output bindings and reject corrupt persisted values safely.

- [ ] **Step 2: Run the red tests.**
  Run `bash scripts/test.sh 'BetterDisplayVolume|SettingsStoreTests'`.
  Record the failures before implementing.

- [ ] **Step 3: Implement models and state machine.**
  Query `get` with `identifiers` for catalog discovery and parse documented
  JSON plus the observed comma-separated JSON-object framing as a constrained
  fallback; never split blindly on commas. Keep only `deviceType == Display`
  entries with a non-empty UUID. For range discovery, send `get` parameters
  `UUID`, `volume:null`, `value:null`, `min:null`, and `max:null` together; the
  observed successful payload is `current,min,max`. Omitting `value` can return
  only `min,max`, so reject that as incomplete current state. Parse plain scalar
  text and `on`/`off` mute text. Do not use the observed `connected` getter as a
  liveness test. Current CLI examples say generic volume/mute follows the
  configured providers; do not assume it always targets hardware DDC.

  Never assume the Core Audio output UID equals BetterDisplay's display UUID.
  Use an explicit user-selected BetterDisplay UUID for the current output when
  mapping cannot be proven. Persist that UUID only as a per-output preference,
  revalidate it against the live catalog after launch/reconnect, and fail
  unavailable if missing/ambiguous. Do not use name/serial, volatile
  `displayID`, or install-scoped `tagID` as fallback identities.

  Run one mutation at a time and retain only the latest unsent volume. Apply
  a maximum send rate, not a trailing-only debounce that starves a long drag.
  Serialize mute and volume mutations. Read back after the latest mutation;
  protect visible drafts using generation and command identity.

  A timeout is not cancellation of an already posted command. Never
  resend it automatically. New topology/selection clears queued work without
  retargeting an old explicit command. Reconcile at 2/10 seconds only while
  demanded, selected, awake and app-present.

- [ ] **Step 4: Integrate with VolumeMonitor and SystemStatusStore.**
  Bind published SettingsStore configuration using the existing configuration
  wiring patterns and wire that binding in AppEnvironment.start(). Native Core
  Audio stays first. Select exactly one external
  backend. Ensure setVolume, toggleMute and flushPendingVolume route to the
  selected owner and check capabilities. Observe/cancel catalog/state streams
  through existing store lifecycle.

  Preserve existing native/DDC tests and shared VolumeStatus publication.
  Invalidate external state immediately on output transitions and discard
  late callbacks. No separate icon renderer or icon cache is added.

- [ ] **Step 5: Run green tests and self-review.**
  Run `bash scripts/test.sh 'BetterDisplay|VolumeMonitor|DDCVolume|SettingsStoreTests|VolumeDetailsDemand|AudioPanelMapper'`.
  Report changed files, pinned UI APIs, request fixture provenance and
  remaining manual-only checks. Do not commit. Parent then reviews this task.

### Task 3: Audio settings, safe UI interaction and localized guidance

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift`
- Modify: `Sources/StatusTrioCore/UI/VolumeControlsView.swift`
- Modify if needed: `Sources/StatusTrioCore/Presentation/Panel/VolumePanelState.swift` and `AudioPanelMapper.swift` for output identity and unknown-mute presentation
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/*/Localizable.strings`
- Extend: relevant audio mapper, scroll and settings tests
- Create: `Tests/StatusTrioCoreTests/BetterDisplayVolumeUITests.swift`
- Create: `docs/verification/betterdisplay-volume-integration.md`

**Consumes:** Task 2's persisted per-output configuration, device catalog,
availability and refresh API. Read Task 2's report for final exact signatures.

**Produces:** User-visible selection/binding and instructions, integrated with
existing audio controls and every shipped localization.

- [ ] **Step 1: Write red UI interaction and localization tests.**
  Add a testable interaction helper or use existing draft/session patterns.
  Observe actual emitted actions, not source text. Pin:

  ```swift
  // external scalar update -> zero setVolume actions
  // user drag with canAdjust == false -> zero setVolume actions
  // user drag with canAdjust == true -> exactly the changed value
  // final release -> one flush; selection change discards old draft
  // unsupported/unknown mute -> disabled mute action
  ```

  Test setting changes apply only to the current non-empty audio UID and
  device-picker selection uses UUIDs rather than labels or display IDs.
  New keys must load in every shipped locale.

- [ ] **Step 2: Run red tests.**
  Run `bash scripts/test.sh 'BetterDisplayVolumeUI|LocalizationParityTests'`.
  Record behavioral failure evidence before changing production bindings.

- [ ] **Step 3: Implement the Audio settings group and safe controls.**
  Follow the current SettingsGroup/SettingsRow components and style. Expose
  existing behavior versus BetterDisplay, an explicit associated-display
  picker, refresh and a concise status. Show app/integration requirements
  without changing another application's configuration.

  Update VolumeControlsView so synchronizing a scalar never emits a user
  action. Keep final flush and scroll routing through existing store actions.
  Preserve native behavior, accessibility labels and 0...1 UI normalization.
  Localize all new copy, including en, zh-Hans and every other shipped locale.

- [ ] **Step 4: Write usage and verification evidence.**
  Document how to select BetterDisplay for an external output, associate a
  display and return to direct DDC. Record API-result versus audible-result
  boundaries. Manual hardware, OSD behavior, CPU/memory and Ventura/current-OS
  runtime checks remain NOT RUN unless actually measured.

- [ ] **Step 5: Run focused green tests and self-review.**
  Run `bash scripts/test.sh 'BetterDisplay|Volume|AudioPanelMapper|SettingsStoreTests|Localization'`.
  Record changed files, evidence and limitations. Do not commit. Parent
  reviews this task, then requests independent whole-branch review and runs
  `bash scripts/verify-local.sh full` on the integrated working tree.
