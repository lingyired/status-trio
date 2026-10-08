# Icon Architecture Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. One `gpt-6-luna` worker executes all tasks; root coordinates one independent final review and remote CI.

**Goal:** Remove the Dock controller's obsolete store dependency, inject a scene-mapping closure, and protect the current presentation boundaries without changing behavior.

**Architecture:** IconPresentationViewModel retains publication, lifecycle and scheduling. A MainActor closure maps resolved inputs/configuration, defaulting to the existing pure mapper. Both canonical and charging-test output call the same closure; scene-only renderers stay unchanged.

**Tech Stack:** SwiftPM, Combine, AppKit, XCTest, Swift Testing; no new dependency.

**Spec:** `docs/superpowers/specs/2026-10-01-icon-architecture-cleanup-review.md` (user feedback plus binding repository review amendments).

## Global Constraints

- Worktree `/Users/lingsmbp/.codex/worktrees/status-trio-2-0/status-trio`, branch `codex/2.0-presentation-refactor`, product baseline `1c1049399ccdddb17ea73cd590445e8292abb856`; do not modify main or create another worktree.
- UI, settings, panel behavior, accessibility, rendering/cache equality, 500ms trailing snapshot debounce, immediate settings updates, synchronized start and stop/restart behavior remain unchanged.
- Implementation uses `gpt-6-luna`; no plugin runtime, registry, protocol hierarchy, external direct scene setter, SDK, serialization, generic host, or new layouts.
- CI runner macos-26 / Xcode 26.6 / Swift 6.3.3; SDK >=26. No isolated deinit, weak let, experimental compiler flags or direct actor method function references.
- Before Swift commit run `swift test`, `swift build -c release`, `git diff --check`. Root runs publish=false preflight on exact final product SHA, with explicit increasing build number. Record failed runs in docs/swift-ci-compatibility.md. No tag, release, appcast update or merge into main.

## Review Focus

1. Initial output and startup delivery both use the injected mapper; duplicate start must not create extra subscriptions.
2. Charging test maps the projected snapshot with the same closure; canonical scene retains real battery values.
3. Snapshot bursts map only after the existing scheduler fires; immediate preferences cancel pending work and use latest delivered values.
4. Equal custom outputs still deduplicate publication; stop cancels pending mapping, and restart uses current publishers.
5. Semantic equality assertions only use equal resolved symbols, RSSI buckets and dots volume buckets; muted dots and arc ignore raw scalar, while unmuted arc stays continuous.

## Task 1 — Remove obsolete Dock dependency

**Files:** App/AppIconController.swift, App/AppEnvironment.swift, Tests/StatusTrioCoreTests/AppIconControllerTests.swift. Search all call sites; current search finds two. Paths under Sources/StatusTrioCore unless specified.

**Interfaces:** AppIconController initializer loses only `store: SystemStatusStore`; settings remains because placement/background are controller concerns.

- [x] Inspect `rg -n 'AppIconController\(|\bstore\b' Sources/StatusTrioCore/App/AppIconController.swift Sources Tests` and confirm the field only initializes/retains the store.
- [x] Delete `private let store: SystemStatusStore`, `store: SystemStatusStore,` and `self.store = store`; remove only that argument from each AppIconController call. Do not remove stores from fixtures whose shared owner needs them.
- [x] Run `swift test --filter AppIconControllerTests`, retaining render-failure retry, cache reuse, hidden Dock, appearance and static animation behavior tests. This removal has no new product behavior; no artificial failing behavior test is needed. Task 3 adds a source boundary regression.

## Task 2 — Inject mapping with deterministic regression coverage

**Files:** Presentation/Icon/IconPresentationViewModel.swift; Tests/StatusTrioCoreTests/IconPresentationViewModelTests.swift; docs/api/icon-presentation.md; docs/presentation-state-architecture.md.

**Interfaces produced:**

```swift
typealias IconSceneMapper = @MainActor (
    IconPresentationInputs,
    IconPresentationConfiguration
) -> IconSceneState
```

Initializer adds this argument after resolveInputs, before snapshotScheduler:

```swift
mapScene: @escaping IconSceneMapper = { inputs, configuration in
    IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
},
```

Store `private let mapScene: IconSceneMapper`, assign before initial output. The existing static helper gains `mapScene: IconSceneMapper`; init and publishLatestOutput both pass it. Replace both concrete mapper calls in the helper with `mapScene(resolveInputs(snapshot), settings.configuration)` (the test path uses projected snapshot). No scheduling changes.

- [x] Add a test with CurrentValueSubject inputs, ManualIconPresentationScheduler, and a spy closure returning a distinctive scene independently of IconPresentationMapper:

```swift
let customScene = IconSceneState(
    center: .text(IconTextState(text: "X", color: .primary, scale: 1))
)
var mapped: [(IconPresentationInputs, IconPresentationConfiguration)] = []
// Supply at the new initializer argument:
mapScene: { inputs, configuration in
    mapped.append((inputs, configuration))
    return customScene
}
```

Assert init scene == customScene and inputs/config match. Start subjects, reset recorded calls, send two snapshots; before scheduler.runScheduled() no calls, afterward one call with latest snapshot. Send preferences changing battery showsPercentage and menuBarSize; immediately assert latest input/config, no pending action, delivered size. This proves actual injection, not an expected value computed with the default mapper.
- [x] Add charging test coverage: with testsChargingEffect true, spy receives real snapshot then ChargingEffectTestMode projected snapshot (assert projected battery differs/charges); both output scenes come from spy. Toggle false and assert menuBarTestScene nil; toggle true after snapshot update and assert both remap through injected closure. Keep default mapper's existing charging parity test unchanged.
- [x] Add lifecycle/dedup coverage using a constant custom scene: snapshot update maps after manual scheduler but does not publish equal output; changed menuBarSize publishes output; pending work is cancelled by stop with no extra spy call; send values while stopped, restart and assert latest delivered inputs. Reuse existing scheduler, avoid sleeps and wall-clock call-count expectations during initial synchronized start.
- [x] Run `swift test --filter IconPresentationViewModelTests` before product changes; expect missing mapScene initializer error. Record RED. Implement the exact closure seam above, rerun to GREEN. Retain every existing owner test.
- [x] Update API constructor documentation and current limitation at docs/api/icon-presentation.md's future producer section: alternate mapper can be injected at construction, but output remains private(set), production uses default, no dynamic registration or external publishing API. Document closure runs on MainActor and should be synchronous, deterministic, inexpensive; caller manages captured producer state invalidation through existing input publishers, not an implicit subscription. Update architecture flow and canonical/test path. No public access changes.

## Task 3 — Guard semantic scene identity and source boundaries

**Files:** Tests/StatusTrioCoreTests/PresentationArchitectureTests.swift; optional focused test support file in Tests/StatusTrioCoreTests/TestSupport (only if scanner size warrants it).

**Interfaces consumed:** IconPresentationResourceResolver.inputs(snapshot:fileExists:isSymbolAvailable:), IconPresentationMapper.scene(inputs:configuration:), PresentationFixtures.snapshot(rssi:scalar:muted:), StatusMappings.wifiBars(rssi:), AccessibilityPresentation.statusItemValue(_:localization:).

- [x] Preserve SSID equality test. Add bucket characterization:

```swift
#expect(StatusMappings.wifiBars(rssi: -62) == 2)
#expect(StatusMappings.wifiBars(rssi: -70) == 2)
let a = PresentationFixtures.snapshot(rssi: -62)
let b = PresentationFixtures.snapshot(rssi: -70)
#expect(IconPresentationMapper.scene(
    inputs: IconPresentationInputs(snapshot: a, audioIcon: nil), configuration: .standard
) == IconPresentationMapper.scene(
    inputs: IconPresentationInputs(snapshot: b, audioIcon: nil), configuration: .standard
))
```

Also compare across -60/-61 boundary and assert center differs, ensuring visual changes remain represented.
- [x] Add muted scalar identity test for `.dots` and `.arc`: reconstruct IconPresentationConfiguration preserving all standard options except VolumeIconOptions.displayStyle; use scalars 0.1 and 0.9 with muted=true. Assert footer and whole scene equal; unmuted arc counterparts differ. Verify exact existing VolumeIconOptions initializer before writing, no API invention.
- [x] Add @MainActor audio metadata identity test by copying an existing Bluetooth AudioOutputDevice fixture with changed descriptive name, same UID/transport/model/icon fields. Enable Bluetooth network replacement in configuration. Use resource resolver with deterministic availability closures, assert nonnil equal audioIcon and that mapped centers equal the intended resolved symbol. Assert whole scenes equal. Choose names that do not change hardware classification; preserve fields intentionally used by classification.
- [x] Add @MainActor accessibility separation test: same visual snapshots with different SSID and nonmuted scalar 0.51/0.60 (both three dots). Assert scene equality under dots configuration, and distinct AccessibilityPresentation.statusItemValue results with fixed English localization using existing Localization test fixtures. Do not expect arbitrary locale or unmuted arc scalar changes to preserve scene.
- [x] Add renderer token guard reading exact sources using #filePath-derived package root; missing files throw and fail (no skip). Forbidden identifier set: BatteryStatus, WiFiStatus, VolumeStatus, NetworkConnection, SystemStatusStore, SettingsStore, IconPresentationMapper. Apply to UI/Icon/StatusIconRenderer.swift and DockIconRenderer.swift. App/AppIconController.swift additionally forbids SystemStatusStore. Leave actor-isolation guard unchanged.
- [x] Implement a tiny lexical identifier scanner or reuse an existing repository scanner if present. Ignore line/block comments (nested block comments), normal/raw/multiline literal text; exact identifier matching avoids suffix false positives. Scanner's fixture tests must reject real declarations/usages but accept forbidden names in comments, literals and longer identifiers. If interpolation contains executable forbidden identifiers, guard must detect them or explicitly choose a simpler conservative approach that does not silently ignore executable code. No AST dependency.
- [x] Verify guard RED by temporarily introducing a forbidden real token in a renderer comment-free declaration, run only the source guard, observe targeted failure, then restore renderer byte-for-byte. Semantic tests are characterization of existing guarantees and should pass immediately; do not corrupt product code just to make characterization tests fail. Run `swift test --filter PresentationArchitectureTests` and confirm scanner fixtures/identity tests GREEN.

## Task 4 — Verify and hand off

- [x] Run the full suite once after final edits, saving complete logs under /tmp; read counts/failures and exit status. It includes the existing forbidden actor guard. Run `swift build -c release` and `git diff --check`. Do not repeat focused suites already covered without a new failure or edit.
- [x] Inspect diff against product baseline: production changes restricted to AppIconController, AppEnvironment, IconPresentationViewModel; renderers must have no changes after mutation check. Review forbidden expanded scope using `git diff 1c10493 -- Sources` and terms Plugin/ModuleRegistry/PanelRegistry/JSContext/WebSocket/HTTP/XPC/DynamicModule/DSL/Manifest (documentation mentions permitted).
- [x] Commit complete verified cleanup on 2.0 branch with message `refactor: finish icon presentation architecture boundaries`. Report actual SHA, RED/GREEN evidence, test/build logs, diff stat, any decisions/deferred limits in a /tmp report. Do not push, dispatch CI, restart app or modify main; root owns those dependent steps.
- [x] Root dispatches one fresh independent reviewer on the complete cleanup diff, baseline 1c10493 (not whole original refactor). Resolve material findings through Luna with RED/GREEN and full verification. No repeated whole-branch review.
- [x] Root pushes feature branch, audits recent CI builds and dispatches release.yml version2.0.0 with next unused build >=33, publish=false. Verify exact head SHA, CI toolchain, tests, universal SDK guard, DMG and artifact upload. Root records final result in handoff doc and starts matching dev build only if needed. Main stays unchanged.

## Plan self-review

All nine feedback tasks map to the four tasks above; non-goals, both mapping paths, metadata conditions, documentation, source guards, dependency graph and validation are covered. Interface labels match current code. Direct default method value was corrected. Existing characterization tests are not forced into artificial RED cycles. No placeholders or unowned future work are required to finish this cleanup.

## Completion evidence

Implemented in `e731036`, single review fix in `8d46656`. Independent review and root dispositions are recorded in `docs/superpowers/reviews/2026-10-01-icon-architecture-cleanup.md`. CI run 36825078720 passed on exact SHA `8d46656f7d4acfa3e408701cdeec04e2c3febdbb`, version 2.0.0 / build 33 / publish=false. Development build 33 is running. Main is unchanged at `fb766263`.
