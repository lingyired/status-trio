import CoreAudio
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothDemandLifecycleTests: XCTestCase {
    func testOrdinaryPanelOpenDoesNotStartBluetoothWhenNoConsumerNeedsIt() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: false)
        fixture.settings.replacesNetworkIconWithBluetoothAudio = false
        fixture.settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        fixture.settings.refreshesAppleBatteriesInBackground = false
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setPopoverVisible(true)

        XCTAssertEqual(fixture.stateMonitor.startCount, 0)
        XCTAssertEqual(fixture.reader.readCount, 0)
        fixture.store.stop()
    }

    func testUndeterminedAuthorizationStaysIdleUntilExplicitRequest() {
        let fixture = makeFixture(authorization: .notDetermined)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 0)
        XCTAssertEqual(
            fixture.store.bluetoothDevices.availability,
            .authorizationNotDetermined
        )

        fixture.store.requestBluetoothAuthorization()
        XCTAssertEqual(fixture.stateMonitor.startCount, 1)
        fixture.store.stop()
    }

    func testAlreadyAllowedExplicitAuthorizationIsConsumedAfterLastConsumerCloses() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 1)

        fixture.store.requestBluetoothAuthorization()
        fixture.store.setPopoverVisible(false)

        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        XCTAssertFalse(fixture.store.bluetoothDevices.isActive)
        XCTAssertEqual(fixture.cache.activeReaderCount, 0)
        fixture.store.stop()
    }

    func testReentrantDemandChangeIsReconciledAfterExplicitActivation() {
        let fixture = makeFixture(authorization: .notDetermined)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        fixture.stateMonitor.onStart = {
            fixture.stateMonitor.authorizationAfterStart = .allowed
            fixture.store.setPopoverVisible(false)
        }

        fixture.store.requestBluetoothAuthorization()

        XCTAssertEqual(fixture.stateMonitor.startCount, 1)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        XCTAssertFalse(fixture.store.bluetoothDevices.isActive)
        XCTAssertEqual(fixture.cache.activeReaderCount, 0)
        fixture.store.stop()
    }

    func testSettingsPageDemandSurvivesPopoverClose() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setBluetoothSettingsVisible(true)
        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 1)

        fixture.store.setPopoverVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 0)

        fixture.store.setBluetoothSettingsVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testSettingsBluetoothDemandCanBeReleasedAfterItsPageDisappears() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setBluetoothSettingsVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 1)

        fixture.store.setBluetoothSettingsVisible(false)

        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testOverlappingSettingsDemandTokensReleaseOnlyTheirOwnClaim() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        let first = fixture.store.beginBluetoothSettingsDemand()
        let second = fixture.store.beginBluetoothSettingsDemand()
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(fixture.stateMonitor.startCount, 1)

        if let second {
            fixture.store.endBluetoothSettingsDemand(second)
        }
        XCTAssertEqual(fixture.stateMonitor.stopCount, 0)

        if let first {
            fixture.store.endBluetoothSettingsDemand(first)
        }
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        XCTAssertFalse(fixture.store.bluetoothDevices.isActive)
        fixture.store.stop()
    }

    func testLegacySettingsVisibilityClaimsAreBalanced() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setBluetoothSettingsVisible(true)
        fixture.store.setBluetoothSettingsVisible(true)
        fixture.store.setBluetoothSettingsVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 0)

        fixture.store.setBluetoothSettingsVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testSettingsDemandBeforeStartIsNotClaimedWithoutPresentation() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)

        fixture.store.setBluetoothSettingsVisible(true)
        fixture.store.start()

        XCTAssertEqual(fixture.stateMonitor.startCount, 0)
        fixture.store.stop()
    }

    func testReconcilingTheSameAuthorizationDoesNotReenter() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setPopoverVisible(true)
        fixture.store.setPopoverVisible(false)

        XCTAssertEqual(fixture.stateMonitor.startCount, 1)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testSelectedPairedIconKeepsReadAfterOtherDemandsDisappear() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.settings.replacesNetworkIconWithBluetoothAudio = true
        fixture.settings.setBluetoothNetworkIconDevice(
            address: "AA-BB-CC-DD-EE-FF",
            symbolName: "keyboard"
        )
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)

        fixture.settings.setPopupSection(.bluetooth, enabled: false)
        fixture.store.setPopoverVisible(false)

        XCTAssertEqual(fixture.stateMonitor.stopCount, 0)
        fixture.settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testCoreAudioOnlyIconDoesNotStartPairedDeviceRead() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.replacesNetworkIconWithBluetoothAudio = true
        fixture.settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)

        XCTAssertEqual(fixture.stateMonitor.startCount, 0)
        XCTAssertEqual(fixture.reader.readCount, 0)
        fixture.store.stop()
    }

    func testExplicitBackgroundRefreshKeepsBluetoothDemandWithoutPanel() {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.showsAppleDevicesAndBattery = true
        fixture.settings.showsBluetoothBatteryLevels = true
        fixture.settings.showsBluetoothDeviceList = true
        fixture.settings.refreshesAppleBatteriesInBackground = true
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        XCTAssertEqual(fixture.stateMonitor.startCount, 1)
        fixture.store.setPopoverVisible(true)
        fixture.store.setPopoverVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 0)

        fixture.settings.refreshesAppleBatteriesInBackground = false
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testBluetoothOutputKeepsListeningModeReadAvailable() async {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.volume, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 0)

        fixture.volumeMonitor.send(VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: "AirPods Pro",
            currentDevice: AudioOutputDevice(
                id: 42,
                name: "AirPods Pro",
                isCurrent: true,
                transport: .bluetooth
            ),
            outputDevices: [
                AudioOutputDevice(
                    id: 42,
                    name: "AirPods Pro",
                    isCurrent: true,
                    transport: .bluetooth
                )
            ]
        ))
        await waitUntil { fixture.stateMonitor.startCount == 1 }

        fixture.settings.setPopupSection(.volume, enabled: false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testListedBluetoothOutputKeepsListeningModeReadAvailable() async {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.volume, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 0)

        fixture.volumeMonitor.send(VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: "MacBook Speakers",
            currentDevice: AudioOutputDevice(
                id: 1,
                name: "MacBook Speakers",
                isCurrent: true,
                transport: .builtIn
            ),
            outputDevices: [
                AudioOutputDevice(
                    id: 1,
                    name: "MacBook Speakers",
                    isCurrent: true,
                    transport: .builtIn
                ),
                AudioOutputDevice(
                    id: 42,
                    name: "AirPods Pro",
                    isCurrent: false,
                    transport: .bluetooth
                )
            ]
        ))
        await waitUntil { fixture.stateMonitor.startCount == 1 }

        fixture.settings.setPopupSection(.volume, enabled: false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testCurrentBluetoothOutputKeepsDemandWhenOutputListIsIncomplete() async {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.volume, enabled: true)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        XCTAssertEqual(fixture.stateMonitor.startCount, 0)

        fixture.volumeMonitor.send(VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: "AirPods Pro",
            currentDevice: AudioOutputDevice(
                id: 42,
                name: "AirPods Pro",
                isCurrent: true,
                transport: .bluetooth
            ),
            outputDevices: [
                AudioOutputDevice(
                    id: 1,
                    name: "MacBook Speakers",
                    isCurrent: true,
                    transport: .builtIn
                )
            ]
        ))
        await waitUntil { fixture.stateMonitor.startCount == 1 }

        fixture.store.setPopoverVisible(false)
        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        fixture.store.stop()
    }

    func testHiddenAudioSectionDoesNotRetainBluetoothForListeningModes() async {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.volume, enabled: false)
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)

        fixture.volumeMonitor.send(VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: "AirPods Pro",
            currentDevice: AudioOutputDevice(
                id: 42,
                name: "AirPods Pro",
                isCurrent: true,
                transport: .bluetooth
            ),
            outputDevices: []
        ))
        await settle()

        XCTAssertEqual(fixture.stateMonitor.startCount, 0)
        fixture.store.stop()
    }

    func testLastDemandClearsTransientDataWithoutChangingPreferences() async {
        let fixture = makeFixture(authorization: .allowed)
        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        fixture.settings.hidesGhostBluetoothDevices = false
        fixture.settings.setBluetoothNetworkIconDevice(
            address: "11-22-33-44-55-66",
            symbolName: "headphones"
        )
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        await waitUntil { fixture.reader.readCount == 1 }

        fixture.reader.complete(.success([
            BluetoothDevice(
                id: "AA:BB:CC:DD:EE:FF",
                name: "AirPods Pro",
                kind: .audio,
                isConnected: true
            )
        ]))
        await waitUntil { fixture.store.bluetoothDevices.devices.count == 1 }
        fixture.cache.store(Data("cached report".utf8))
        // Establishing the second controller demand is an intentional
        // preference change; take the invariant snapshot after it.
        fixture.settings.setPopupSection(.bluetooth, enabled: false)
        let preferencesBefore = serializedPreferences(fixture.suite.defaults)

        fixture.settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        await waitUntil { fixture.store.bluetoothDevices.devices.isEmpty }

        XCTAssertEqual(fixture.stateMonitor.stopCount, 1)
        XCTAssertEqual(fixture.cache.storedEntryCount, 0)
        XCTAssertTrue(
            preferenceValuesAreUnchanged(since: preferencesBefore, defaults: fixture.suite.defaults),
            "dropping Bluetooth state must not rewrite persistent preferences"
        )

        _ = fixture.reader.complete(.success([
            BluetoothDevice(
                id: "STALE",
                name: "Late device",
                kind: .audio,
                isConnected: true
            )
        ]))
        await settle()
        XCTAssertTrue(
            fixture.store.bluetoothDevices.devices.isEmpty,
            "a completion from the released read must not repopulate cleared state"
        )
        fixture.store.stop()
    }

    func testProfilerCacheResetWaitsForEveryReaderToRelease() {
        let cache = BluetoothProfilerReportCache()
        let first = cache.acquireReader()
        let second = cache.acquireReader()
        cache.store(Data("shared".utf8))

        cache.releaseReader(first)
        XCTAssertEqual(cache.storedEntryCount, 1)

        cache.releaseReader(second)
        XCTAssertEqual(cache.storedEntryCount, 0)
    }

    private func makeFixture(
        authorization: BluetoothAuthorizationStatus
    ) -> DemandFixture {
        let suiteName = "BluetoothDemandLifecycleTests.\(UUID().uuidString)"
        let suite = UserDefaultsSuite(
            defaults: UserDefaults(suiteName: suiteName)!,
            suiteName: suiteName
        )
        let settings = SettingsStore(defaults: suite.defaults)
        settings.setPopupSection(.bluetooth, enabled: false)
        settings.setPopupSection(.volume, enabled: true)
        settings.replacesNetworkIconWithBluetoothAudio = false
        settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        settings.showsAppleDevicesAndBattery = false
        settings.refreshesAppleBatteriesInBackground = false

        let stateMonitor = DemandStateMonitor(authorization: authorization)
        let reader = DemandBluetoothReader()
        let batteryReader = DemandBluetoothBatteryReader()
        let cache = BluetoothProfilerReportCache()
        let bluetoothController = BluetoothDeviceController(
            worker: reader,
            stateMonitor: stateMonitor,
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let volumeMonitor = DemandVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: DemandBatteryMonitor(),
            wifiMonitor: DemandWiFiMonitor(),
            volumeMonitor: volumeMonitor,
            bluetoothDevices: bluetoothController,
            bluetoothProfilerCache: cache
        )
        addTeardownBlock {
            store.stop()
            suite.defaults.removePersistentDomain(forName: suiteName)
        }
        return DemandFixture(
            suite: suite,
            settings: settings,
            store: store,
            stateMonitor: stateMonitor,
            reader: reader,
            volumeMonitor: volumeMonitor,
            cache: cache
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
        XCTAssertTrue(condition(), "Timed out waiting for Bluetooth demand state")
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<20 { await Task.yield() }
    }

    private func serializedPreferences(_ defaults: UserDefaults) -> [String: Any] {
        defaults.dictionaryRepresentation()
    }

    private func preferenceValuesAreUnchanged(
        since previous: [String: Any],
        defaults: UserDefaults
    ) -> Bool {
        let current = defaults.dictionaryRepresentation()
        // UserDefaults adds process-wide metadata such as NSRegistrationDomain
        // keys while the store runs. Persistence ownership is about the app's
        // registered values, so compare exactly those keys rather than volatile
        // framework domains.
        return previous.keys.contains { key in
            current[key] != nil && String(describing: current[key]) != String(describing: previous[key])
        } == false
    }
}

@MainActor
private struct DemandFixture {
    let suite: UserDefaultsSuite
    let settings: SettingsStore
    let store: SystemStatusStore
    let stateMonitor: DemandStateMonitor
    let reader: DemandBluetoothReader
    let volumeMonitor: DemandVolumeMonitor
    let cache: BluetoothProfilerReportCache
}

private struct UserDefaultsSuite {
    let defaults: UserDefaults
    let suiteName: String
}

@MainActor
private final class DemandStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private let initialAuthorization: BluetoothAuthorizationStatus
    private var mutableAuthorization: BluetoothAuthorizationStatus
    var authorization: BluetoothAuthorizationStatus {
        mutableAuthorization
    }
    var authorizationAfterStart: BluetoothAuthorizationStatus? {
        get {
            mutableAuthorization == initialAuthorization ? nil : mutableAuthorization
        }
        set {
            mutableAuthorization = newValue ?? initialAuthorization
        }
    }
    var onStart: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(authorization: BluetoothAuthorizationStatus) {
        initialAuthorization = authorization
        mutableAuthorization = authorization
    }

    func start() {
        startCount += 1
        onStart?()
        onStateChange?(authorization, authorization == .allowed ? .poweredOn : .unknown)
    }

    func stop() {
        stopCount += 1
    }
}

private final class DemandBluetoothReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (BluetoothWorkerResult) -> Void] = []
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock {
            count += 1
            pending.append(completion)
        }
    }

    @discardableResult
    func complete(_ result: BluetoothWorkerResult) -> Bool {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        completion?(result)
        return completion != nil
    }
}

private final class DemandBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class DemandBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DemandWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class DemandVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func send(_ status: VolumeStatus) { continuation.yield(status) }
}
