import Foundation
import XCTest
@testable import StatusTrioCore

/// A device connecting or disconnecting is the event that matters, and it
/// arrives once per device: several at a time must collapse into one read.
@MainActor
final class BluetoothConnectionEventTests: XCTestCase {
    func testConnectEventsCoalesceIntoOneDebouncedRefresh() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: true)
        let sleeper = ManualEventSleeper()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events,
            connectionEventDebounceInterval: .milliseconds(750),
            connectionEventDebounceSleep: { duration in await sleeper.sleep(duration) }
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        // The event registration lives and dies with the popover that shows
        // device state, so the popover claim comes first: a view token only
        // narrows the poll and never starts it (rider 1 of the lifetime task).
        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(events.isRunning)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)

        events.emit()
        events.emit()
        events.emit()
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .milliseconds(750))
        XCTAssertEqual(reader.readCount, 1, "the debounce must hold the read until it fires")

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }

        controller.deactivate()
        XCTAssertFalse(events.isRunning)
    }

    // MARK: - Invalidating the battery gate before the next snapshot

    func testConnectionEventBlocksWarmReadsUntilAFreshSnapshotArrives() async {
        let rig = ConnectionBatteryRig()
        await load(rig)
        rig.controller.requestBatteryLevels("battery")
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.events.emit()
        let received = await rig.sleeper.waitForCallCount(1, timeout: .seconds(2))
        XCTAssertTrue(received)
        XCTAssertTrue(rig.controller.batteryLevels.isEmpty)
        let reads = rig.battery.readCount
        rig.controller.requestBatteryLevels("battery")
        XCTAssertEqual(rig.battery.readCount, reads, "old devices must not warm a new battery read")

        rig.sleeper.releaseOldest()
        await waitUntil { rig.worker.readCount == 2 }
        rig.worker.completeNext(name: "Fresh")
        await waitUntil { rig.controller.devices.first?.name == "Fresh" }
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.controller.deactivate()
    }

    func testPreEventProfilerCompletionCannotUnlockBatteryReads() async {
        let rig = ConnectionBatteryRig()
        await load(rig)
        rig.controller.requestBatteryLevels("battery")
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.controller.refresh()
        XCTAssertEqual(rig.worker.readCount, 2)
        rig.events.emit()
        let received = await rig.sleeper.waitForCallCount(1, timeout: .seconds(2))
        XCTAssertTrue(received)
        let reads = rig.battery.readCount
        rig.worker.completeNext(name: "Pre-event")
        await waitUntil { rig.controller.devices.first?.name == "Pre-event" }
        XCTAssertEqual(rig.battery.readCount, reads, "old generation profiler must not unlock battery reads")
        rig.controller.requestBatteryLevels("battery")
        XCTAssertEqual(rig.battery.readCount, reads)

        rig.sleeper.releaseOldest()
        await waitUntil { rig.worker.readCount == 3 }
        rig.worker.completeNext(name: "Fresh")
        await waitUntil { rig.controller.devices.first?.name == "Fresh" }
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.controller.deactivate()
    }

    func testEveryEventInOneDebouncedBurstInvalidatesTheNewSnapshot() async {
        let rig = ConnectionBatteryRig()
        await load(rig)
        rig.controller.requestBatteryLevels("battery")
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.events.emit()
        let received = await rig.sleeper.waitForCallCount(1, timeout: .seconds(2))
        XCTAssertTrue(received)
        // Another existing refresh may finish before the debounce expires.
        rig.controller.refresh()
        rig.worker.completeNext(name: "Between events")
        await waitUntil { rig.controller.devices.first?.name == "Between events" }
        await waitUntil { !rig.controller.batteryLevels.isEmpty }

        rig.events.emit()
        // Clearing is synchronous in the event handler; the wait only lets the
        // MainActor task that carries the notification run.
        await waitUntil { rig.controller.batteryLevels.isEmpty }
        let reads = rig.battery.readCount
        rig.controller.requestBatteryLevels("battery")
        XCTAssertEqual(rig.battery.readCount, reads, "the second event must invalidate even while a refresh is scheduled")
        rig.sleeper.releaseOldest()
        await waitUntil { rig.worker.readCount == 3 }
        rig.worker.completeNext(name: "After burst")
        await waitUntil { rig.controller.devices.first?.name == "After burst" }
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.controller.deactivate()
    }

    func testConnectionEventRejectsOldAccessoryBeforeTheNextProfilerCompletes() async {
        let rig = ConnectionBatteryRig(accessoryOnly: true)
        await load(rig)
        rig.controller.requestBatteryLevels("battery")
        await waitUntil { rig.accessory.readCount == 1 }
        rig.events.emit()
        let received = await rig.sleeper.waitForCallCount(1, timeout: .seconds(2))
        XCTAssertTrue(received)
        rig.accessory.completeNext()
        await settle()
        XCTAssertTrue(rig.controller.batteryLevels.isEmpty, "old accessory callback must fail the gate immediately after the event")
        // New profiler has not even started: this is the pre-snapshot window.
        XCTAssertEqual(rig.worker.readCount, 1)
        rig.sleeper.releaseOldest()
        await waitUntil { rig.worker.readCount == 2 }
        rig.worker.completeNext(name: "Fresh")
        await waitUntil { rig.accessory.readCount == 2 }
        rig.accessory.completeNext()
        await waitUntil { !rig.controller.batteryLevels.isEmpty }
        rig.controller.deactivate()
    }

    private func load(_ rig: ConnectionBatteryRig) async {
        rig.controller.activate()
        await waitUntil { rig.worker.readCount == 1 }
        rig.worker.completeNext(name: "Initial")
        await waitUntil { rig.controller.hasLoadedDevices }
        rig.controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertTrue(rig.events.isRunning)
    }

    /// The event source is optional: without it the safety-net poll is the only
    /// source, and holding a surface must not crash or spin.
    func testAnUnavailableEventSourceLeavesTheSafetyNetAsTheOnlySource() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: false)
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.popover")

        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// Without an injected source the controller must not reach for the system
    /// on its own; the app wires the IOBluetooth monitor through `makeStore`.
    func testADefaultControllerHasNoSystemEventSource() {
        let controller = BluetoothDeviceController(
            stateMonitor: ConnectionEventStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        XCTAssertFalse(controller.hasConnectionEventSource)
    }

    /// Production must hand the controller a real event source: the default is
    /// `nil` so unit tests never touch the system's Bluetooth service.
    func testAppEnvironmentWiresTheIOBluetoothEventSource() {
        let store = AppEnvironment.makeStore(
            batteryMonitor: ConnectionEventBatteryMonitor(),
            wifiMonitor: ConnectionEventWiFiMonitor(),
            volumeMonitor: ConnectionEventVolumeMonitor()
        )
        XCTAssertTrue(store.bluetoothDevices.hasConnectionEventSource)
    }

    /// The SDK invalidates a device's disconnect registration only through
    /// `unregister()`; overwriting or clearing the stored token leaves the
    /// registration live, so every disconnect aimed one more callback at the
    /// next one. This pins unregister-before-drop on all three paths.
    func testEveryPerDeviceRegistrationIsUnregisteredOnDisconnectReconnectAndStop() {
        let monitor = IOBluetoothConnectionEventMonitor()
        var tokens: [CountingBluetoothNotificationToken] = []

        func register(_ identity: String) {
            let token = CountingBluetoothNotificationToken()
            tokens.append(token)
            monitor.handleDeviceConnected(identity: identity) { token }
        }

        register("AA:BB:CC:DD:EE:01")
        monitor.handleDeviceDisconnected(identity: "AA:BB:CC:DD:EE:01")
        XCTAssertTrue(
            tokens[0].isUnregistered,
            "a disconnect must unregister the device's registration, not just drop it"
        )

        // A reconnect while the old registration is still live replaces the
        // entry; the token it displaced has to be invalidated too.
        register("AA:BB:CC:DD:EE:02")
        register("AA:BB:CC:DD:EE:02")
        XCTAssertTrue(tokens[1].isUnregistered, "a replaced registration must be unregistered")
        XCTAssertFalse(tokens[2].isUnregistered, "the replacement must stay live")

        // Teardown releases whatever is still registered, including a device
        // that never disconnected.
        register("AA:BB:CC:DD:EE:03")
        monitor.stop()
        XCTAssertTrue(tokens[2].isUnregistered, "stop() must unregister the live replacement")
        XCTAssertTrue(tokens[3].isUnregistered, "stop() must unregister every device registration")
        XCTAssertEqual(
            [tokens[0].unregisterCount, tokens[1].unregisterCount, tokens[2].unregisterCount, tokens[3].unregisterCount],
            [1, 1, 1, 1],
            "each registration must be unregistered exactly once"
        )
    }

    /// Both callbacks route through one derivation, so a device with no address
    /// is removed under the key it was registered with. The disconnect path used
    /// to key it differently and left the registration behind.
    func testTheConnectAndDisconnectPathsKeyADeviceIdentically() {
        XCTAssertEqual(
            IOBluetoothConnectionEventMonitor.deviceIdentity(addressString: "AA:BB:CC:DD:EE:01", name: "AirPods Pro"),
            "AA:BB:CC:DD:EE:01"
        )
        XCTAssertEqual(
            IOBluetoothConnectionEventMonitor.deviceIdentity(addressString: nil, name: "AirPods Pro"),
            "AirPods Pro"
        )
        XCTAssertEqual(
            IOBluetoothConnectionEventMonitor.deviceIdentity(addressString: nil, name: nil),
            ""
        )
    }

    /// A device that was already connected when monitoring began never fires a
    /// connect callback, so under the connect path alone it got no disconnect
    /// observation and its departure was only noticed by the slow safety-net
    /// poll. Adoption installs that observation up front; this pins the
    /// bookkeeping it relies on.
    func testAdoptedConnectedDevicesGetTheSameDisconnectBookkeepingAsAConnect() {
        let monitor = IOBluetoothConnectionEventMonitor()
        var tokens: [CountingBluetoothNotificationToken] = []

        func adopt(_ identity: String) -> IOBluetoothConnectionEventMonitor.ConnectedDevice {
            let token = CountingBluetoothNotificationToken()
            tokens.append(token)
            return IOBluetoothConnectionEventMonitor.ConnectedDevice(identity: identity) { token }
        }

        monitor.adoptConnectedDevices([adopt("AA:BB:CC:DD:EE:01")])
        monitor.handleDeviceDisconnected(identity: "AA:BB:CC:DD:EE:01")
        XCTAssertTrue(
            tokens[0].isUnregistered,
            "an adopted device's disconnect must unregister its registration"
        )

        // A device that was adopted and then re-connects replaces the entry; the
        // superseded adopted token has to be unregistered too.
        monitor.adoptConnectedDevices([adopt("AA:BB:CC:DD:EE:02")])
        monitor.handleDeviceConnected(identity: "AA:BB:CC:DD:EE:02") { CountingBluetoothNotificationToken() }
        XCTAssertTrue(tokens[1].isUnregistered, "a reconnect must unregister the adopted registration")

        // Teardown releases what is still live, including an adopted device that
        // never disconnected.
        monitor.adoptConnectedDevices([adopt("AA:BB:CC:DD:EE:03")])
        monitor.stop()
        XCTAssertTrue(tokens[2].isUnregistered, "stop() must unregister an adopted, still-live registration")

        // A registration the SDK refuses (nil) must not create an entry; a later
        // disconnect on that identity is a harmless no-op.
        var refused = 0
        monitor.adoptConnectedDevices([
            IOBluetoothConnectionEventMonitor.ConnectedDevice(identity: "AA:BB:CC:DD:EE:04") {
                refused += 1
                return nil
            }
        ])
        XCTAssertEqual(refused, 1)
        monitor.handleDeviceDisconnected(identity: "AA:BB:CC:DD:EE:04")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }

    /// Let the MainActor jobs a callback dispatched run, without a wall-clock
    /// sleep: the same shape the other lifecycle suites use.
    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }
}

/// One fixture for all event/snapshot windows. Only the debounce is suspended;
/// the two readers complete through callbacks under test control.
@MainActor
private final class ConnectionBatteryRig {
    let worker = ConnectionSnapshotReader()
    let events = FakeBluetoothConnectionEventMonitor(isAvailable: true)
    let sleeper = ManualEventSleeper()
    let battery: ConnectionCountingBatteryReader
    let accessory = ConnectionControlledAccessoryReader()
    let controller: BluetoothDeviceController

    init(accessoryOnly: Bool = false) {
        let battery = ConnectionCountingBatteryReader(empty: accessoryOnly)
        self.battery = battery
        let sleeper = self.sleeper
        controller = BluetoothDeviceController(
            worker: worker, stateMonitor: ConnectionEventStateMonitor(), batteryReader: battery,
            accessoryBatteryReader: accessory,
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events,
            connectionEventDebounceSleep: { duration in await sleeper.sleep(duration) }
        )
    }
}

private final class ConnectionSnapshotReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [@Sendable (BluetoothWorkerResult) -> Void] = []
    private var count = 0
    var readCount: Int { lock.withLock { count } }
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1; completions.append(completion) }
    }
    func completeNext(name: String) {
        let callback = lock.withLock { completions.removeFirst() }
        callback(.success([BluetoothDevice(id: "11:22:33:44:55:66", name: name, kind: .audio,
                                            isConnected: true, vendorID: 76, productID: 8207)]))
    }
}

private final class ConnectionCountingBatteryReader: BluetoothBatteryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let empty: Bool
    init(empty: Bool) { self.empty = empty }
    var readCount: Int { lock.withLock { count } }
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        lock.withLock { count += 1 }
        let address = "11:22:33:44:55:66"
        completion(empty ? [:] : [BluetoothBatteryReader.normalizedAddress(address):
            BluetoothBatteryLevel(deviceAddress: address, main: 55, left: nil, right: nil, caseLevel: nil)])
    }
}

private final class ConnectionControlledAccessoryReader: BluetoothAccessoryBatteryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [@Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void] = []
    private var count = 0
    var readCount: Int { lock.withLock { count } }
    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        lock.withLock { count += 1; completions.append(completion) }
    }
    func completeNext() {
        let callback = lock.withLock { completions.removeFirst() }
        callback([BluetoothAccessoryBatteryLevel(identifier: "one", name: "AirPods", vendorID: 76,
                                                 productID: 8207, part: .left, percentage: 93)])
    }
}

private final class CountingBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
    }
}

private final class ConnectionEventBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class ConnectionEventStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class FakeBluetoothConnectionEventMonitor: BluetoothConnectionEventMonitoring, @unchecked Sendable {
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

/// A counted stand-in for a registered IOBluetooth notification. Only
/// `unregister()` invalidates such a registration, so counting the calls is what
/// makes a registration that was merely dropped observable.
private final class CountingBluetoothNotificationToken: BluetoothNotificationToken, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var unregisterCount: Int { lock.withLock { calls } }
    var isUnregistered: Bool { lock.withLock { calls > 0 } }

    func unregister() {
        lock.withLock { calls += 1 }
    }
}

@MainActor
private final class ConnectionEventBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class ConnectionEventWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class ConnectionEventVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
