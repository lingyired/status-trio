# Status Trio 2.0 Presentation Refactor — Final Architecture Cleanup Plan

## Context

Repository:

```text
https://github.com/lingyired/status-trio
```

Target branch:

```text
codex/2.0-presentation-refactor
```

The large Presentation State / MVVM refactor is already complete.

Current architecture already provides:

- `SystemStatusStore` as domain state authority
- `SettingsStore` as preference authority
- `IconPresentationMapper`
- shared `IconPresentationViewModel`
- immutable `IconSceneState`
- scene-only Menu Bar / Dock rendering
- presentation-level render cache identity
- panel presentation state
- panel action boundary
- accessibility presentation separated from icon raster state
- Menu Bar / Dock parity tests
- renderer parity tests
- panel mapper/action tests
- v1.4.0 `main` integration

Do **not** start another large architecture refactor.

This plan is a small final cleanup pass before considering the presentation refactor complete and moving on to the future Plugin / Presentation Host architecture.

---

# Goals

Complete three focused architecture improvements:

1. Remove obsolete domain dependency from `AppIconController`.
2. Add an injectable icon scene mapping seam to `IconPresentationViewModel`.
3. Strengthen architecture regression tests so future changes cannot silently reintroduce domain/render coupling.

The existing UI, rendering, behavior, settings, animation, lifecycle, cache semantics, accessibility output, and performance characteristics must remain unchanged.

---

# Non-goals

Do **not** implement any of the following in this task:

- plugin runtime
- JavaScript runtime
- XPC
- HTTP/WebSocket producer support
- dynamic plugin registration
- dynamic panel registration
- Panel DSL
- generic module registry
- public SDK
- scene serialization
- JSON protocol
- remote status producer
- user-defined icon slots
- multi-segment ring rendering
- more than four footer dots
- arbitrary icon layouts
- `StatusPanelActions` decomposition
- panel architecture redesign
- new visual features
- UI redesign
- settings redesign

This is strictly the final cleanup of the existing Presentation State refactor.

---

# Task 1 — Remove the unused `SystemStatusStore` dependency from `AppIconController`

## Problem

`AppIconController` still declares and receives:

```swift
private let store: SystemStatusStore
```

even though the controller no longer consumes domain state.

The actual icon state now comes through:

```swift
IconPresentationViewModel
```

Keeping the unused `SystemStatusStore` reference weakens the architecture boundary and makes it appear that Dock presentation is still allowed to read domain state directly.

## Target architecture

Before:

```text
SystemStatusStore ──────────────┐
                               ↓
                    AppIconController
                               ↑
                    IconPresentationViewModel
```

After:

```text
SystemStatusStore
       ↓
IconPresentationViewModel
       ↓
AppIconController
       ↓
Dock Renderer
```

## Files

Primary:

```text
Sources/StatusTrioCore/App/AppIconController.swift
Sources/StatusTrioCore/App/AppEnvironment.swift
```

Tests likely affected:

```text
Tests/StatusTrioCoreTests/AppIconControllerTests.swift
Tests/StatusTrioCoreTests/IconSurfaceIntegrationTests.swift
```

Also search globally for all `AppIconController(` initializers.

## Implementation

Remove:

```swift
private let store: SystemStatusStore
```

Remove the initializer argument:

```swift
store: SystemStatusStore
```

Remove:

```swift
self.store = store
```

Update all construction sites accordingly.

For example, `AppEnvironment.live()` should change from approximately:

```swift
let appIconController = AppIconController(
    store: store,
    settings: settings,
    iconPresentation: iconPresentation,
    ...
)
```

to:

```swift
let appIconController = AppIconController(
    settings: settings,
    iconPresentation: iconPresentation,
    ...
)
```

Update tests and fixtures that instantiate `AppIconController`.

## Acceptance criteria

- `AppIconController.swift` does not reference `SystemStatusStore`.
- Dock rendering continues to consume only `IconPresentationViewModel.output`.
- No behavior change.
- Existing AppIcon/Dock tests pass.

---

# Task 2 — Add an injectable scene mapping seam to `IconPresentationViewModel`

## Problem

The current presentation owner has successfully centralized icon state, but internally it still directly calls:

```swift
IconPresentationMapper.scene(...)
```

This means the runtime pipeline is effectively hard-coded to the built-in mapper.

Current flow:

```text
StatusSnapshot
     ↓
IconPresentationViewModel
     ↓
IconPresentationMapper.scene(...)
     ↓
IconSceneState
```

This is acceptable for the current app, but creates unnecessary coupling before the future Presentation Host / Plugin architecture.

We do **not** want to implement plugins now.

We only want one narrow dependency-injection seam so the owner does not permanently own the concrete built-in mapper.

## Desired design

Introduce a lightweight mapping abstraction.

Prefer the smallest design that preserves the current architecture.

### Recommended approach

Define a closure type:

```swift
typealias IconSceneMapper = @MainActor (
    IconPresentationInputs,
    IconPresentationConfiguration
) -> IconSceneState
```

Then inject it into `IconPresentationViewModel`:

```swift
private let mapScene: IconSceneMapper
```

Initializer:

```swift
init(
    snapshot: StatusSnapshot,
    settings: IconPresentationSettings,
    snapshots: AnyPublisher<StatusSnapshot, Never>,
    preferences: AnyPublisher<IconPresentationSettings, Never>,
    resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs,
    mapScene: @escaping IconSceneMapper = IconPresentationMapper.scene,
    snapshotScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler()
)
```

Store:

```swift
self.mapScene = mapScene
```

Then replace direct calls to:

```swift
IconPresentationMapper.scene(...)
```

with:

```swift
mapScene(
    resolveInputs(snapshot),
    settings.configuration
)
```

The same injected mapper must also be used for:

```text
menuBarTestScene
```

Do not let canonical scene and test scene use different mapping paths.

---

## Important design requirement

Do **not** introduce a protocol hierarchy unless necessary.

Avoid unnecessary constructs such as:

```text
IconSceneProvider
IconSceneProviderProtocol
DefaultIconSceneProvider
BuiltinIconSceneProvider
IconSceneFactory
IconSceneService
```

A simple injected closure is sufficient for the current requirement.

The goal is dependency inversion, not abstraction for its own sake.

---

## Why this seam exists

The immediate behavior remains:

```text
SystemStatusStore
        ↓
IconPresentationInputs
        ↓
Built-in IconPresentationMapper
        ↓
IconSceneState
```

But the owner becomes compatible with a future architecture such as:

```text
Built-in system state ──────┐
                            │
Plugin state ───────────────┼─► Presentation Host / Composer
                            │
Remote/custom state ────────┘
                                      ↓
                               IconSceneState
                                      ↓
                         IconPresentationViewModel
                                      ↓
                           Menu Bar + Dock
```

No part of that future host/composer should be implemented in this task.

---

## Static function consideration

Currently scene generation may happen from a static helper similar to:

```swift
private static func output(...)
```

If injecting `mapScene` makes this helper awkward, either:

### Option A

Pass the mapper explicitly:

```swift
private static func output(
    snapshot: StatusSnapshot,
    settings: IconPresentationSettings,
    resolveInputs: ...,
    mapScene: IconSceneMapper
) -> IconPresentationOutput
```

or:

### Option B

Convert scene output construction into an instance method.

Prefer whichever produces the simpler implementation.

Do not introduce shared mutable/global mapper state.

---

# Task 3 — Add tests for mapper injection

Update:

```text
Tests/StatusTrioCoreTests/IconPresentationViewModelTests.swift
```

Add coverage proving that the owner actually uses the injected mapper.

Example strategy:

Inject a mapper returning a distinctive scene:

```swift
let customScene = IconSceneState(
    center: .text(
        IconTextState(
            text: "X",
            color: .primary,
            scale: 1
        )
    )
)
```

Mapper:

```swift
mapScene: { _, _ in
    customScene
}
```

Assert:

```swift
owner.output.scene == customScene
```

Also test subsequent publisher updates.

The custom mapper should be invoked when:

- snapshot changes
- presentation settings change

If `testsChargingEffect == true`, verify that `menuBarTestScene` also goes through the injected mapper.

Do not test future plugin behavior.

---

# Task 4 — Strengthen `PresentationArchitectureTests`

## Problem

Current architecture-level protection is too narrow.

At present the architecture test mainly proves that changing SSID does not change `IconSceneState`.

That is valuable, but more semantic/nonvisual domain data should be explicitly prevented from leaking into scene identity.

## File

```text
Tests/StatusTrioCoreTests/PresentationArchitectureTests.swift
```

Add focused semantic identity tests.

---

## Test 4.1 — SSID does not affect icon scene

Keep the existing test.

Conceptually:

```text
same visual Wi-Fi state
different SSID
→ identical IconSceneState
```

---

## Test 4.2 — Non-visible Bluetooth/audio device naming does not affect scene

Create two snapshots whose currently selected audio device resolves to the same final icon representation but has different descriptive metadata such as device name.

Expected:

```text
same final icon source
different descriptive metadata
→ identical IconSceneState
```

Be careful not to change fields that intentionally affect symbol resolution.

If device naming currently participates in hardware icon classification, construct test data that avoids changing the resolved `IconSymbolSource`.

The test should prove that descriptive metadata does not enter scene identity after resource resolution.

---

## Test 4.3 — RSSI changes within the same visual bucket do not affect scene

The scene stores resolved Wi-Fi visual level, not raw RSSI.

Example:

```text
RSSI A → same Wi-Fi bars
RSSI B → same Wi-Fi bars
```

Expected:

```swift
sceneA == sceneB
```

Use real values verified against the current `StatusMappings.wifiBars(...)` thresholds.

Do not hard-code guessed threshold values without checking the implementation.

---

## Test 4.4 — Muted raw volume does not affect scene

When audio is muted, the visual footer should represent mute/zero visual fill.

Construct:

```text
isMuted = true
scalar = A
```

and:

```text
isMuted = true
scalar = B
```

Expected:

```swift
sceneA == sceneB
```

Run this against all relevant current volume presentation modes where appropriate:

```text
dots
arc
```

If separate tests are cleaner, use separate tests.

---

## Test 4.5 — Accessibility-only metadata must not affect icon raster scene

The icon scene must not contain exact spoken metadata such as:

- SSID
- localized accessibility text
- exact volume accessibility formatting

Existing `AccessibilityPresentation` is the separate presentation path.

Add the strongest practical architecture test possible without coupling tests to implementation details.

At minimum, document through tests that known accessibility-only domain changes do not change `IconSceneState`.

---

# Task 5 — Add source-level renderer architecture guards

## Goal

Prevent future code from accidentally reintroducing domain logic into:

```text
StatusIconRenderer
DockIconRenderer
```

Today these renderers correctly consume presentation primitives and do not depend on domain models.

Protect that boundary.

## Target files

```text
Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift
Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift
```

They must not directly reference:

```text
BatteryStatus
WiFiStatus
VolumeStatus
NetworkConnection
SystemStatusStore
SettingsStore
IconPresentationMapper
```

## Preferred implementation

Extend an existing source architecture/forbidden-pattern test if there is an appropriate place.

Possible files:

```text
Tests/StatusTrioCoreTests/PresentationArchitectureTests.swift
Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift
```

Prefer a focused architecture test rather than placing unrelated checks in the actor-isolation guard.

A simple source inspection test is acceptable.

For example:

```swift
let forbiddenTokens = [
    "BatteryStatus",
    "WiFiStatus",
    "VolumeStatus",
    "NetworkConnection",
    "SystemStatusStore",
    "SettingsStore",
    "IconPresentationMapper"
]
```

Read the two renderer source files and assert the forbidden tokens are absent.

However, avoid fragile substring matching where comments could cause unnecessary failures.

A small repository script is also acceptable if it provides clearer enforcement.

Do not introduce a heavy AST/source-analysis dependency for this.

---

# Task 6 — Document the new scene-mapping seam

Update:

```text
docs/api/icon-presentation.md
docs/presentation-state-architecture.md
```

The existing documentation currently notes that:

```text
the owner cannot inject an alternate mapper or directly publish a custom scene
```

That statement must be updated.

Document the actual new behavior:

```text
IconPresentationViewModel
    owns publication/lifecycle/debounce

IconSceneMapper
    decides how inputs/configuration become IconSceneState

default implementation
    IconPresentationMapper.scene
```

Clearly state that this is **not** a plugin API.

Recommended wording:

```text
The owner supports injecting an alternate scene mapping function for
composition, testing, and future host integration. The production application
continues to use IconPresentationMapper.scene. No dynamic registration,
plugin runtime, public SDK, or external scene injection is exposed yet.
```

Also update any examples of the initializer to include the default mapper behavior where relevant.

---

# Task 7 — Verify no accidental expansion of scope

Before finalizing, search the diff for any introduction of concepts such as:

```text
Plugin
ModuleRegistry
PanelRegistry
JavaScript
JSContext
WebSocket
HTTP
XPC
DynamicModule
DSL
Manifest
```

Documentation may mention future plugins, but production implementation must not introduce these systems in this task.

This plan is intended only to create a clean seam for those future features.

---

# Task 8 — Full validation

Run the existing test suite.

```bash
swift test
```

Run release build:

```bash
swift build -c release
```

Run:

```bash
git diff --check
```

Also run the existing forbidden-pattern guard if it is not already included automatically by `swift test`:

```bash
scripts/check-forbidden-patterns.sh
```

If there are existing focused presentation test filters, run them as well.

At minimum explicitly verify:

```text
IconPresentationMapperTests
IconPresentationViewModelTests
IconSceneStateTests
IconSceneRendererParityTests
IconSurfaceIntegrationTests
AppIconControllerTests
StatusIconRendererTests
DockIconRendererTests
PresentationArchitectureTests
```

---

# Task 9 — Review the final dependency graph

After implementation, verify the icon production path is structurally:

```text
System APIs / Monitors
        ↓
SystemStatusStore
        ↓
StatusSnapshot

SettingsStore
        ↓
IconPresentationSettings

StatusSnapshot
IconPresentationSettings
        ↓
IconPresentationViewModel
        ↓
resolveInputs
        ↓
IconSceneMapper
(default: IconPresentationMapper.scene)
        ↓
IconSceneState
       ┌┴───────────────┐
       ↓                ↓
StatusBarController   AppIconController
       ↓                ↓
StatusIconRenderer   DockIconRenderer
```

Important rules:

```text
Renderers do not understand domain state.

AppIconController does not understand SystemStatusStore.

StatusBarController may still own non-icon panel/system interactions,
but icon raster decisions come from IconPresentationViewModel.

IconPresentationViewModel owns lifecycle/publication behavior,
not built-in product mapping policy.

IconPresentationMapper remains the default built-in mapping policy.
```

---

# Expected final diff

The final diff should be small.

Expected production changes approximately limited to:

```text
Sources/StatusTrioCore/App/AppIconController.swift
Sources/StatusTrioCore/App/AppEnvironment.swift
Sources/StatusTrioCore/Presentation/Icon/IconPresentationViewModel.swift
```

Expected test changes approximately:

```text
Tests/StatusTrioCoreTests/AppIconControllerTests.swift
Tests/StatusTrioCoreTests/IconPresentationViewModelTests.swift
Tests/StatusTrioCoreTests/PresentationArchitectureTests.swift
```

Possibly:

```text
Tests/StatusTrioCoreTests/IconSurfaceIntegrationTests.swift
```

Expected documentation changes:

```text
docs/api/icon-presentation.md
docs/presentation-state-architecture.md
```

Do not allow this cleanup to turn into another multi-thousand-line architecture change.

---

# Completion criteria

This task is complete when all of the following are true:

- `AppIconController` has no `SystemStatusStore` dependency.
- `IconPresentationViewModel` does not hard-code the concrete mapper as its only possible implementation.
- Production behavior still defaults to `IconPresentationMapper.scene`.
- Both canonical scene and charging-test scene use the same injected mapper path.
- Mapper injection has dedicated tests.
- Scene identity tests protect important nonvisual state boundaries.
- Renderers are protected against reintroducing domain/store dependencies.
- Existing Menu Bar and Dock output remains unchanged.
- Existing lifecycle/debounce behavior remains unchanged.
- Existing accessibility behavior remains unchanged.
- Existing cache semantics remain unchanged.
- Existing panel behavior remains unchanged.
- `swift test` passes.
- release build passes.
- `git diff --check` passes.
- no Plugin Runtime / Panel Registry / DSL implementation is introduced.

---

# Final handoff

Once this plan is complete, consider:

```text
codex/2.0-presentation-refactor
```

architecturally finished.

Do **not** continue adding generic abstractions to this branch.

The next architecture effort should be a separate design/branch focused on:

```text
Presentation Host / Plugin Architecture
```

Its first design problem should be:

> Allow an external producer to provide a value such as a website's current online-user count and request that Status Trio display it in the center slot, while the external producer supplies state only and is never allowed to draw arbitrary UI.

That future system should build on:

```text
IconSceneState
IconSceneMapper
existing Menu Bar/Dock rendering
```

rather than modifying or bypassing the renderer.
## Repository review amendments (binding)

Reviewed against `1c1049399ccdddb17ea73cd590445e8292abb856` on `codex/2.0-presentation-refactor`.
The three cleanup goals are accepted. This is scoped cleanup of the existing icon pipeline; it does not provide a plugin host or alternate scene publication API.

- The built-in mapper is presently pure and not actor-isolated, but the injected closure is MainActor-bound. Use an explicit default closure `{ inputs, configuration in IconPresentationMapper.scene(inputs: inputs, configuration: configuration) }`, consistent with AGENTS.md's prohibition on passing actor-isolated methods as function values. Do not use the draft's direct method default.
- Keep the existing static output helper and pass the injected mapper explicitly. This allows initialization before all instance properties are initialized and preserves both canonical/test paths without changing lifecycle scheduling.
- `StatusMappings.wifiBars` currently maps -62 and -70 to two bars. Assert the bucket as a precondition. Exact volume identity is invariant only within dots buckets or while muted; unmuted arc is continuous and must retain that distinction.
- Device metadata tests must resolve the same IconSymbolSource, with Bluetooth route replacement enabled; assert nonnil equal resolved source and exercise the actual resource resolver. Names can legitimately affect hardware classification.
- Source guards belong to presentation architecture coverage, not the actor guard. Match identifier tokens after stripping comments and literals; fail if source files are missing. Include AppIconController's SystemStatusStore boundary. Prove scanner precision with fixtures, including nested comments and literal contents, without adding an AST dependency.
- All changes stay in the existing worktree/2.0 branch. Main is untouched. CI acceptance remains macos-26 / Xcode 26.6 / Swift 6.3.3; non-publishing release preflight is required because this touches actor-bound closure interfaces.
- User requested review, a plan, and Luna execution if the recommendations are sound. Use one Luna implementer for the whole small cleanup, followed by one independent whole-change review. No repeated per-task review loops.
