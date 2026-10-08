import XCTest
@testable import StatusTrioCore

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

    private func airPodsConfigured() -> IconConfigurationV1 {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing.primary = .airPodsBattery
        return configuration
    }
}
