import XCTest
@testable import StatusTrioCore

/// The panel renders `popupSnapshot`, which normally waits for a 500 ms
/// debounce. Interactive brightness writes (wheel/drag) must reach the panel
/// immediately and must not be dragged back by a stale read-back.
@MainActor
final class BrightnessOptimisticPublishTests: XCTestCase {
    private let displayID = "display-1"

    private func makeDisplay(_ scalar: Double, readSequence: UInt64? = nil) -> DisplayBrightness {
        DisplayBrightness(
            id: displayID,
            name: "XV272U",
            isBuiltin: false,
            scalar: scalar,
            canAdjust: true,
            backend: .directDDC,
            source: .directDDC,
            readSequence: readSequence
        )
    }

    private func makeStore(_ brightness: FakeBrightnessMonitor) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            brightnessMonitor: brightness,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in },
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: .placeholder,
                brightness: BrightnessStatus(displays: [makeDisplay(0.2)])
            )
        )
    }

    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(10))
    }

    func testBrightnessWritePublishesToThePanelImmediately() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }

        store.setBrightness(0.8, forDisplayID: displayID)

        XCTAssertEqual(
            store.popupSnapshot.brightness.displays.first?.scalar,
            0.8,
            "the panel must follow the wheel without waiting for the read-back"
        )
        XCTAssertEqual(brightness.lastWrittenScalar, 0.8, accuracy: 0.0001)
    }

    func testStaleReadBackDoesNotDragThePanelBack() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }

        store.setBrightness(0.8, forDisplayID: displayID)
        XCTAssertEqual(store.popupSnapshot.brightness.displays.first?.scalar, 0.8)

        // A read-back queued before the write still reports 0.2.
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.2)]))
        await settle()

        XCTAssertEqual(
            store.popupSnapshot.brightness.displays.first?.scalar,
            0.8,
            "a stale read-back must not undo the optimistic value"
        )
    }

    func testConfirmedReadBackClearsTheOptimisticValue() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }

        store.setBrightness(0.8, forDisplayID: displayID)
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.8)]))
        await settle()

        // Now a genuine external change (e.g. the display's own buttons) must be
        // shown instead of the pinned optimistic value.
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.4)]))
        await settle()

        XCTAssertEqual(
            store.popupSnapshot.brightness.displays.first?.scalar,
            0.4,
            "once confirmed, later read-backs own the shown value"
        )
    }

    func testUnreadableReadBackDropsTheOptimisticValue() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }

        store.setBrightness(0.8, forDisplayID: displayID)
        let unavailable = DisplayBrightness(
            id: displayID,
            name: "XV272U",
            isBuiltin: false,
            scalar: nil,
            canAdjust: false,
            backend: .directDDC,
            source: .unavailable(.unresponsive)
        )
        brightness.send(BrightnessStatus(displays: [unavailable]))
        await settle()

        XCTAssertNil(
            store.popupSnapshot.brightness.displays.first?.scalar,
            "a failed write must surface the unavailable state"
        )
    }

    func testAnotherDisplaysNewReadingCannotReleaseThisDisplaysPendingTarget() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.2, readSequence: 10)]))
        await settle()

        store.setBrightness(0.8, forDisplayID: displayID)
        let other = DisplayBrightness(
            id: "other-screen", name: "Other", isBuiltin: true,
            scalar: 0.9, canAdjust: true, backend: .displayServices,
            source: .displayServices, readSequence: 11
        )
        // Only the other screen was read. This screen still carries its cached
        // pre-write value, even though the aggregate snapshot was just published.
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.2, readSequence: 10), other]))
        await settle()
        XCTAssertEqual(store.liveBrightness.displays.first?.scalar, 0.8)
        XCTAssertEqual(store.liveBrightness.displays.last?.scalar, 0.9)

        // A real new observation of this display is authoritative, including
        // quantized values that differ from the requested target by > 2%.
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.75, readSequence: 12), other]))
        await settle()
        XCTAssertEqual(store.liveBrightness.displays.first?.scalar, 0.75)
    }

    func testReadAlreadyPublishedBeforeWriteCannotUndoTheTarget() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }
        // Queue an old reading without giving the consumer a turn yet.
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.2, readSequence: 10)]))
        store.setBrightness(0.8, forDisplayID: displayID)
        await settle()
        XCTAssertEqual(store.liveBrightness.displays.first?.scalar, 0.8)
    }

    private final class SingleDisplayCatalog: DisplayCatalogProviding {
        let display: DisplayDescriptor
        init(_ display: DisplayDescriptor) { self.display = display }
        func currentDisplays() -> [DisplayDescriptor] { [display] }
    }

    private final class ReproDisplayServicesAPI: DisplayServicesBrightnessAPI, @unchecked Sendable {
        var isAvailable = true
        var value: Float
        init(value: Float) { self.value = value }
        func getBrightness(
            _ displayID: CGDirectDisplayID, _ output: UnsafeMutablePointer<Float>
        ) -> Int32 {
            output.pointee = value
            return 0
        }
        func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) -> Int32 {
            self.value = value
            return 0
        }
        func startBrightnessChangeNotifications(
            for displayID: CGDirectDisplayID, observerID: UInt32
        ) -> Bool { true }
        func stopBrightnessChangeNotifications(for displayID: CGDirectDisplayID, observerID: UInt32) {}
    }

    func testExternalRefreshInTheSameTurnAsALocalWriteWinsOverTheOptimisticTarget() async {
        let api = ReproDisplayServicesAPI(value: 0.2)
        let descriptor = DisplayDescriptor(
            id: displayID, name: "Built-in", isBuiltin: true, displayID: 1
        )
        let monitor = BrightnessMonitor(
            catalog: SingleDisplayCatalog(descriptor),
            makeDisplayServices: { id, onUpdate in
                DisplayServicesBrightnessController(displayID: id, api: api, onUpdate: onUpdate)
            }
        )
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            brightnessMonitor: monitor,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in },
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: .placeholder,
                brightness: BrightnessStatus(displays: [makeDisplay(0.2)])
            )
        )
        store.start()
        store.setBrightnessSettingsVisible(true)
        defer { store.stop() }

        store.setBrightness(0.6, forDisplayID: displayID)
        // The display changes from outside before the store's consumer task has
        // drained the write confirmation. `bufferingNewest(1)` keeps only this
        // later reading; the store must still let it replace the old target.
        api.value = 0.3
        monitor.refresh()
        await settle()

        XCTAssertEqual(
            store.liveBrightness.displays.first?.scalar ?? -1,
            0.3,
            accuracy: 0.0001,
            "a later external reading must not stay hidden behind the drag target"
        )
    }

    func testManyExternalRefreshesInOneTurnStillShowTheLastReading() async {
        let api = ReproDisplayServicesAPI(value: 0.2)
        let descriptor = DisplayDescriptor(
            id: displayID, name: "Built-in", isBuiltin: true, displayID: 1
        )
        let monitor = BrightnessMonitor(
            catalog: SingleDisplayCatalog(descriptor),
            makeDisplayServices: { id, onUpdate in
                DisplayServicesBrightnessController(displayID: id, api: api, onUpdate: onUpdate)
            }
        )
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            brightnessMonitor: monitor,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in },
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: .placeholder,
                brightness: BrightnessStatus(displays: [makeDisplay(0.2)])
            )
        )
        store.start()
        store.setBrightnessSettingsVisible(true)
        defer { store.stop() }

        for step in 1...16 {
            api.value = Float(step) / 20
            monitor.refresh()
        }
        await settle()

        XCTAssertEqual(
            store.liveBrightness.displays.first?.scalar ?? -1,
            0.8,
            accuracy: 0.0001,
            "the last external reading must never be dropped"
        )
    }

    func testManyLocalWritesDoNotPinTheTargetWhenTheDisplayChangesExternally() async {
        let api = ReproDisplayServicesAPI(value: 0.2)
        let descriptor = DisplayDescriptor(
            id: displayID, name: "Built-in", isBuiltin: true, displayID: 1
        )
        let monitor = BrightnessMonitor(
            catalog: SingleDisplayCatalog(descriptor),
            makeDisplayServices: { id, onUpdate in
                DisplayServicesBrightnessController(displayID: id, api: api, onUpdate: onUpdate)
            }
        )
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            brightnessMonitor: monitor,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in },
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: .placeholder,
                brightness: BrightnessStatus(displays: [makeDisplay(0.2)])
            )
        )
        store.start()
        store.setBrightnessSettingsVisible(true)
        defer { store.stop() }

        for step in 2...17 {
            store.setBrightness(Double(step) / 20, forDisplayID: displayID)
        }
        api.value = 0.3
        monitor.refresh()
        await settle()

        XCTAssertEqual(
            store.liveBrightness.displays.first?.scalar ?? -1,
            0.3,
            accuracy: 0.0001,
            "a burst of local writes must not hide the later external value"
        )
    }

    func testHidingThePanelDropsThePendingTargetAndShowsTheFreshValueOnReopen() async {
        let brightness = FakeBrightnessMonitor()
        let store = makeStore(brightness)
        store.start()
        store.setPopoverVisible(true)
        defer { store.stop() }

        store.setBrightness(0.8, forDisplayID: displayID)
        XCTAssertEqual(store.popupSnapshot.brightness.displays.first?.scalar, 0.8)

        // The user closes the panel before the write is confirmed; the display
        // is later adjusted from outside (brightness keys or its own buttons).
        store.setPopoverVisible(false)
        brightness.send(BrightnessStatus(displays: [makeDisplay(0.3)]))
        await settle()

        XCTAssertEqual(
            store.liveBrightness.displays.first?.scalar,
            0.3,
            "a pending target must not outlive the panel that produced it"
        )

        store.setPopoverVisible(true)
        await settle()
        XCTAssertEqual(
            store.popupSnapshot.brightness.displays.first?.scalar,
            0.3,
            "reopening must show the display's actual brightness, not the stale target"
        )
    }
}

// MARK: - Minimal monitors

@MainActor
private final class FakeBrightnessMonitor: BrightnessMonitoring {
    let updates: AsyncStream<BrightnessStatus>
    private let continuation: AsyncStream<BrightnessStatus>.Continuation
    private(set) var lastWrittenScalar: Double = 0
    private var readSequences: [String: UInt64] = [:]

    func latestUpdateSequence(forDisplayID displayID: String) -> UInt64 {
        readSequences[displayID] ?? 0
    }

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func setBrightness(_ scalar: Double, forDisplayID displayID: String) {
        lastWrittenScalar = scalar
    }
    func finishBrightnessAdjustment(displayID: String) {}
    func send(_ value: BrightnessStatus) {
        for display in value.displays {
            if let sequence = display.readSequence { readSequences[display.id] = sequence }
        }
        continuation.yield(value)
    }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class FakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation
    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
    func setDetailsVisible(_ visible: Bool) {}
}

@MainActor
private final class FakeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private let catalogContinuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation
    init() {
        (updates, continuation) = AsyncStream.makeStream()
        (betterDisplayCatalogUpdates, catalogContinuation) = AsyncStream.makeStream()
    }
    func start() {}
    func stop() {
        continuation.finish()
        catalogContinuation.finish()
    }
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setExternalVolumeConfigurations(_ configurations: [String: ExternalVolumeConfiguration]) {}
    func refreshBetterDisplayDevices() {}
}
