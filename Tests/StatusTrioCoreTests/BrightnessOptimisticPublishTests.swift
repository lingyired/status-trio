import XCTest
@testable import StatusTrioCore

/// The panel renders `popupSnapshot`, which normally waits for a 500 ms
/// debounce. Interactive brightness writes (wheel/drag) must reach the panel
/// immediately and must not be dragged back by a stale read-back.
@MainActor
final class BrightnessOptimisticPublishTests: XCTestCase {
    private let displayID = "display-1"

    private func makeDisplay(_ scalar: Double) -> DisplayBrightness {
        DisplayBrightness(
            id: displayID,
            name: "XV272U",
            isBuiltin: false,
            scalar: scalar,
            canAdjust: true,
            backend: .directDDC,
            source: .directDDC
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
}

// MARK: - Minimal monitors

@MainActor
private final class FakeBrightnessMonitor: BrightnessMonitoring {
    let updates: AsyncStream<BrightnessStatus>
    private let continuation: AsyncStream<BrightnessStatus>.Continuation
    private(set) var lastWrittenScalar: Double = 0

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func setBrightness(_ scalar: Double, forDisplayID displayID: String) {
        lastWrittenScalar = scalar
    }
    func finishBrightnessAdjustment(displayID: String) {}
    func send(_ value: BrightnessStatus) { continuation.yield(value) }
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
