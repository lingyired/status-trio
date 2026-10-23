import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothRadioPowerControllerTests: XCTestCase {
    func testReadsPowerStateWithoutChangingTheRadio() {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        let controller = BluetoothRadioPowerController(backend: backend)

        controller.refresh()

        XCTAssertEqual(controller.power, .on)
        XCTAssertEqual(backend.setRequests, [])
    }

    func testInitializationDefersTheBackendAndPrivatePowerRead() {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        var factoryCalls = 0
        let controller = BluetoothRadioPowerController(backendFactory: {
            factoryCalls += 1
            return backend
        })

        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(backend.readCount, 0)
        XCTAssertEqual(controller.power, .unknown)

        controller.refresh()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(backend.readCount, 1)
        XCTAssertEqual(controller.power, .on)
    }

    func testPowerControlVisibilityRequiresPermissionAndPanelSection() {
        for authorization in [
            BluetoothAuthorizationStatus.notDetermined,
            .denied,
            .restricted
        ] {
            XCTAssertFalse(BluetoothPowerControlVisibility.canConfigure(
                authorization: authorization,
                showsInStatusPanel: true
            ))
            XCTAssertFalse(BluetoothPowerControlVisibility.showsPanelControl(
                authorization: authorization,
                showsInStatusPanel: true,
                isEnabled: true
            ))
        }

        XCTAssertFalse(BluetoothPowerControlVisibility.canConfigure(
            authorization: .allowed,
            showsInStatusPanel: false
        ))
        XCTAssertFalse(BluetoothPowerControlVisibility.showsPanelControl(
            authorization: .allowed,
            showsInStatusPanel: true,
            isEnabled: false
        ))
        XCTAssertTrue(BluetoothPowerControlVisibility.canConfigure(
            authorization: .allowed,
            showsInStatusPanel: true
        ))
        XCTAssertTrue(BluetoothPowerControlVisibility.showsPanelControl(
            authorization: .allowed,
            showsInStatusPanel: true,
            isEnabled: true
        ))
    }

    func testUnavailableBackendCannotBeToggled() async {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: false, initialState: .unknown)
        let controller = BluetoothRadioPowerController(backend: backend)

        await controller.setPower(false)

        XCTAssertEqual(controller.power, .unavailable)
        XCTAssertEqual(backend.setRequests, [])
        XCTAssertFalse(controller.canSetPower)
    }

    func testRequestWaitsForTheReadBackStateRatherThanOptimisticallyChanging() async {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        // The write is accepted, but the system has not changed power yet.
        backend.powerAfterAcceptedWrite = .on
        backend.changesPowerAfterAcceptedWrite = false
        let controller = BluetoothRadioPowerController(
            backend: backend,
            readBackAttempts: 2,
            sleep: { _ in }
        )

        let changed = await controller.setPower(false)

        XCTAssertEqual(backend.setRequests, [false])
        XCTAssertEqual(controller.power, .on)
        XCTAssertEqual(controller.failure, .stateDidNotChange)
        XCTAssertFalse(changed)
    }

    func testDelayedSystemTransitionIsObservedBeforeReportingFailure() async {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        backend.powerAfterAcceptedWrite = .on
        backend.changesPowerAfterAcceptedWrite = false
        backend.readPowerHook = { readCount in
            if readCount >= 3 {
                backend.powerAfterAcceptedWrite = .off
            }
        }
        let controller = BluetoothRadioPowerController(
            backend: backend,
            readBackAttempts: 4,
            sleep: { _ in }
        )

        let changed = await controller.setPower(false)

        XCTAssertTrue(changed)
        XCTAssertEqual(controller.power, .off)
        XCTAssertNil(controller.failure)
    }

    func testAcceptedWriteBecomesTheReportedPowerAfterReadBack() async {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        backend.powerAfterAcceptedWrite = .off
        let controller = BluetoothRadioPowerController(backend: backend)

        let changed = await controller.setPower(false)

        XCTAssertEqual(controller.power, .off)
        XCTAssertNil(controller.failure)
        XCTAssertFalse(controller.isChanging)
        XCTAssertTrue(changed)
    }

    func testRepeatedTapWhileChangingIsIgnored() async {
        let backend = BluetoothRadioPowerBackendSpy(isAvailable: true, initialState: .on)
        backend.powerAfterAcceptedWrite = .off
        backend.holdsWrite = true
        let controller = BluetoothRadioPowerController(backend: backend)

        let first = Task { await controller.setPower(false) }
        await backend.waitUntilWriteStarts()
        await controller.setPower(true)

        XCTAssertEqual(backend.setRequests, [false])

        backend.releaseWrite()
        _ = await first.value
    }

    func testDisconnectConfirmationOnlyCoversConnectedInputCapableDevices() {
        let keyboard = BluetoothDevice(
            id: "AA",
            name: "MX Keys",
            kind: .peripheral(.keyboard),
            isConnected: true
        )
        let headphones = BluetoothDevice(
            id: "BB",
            name: "AirPods",
            kind: .audio,
            isConnected: true
        )
        let unknown = BluetoothDevice(
            id: "CC",
            name: "Unknown",
            kind: .unknown,
            isConnected: true
        )

        XCTAssertTrue(BluetoothRadioPowerPolicy.requiresConfirmation(
            beforeTurningOff: [headphones, keyboard]
        ))
        XCTAssertTrue(BluetoothRadioPowerPolicy.requiresConfirmation(
            beforeTurningOff: [unknown]
        ))
        XCTAssertFalse(BluetoothRadioPowerPolicy.requiresConfirmation(
            beforeTurningOff: [headphones]
        ))
    }

    func testTurningTheRadioOffClearsDevicesAndTurningItBackOnRefreshes() async {
        let devices = [
            BluetoothDevice(
                id: "AA",
                name: "MX Keys",
                kind: .peripheral(.keyboard),
                isConnected: true
            )
        ]
        let reader = RadioMutableBluetoothDeviceReader(devices: devices)
        let monitor = RadioBluetoothStateMonitor()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: monitor,
            batteryReader: RadioSilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        controller.activate()
        await waitUntil { controller.devices.count == 1 }

        monitor.emit(authorization: .allowed, managerState: .poweredOff)

        XCTAssertEqual(controller.availability, .poweredOff)
        XCTAssertTrue(controller.devices.isEmpty)

        monitor.emit(authorization: .allowed, managerState: .poweredOn)
        await waitUntil { controller.devices.map(\.id) == ["AA"] }

        XCTAssertEqual(controller.devices.map(\.id), ["AA"])
        controller.deactivate()
    }

    func testBackendReadsPrivateStateAndFallsBackWhenSymbolsAreMissing() {
        BluetoothRadioPowerTestSymbols.requestedStates = []
        let available = IOBluetoothRadioPowerBackend(symbols: .init(
            readPower: { 0 },
            setPower: { BluetoothRadioPowerTestSymbols.requestedStates.append($0) },
            preferencesAvailable: { 1 }
        ))

        XCTAssertTrue(available.isAvailable)
        XCTAssertEqual(available.readPower(), .off)

        let missing = IOBluetoothRadioPowerBackend(symbols: .init(
            readPower: nil,
            setPower: nil,
            preferencesAvailable: nil
        ))
        XCTAssertFalse(missing.isAvailable)
        XCTAssertEqual(missing.readPower(), .unavailable)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }
}

private enum BluetoothRadioPowerTestSymbols {
    nonisolated(unsafe) static var requestedStates: [Int32] = []
}

@MainActor
private final class BluetoothRadioPowerBackendSpy: BluetoothRadioPowerBacking {
    let isAvailable: Bool
    var powerAfterAcceptedWrite: BluetoothRadioPower
    var changesPowerAfterAcceptedWrite = true
    var holdsWrite = false
    var readPowerHook: ((Int) -> Void)?
    private(set) var setRequests: [Bool] = []
    private(set) var readCount = 0
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var writeStarted = false

    init(isAvailable: Bool, initialState: BluetoothRadioPower) {
        self.isAvailable = isAvailable
        powerAfterAcceptedWrite = initialState
    }

    func readPower() -> BluetoothRadioPower {
        readCount += 1
        readPowerHook?(readCount)
        return isAvailable ? powerAfterAcceptedWrite : .unavailable
    }

    func setPower(_ enabled: Bool) async -> Bool {
        setRequests.append(enabled)
        writeStarted = true
        writeWaiters.forEach { $0.resume() }
        writeWaiters = []
        if holdsWrite {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        if changesPowerAfterAcceptedWrite {
            powerAfterAcceptedWrite = enabled ? .on : .off
        }
        return true
    }

    func waitUntilWriteStarts() async {
        guard !writeStarted else { return }
        await withCheckedContinuation { writeWaiters.append($0) }
    }

    func releaseWrite() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }
}

@MainActor
private final class RadioBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(.allowed, .poweredOn)
    }

    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
}

private final class RadioMutableBluetoothDeviceReader: BluetoothPairedDeviceReading {
    let lock = NSLock()
    var devices: [BluetoothDevice]
    private(set) var readCount = 0

    init(devices: [BluetoothDevice]) {
        self.devices = devices
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        let devices = lock.withLock {
            readCount += 1
            return self.devices
        }
        completion(.success(devices))
    }
}

private final class RadioSilentBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
