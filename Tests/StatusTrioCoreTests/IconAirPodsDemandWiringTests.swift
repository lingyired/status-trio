import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconAirPodsDemandWiringTests: XCTestCase {
    func testSelectingAirPodsRingClaimsActivationAndBackgroundBatteryRead() async {
        let (settings, defaults) = makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        settings.outerRingContent = .airPodsBattery

        let bluetooth = SpyBluetoothDemandSource()
        bluetooth.setDevices([connectedAirPods])
        var refreshCount = 0
        var demandStates: [Bool] = []
        let wiring = IconAirPodsDemandWiring(
            settings: settings,
            bluetooth: bluetooth,
            onBluetoothDemandChange: { demandStates.append($0) },
            onRefresh: { refreshCount += 1 }
        )
        wiring.start()
        await settle()

        XCTAssertEqual(bluetooth.activationRequests, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertEqual(bluetooth.batteryRequests, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertGreaterThan(refreshCount, 0, "a battery reading must repaint the icon")
        XCTAssertEqual(demandStates.last, true, "the store must own the background demand")

        wiring.stop()
    }

    func testSwitchingRingBackToBatteryReleasesClaims() async {
        let (settings, defaults) = makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        settings.outerRingContent = .airPodsBattery

        let bluetooth = SpyBluetoothDemandSource()
        bluetooth.setDevices([connectedAirPods])
        var demandStates: [Bool] = []
        let wiring = IconAirPodsDemandWiring(
            settings: settings,
            bluetooth: bluetooth,
            onBluetoothDemandChange: { demandStates.append($0) }
        )
        wiring.start()
        await settle()
        XCTAssertFalse(bluetooth.batteryRequests.isEmpty)
        XCTAssertEqual(demandStates.last, true)

        settings.outerRingContent = .systemBattery
        await settle()

        XCTAssertEqual(bluetooth.activationReleases, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertEqual(bluetooth.batteryReleases, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertTrue(bluetooth.batteryRequests.count == 1, "no second read after release")
        XCTAssertEqual(demandStates.last, false, "the store demand must be released")

        wiring.stop()
    }

    /// A burst that enables then disables the AirPods ring in the same turn must
    /// not claim a read for an intermediate state.
    func testQueuedEnableThenDisableDoesNotClaim() async {
        let (settings, defaults) = makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        settings.outerRingContent = .systemBattery

        let bluetooth = SpyBluetoothDemandSource()
        bluetooth.setDevices([connectedAirPods])
        var demandStates: [Bool] = []
        let wiring = IconAirPodsDemandWiring(
            settings: settings,
            bluetooth: bluetooth,
            onBluetoothDemandChange: { demandStates.append($0) }
        )
        wiring.start()
        await settle()
        XCTAssertTrue(bluetooth.activationRequests.isEmpty)

        settings.outerRingContent = .airPodsBattery
        settings.outerRingContent = .systemBattery
        await settle()

        XCTAssertTrue(bluetooth.activationRequests.isEmpty, "final state is off, so nothing is claimed")
        XCTAssertTrue(bluetooth.batteryRequests.isEmpty)
        XCTAssertFalse(demandStates.contains(true), "a revoked queue must never enable the store demand")

        wiring.stop()
    }

    /// Without connected AirPods the lightweight connection monitor is still
    /// claimed so a later connection can start the read, but no battery read is.
    func testDisconnectedAirPodsKeepsMonitorWithoutBatteryRead() async {
        let (settings, defaults) = makeSettings()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        settings.outerRingContent = .airPodsBattery

        let bluetooth = SpyBluetoothDemandSource()
        bluetooth.setDevices([])
        var demandStates: [Bool] = []
        let wiring = IconAirPodsDemandWiring(
            settings: settings,
            bluetooth: bluetooth,
            onBluetoothDemandChange: { demandStates.append($0) }
        )
        wiring.start()
        await settle()

        XCTAssertEqual(bluetooth.activationRequests, [IconSourceDemandBridge.batteryLevelsToken])
        XCTAssertTrue(bluetooth.batteryRequests.isEmpty)
        XCTAssertEqual(demandStates.last, true, "the ring still owns Bluetooth so a later connection reads")

        wiring.stop()
    }

    // MARK: - Source snapshot hold

    func testHeldAirPodsBatterySurvivesTheFreshnessWindow() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let now = observedAt.addingTimeInterval(AirPodsBatteryIconSnapshot.freshnessInterval + 30)

        let snapshot = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: .placeholder,
            bluetoothDevices: [connectedAirPods],
            batteryLevels: [airPodsNormalizedAddress: airPodsLevel],
            batteryLevelsUpdatedAt: observedAt,
            selectedAirPodsAddress: airPodsAddress,
            holdsAirPodsBattery: true,
            now: now
        )

        XCTAssertNotNil(snapshot.airPodsBattery)
        XCTAssertEqual(snapshot.availability[RingSource.airPodsBattery.rawValue], .available)
        XCTAssertTrue(snapshot.holdingSourceIDs.contains(RingSource.airPodsBattery.rawValue))
    }

    func testStaleAirPodsBatteryWithoutHoldFallsBack() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let now = observedAt.addingTimeInterval(AirPodsBatteryIconSnapshot.freshnessInterval + 30)

        let snapshot = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: .placeholder,
            bluetoothDevices: [connectedAirPods],
            batteryLevels: [airPodsNormalizedAddress: airPodsLevel],
            batteryLevelsUpdatedAt: observedAt,
            selectedAirPodsAddress: airPodsAddress,
            holdsAirPodsBattery: false,
            now: now
        )

        XCTAssertNil(snapshot.airPodsBattery)
        XCTAssertEqual(
            snapshot.availability[RingSource.airPodsBattery.rawValue],
            .unavailable(.temporarilyStale)
        )
        XCTAssertFalse(snapshot.holdingSourceIDs.contains(RingSource.airPodsBattery.rawValue))
    }

    // MARK: - Helpers

    private let defaultsSuiteName = "IconAirPodsDemandWiringTests.\(UUID().uuidString)"
    private let airPodsAddress = "AA:BB:CC:DD:EE:FF"
    private let airPodsNormalizedAddress = "AABBCCDDEEFF"
    private var connectedAirPods: BluetoothDevice {
        BluetoothDevice(
            id: airPodsAddress,
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPodsPro
        )
    }
    private var airPodsLevel: BluetoothBatteryLevel {
        BluetoothBatteryLevel(
            deviceAddress: airPodsAddress, main: 82, left: 81, right: 83, caseLevel: 90
        )
    }

    private func makeSettings() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return (SettingsStore(defaults: defaults), defaults)
    }

    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class SpyBluetoothDemandSource: IconAirPodsBluetoothDemandSource {
    private let devicesSubject = CurrentValueSubject<[BluetoothDevice], Never>([])
    private let batteryLevelsSubject = CurrentValueSubject<[String: BluetoothBatteryLevel], Never>([:])
    private let batteryLevelsUpdatedAtSubject = CurrentValueSubject<Date?, Never>(nil)
    private let availabilitySubject = CurrentValueSubject<BluetoothAvailability, Never>(.available)

    private(set) var storedDevices: [BluetoothDevice] = []
    var devices: [BluetoothDevice] { storedDevices }
    var devicesPublisher: AnyPublisher<[BluetoothDevice], Never> { devicesSubject.eraseToAnyPublisher() }
    var batteryLevelsPublisher: AnyPublisher<[String: BluetoothBatteryLevel], Never> { batteryLevelsSubject.eraseToAnyPublisher() }
    var batteryLevelsUpdatedAtPublisher: AnyPublisher<Date?, Never> { batteryLevelsUpdatedAtSubject.eraseToAnyPublisher() }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> { availabilitySubject.eraseToAnyPublisher() }

    private(set) var activationRequests: [String] = []
    private(set) var activationReleases: [String] = []
    private(set) var batteryRequests: [String] = []
    private(set) var batteryReleases: [String] = []
    var activationGranted = true

    func setDevices(_ devices: [BluetoothDevice]) {
        storedDevices = devices
        devicesSubject.send(devices)
    }

    func requestActivation(_ token: String) -> Bool {
        activationRequests.append(token)
        return activationGranted
    }

    func releaseActivation(_ token: String) {
        activationReleases.append(token)
    }

    func requestBackgroundBatteryLevels(_ token: String) {
        batteryRequests.append(token)
    }

    func releaseBackgroundBatteryLevels(_ token: String) {
        batteryReleases.append(token)
    }
}
