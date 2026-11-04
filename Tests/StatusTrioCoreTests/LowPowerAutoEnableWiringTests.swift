import Combine
import XCTest
@testable import StatusTrioCore

/// #246 end-to-end wiring: the store turns Low Power Mode on when the existing
/// low-battery threshold is crossed on battery, and only once per cycle.
@MainActor
final class LowPowerAutoEnableWiringTests: XCTestCase {
    func testLowBatteryOnBatteryTurnsLowPowerModeOnOnce() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 15, connectedToPower: false))

        await waitUntil { client.setCallCount == 1 }
        XCTAssertEqual(client.lastSetValue, true)

        // A second low snapshot in the same cycle must not write again.
        battery.send(batteryStatus(percent: 14, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 1)

        store.stop()
    }

    func testPluggedInLowBatteryDoesNotTurnItOn() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: true))
        await settle()

        XCTAssertEqual(client.setCallCount, 0)
        store.stop()
    }

    func testAutomationStaysDormantWithoutBothSwitches() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        // The helper-backed control is off, so even with the automation on the
        // system write must never happen.
        settings.controlsLowPowerMode = false
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await settle()

        XCTAssertEqual(client.setCallCount, 0)
        store.stop()
    }

    func testReadinessNotReadyDoesNotConsumeTheCycle() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let readiness = FakeHelperReadiness(isReady: false)
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client, readiness: readiness)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 15, connectedToPower: false))
        await settle()

        // The helper is not usable: no write, and the low-battery cycle must
        // stay unconsumed.
        XCTAssertEqual(client.setCallCount, 0)

        readiness.isReady = true
        await waitUntil { client.setCallCount == 1 }
        XCTAssertEqual(client.lastSetValue, true)

        // The cycle is now consumed: a further low snapshot must not write.
        battery.send(batteryStatus(percent: 14, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 1)

        store.stop()
    }

    func testReadinessChangeReevaluatesImmediately() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let readiness = FakeHelperReadiness(isReady: false)
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client, readiness: readiness)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 0)

        // Becoming ready must act on the snapshot already on screen.
        readiness.isReady = true
        await waitUntil { client.setCallCount == 1 }

        store.stop()
    }

    func testThresholdChangeReevaluatesImmediately() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        // 25% is above the current threshold: nothing to do yet.
        battery.send(batteryStatus(percent: 25, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 0)

        // Raising the threshold above the current percentage must act without
        // waiting for another battery snapshot.
        settings.autoLowPowerThreshold = 30
        await waitUntil { client.setCallCount == 1 }
        XCTAssertEqual(client.lastSetValue, true)

        store.stop()
    }

    func testControlsChangeReevaluatesImmediately() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        // The helper-backed control is off, so the automation stays dormant.
        settings.controlsLowPowerMode = false
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 0)

        // Turning the control on while the battery is already low must act at
        // once.
        settings.controlsLowPowerMode = true
        await waitUntil { client.setCallCount == 1 }
        XCTAssertEqual(client.lastSetValue, true)

        store.stop()
    }

    func testAutomationEnableReevaluatesImmediately() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = false
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await settle()
        XCTAssertEqual(client.setCallCount, 0)

        settings.autoEnablesLowPowerMode = true
        await waitUntil { client.setCallCount == 1 }
        XCTAssertEqual(client.lastSetValue, true)
        store.stop()
    }

    func testStopCancelsReadinessAndSettingsReevaluation() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        let readiness = FakeHelperReadiness(isReady: false)
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client, readiness: readiness)
        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await settle()
        store.stop()

        readiness.isReady = true
        settings.autoLowPowerThreshold = 30
        settings.autoEnablesLowPowerMode = false
        settings.autoEnablesLowPowerMode = true
        await settle()
        XCTAssertEqual(client.setCallCount, 0)
    }

    func testUnknownPercentageDoesNotTrigger() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let client = RecordingLowPowerClient(reads: false)
        let store = makeStore(battery: battery, client: client)

        store.bindLowPowerModeSettings(settings)
        store.start()
        battery.send(
            BatteryStatus(
                rawPercentage: nil,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            )
        )
        await settle()
        XCTAssertEqual(client.setCallCount, 0)

        // A known low reading afterwards still fires once.
        battery.send(batteryStatus(percent: 15, connectedToPower: false))
        await waitUntil { client.setCallCount == 1 }

        store.stop()
    }

    // MARK: - Helpers

    private func makeStore(
        battery: FakeBatterySource,
        client: RecordingLowPowerClient,
        readiness: FakeHelperReadiness = FakeHelperReadiness(isReady: true)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiSource(),
            volumeMonitor: FakeVolumeSource(),
            refreshInterval: .seconds(60),
            lowPowerMode: LowPowerModeController(
                client: client,
                initialIsLowPowerMode: false
            ),
            helperReadiness: readiness
        )
    }

    private func makeSettings() -> SettingsStore {
        let name = "StatusTrioCoreTests.LowPowerAutoEnable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return SettingsStore(defaults: defaults)
    }

    private func batteryStatus(percent: Int, connectedToPower: Bool) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percent,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: connectedToPower
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for the store wiring to settle.")
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func settle() async {
        for _ in 0..<30 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

// MARK: - Fakes

@MainActor
private final class FakeBatterySource: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func send(_ status: BatteryStatus) {
        continuation.yield(status)
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class FakeWiFiSource: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class FakeVolumeSource: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private let catalogContinuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
        (betterDisplayCatalogUpdates, catalogContinuation) =
            AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setExternalVolumeConfigurations(
        _ configurations: [String: ExternalVolumeConfiguration]
    ) {}
    func refreshBetterDisplayDevices() {}
}

private final class RecordingLowPowerClient: LowPowerModeClienting, @unchecked Sendable {
    var reads: Bool
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(reads: Bool) {
        self.reads = reads
    }

    func readLowPowerMode() async throws -> Bool { reads }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        setCallCount += 1
        lastSetValue = enabled
        reads = enabled
        return enabled
    }
}

@MainActor
private final class FakeHelperReadiness: HelperReadinessProviding {
    @Published var isReady: Bool

    var readinessPublisher: AnyPublisher<Bool, Never> {
        $isReady.eraseToAnyPublisher()
    }

    init(isReady: Bool) {
        self.isReady = isReady
    }
}
