import Foundation
import XCTest
@testable import StatusTrioCore

/// Accessory battery notifications are the second event source behind the
/// Bluetooth row. They follow the battery claim rather than the visible surface
/// alone, they debounce for longer than a connect/disconnect because the power
/// manager posts them often, and the safety-net poll still runs behind them.
@MainActor
final class BluetoothAccessoryBatteryEventTests: XCTestCase {
    private let address = "AC:90:85:C2:9C:1F"

    // MARK: - The event source

    func testAccessoryBatteryEventsCoalesceIntoOneDebouncedRefresh() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeAccessoryBatteryEventMonitor(isAvailable: true)
        let sleeper = ManualEventSleeper()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: [:]),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            accessoryBatteryEvents: events,
            accessoryBatteryEventDebounceInterval: .seconds(3),
            accessoryBatteryEventDebounceSleep: { duration in await sleeper.sleep(duration) }
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }

        // The registration is held only while a surface actually shows levels, so
        // a visible surface alone must not start it.
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertFalse(events.isRunning, "the battery registration must wait for a battery claim")

        controller.requestBatteryLevels("bluetooth.summary")
        XCTAssertTrue(events.isRunning)
        XCTAssertTrue(controller.isMonitoringAccessoryBatteryEvents)

        events.emit()
        events.emit()
        events.emit()
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(
            sleeper.durations.first,
            .seconds(3),
            "an accessory battery notification must hold the read for its own longer interval"
        )
        XCTAssertEqual(reader.readCount, 1, "the debounce must hold the read until it fires")

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }

        // Releasing the claim releases the registration, whatever else is still
        // on screen.
        controller.releaseBatteryLevels("bluetooth.summary")
        XCTAssertFalse(events.isRunning)
        XCTAssertFalse(controller.isMonitoringAccessoryBatteryEvents)
    }

    /// A refused registration is not a failure: the safety-net poll is what
    /// carries the levels, exactly as it does for the connect events.
    func testAnUnavailableEventSourceLeavesTheSafetyNetAsTheOnlySource() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeAccessoryBatteryEventMonitor(isAvailable: false)
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: [:]),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            accessoryBatteryEvents: events
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")

        XCTAssertFalse(controller.isMonitoringAccessoryBatteryEvents)
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// The registration is a system resource, so closing the surface has to
    /// release it even while the level claim is still held.
    func testReleasingTheSurfaceStopsTheAccessoryRegistration() async {
        let events = FakeAccessoryBatteryEventMonitor(isAvailable: true)
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: [:]),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            accessoryBatteryEvents: events
        )

        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")
        XCTAssertTrue(events.isRunning)

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertFalse(events.isRunning, "closing the surface must release the registration")

        controller.deactivate()
    }

    func testADefaultControllerHasNoAccessoryEventSource() {
        let controller = BluetoothDeviceController(
            stateMonitor: AccessoryEventStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        XCTAssertFalse(controller.hasAccessoryBatteryEventSource)
    }

    /// Production must hand the controller the real sources; the defaults are
    /// `nil` so unit tests never touch the system's notification centre or spawn
    /// `/usr/bin/pmset`.
    func testAppEnvironmentWiresTheAccessorySources() {
        let store = AppEnvironment.makeStore(
            batteryMonitor: AccessoryEventBatteryMonitor(),
            wifiMonitor: AccessoryEventWiFiMonitor(),
            volumeMonitor: AccessoryEventVolumeMonitor()
        )
        XCTAssertTrue(store.bluetoothDevices.hasAccessoryBatteryEventSource)
    }

    // MARK: - The second battery source

    /// The case the second source exists for: a connected device the report
    /// carries no level for.
    func testTheSecondSourceFillsADeviceTheReportHasNoLevelFor() async {
        let accessoryReader = StubAccessoryBatteryReader(levels: [
            BluetoothAccessoryBatteryLevel(
                name: "机灵的耳机",
                vendorID: 76,
                productID: 8207,
                part: .left,
                percentage: 93
            )
        ])
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(devices: [pairedDevice]),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: [:]),
            accessoryBatteryReader: accessoryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")

        await waitUntil { accessoryReader.readCount == 1 }
        await waitUntil { controller.batteryLevels[self.normalizedAddress]?.left == 93 }
        XCTAssertEqual(controller.batteryLevels[normalizedAddress]?.summary, "L 93%")

        controller.deactivate()
    }

    /// The common case must not pay for a second subprocess.
    func testAReportThatCoversEveryDeviceDoesNotReadTheSecondSource() async {
        let accessoryReader = StubAccessoryBatteryReader(levels: [
            BluetoothAccessoryBatteryLevel(
                name: "机灵的耳机",
                vendorID: 76,
                productID: 8207,
                part: .left,
                percentage: 93
            )
        ])
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(devices: [pairedDevice]),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: [
                normalizedAddress: BluetoothBatteryLevel(
                    deviceAddress: address,
                    main: 64,
                    left: nil,
                    right: nil,
                    caseLevel: nil
                )
            ]),
            accessoryBatteryReader: accessoryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")

        await waitUntil { controller.batteryLevels[self.normalizedAddress]?.main == 64 }
        XCTAssertEqual(accessoryReader.readCount, 0, "a covered report must not cost a second read")

        controller.deactivate()
    }

    /// A failed primary read that the second source cannot fill keeps its line:
    /// the panel must never go quiet about a read that failed outright.
    func testAFailedReportKeepsItsLineWhenTheSecondSourceAddsNothing() async {
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(devices: [pairedDevice]),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: nil),
            accessoryBatteryReader: StubAccessoryBatteryReader(levels: []),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")

        await waitUntil { controller.batteryLevelsReadFailed }
        XCTAssertTrue(controller.batteryLevels.isEmpty)

        controller.deactivate()
    }

    func testAccessoryFallbackPublishesFreshnessAndExpiresFromObservationTime() async throws {
        let accessoryReader = StubAccessoryBatteryReader(levels: [
            BluetoothAccessoryBatteryLevel(
                name: "机灵的耳机", vendorID: 76, productID: 8207,
                part: nil, percentage: 55
            )
        ])
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(devices: [pairedDevice]),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: nil),
            accessoryBatteryReader: accessoryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let device = BluetoothDevice(
            id: address, name: "AirPods", kind: .audio,
            isConnected: true, airPodsModel: .airPodsPro
        )
        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")
        await waitUntil { controller.batteryLevels[normalizedAddress]?.main == 55 }

        let observedAt = try XCTUnwrap(controller.batteryLevelsUpdatedAt)
        XCTAssertLessThanOrEqual(
            Date().timeIntervalSince(observedAt),
            AirPodsBatteryIconSnapshot.freshnessInterval
        )
        let expired = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: .placeholder,
            bluetoothDevices: [device],
            batteryLevels: controller.batteryLevels,
            batteryLevelsUpdatedAt: observedAt,
            now: observedAt.addingTimeInterval(AirPodsBatteryIconSnapshot.freshnessInterval + 1)
        )
        XCTAssertEqual(expired.availability[RingSource.airPodsBattery.rawValue], .unavailable(.temporarilyStale))
        controller.deactivate()
    }

    /// A failed primary read that the second source does fill has something to
    /// show, so the failure line goes with it.
    func testAFailedReportLiftsItsLineWhenTheSecondSourceFillsIt() async {
        let controller = BluetoothDeviceController(
            worker: CountingBluetoothDeviceReader(devices: [pairedDevice]),
            stateMonitor: AccessoryEventStateMonitor(),
            batteryReader: StubBatteryReader(levels: nil),
            accessoryBatteryReader: StubAccessoryBatteryReader(levels: [
                BluetoothAccessoryBatteryLevel(
                    name: "机灵的耳机",
                    vendorID: 76,
                    productID: 8207,
                    part: nil,
                    percentage: 55
                )
            ]),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.activate()
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.requestBatteryLevels("bluetooth.summary")

        await waitUntil { controller.batteryLevels[self.normalizedAddress]?.main == 55 }
        XCTAssertFalse(controller.batteryLevelsReadFailed)

        controller.deactivate()
    }

    // MARK: - Helpers

    private var normalizedAddress: String {
        BluetoothBatteryReader.normalizedAddress(address)
    }

    private var pairedDevice: BluetoothDevice {
        BluetoothDevice(
            id: address,
            name: "机灵的耳机",
            kind: .audio,
            isConnected: true,
            vendorID: 76,
            productID: 8207
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }
}

/// The accessory battery monitor, with the registration result under the test's
/// control so a refused registration can be exercised.
private final class FakeAccessoryBatteryEventMonitor: BluetoothAccessoryBatteryEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let isAvailable: Bool
    private var handler: (@Sendable () -> Void)?
    private var running = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isRunning: Bool { lock.withLock { running } }

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            self.handler = handler
            running = isAvailable
            return isAvailable
        }
    }

    func stop() {
        lock.withLock {
            handler = nil
            running = false
        }
    }

    func emit() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

private final class CountingBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let devices: [BluetoothDevice]

    init(devices: [BluetoothDevice] = [
        BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "机灵的耳机", kind: .audio, isConnected: true)
    ]) {
        self.devices = devices
    }

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success(devices))
    }
}

private final class StubBatteryReader: BluetoothBatteryReading, @unchecked Sendable {
    private let levels: [String: BluetoothBatteryLevel]?

    init(levels: [String: BluetoothBatteryLevel]?) {
        self.levels = levels
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion(levels)
    }
}

private final class StubAccessoryBatteryReader: BluetoothAccessoryBatteryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let levels: [BluetoothAccessoryBatteryLevel]?

    init(levels: [BluetoothAccessoryBatteryLevel]?) {
        self.levels = levels
    }

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        lock.withLock { count += 1 }
        completion(levels)
    }
}

@MainActor
private final class AccessoryEventStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

@MainActor
private final class AccessoryEventBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class AccessoryEventWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class AccessoryEventVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

/// `notify_cancel` is the only thing that invalidates a `notify(3)`
/// registration, so a token that is merely dropped leaves the callback armed.
/// These pin the bookkeeping against counted fakes, the way the IOBluetooth
/// monitor's registrations are pinned, without touching the system's
/// notification centre.
final class AccessoryPowerNotifyEventMonitorTests: XCTestCase {
    /// The keys are Apple's own wording, so a typo in one silently removes an
    /// event source: it is pinned here rather than in a comment.
    func testTheKeysAreTheOnesThePowerManagerPosts() {
        XCTAssertEqual(
            AccessoryPowerNotifyEventMonitor.notificationKeys,
            [
                "com.apple.system.accpowersources.timeremaining",
                "com.apple.system.accpowersources.attach"
            ]
        )
    }

    func testEveryKeyIsRegisteredAndEveryRegistrationIsCancelledOnStop() {
        let collector = AccessoryTokenCollector()
        let monitor = AccessoryPowerNotifyEventMonitor { _, _ in
            collector.makeToken()
        }

        XCTAssertTrue(monitor.start(handler: {}))
        XCTAssertTrue(monitor.isRegistered)
        XCTAssertEqual(
            collector.tokens.count,
            AccessoryPowerNotifyEventMonitor.notificationKeys.count
        )

        monitor.stop()
        XCTAssertEqual(collector.tokens.map(\.cancelCount), [1, 1])
        XCTAssertFalse(monitor.isRegistered)
    }

    /// A system that refuses every registration is not an error: the controller
    /// keeps the safety-net poll as its only source.
    func testARefusedRegistrationReportsUnavailable() {
        let monitor = AccessoryPowerNotifyEventMonitor { _, _ in nil }

        XCTAssertFalse(monitor.start(handler: {}))
        XCTAssertFalse(monitor.isRegistered)
    }

    /// A second `start` displaces the first registration, and the displaced one
    /// has to be cancelled rather than dropped.
    func testARepeatedStartCancelsTheDisplacedRegistrations() {
        let collector = AccessoryTokenCollector()
        let monitor = AccessoryPowerNotifyEventMonitor { _, _ in
            collector.makeToken()
        }

        XCTAssertTrue(monitor.start(handler: {}))
        XCTAssertTrue(monitor.start(handler: {}))

        let tokens = collector.tokens
        XCTAssertEqual(tokens.count, 4)
        XCTAssertEqual(tokens.map(\.cancelCount), [1, 1, 0, 0])

        monitor.stop()
        XCTAssertEqual(tokens.map(\.cancelCount), [1, 1, 1, 1])
    }

    /// Teardown releases whatever is still registered, and doing it twice must
    /// not cancel a registration twice.
    func testStopIsIdempotent() {
        let collector = AccessoryTokenCollector()
        let monitor = AccessoryPowerNotifyEventMonitor { _, _ in
            collector.makeToken()
        }

        XCTAssertTrue(monitor.start(handler: {}))
        monitor.stop()
        monitor.stop()

        XCTAssertEqual(collector.tokens.map(\.cancelCount), [1, 1])
    }
}

private final class AccessoryTokenCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [CountingAccessoryBatteryEventToken] = []

    var tokens: [CountingAccessoryBatteryEventToken] { lock.withLock { stored } }

    func makeToken() -> CountingAccessoryBatteryEventToken {
        let token = CountingAccessoryBatteryEventToken()
        lock.withLock { stored.append(token) }
        return token
    }
}

/// A counted stand-in for a registered `notify(3)` key.
private final class CountingAccessoryBatteryEventToken: AccessoryBatteryEventToken, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var cancelCount: Int { lock.withLock { calls } }

    func cancel() {
        lock.withLock { calls += 1 }
    }
}
