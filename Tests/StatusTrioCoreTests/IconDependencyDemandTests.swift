import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDependencyDemandTests: XCTestCase {
    func testUnconfiguredIconDoesNotClaimAirPodsBatteryMonitoring() {
        XCTAssertFalse(IconSourceDemandPolicy.requiresAirPodsBattery(in: .classic))
    }

    func testPrimaryAndFallbackBothRequireAirPodsMonitoring() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .airPodsBattery)
        XCTAssertTrue(IconSourceDemandPolicy.requiresAirPodsBattery(in: configuration))
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: nil)
        XCTAssertTrue(IconSourceDemandPolicy.requiresAirPodsBattery(in: configuration))
    }

    func testBatteryOptOutPreventsDetailedAirPodsReads() {
        let connected = [BluetoothDevice(
            id: "AA:BB:CC:DD:EE:10", name: "AirPods", kind: .audio,
            isConnected: true, airPodsModel: .airPodsPro
        )]
        XCTAssertFalse(IconSourceDemandPolicy.shouldReadAirPodsBattery(
            configuration: airPodsConfigured(), userOptedIn: false,
            bluetoothDevices: connected, selectedAddress: nil
        ))
        XCTAssertTrue(IconSourceDemandPolicy.shouldReadAirPodsBattery(
            configuration: airPodsConfigured(), userOptedIn: true,
            bluetoothDevices: connected, selectedAddress: nil
        ))
    }

    func testReconcileIsIdempotentAndReleasesWhenConfigurationNoLongerNeedsAirPods() {
        var activationClaims: [String] = []
        var activationReleases: [String] = []
        var batteryClaims: [String] = []
        var batteryReleases: [String] = []
        var demand = IconSourceDemandBridge()
        let configuration = airPodsConfigured()
        let activate: (String) -> Bool = { activationClaims.append($0); return true }
        let releaseActivation: (String) -> Void = { activationReleases.append($0) }
        let requestBattery: (String) -> Void = { batteryClaims.append($0) }
        let releaseBattery: (String) -> Void = { batteryReleases.append($0) }

        demand.reconcile(configuration: configuration, userOptedInToBackgroundBattery: true,
                         bluetoothDevices: [BluetoothDevice(id: "01", name: "AirPods", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)],
                         selectedAirPodsAddress: nil,
                         requestActivation: activate, releaseActivation: releaseActivation,
                         requestBatteryLevels: requestBattery, releaseBatteryLevels: releaseBattery)
        demand.reconcile(configuration: configuration, userOptedInToBackgroundBattery: true,
                         bluetoothDevices: [BluetoothDevice(id: "01", name: "AirPods", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)],
                         selectedAirPodsAddress: nil,
                         requestActivation: activate, releaseActivation: releaseActivation,
                         requestBatteryLevels: requestBattery, releaseBatteryLevels: releaseBattery)
        demand.reconcile(configuration: .classic, userOptedInToBackgroundBattery: true,
                         bluetoothDevices: [BluetoothDevice(id: "01", name: "AirPods", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)],
                         selectedAirPodsAddress: nil,
                         requestActivation: activate, releaseActivation: releaseActivation,
                         requestBatteryLevels: requestBattery, releaseBatteryLevels: releaseBattery)

        XCTAssertEqual(activationClaims, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertEqual(activationReleases, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertEqual(batteryClaims, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertEqual(batteryReleases, [IconSourceDemandBridge.batteryLevelsToken])
    }

    func testDisconnectedAirPodsReleaseDetailedReadsButKeepConnectionMonitoring() {
        let connected = [BluetoothDevice(
            id: "AA:BB:CC:DD:EE:10", name: "AirPods", kind: .audio,
            isConnected: true, airPodsModel: .airPodsPro
        )]
        let disconnected = [BluetoothDevice(
            id: "AA:BB:CC:DD:EE:10", name: "AirPods", kind: .audio,
            isConnected: false, airPodsModel: .airPodsPro
        )]
        var batteryClaims = 0
        var batteryReleases = 0
        var activationClaims = 0
        var demand = IconSourceDemandBridge()
        let requestActivation: (String) -> Bool = { _ in activationClaims += 1; return true }
        let noOp: (String) -> Void = { _ in }
        demand.reconcile(
            configuration: airPodsConfigured(), userOptedInToBackgroundBattery: true,
            bluetoothDevices: connected, selectedAirPodsAddress: nil,
            requestActivation: requestActivation, releaseActivation: noOp,
            requestBatteryLevels: { _ in batteryClaims += 1 },
            releaseBatteryLevels: { _ in batteryReleases += 1 }
        )
        demand.reconcile(
            configuration: airPodsConfigured(), userOptedInToBackgroundBattery: true,
            bluetoothDevices: disconnected, selectedAirPodsAddress: nil,
            requestActivation: requestActivation, releaseActivation: noOp,
            requestBatteryLevels: { _ in batteryClaims += 1 },
            releaseBatteryLevels: { _ in batteryReleases += 1 }
        )

        XCTAssertEqual(activationClaims, 1, "Lightweight connection events remain claimed while the source is configured")
        XCTAssertEqual(batteryClaims, 1)
        XCTAssertEqual(batteryReleases, 1, "Detailed battery reads release immediately after disconnect")
        XCTAssertTrue(demand.activationClaimed)
        XCTAssertFalse(demand.batteryLevelsClaimed)
    }

    func testConnectedDeviceSourceClaimsMonitoringWithoutBatteryReadOptIn() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .connectedBluetoothDevice
        XCTAssertTrue(IconSourceDemandPolicy.requiresBluetoothMonitor(in: configuration))
        XCTAssertFalse(IconSourceDemandPolicy.shouldReadAirPodsBattery(
            configuration: configuration, userOptedIn: true,
            bluetoothDevices: [], selectedAddress: nil
        ))
    }

    func testPopoverClosedSingleConnectionEventRestoresDemandAndSource() async {
        let connected = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:10", name: "AirPods", kind: .audio,
            isConnected: true, airPodsModel: .airPodsPro
        )
        let reader = DemandSequenceBluetoothReader()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: DemandTestBluetoothStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        var demand = IconSourceDemandBridge()
        let configuration = airPodsConfigured()
        let initialReadCommitted = expectation(description: "initial empty device report commits")
        let connectedEvent = expectation(description: "committed connection event restores icon source")
        var didObserveInitialRead = false
        var didObserveConnectedEvent = false
        var cancellables = Set<AnyCancellable>()

        controller.$devices
            .combineLatest(controller.$batteryLevels, controller.$batteryLevelsUpdatedAt)
            .receive(on: DispatchQueue.main)
            .sink { _, _, _ in
                demand.reconcile(
                    configuration: configuration,
                    userOptedInToBackgroundBattery: true,
                    bluetoothDevices: controller.devices,
                    selectedAirPodsAddress: nil,
                    requestActivation: { controller.requestActivation($0) },
                    releaseActivation: { controller.releaseActivation($0) },
                    requestBatteryLevels: { controller.requestBackgroundBatteryLevels($0) },
                    releaseBatteryLevels: { controller.releaseBackgroundBatteryLevels($0) }
                )
                let sources = IconPresentationResourceResolver.sourceSnapshot(
                    snapshot: .placeholder,
                    bluetoothDevices: controller.devices,
                    batteryLevels: controller.batteryLevels,
                    batteryLevelsUpdatedAt: controller.batteryLevelsUpdatedAt,
                    selectedAirPodsAddress: nil,
                    selectedConnectedDeviceAddress: connected.id
                )
                if reader.readCount == 1, !didObserveInitialRead {
                    didObserveInitialRead = true
                    initialReadCommitted.fulfill()
                }
                if controller.devices.contains(where: \.isConnected), !didObserveConnectedEvent {
                    didObserveConnectedEvent = true
                    XCTAssertTrue(demand.batteryLevelsClaimed)
                    XCTAssertEqual(sources.availability[CenterSource.connectedBluetoothDevice.rawValue], .available)
                    connectedEvent.fulfill()
                }
            }
            .store(in: &cancellables)

        XCTAssertTrue(controller.requestActivation("icon.test"))
        await fulfillment(of: [initialReadCommitted], timeout: 1)
        XCTAssertFalse(demand.batteryLevelsClaimed)

        reader.enqueue([connected])
        controller.refresh() // one connection event, with the popover closed
        await fulfillment(of: [connectedEvent], timeout: 1)
        controller.releaseActivation("icon.test")
        cancellables.removeAll()
    }

    func testPublishedAvailabilityReconciliationIsSerializedAcrossTwentyConfigurationChanges() async {
        let controller = BluetoothDeviceController(
            worker: DemandSequenceBluetoothReader(),
            stateMonitor: DemandTestBluetoothStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        var demand = IconSourceDemandBridge()
        var configuration = airPodsConfigured()
        let releasedAvailability = expectation(description: "each deactivation publishes availability")
        releasedAvailability.expectedFulfillmentCount = 10
        var cancellables = Set<AnyCancellable>()
        controller.$availability
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { availability in
                guard availability == .idle else { return }
                demand.reconcile(
                    configuration: configuration,
                    userOptedInToBackgroundBattery: false,
                    bluetoothDevices: [], selectedAirPodsAddress: nil,
                    requestActivation: { controller.requestActivation($0) },
                    releaseActivation: { controller.releaseActivation($0) },
                    requestBatteryLevels: { _ in }, releaseBatteryLevels: { _ in }
                )
                releasedAvailability.fulfill()
            }
            .store(in: &cancellables)

        for index in 0..<20 {
            configuration = index.isMultiple(of: 2) ? airPodsConfigured() : .classic
            demand.reconcile(
                configuration: configuration,
                userOptedInToBackgroundBattery: false,
                bluetoothDevices: [], selectedAirPodsAddress: nil,
                requestActivation: { controller.requestActivation($0) },
                releaseActivation: { controller.releaseActivation($0) },
                requestBatteryLevels: { _ in }, releaseBatteryLevels: { _ in }
            )
        }
        await fulfillment(of: [releasedAvailability], timeout: 1)
        XCTAssertFalse(demand.activationClaimed, "the twentieth configuration is classic and must release the claim")
        demand.releaseAll(
            releaseActivation: { controller.releaseActivation($0) },
            releaseBatteryLevels: { _ in }
        )
        cancellables.removeAll()
    }

    private func airPodsConfigured() -> IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing.primary = .airPodsBattery
        return configuration
    }
}

@MainActor
private final class DemandTestBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class DemandSequenceBluetoothReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedDevices: [[BluetoothDevice]] = [[]]
    private var storedReadCount = 0
    var readCount: Int { lock.withLock { storedReadCount } }

    func enqueue(_ devices: [BluetoothDevice]) {
        lock.withLock { queuedDevices.append(devices) }
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        let devices = lock.withLock { () -> [BluetoothDevice] in
            storedReadCount += 1
            return queuedDevices.isEmpty ? [] : queuedDevices.removeFirst()
        }
        completion(.success(devices))
    }
}
