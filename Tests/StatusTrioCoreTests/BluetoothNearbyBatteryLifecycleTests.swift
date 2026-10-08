import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothNearbyBatteryLifecycleTests: XCTestCase {
    func testScannerRequiresActiveControllerPopoverRequestAndAvailableBluetooth() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertEqual(scanner.startCount, 0, "a claim cannot start an inactive controller")

        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOff)
        XCTAssertEqual(scanner.startCount, 0, "Bluetooth off must keep the scanner stopped")

        monitor.emit(authorization: .allowed, state: .poweredOn)
        XCTAssertEqual(scanner.startCount, 1)

        controller.deactivate()
    }

    func testSettingsDiscoveryDoesNotScanAndViewClaimDoesNotPermitReads() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.startCount, 0, "a Settings claim alone must not start scanning")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "a Settings claim does not grant reads")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertEqual(scanner.startCount, 0, "the summary view alone is not an active popover")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "a view claim cannot substitute for visible rows")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertEqual(scanner.startCount, 1, "foreground summary claims demand discovery")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "discovery does not grant reads without visible rows")

        controller.deactivate()
    }

    func testHidingEitherCompatibleAliasRevokesForegroundBLEReadAndRejectsLateCallback() async {
        let bleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
        let ble = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(bleID), name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )
        let trusted = BluetoothDevice(
            id: AppleDeviceID.trustedDevice("phone-c").rowID, name: "Phone", kind: .mobile(.phone),
            isConnected: false, appleMobileModel: "iPhone18,1", isReadOverTheAir: true
        )

        for hiddenID in [ble.id, trusted.id] {
            let scanner = NearbyBatteryScannerSpy()
            let monitor = NearbyBatteryStateMonitorSpy()
            let controller = makeReadyController(scanner: scanner, monitor: monitor)
            controller.configureNearbyBLEDevices(enabled: true, knownIDs: [bleID], hiddenIDs: [])
            controller.requestNearbyBLEDiscovery("foreground-summary")
            let reading = NearbyBluetoothBatteryDevice(
                id: bleID, name: "Phone", batteryLevel: 52, model: "iPhone18,1",
                manufacturer: nil, lastUpdated: Date()
            )
            controller.setVisibleNearbyBLEDevices([bleID], for: "panel")
            XCTAssertEqual(scanner.allowedReadDeviceIDs, [bleID])
            scanner.publish([reading])
            await Task.yield()
            XCTAssertEqual(controller.nearbyBatteryDevices, [reading])
            let callbackBeforeHide = scanner.onDevicesChanged

            let options = BluetoothDeviceListOptions(
                showsList: true, maxVisibleDevices: 5, order: [],
                hiddenDeviceAddresses: [hiddenID]
            )
            let effectiveOptions = BluetoothDeviceListPresentation.expandingHiddenAliases(
                in: options, among: [ble, trusted]
            )
            let hiddenBLEIDs = Set(effectiveOptions.hiddenDeviceAddresses.compactMap {
                BluetoothDeviceIdentity.bleUUID(from: $0)
            })
            controller.configureNearbyBLEDevices(enabled: true, knownIDs: [bleID], hiddenIDs: hiddenBLEIDs)

            XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "hiding either alias immediately revokes the BLE read")
            XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "hiding an alias purges its cached BLE reading")
            callbackBeforeHide?([reading])
            await Task.yield()
            XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "the previous read callback cannot restore the hidden row")
            controller.deactivate()
        }
    }

    func testReleasingPopoverStopsImmediatelyAndRejectsOldCallbacks() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.startCount, 1)

        let device = nearbyDevice(name: "Sensor", level: 52)
        controller.setVisibleNearbyBLEDevices([device.id], for: "panel")
        scanner.publish([device])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "a visible row accepts its reading")
        let callbackFromStoppedScan = scanner.onDevicesChanged

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)

        var lateDevice = device
        lateDevice.batteryLevel = 91
        lateDevice.lastUpdated = Date().addingTimeInterval(1)
        callbackFromStoppedScan?([lateDevice])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "a captured callback from the stopped generation cannot replace the visible-row cache")

        controller.deactivate()
    }

    func testLeavingBluetoothSummaryStopsNearbyScanWhilePopoverRemainsOpen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.startCount, 1, "an active Bluetooth summary demands a foreground scan")
        let device = nearbyDevice(name: "Sensor", level: 52)
        scanner.publish([device])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "a visible summary row accepts its reading")
        let callbackFromStoppedScan = scanner.onDevicesChanged

        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")

        XCTAssertTrue(controller.hasVisibleSurface, "the overall popover remains open")
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        var lateDevice = device
        lateDevice.batteryLevel = 91
        lateDevice.lastUpdated = Date().addingTimeInterval(1)
        callbackFromStoppedScan?([lateDevice])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "a captured callback from the stopped summary cannot replace its cached reading")
        controller.deactivate()
    }

    /// Turning off the feature stops scanning and clears consented battery readings.
    func testReleasingLastNearbyRequestClearsCacheAndStopsScanner() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Scale", level: 0)])

        controller.configureNearbyBLEDevices(enabled: false, knownIDs: [], hiddenIDs: [])

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    /// A reading accepted while visible is cached while the panel is closed.
    func testClosingPanelRetainsVisibleReadingButStopsScanner() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let device = nearbyDevice(name: "Ling's iPhone", level: 31)
        controller.setVisibleNearbyBLEDevices([device.id], for: "panel")
        scanner.publish([device])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [device.id])

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")

        XCTAssertEqual(scanner.stopCount, 1, "the radio still stops with the panel")
        XCTAssertFalse(scanner.isRunning)
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [device.id], "visible rows retain the last read without active work")
        controller.deactivate()
    }

    /// Losing Bluetooth availability stops discovery and clears battery readings.
    func testUnavailableBluetoothStopsScannerAndClearsNearbyResults() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 61)])

        monitor.emit(authorization: .allowed, state: .poweredOff)

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testDeactivateStopsScannerAndClearsNearbyResults() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 73)])

        controller.deactivate()

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
    }

    func testDeactivateClearsReadingsButKeepsTheFeatureOptInForReopen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let device = nearbyDevice(name: "Sensor", level: 68)
        controller.setVisibleNearbyBLEDevices([device.id], for: "panel")
        scanner.publish([device])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device])

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.deactivate()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)

        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertEqual(scanner.startCount, 2, "the still-enabled feature should restart on the next authorized popover")
        controller.deactivate()
    }

    func testDeinitWithoutDeactivateStopsNearbyScanner() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        var controller: BluetoothDeviceController? = makeController(scanner: scanner, monitor: monitor)
        controller?.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller?.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller?.requestNearbyBLEDiscovery("settings")
        controller?.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller?.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertTrue(scanner.isRunning)

        testController = nil
        controller = nil
        await waitUntil { scanner.stopCount == 1 }
    }

    func testManualRefreshUsesNearbyScannerSeparately() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let worker = NearbyBatteryPairedReaderSpy()
        let controller = makeController(scanner: scanner, monitor: monitor, worker: worker)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        controller.refreshFromUser()

        XCTAssertEqual(scanner.refreshCount, 1)
        XCTAssertGreaterThanOrEqual(worker.readCount, 1)
        controller.deactivate()
    }

    private func makeReadyController(
        scanner: NearbyBatteryScannerSpy,
        monitor: NearbyBatteryStateMonitorSpy,
    ) -> BluetoothDeviceController {
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        return controller
    }

    private func actions(for controller: BluetoothDeviceController) -> StatusPanelActions {
        StatusPanelActions(
            requestNearbyBatteryDevices: { controller.requestNearbyBatteryDevices($0) },
            releaseNearbyBatteryDevices: { controller.releaseNearbyBatteryDevices($0, keepingResults: $1) },
            holdBluetoothSummary: {
                controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
            },
            releaseBluetoothSummary: {
                controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
            }
        )
    }

    private func makeSettings() -> SettingsStore {
        let name = "BluetoothNearbyBatteryLifecycleTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return SettingsStore(defaults: defaults)
    }

    private func makeController(
        scanner: NearbyBatteryScannerSpy,
        monitor: NearbyBatteryStateMonitorSpy,
        worker: NearbyBatteryPairedReaderSpy = NearbyBatteryPairedReaderSpy(),
    ) -> BluetoothDeviceController {
        let controller = BluetoothDeviceController(
            worker: worker,
            stateMonitor: monitor,
            batteryReader: NearbyBatteryLevelReaderSpy(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            nearbyBatteryScanner: scanner
        )
        testController = controller
        return controller
    }

    private var testSelectedIDs: Set<UUID> = []
    private var testController: BluetoothDeviceController?

    private func nearbyDevice(name: String, level: Int) -> NearbyBluetoothBatteryDevice {
        let id = UUID()
        testSelectedIDs.insert(id)
        testController?.configureNearbyBLEDevices(enabled: true, knownIDs: testSelectedIDs, hiddenIDs: [])
        testController?.setVisibleNearbyBLEDevices(testSelectedIDs, for: "panel")
        return NearbyBluetoothBatteryDevice(
            id: id,
            name: name,
            batteryLevel: level,
            model: nil,
            manufacturer: nil,
            lastUpdated: Date()
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Timed out waiting for Nearby scanner state")
    }
}


@MainActor
final class NearbyBatteryScannerSpy: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var allowedReadDeviceIDs: Set<UUID> = []
    private(set) var initialReadDeviceIDs: Set<UUID> = []
    var discoveredCandidates: [NearbyBLEDeviceCandidate] = []
    private(set) var isRunning = false
    private(set) var isScanning = false
    private(set) var startCount = 0
    private(set) var refreshCount = 0
    private(set) var stopCount = 0

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) {
        allowedReadDeviceIDs = ids
    }
    func setInitialReadCandidateIDs(_ ids: Set<UUID>) {
        initialReadDeviceIDs = ids
    }

    func start() {
        startCount += 1
        isRunning = true
    }

    func refresh() {
        refreshCount += 1
    }

    func stop() {
        stopCount += 1
        isRunning = false
        isScanning = false
    }

    func publish(_ devices: [NearbyBluetoothBatteryDevice]) {
        onDevicesChanged?(devices)
    }
}


@MainActor
private final class NearbyBatteryStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    var authorization: BluetoothAuthorizationStatus = .allowed

    func start() {}
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, state: BluetoothManagerState) {
        self.authorization = authorization
        onStateChange?(authorization, state)
    }
}

private final class NearbyBatteryPairedReaderSpy: BluetoothPairedDeviceReading {
    private let lock = NSLock()
    private var storedReadCount = 0

    var readCount: Int { lock.withLock { storedReadCount } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { storedReadCount += 1 }
        completion(.success([]))
    }
}

private final class NearbyBatteryLevelReaderSpy: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
