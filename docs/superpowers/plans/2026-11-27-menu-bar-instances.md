# 菜单栏自定义实例 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create multiple independent two-line menu-bar status items, each built from text/data-source segments, with per-line styling, configurable click/hover panels, disable-only right-click, and persisted positions.

**Architecture:** Every instance is its own `NSStatusItem` with a custom-drawn subview (approach A). A pure `MenuBarInstanceRenderer` measures and draws the two lines; a controller owns the status items; a metric registry reuses existing hardware/status snapshots as a display-only layer, and a demand coordinator registers per-instance owners so sampling is aggregated and released.

**Tech Stack:** Swift 6.4 / AppKit (`NSStatusItem`, `NSAttributedString`/CoreText drawing), SwiftUI for Settings, Swift Testing (`import Testing`) for unit tests, existing `SettingsStore`/`SettingsSemanticCatalog`/`SettingsPreferenceCatalog` infrastructure.

**Spec:** `docs/superpowers/specs/2026-11-27-menu-bar-instances-design.md` (v3, frozen)

## Global Constraints

- Deployment floor macOS 13; do not use `isolated deinit`, experimental `IsolatedDeinit`, `weak let`, or pass an actor-isolated method directly as a function value (use an explicit closure).
- All persisted/observable state is `@MainActor`; follow existing `SettingsStore` `@Published` + `didSet` JSON-encode pattern.
- New user-visible settings MUST be added to `SettingsSemanticCatalog` and to the `SettingsPreferenceCatalog` export/import allowlist, and `docs/settings/settings-inventory.md` kept current.
- Menu Bar/Dock scene parity applies to the MAIN icon only. New instances are intentionally menu-bar-only: document and test that they never touch the Dock.
- No new polling/animation/logging/background work. Every metric demand has an owner and a stop path; disabled/removed instances release demand.
- No truncation/fixed width: instance width is adaptive (content + innerPadding + outerMargin). Numeric segments use tabular digits.
- Never weaken/skip/retry a test to go green.
- Test entry point is `bash scripts/test.sh '<filter>'`; visible-UI tests run only under `STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1` via `VisibleUITestCase`, default skipped.
- Color resolution is a **temporary minimal copy** of `HardwareDetailView.metricColor`; leave `HardwareDetailView` unchanged and add `// TODO(p3): converge with HardwareDetailView` where copied.
- Limits (from spec §6.1): instance cap 20; innerPadding/outerMargin range 0…24; ≤32 segments per line; ≤64 chars per text segment; `schemaVersion = 1`.

## Review Focus

1. **System menu-bar overflow vs user removal** — when macOS runs out of room, an item's `isVisible` must not be treated as a user drag-out; the instance must stay enabled and keep its demand. Pinned by Task 7 tests.
2. **Programmatic visibility changes self-triggering removal handling** — our own `setVisible` must never be read back as a user removal (the fund01 churn bug). Pinned by Task 7 tests.
3. **Shared-metric demand leak / double sampling** — two instances on the same metric must share one sample, and disabling/removing either must release only its own owner. Pinned by Task 11 tests.
4. **Hover panel cross-instance close** — a stale delayed-close from instance A must not close instance B's freshly opened panel. Pinned by Task 10 tests.
5. **Width jitter / multi-segment measurement** — the two lines share one width = max(line widths) + padding; a value change must not shift the item in `content` mode beyond tabular tolerance. Pinned by Task 5 tests.

---

## File Structure

**New (core):**
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceModels.swift` — Codable config + validation.
- `Sources/StatusTrioCore/MenuBar/MenuBarMetricRegistry.swift` — metric ids, titles, formats, availability mapping.
- `Sources/StatusTrioCore/MenuBar/MenuBarMetricColorResolver.swift` — copied minimal color logic.
- `Sources/StatusTrioCore/MenuBar/MenuBarMetricValueProvider.swift` — read snapshots → readings.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceRenderer.swift` — measure + draw.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceActivation.swift` — pure activation resolution.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceRightClickMenu.swift` — pure menu descriptor.
- `Sources/StatusTrioCore/MenuBar/MenuBarHoverPanelStateMachine.swift` — hover/pin state machine.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceDemandCoordinator.swift` — owner-based demand.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstanceVisibilityTracker.swift` — removal-vs-overflow decision.
- `Sources/StatusTrioCore/MenuBar/MenuBarInstancesController.swift` — owns `NSStatusItem`s.

**New (settings UI):**
- `Sources/StatusTrioCore/UI/Settings/MenuBarInstancesSectionView.swift`
- `Sources/StatusTrioCore/UI/Settings/MenuBarInstancesListModel.swift`
- `Sources/StatusTrioCore/UI/Settings/MenuBarInstanceEditorView.swift`
- `Sources/StatusTrioCore/UI/Settings/MenuBarInstanceEditorModel.swift`
- `Sources/StatusTrioCore/UI/Settings/MenuBarLineChipEditorView.swift`

**Modified:** `SettingsStore.swift`, `Settings/Semantic/SettingsSemanticCatalog.swift`, `SettingsPreferenceCatalog.swift`, `UI/Settings/SettingsView.swift`, `UI/Settings/SettingsNavigationModel.swift`, `App/AppEnvironment.swift`, `UI/StatusBarController.swift`, `Localization/LocalizationKey.swift`, all `Resources/*.lproj/Localizable.strings`, `docs/settings/settings-inventory.md`.

**Tests (new):** `Tests/StatusTrioCoreTests/MenuBarModelsTests.swift`, `MenuBarMetricRegistryTests.swift`, `MenuBarMetricColorResolverTests.swift`, `MenuBarMetricValueProviderTests.swift`, `MenuBarInstanceRendererTests.swift`, `MenuBarInstanceActivationTests.swift`, `MenuBarInstanceRightClickMenuTests.swift`, `MenuBarHoverPanelStateMachineTests.swift`, `MenuBarInstanceDemandCoordinatorTests.swift`, `MenuBarInstanceVisibilityTrackerTests.swift`, `MenuBarInstancesStoreTests.swift`, `MenuBarInstancesTransferTests.swift`, `MenuBarInstanceEditorModelTests.swift`.

---

### Task 1: Core Codable models + configuration validation

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceModels.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarModelsTests.swift`

**Interfaces:**
- Produces: all Codable types below, plus `MenuBarInstancesConfiguration.validated() -> (config: MenuBarInstancesConfiguration, warnings: [String])`.

```swift
struct ColorValue: Codable, Equatable, Sendable { var red: Double; var green: Double; var blue: Double; var alpha: Double }
enum LineColor: Codable, Equatable, Sendable { case inheritSource; case fixed(ColorValue) }
enum LineAlignment: String, Codable, CaseIterable, Sendable { case leading, center, trailing }
enum MenuBarIconSource: Codable, Equatable, Sendable { case sfSymbol(String); case emoji(String); case asset(String) }
struct MenuBarIconSpec: Codable, Equatable, Sendable { var source: MenuBarIconSource; var tint: Bool }
enum MenuBarMetricID: String, Codable, CaseIterable, Identifiable, Sendable {
  case cpuUsage, cpuTemperature, gpuUsage, gpuTemperature, memoryUsage,
       diskReadSpeed, diskWriteSpeed, networkDownload, networkUpload,
       fanRPM, batteryLevel, wifiConnectionStatus, outputVolume, screenBrightness
  var id: String { rawValue }
}
enum MenuBarLineSegment: Codable, Equatable, Sendable { case text(String); case metric(MenuBarMetricID) }
struct MenuBarLine: Codable, Equatable, Sendable { var segments: [MenuBarLineSegment]; var icon: MenuBarIconSpec?; var color: LineColor; var isBold: Bool; var fontSize: Double?; var usesMonospacedDigits: Bool; var alignment: LineAlignment }
enum SystemSettingsPane: String, Codable, CaseIterable, Sendable { case wifi, bluetooth, battery, sound, network }
enum InstanceActivation: Codable, Equatable, Sendable { case none; case sameAsMainIcon; case panel(String); case openAppSettings; case openActivityMonitor; case openSystemSettings(SystemSettingsPane) }
enum InstanceRightClick: Codable, Equatable, Sendable { case sameAsMainIcon; case quickAction(String) }
struct MenuBarInstance: Codable, Equatable, Identifiable, Sendable {
  var id: UUID; var name: String; var isEnabled: Bool
  var top: MenuBarLine?; var bottom: MenuBarLine?
  var leadingIcon: MenuBarIconSpec?
  var innerPadding: Double; var outerMargin: Double
  var clickAction: InstanceActivation; var hoverAction: InstanceActivation; var rightClick: InstanceRightClick
}
struct MenuBarInstancesConfiguration: Codable, Equatable, Sendable { var schemaVersion: Int; var instances: [MenuBarInstance] }
```

- [ ] **Step 1: Write the failing test** — `MenuBarModelsTests.swift`
  - `testRoundTrip`: build one instance with top `.text("CPU ")` + `.metric(.cpuUsage)`, bottom `.metric(.cpuTemperature)`, encode/decode, assert equal.
  - `testDefaultsForNewInstance`: factory `MenuBarInstance.default()` has `innerPadding == 0`, `outerMargin == 4`, `clickAction == .panel("summary")`, `hoverAction == .none`, `rightClick == .sameAsMainIcon`, `isEnabled == true`.
  - `testValidatedRejectsMoreThan20`: 21 instances → `.validated().config.instances.count == 20` and one warning.
  - `testValidatedDropsDuplicateIDs`: two same `id` → keeps first, one warning.
  - `testValidatedClampsAndDrops`: innerPadding 99 → 24; a text segment of 100 chars → 64; unknown metric raw JSON is dropped (decode a single-instance JSON with `"metric":"bogus"` inside segments) leaving 0 metric segments + warning.
- [ ] **Step 2: Run test to verify it fails** — `bash scripts/test.sh 'MenuBarModelsTests'` → FAIL (types missing).
- [ ] **Step 3: Implement the models + `MenuBarInstance.default()` + `validated()`** in `MenuBarInstanceModels.swift`. `validated()` enforces: cap 20, unique ids (keep first), clamp padding to 0…24, clamp text segments to 64 chars, ≤32 segments (drop overflow), drop unsupported metric (decode tolerant via custom `init(from:)` on `MenuBarLineSegment` that throws to be filtered — instead decode segments as raw strings and filter in `validated`). `schemaVersion` default 1.
- [ ] **Step 4: Run test to verify it passes** — `bash scripts/test.sh 'MenuBarModelsTests'` → PASS.
- [ ] **Step 5: Commit** — `git add Sources/StatusTrioCore/MenuBar/MenuBarInstanceModels.swift Tests/StatusTrioCoreTests/MenuBarModelsTests.swift && git commit -m "feat(menubar): add menu bar instance models"`

---

### Task 2: Metric registry (display-only)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarMetricRegistry.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarMetricRegistryTests.swift`

**Interfaces:**
- Consumes: `MenuBarMetricID`, `HardwareMonitorMetric`, `HardwareMetricID`, `HardwareMetricsSnapshot`, `StatusSnapshot`, `HardwareMetricAvailability`, `NetworkSpeedFormatter`.
- Produces:
```swift
enum MenuBarMetricValueKind: Equatable, Sendable { case numeric; case text }
struct MenuBarMetricReading: Equatable, Sendable { var text: String; var value: Double?; var availability: HardwareMetricAvailability }
enum MenuBarMetricRegistry {
  static func titleKey(for: MenuBarMetricID) -> LocalizationKey
  static func valueKind(for: MenuBarMetricID) -> MenuBarMetricValueKind
  static func hardwareMonitorMetric(for: MenuBarMetricID) -> HardwareMonitorMetric?
  static func format(_ value: Double, for: MenuBarMetricID) -> String   // numeric only
}
```
- [ ] **Step 1: Write the failing test**
  - `testAllIdsHaveTitleAndKind`: every `MenuBarMetricID.allCases` returns a title key and a kind; `wifiConnectionStatus` is `.text`, the rest `.numeric`.
  - `testFormats`: `format(45.0, .cpuUsage) == "45%"`; `format(62.4, .cpuTemperature) == "62°"` (whole-degree); `format(1500, .fanRPM) == "1500 RPM"`; disk/network speed uses `NetworkSpeedFormatter` (assert non-empty + contains "B"); `format(80, .batteryLevel) == "80%"`.
  - `testHardwareMapping`: `.cpuUsage → .cpuUsage`, `.batteryLevel → .batteryLevel`, `.wifiConnectionStatus → nil`.
  - `testPrecisionNames`: registry count for the exact list equals 14 (guards accidental renames).
- [ ] **Step 2: Run** `bash scripts/test.sh 'MenuBarMetricRegistryTests'` → FAIL.
- [ ] **Step 3: Implement** mapping table + format dispatch (percent `"%.0f%%"`, temperature `"%.0f°"`, RPM `"%.0f RPM"`, speeds via `NetworkSpeedFormatter`). Add `LocalizationKey` cases referenced here are created in Task 17; for now reference an existing pattern — add temporary `.menubarMetricCPUUsage` etc. in Task 17; to keep this task compiling, define a local `--` fallback is NOT allowed; instead create the `LocalizationKey` cases in this task's step 3 as minimal additions and finish the strings in Task 17. (Commit message notes strings pending.)
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git add Sources/StatusTrioCore/MenuBar/MenuBarMetricRegistry.swift Sources/StatusTrioCore/Localization/LocalizationKey.swift Tests/StatusTrioCoreTests/MenuBarMetricRegistryTests.swift && git commit -m "feat(menubar): metric registry"`

---

### Task 3: Minimal color resolver (copied)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarMetricColorResolver.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarMetricColorResolverTests.swift`

**Interfaces:**
- Consumes: `HardwareMonitorMetric`, `IconRGBA`, `HardwareRingColorConfiguration`, `LineColor`, `ColorValue`.
- Produces:
```swift
enum MenuBarMetricColorResolver {
  static func sourceColor(for metric: MenuBarMetricID,
                          overrides: [HardwareMonitorMetric: IconRGBA],
                          batteryLevel: Double?) -> IconRGBA
  static func appliedColor(line: LineColor, source: IconRGBA) -> IconRGBA
}
```
- [ ] **Step 1: Write the failing test**
  - `testRecommendedFallback`: no override → equals `HardwareRingColorConfiguration.recommendedBaseColor(for: .cpuUsage)`.
  - `testUserOverride`: override `.cpuUsage` → returned color is override.
  - `testBatteryUsesStatusColor`: `.batteryLevel` with `batteryLevel: 10` yields the low-battery status color used by the icon ring (assert it differs from the 90 value's color).
  - `testFixedWins`: `appliedColor(line: .fixed(cv), source: x)` returns `cv`; `.inheritSource` returns `source`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** by copying the minimal branch logic from `HardwareDetailView.metricColor` (do not modify that file); add `// TODO(p3): converge with HardwareDetailView` at top.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 4: Metric value provider

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarMetricValueProvider.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarMetricValueProviderTests.swift`

**Interfaces:**
- Consumes: `HardwareMetricsSnapshot`, `StatusSnapshot`, `MenuBarMetricRegistry`, `HardwareMetricID`, `HardwareMetricAvailability`.
- Produces:
```swift
protocol MenuBarMetricValueProviding { func readings(for metrics: Set<MenuBarMetricID>, hardware: HardwareMetricsSnapshot, status: StatusSnapshot) -> [MenuBarMetricID: MenuBarMetricReading] }
struct MenuBarMetricValueProvider: MenuBarMetricValueProviding { ... }
```
- [ ] **Step 1: Write the failing test**
  - `testMeasuredFormatsValue`: snapshot with `.cpuUsage` sample value 45, availability `.measured` → reading text `"45%"`, value 45.
  - `testZeroShowsZeroNotDash`: value 0, `.measured` → `"0%"` (not `--`).
  - `testNonMeasuredShowsDash`: `.stale` / `.unsupported` / `.collecting` → text `"--"`, value nil.
  - `testWiFiStatusText`: `status.wifi` connected → reading text equals the connected localization string; disconnected → disconnected string; kind `.text`.
  - `testBatteryFromStatusSnapshot`: battery level 80 → `"80%"`.
  - `testUnknownMetricMissing`: metric with no sample → `"--"`, `.collecting`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** dispatch per `MenuBarMetricID` to `hardware.samples[id]` or `status.battery/wifi/volume/brightness`. Wi‑Fi status uses `WiFiStatus` connected state → connected/disconnected localization keys.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 5: Renderer measurement

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceRenderer.swift` (measurement half)
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceRendererTests.swift`

**Interfaces:**
- Consumes: `MenuBarInstance`, `[MenuBarMetricID: MenuBarMetricReading]`, `LineColor`, colors resolver.
- Produces:
```swift
struct MenuBarRenderInput: Equatable { var instance: MenuBarInstance; var readings: [MenuBarMetricID: MenuBarMetricReading] }
struct MenuBarInstanceMeasurement: Equatable {
  var lineWidths: [Double]   // top, bottom (0 when absent/empty)
  var contentWidth: Double   // max(lineWidths)
  var totalWidth: Double     // contentWidth + 2*innerPadding + 2*outerMargin
  var lineHeights: [Double]
  var totalHeight: Double
}
enum MenuBarInstanceRenderer {
  static func measure(_ input: MenuBarRenderInput, appearance: NSAppearance) -> MenuBarInstanceMeasurement
}
```
- [ ] **Step 1: Write the failing test**
  - `testSharedWidthIsMaxPlusPadding`: top short, bottom long, innerPadding 6, outerMargin 4 → `totalWidth == max(lineWidths)+2*6+2*4` (tolerance 0.5).
  - `testLongerTextWider`: `.text("CPU")` vs `.text("CPU CPU CPU")` → larger `lineWidths[0]`.
  - `testSegmentConcatenation`: `[.text("CPU "), .metric(.cpuUsage)]` reading `"45%"` width ≈ width of `"CPU 45%"` (tolerance 1.0).
  - `testMonospacedReducesJitter`: with `usesMonospacedDigits`, widths of `"9%"` and `"10%"` differ by the tabular digit width only (assert difference < width of "9").
  - `testSingleLineHeightCentered`: bottom nil → `lineHeights[1] == 0` and total height equals one line height.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** measurement using `NSString.size(withAttributes:)`, tabular font via `NSFont.monospacedDigitSystemFont`, icon widths (row icon height = line height, leading column fixed width), `--` for non-measured numeric.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 6: Renderer drawing

**Files:**
- Modify: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceRenderer.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceRendererTests.swift` (add drawing tests)

**Interfaces:**
- Produces: `static func render(_ input: MenuBarRenderInput, appearance: NSAppearance, scale: CGFloat) -> NSImage?`
- [ ] **Step 1: Write failing tests**
  - `testRenderProducesImageAtMeasuredSize`: image non-nil, `image.size` ≈ `measure(...).totalWidth/totalHeight` (tolerance 0.5).
  - `testSingleColorStillRenders` and `testTwoLineRenders`: both produce non-nil.
  - `testDarkAppearanceDoesNotCrash`: render with `.init(named: .darkAqua)!` non-nil.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** drawing: per line, row icon → segments (each with own color) → trailing; honor alignment within totalWidth; leading column icon vertically centered; `tint` template drawing for SF Symbol/asset; emoji drawn as text; return `NSImage` sized to measurement, `isTemplate=false` (colored).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 7: Visibility tracker + status-item handle abstraction

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceVisibilityTracker.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceVisibilityTrackerTests.swift`

**Interfaces:**
- Produces:
```swift
enum MenuBarVisibilityDecision: Equatable { case none; case userRemoved; }
@MainActor final class MenuBarInstanceVisibilityTracker {
  init()
  func setSelfInitiated(_ active: Bool)           // wrap our own setVisible calls
  func evaluate(previousVisible: Bool, newVisible: Bool, isEnabled: Bool) -> MenuBarVisibilityDecision
}
```
- [ ] **Step 1: Write failing tests**
  - `testSelfInitiatedChangeIgnored`: setSelfInitiated(true) then previous true→new false → `.none`.
  - `testUserDragOutDetected`: not self-initiated, isEnabled true, true→false → `.userRemoved`.
  - `testAlreadyDisabledIgnored`: isEnabled false, true→false → `.none`.
  - `testNoChangeIgnored`: false→false / true→true → `.none`.
  - `testSystemOverflowDoesNotFlipVisible`: doc-test asserting `evaluate` only reacts to actual visible transition (overflow leaves visible true → `.none`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the pure tracker. Document that real controller only calls `evaluate` on KVO `isVisible` changes, and that `setSelfInitiated` is reset in `defer`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 8: Activation resolver (pure)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceActivation.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceActivationTests.swift`

**Interfaces:**
- Consumes: `InstanceActivation`, `MenuBarQuickActionAvailability`, `StatusPanelRoute` (by raw string mapping).
- Produces:
```swift
enum MenuBarInstanceResolvedAction: Equatable {
  case noop
  case followMainIcon
  case showPanel(routeRaw: String)
  case openAppSettings
  case openActivityMonitor
  case openSystemSettings(SystemSettingsPane)
}
enum MenuBarInstanceActivationResolver {
  static func resolve(_ activation: InstanceActivation, forHover: Bool) -> MenuBarInstanceResolvedAction
}
```
- [ ] **Step 1: Write failing tests**
  - `testPanelMaps`: `.panel("cpu")` → `.showPanel(routeRaw: "cpu")`.
  - `testHoverRejectsExternalActions`: `forHover: true` with `.openAppSettings` → `.noop`; with `.openSystemSettings(.wifi)` → `.noop`; with `.panel("summary")` → `.showPanel("summary")`.
  - `testLeftAllowsExternal`: `forHover: false` with `.openActivityMonitor` → `.openActivityMonitor`.
  - `testSameAsMainIcon`: `.sameAsMainIcon` → `.followMainIcon` both modes.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**; hover drops `.openAppSettings/.openActivityMonitor/.openSystemSettings` to `.noop`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 9: Right-click menu descriptor (pure)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceRightClickMenu.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceRightClickMenuTests.swift`

**Interfaces:**
- Produces:
```swift
enum MenuBarMenuEntry: Equatable {
  case action(id: String, titleKey: LocalizationKey, enabled: Bool)
  case separator
}
enum MenuBarInstanceRightClickMenu {
  static func entries(rightClick: InstanceRightClick, mainActionTitleKey: LocalizationKey, mainActionEnabled: Bool) -> [MenuBarMenuEntry]
}
```
- [ ] **Step 1: Write failing tests**
  - `testQuickActionPlusDisable`: `.quickAction("toggleWiFi")` → first entry is that action (enabled per input), then `.separator`, then disable entry `menubar.instance.disable`.
  - `testSameAsMainIcon`: `.sameAsMainIcon` → first entry uses `mainActionTitleKey`/`mainActionEnabled`.
  - `testNeverContainsDelete`: no entry id contains "delete".
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**.

---

### Task 10: Hover panel state machine (pure)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarHoverPanelStateMachine.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarHoverPanelStateMachineTests.swift`

**Interfaces:**
- Produces:
```swift
struct MenuBarHoverPanelState: Equatable { var isOpen: Bool; var sourceInstanceID: UUID?; var presentedByHover: Bool; var generation: Int }
enum MenuBarHoverEvent { case hoverEnter(UUID), hoverExit(UUID), openConfirmed(UUID), click(UUID), closeAll }
enum MenuBarHoverDecision: Equatable { case none; case scheduleOpen(UUID, generation: Int); case scheduleClose(UUID, generation: Int); case present(UUID); case pin; case close }
@MainActor final class MenuBarHoverPanelStateMachine { private(set) var state: MenuBarHoverPanelState; func handle(_ event: MenuBarHoverEvent) -> MenuBarHoverDecision; func fire(generation: Int, _ action: MenuBarHoverDecision) -> MenuBarHoverDecision }
```
- [ ] **Step 1: Write failing tests**
  - `testHoverEnterSchedulesOpen`: `.hoverEnter(a)` → `.scheduleOpen(a, gen)`.
  - `testHoverExitBeforeOpenCancels`: enter then exit same gen → `.scheduleClose(a, gen)`; `fire` returns `.none`.
  - `testStaleCloseDoesNotCloseNewInstance`: open A (gen N), then hoverEnter B → gen N+1; firing old `scheduleClose(A, N)` → `.none`.
  - `testClickOnHoverPanelPins`: openA presentedByHover true, `.click(A)` → `.pin` (panel stays).
  - `testOpenOnlyOnePanel`: opening B while A open produces close of A then present B (assert decision sequence or final sourceInstanceID == B and single panel).
- [ ] **Step 2–4:** implement + pass. **Step 5: Commit**.

---

### Task 11: Demand coordinator (owner aggregation)

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstanceDemandCoordinator.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceDemandCoordinatorTests.swift`

**Interfaces:**
- Produces:
```swift
@MainActor final class MenuBarInstanceDemandCoordinator {
  init(register: @escaping (String, Set<HardwareMetricID>) -> Void, unregister: @escaping (String) -> Void)
  func setInstances(_ instances: [MenuBarInstance])   // computes metric set per enabled instance
  func metricSet(for instance: MenuBarInstance) -> Set<HardwareMetricID>
  var registeredOwners: [String: Set<HardwareMetricID>] { get }
}
```
- [ ] **Step 1: Write failing tests**
  - `testDisabledInstanceHasNoDemand`: disabled instance → owner absent, unregister called.
  - `testOwnerIDFormat`: owner key `"menuBarInstance:<uuid>"`.
  - `testSharedMetricRegisteredOnce`: two enabled instances both use CPU → each owner registered with `{.cpuUsage}`; a downstream aggregate (test a helper `mergedMetrics`) contains `.cpuUsage` once.
  - `testRemovingInstanceUnregistersOwner`: remove from list → unregister called for that id only, other remains.
  - `testWiFiStatusNeedsNoHardwareDemand`: `wifiConnectionStatus` not in `HardwareMetricID` set (no hardware sampling needed) — assert metricSet excludes it.
- [ ] **Step 2–4:** implement + pass. **Step 5: Commit**.

---

### Task 12: Status item controller

**Files:**
- Create: `Sources/StatusTrioCore/MenuBar/MenuBarInstancesController.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstancesControllerTests.swift` (introduce `MenuBarStatusItemHandle`/`MenuBarStatusBarProviding` fakes in this file)

**Interfaces:**
- Consumes: Task 5/6 renderer, Task 7 visibility tracker, Task 8 activation, Task 9 menu, Task 10 hover machine.
- Produces:
```swift
protocol MenuBarStatusItemHandle: AnyObject {
  var length: CGFloat { get set }
  var isVisible: Bool { get set }
  var autosaveName: String? { get set }
  var hasRemovalBehavior: Bool { get set }
  var button: NSStatusBarButton? { get }
}
protocol MenuBarStatusBarProviding { func makeItem() -> MenuBarStatusItemHandle }
@MainActor final class MenuBarInstancesController {
  init(statusBar: MenuBarStatusBarProviding, onUserRemoved: @escaping (UUID) -> Void)
  func sync(_ configuration: MenuBarInstancesConfiguration)
  func update(id: UUID, renderState: MenuBarRenderState)
  var itemIDs: [UUID] { get }
}
struct MenuBarRenderState { var image: NSImage; var width: CGFloat }
```
- [ ] **Step 1: Write failing tests**
  - `testCreateOneItemPerEnabledInstance`: 2 enabled → `itemIDs.count == 2`; disabled excluded.
  - `testAutosaveNamePerInstance`: created handle gets `"statusTrio.menuBarInstance.<uuid>"`.
  - `testRemovalBehaviorEnabled`: `hasRemovalBehavior == true`.
  - `testLengthMatchesRenderState`: after `update(width: 57)`, handle `length == 57`.
  - `testDisableOnlyHidesNotRemoves`: disabling keeps item id in `itemIDs` (retained) but `isVisible=false`.
  - `testProgrammaticVisibleDoesNotCallOnUserRemoved`: controller-initiated hide → `onUserRemoved` not called; external true→false → called once with id.
- [ ] **Step 2–4:** implement + pass (KVO via `handle` observation stubbed through a `notifyExternalVisibilityChange(id:newVisible:)` test hook that feeds the tracker). **Step 5: Commit**.

---

### Task 13: SettingsStore persistence

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstancesStoreTests.swift`

**Interfaces:**
- Produces: `@Published var menuBarInstances: MenuBarInstancesConfiguration`, `static let menuBarInstancesDefaultsKey`, and `func updateMenuBarInstance(_ instance: MenuBarInstance)` / `func deleteMenuBarInstance(id: UUID)` / `func moveMenuBarInstance(from:to:)` that write through `didSet` JSON encode like `hardwareMonitorMetricColors`.
- [ ] **Step 1: Write failing tests** (use a scratch `UserDefaults(suiteName:)`):
  - `testDefaultEmpty`: new store → `menuBarInstances.instances.isEmpty`, `schemaVersion == 1`.
  - `testPersistAndReload`: set one instance → reload store from same defaults → instance present with same id.
  - `testDeleteRemoves`: add two, delete one → one remains; persisted.
  - `testMoveReorders`: move index 0 → 1 changes order and persists.
  - `testCorruptDataFallsBackToEmpty`: write garbage under key → init yields empty config, no crash.
- [ ] **Step 2–4:** implement + pass. **Step 5: Commit**.

---

### Task 14: Semantic catalog + preference catalog + inventory

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/Semantic/SettingsSemanticCatalog.swift`, `Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift`, `docs/settings/settings-inventory.md`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstancesTransferTests.swift` (plus existing `SettingsSchemaArtifactConsistencyTests` must stay green)

**Interfaces:**
- Produces: semantic descriptor id `menubar.instances` (category `menubar`, type `.object`, `accessPolicy` transferable+profile-safe=false), and a `SettingsPreferenceCatalog` entry keyed `"menuBarInstances"` with default empty config, validation via `MenuBarInstancesConfiguration.validated()`, write via `store.menuBarInstances = ...`.
- [ ] **Step 1: Write failing tests**
  - `testSnapshotContainsMenuBarInstances`: snapshot includes key `"menuBarInstances"` default empty.
  - `testRoundTripOneInstance`: snapshot → prepare → apply to fresh store → one instance restored.
  - `testImportOver20Rejected`: prepare with 21 instances → key dropped, warning mentioning cap.
  - `testCorruptImportFallsBack`: invalid payload → default empty + warning.
- [ ] **Step 2–4:** implement + run `bash scripts/test.sh 'MenuBarInstancesTransferTests'` then `bash scripts/test.sh 'SettingsSchemaArtifactConsistencyTests'` → PASS. **Step 5: Commit**.

---

### Task 15: Settings UI — list section + list model

**Files:**
- Create: `Sources/StatusTrioCore/UI/Settings/MenuBarInstancesSectionView.swift`, `Sources/StatusTrioCore/UI/Settings/MenuBarInstancesListModel.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsView.swift`, `Sources/StatusTrioCore/UI/Settings/SettingsNavigationModel.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstancesListModelTests.swift`

**Interfaces:**
- Produces: `SettingsView.Section.menuBarInstances` (glyph `.symbol("rectangle.topthird.inset.filled")`, tint `.teal`), a switch branch rendering `MenuBarInstancesSectionView(store:)`; `MenuBarInstancesListModel` with `addPreset(_ preset: MenuBarPreset)`, `duplicate(id:)`, `delete(id:)`, `move(from:to:)`, `setEnabled(id:_:)`, `canAdd` (count < 20). `MenuBarPreset`: `.cpu`, `.temperature`, `.memory`, `.network`, `.battery` (returns a `MenuBarInstance`).
- [ ] **Step 1: Write failing tests**
  - `testAddPresetCPU`: `.cpu` yields top `[.text("CPU "), .metric(.cpuUsage)]`, bottom nil.
  - `testCanAddFalseAt20`: 20 instances → `canAdd == false`.
  - `testDuplicateNewID`: duplicate copy has new UUID and same content.
  - `testDeleteAndMovePersistThroughStore`.
- [ ] **Step 2–4:** implement + pass; run `bash scripts/test.sh 'SettingsViewTests'` to ensure section switch compiles/works. **Step 5: Commit**.

---

### Task 16: Chip editor model + editor view + preview

**Files:**
- Create: `Sources/StatusTrioCore/UI/Settings/MenuBarInstanceEditorModel.swift`, `MenuBarInstanceEditorView.swift`, `MenuBarLineChipEditorView.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstanceEditorModelTests.swift`

**Interfaces:**
- Produces: `MenuBarInstanceEditorModel` operating on a `MenuBarInstance`:
  `addTextSegment(line:topOrBottom:)`, `addMetricSegment(_:line:)`, `removeSegment(at:line:)`, `moveSegment(from:to:line:)`, `setText(_:at:line:)`, `setColor(_:line:)`, `setAlignment`, `setIcon`, `setPadding(inner:outer:)`, `setActivation(click:hover:rightClick:)`, and `previewImage(snapshot:) -> NSImage?` calling `MenuBarInstanceRenderer.render` with a mock snapshot (never creates a status item, never registers demand).
- [ ] **Step 1: Write failing tests**
  - `testAddMetricSegmentOrder`: add text then metric → segment order preserved.
  - `testMoveSegment`: moving segment 1→0 reorders.
  - `testRemoveSegment`: removal by index.
  - `testPreviewUsesRendererWithoutStatusItem`: `previewImage` returns non-nil image and a spy asserts no status-item provider instantiated (pass a flag / inject renderer closure).
  - `testEditWritesStore`: after edits `store.menuBarInstances.instances[0]` reflects change.
- [ ] **Step 2–4:** implement + pass. **Step 5: Commit**.

---

### Task 17: Localization keys + strings for all shipped languages

**Files:**
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift` and every `Sources/StatusTrioCore/Resources/<lang>.lproj/Localizable.strings`
- Test: `Tests/StatusTrioCoreTests/MenuBarLocalizationTests.swift` (and existing localization regression filter)

**Interfaces:** keys `menubar.instances.title`, `menubar.instance.disable`, `menubar.metric.cpuUsage`…`menubar.metric.screenBrightness` (14), `menubar.metric.wifiConnected`, `menubar.metric.wifiDisconnected`, `menubar.editor.addText`, `menubar.editor.addMetric`, `menubar.editor.innerPadding`, `menubar.editor.outerMargin`, `menubar.editor.clickAction`, `menubar.editor.hoverAction`, `menubar.editor.rightClick`, `menubar.editor.leadingIcon`, `menubar.editor.segmentPlaceholder`.
- [ ] **Step 1: Write failing test** — every new key has a non-empty value in `zh-Hans` and `en`; key appears in `LocalizationKey.allCases`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** add keys + translations in zh-Hans/en and the remaining shipped `.lproj` directories (use English fallback text where the language is not authored; follow existing file format).
- [ ] **Step 4: Run** `bash scripts/test.sh 'MenuBarLocalizationTests'` and `bash scripts/verify-local.sh docs` → PASS. **Step 5: Commit**.

---

### Task 18: Wiring, panel anchoring, integration tests + acceptance

**Files:**
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`, `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Test: `Tests/StatusTrioCoreTests/MenuBarInstancesIntegrationTests.swift`

**Interfaces:**
- Add to `StatusBarController`: `func presentStatusPanel(route: StatusPanelRoute, anchoredTo buttonFrame: NSRect, presentedByHover: Bool)` that reuses `presentPopover(relativeTo:...)`'s panel with the given anchor (do not use `statusItemButtonScreenFrame`). Expose `func presentRouteRaw(_ raw: String, anchoredTo: NSRect)` mapping raw→`StatusPanelRoute` (unknown → `summary`).
- `MenuBarInstancesController` gains `onActivate: (UUID, MenuBarInstanceResolvedAction, NSRect) -> Void`; AppEnvironment builds the controller, subscribes `settings.$menuBarInstances` to `sync` + `demandCoordinator.setInstances`, feeds render state from `HardwareMonitorObservable.snapshot` + `SystemStatusStore.snapshot`, and routes actions (panel → `statusBarController`, app settings → `settingsWindowController.show()`, activity monitor → `NSWorkspace.open(activityMonitorURL)`, system settings → existing `openSystemSettings`).
- [ ] **Step 1: Write failing tests** (headless, pure):
  - `testActivationRoutesToPanelWithInstanceAnchor`: spy `presentStatusPanel` receives the instance's button frame (1,2,3,4), not main icon frame.
  - `testUnknownRouteFallsBackToSummary`.
  - `testOpenSystemSettingsMapsPane`: `.openSystemSettings(.wifi)` → resolver action `.openSystemSettings(.wifi)` (already Task 8) and AppEnvironment wiring maps to Wi‑Fi settings URL list (assert URL contains `com.apple.wifi-settings-extension`).
  - `testMenuBarInstancesNeverTouchDock`: syncing instances does not call any Dock/`AppIconController` dependency (assert injected Dock spy untouched) — covers parity constraint.
- [ ] **Step 2–4:** implement + pass; run `bash scripts/test.sh 'MenuBarInstancesIntegrationTests'`.
- [ ] **Step 5: Full verification + acceptance doc** — run `bash scripts/verify-local.sh full`; record the tested SHA/branch/warnings in the plan's task note; write `docs/menubar-instances-acceptance.md` with the manual matrix from spec §14 (widths, two/single/empty lines, dark/light, Retina, icons, activation matrix, drag-out one instance, restart positions, disable releases demand, export/import, import >20 reject).
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(menubar): wire instances, panel anchoring, verification"`

---

## Self-Review (author check)

- **Spec coverage:** models/validation (T1), metric registry + precise names + Wi‑Fi text (T2/T4), color inherit/fixed/threshold copy (T3), adaptive width + inner/outer margin (T5), two-line/column/row icon/tint (T6), enable-vs-visible + drag-out (T7/T12), activation incl hover restriction + system settings (T8/T18), right-click disable-only no delete (T9), hover state machine (T10), owner demand (T11), persistence/autosaveName (T12/T13), settings pane + chip editor + preview-without-status-item (T15/T16), semantic + transfer + inventory (T14), localization (T17), verification matrix (T18). No spec section left without a task.
- **Type consistency:** `MenuBarMetricReading`, `MenuBarRenderInput/Measurement`, `MenuBarInstanceResolvedAction`, `MenuBarMenuEntry`, `MenuBarVisibilityDecision` names are used identically across tasks.
- **Review Focus:** each of the five lines has a test in its owning task (T7×2, T11, T10, T5).
- **Known implementation-time verification (not a task):** whether macOS space-overflow ever flips `isVisible`/`button.window`; if it does, extend `MenuBarInstanceVisibilityTracker` with the `button.window` signal — recorded in spec §9.4.
