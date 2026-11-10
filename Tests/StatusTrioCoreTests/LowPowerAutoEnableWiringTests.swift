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

    func testHelperApprovalRefreshesBothModesWithoutANewSnapshot() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        let readiness = FakeHelperReadiness(isReady: false)
        let low = RecordingLowPowerClient(reads: false)
        let high = RecordingHighPowerClient()
        high.isAvailable = false
        let store = makeStore(battery: battery, client: low, readiness: readiness, highClient: high)
        store.bindLowPowerModeSettings(settings)
        store.start()
        defer { store.stop() }
        await waitUntil { store.highPowerMode.hasProbed }
        XCTAssertFalse(store.highPowerMode.isSupported)

        high.isAvailable = true
        high.reads = true
        low.reads = true
        readiness.isReady = true
        await settle()

        XCTAssertTrue(store.highPowerMode.isSupported)
        XCTAssertTrue(store.highPowerMode.isHighPowerMode)
        XCTAssertTrue(store.lowPowerMode.isLowPowerMode)
    }

    func testPowerStateNotificationRefreshesBothModesEvenWithAnUnchangedSnapshot() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        let low = RecordingLowPowerClient(reads: false)
        let high = RecordingHighPowerClient()
        let store = makeStore(battery: battery, client: low, highClient: high)
        store.bindLowPowerModeSettings(settings)
        store.start()
        defer { store.stop() }
        let status = batteryStatus(percent: 60, connectedToPower: false)
        battery.send(status)
        await waitUntil { store.highPowerMode.hasProbed && store.snapshot.battery.percentage == 60 }
        // Establish the helper as authoritative: ProcessInfo seeds can now lag.
        store.lowPowerMode.refresh()
        await waitUntil { low.readCallCount > 0 }
        let snapshot = store.snapshot
        high.reads = true
        low.reads = true
        battery.send(status)
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await settle()

        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertTrue(store.highPowerMode.isHighPowerMode)
        XCTAssertTrue(store.lowPowerMode.isLowPowerMode)
    }

    func testHighPowerNotifyKeyRefreshesBothModesWhenTheSnapshotIsUnchanged() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        let low = RecordingLowPowerClient(reads: false)
        let high = RecordingHighPowerClient()
        let notifications = FakePowerModeNotifications()
        let store = makeStore(
            battery: battery, client: low, highClient: high, notifications: notifications
        )
        store.bindLowPowerModeSettings(settings)
        store.start()
        defer { store.stop() }
        let status = batteryStatus(percent: 60, connectedToPower: false)
        battery.send(status)
        await waitUntil { store.highPowerMode.hasProbed && store.snapshot.battery.percentage == 60 }
        store.lowPowerMode.refresh()
        await waitUntil { low.readCallCount > 0 }
        let snapshot = store.snapshot
        high.reads = true
        low.reads = true

        // High Power Mode has no public Foundation notification: a system-side
        // change only reaches the app through powerd's notify key.
        notifications.fire()
        await settle()

        XCTAssertEqual(store.snapshot, snapshot, "the notify key must not require a new snapshot")
        XCTAssertTrue(store.highPowerMode.isHighPowerMode)
        XCTAssertTrue(store.lowPowerMode.isLowPowerMode)
    }

    func testBatteryPowerSourceAndLowPowerChangesRefreshButPercentageChangesDoNot() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        let low = RecordingLowPowerClient(reads: false)
        let high = RecordingHighPowerClient()
        let store = makeStore(battery: battery, client: low, highClient: high)
        store.bindLowPowerModeSettings(settings)
        store.start()
        defer { store.stop() }
        battery.send(batteryStatus(percent: 60, connectedToPower: false))
        await settle()
        let highReads = high.readCallCount
        let lowReads = low.readCallCount
        battery.send(batteryStatus(percent: 59, connectedToPower: false))
        await settle()
        XCTAssertEqual(high.readCallCount, highReads)
        XCTAssertEqual(low.readCallCount, lowReads)

        high.reads = true
        low.reads = true
        battery.send(batteryStatus(percent: 59, connectedToPower: true))
        await settle()
        XCTAssertTrue(store.highPowerMode.isHighPowerMode)
        XCTAssertTrue(store.lowPowerMode.isLowPowerMode)

        high.reads = false
        low.reads = false
        battery.send(batteryStatus(percent: 59, connectedToPower: true, isLowPowerMode: true))
        await settle()
        XCTAssertFalse(store.highPowerMode.isHighPowerMode)
        XCTAssertFalse(store.lowPowerMode.isLowPowerMode, "helper read must supersede the lagging system seed")
    }

    func testAutomaticLowPowerSuccessRefreshesHighPowerWithoutANotification() async {
        let battery = FakeBatterySource()
        let settings = makeSettings()
        settings.controlsLowPowerMode = true
        settings.autoEnablesLowPowerMode = true
        settings.autoLowPowerThreshold = 20
        let low = RecordingLowPowerClient(reads: false)
        let high = RecordingHighPowerClient()
        high.reads = true
        let store = makeStore(battery: battery, client: low, highClient: high)
        store.bindLowPowerModeSettings(settings)
        store.start()
        defer { store.stop() }
        await waitUntil { store.highPowerMode.hasProbed }
        XCTAssertTrue(store.highPowerMode.isHighPowerMode)
        // Model the helper's successful mutually-exclusive switch.
        low.onSet = { high.reads = false }
        battery.send(batteryStatus(percent: 10, connectedToPower: false))
        await waitUntil { low.setCallCount == 1 && !store.lowPowerMode.isApplying }
        await settle()

        XCTAssertTrue(store.lowPowerMode.isLowPowerMode)
        XCTAssertFalse(store.highPowerMode.isHighPowerMode)
    }

    func testAutomaticLowPowerFailureOrObservedOffDoesNotClearHighPower() async {
        for fails in [true, false] {
            let battery = FakeBatterySource()
            let settings = makeSettings()
            settings.controlsLowPowerMode = true
            settings.autoEnablesLowPowerMode = true
            settings.autoLowPowerThreshold = 20
            let low = RecordingLowPowerClient(reads: false)
            low.fails = fails
            low.setResult = false
            let high = RecordingHighPowerClient()
            high.reads = true
            let store = makeStore(battery: battery, client: low, highClient: high)
            store.bindLowPowerModeSettings(settings)
            store.start()
            await waitUntil { store.highPowerMode.hasProbed }
            let highReads = high.readCallCount
            battery.send(batteryStatus(percent: 10, connectedToPower: false))
            await waitUntil { low.setCallCount == 1 && !store.lowPowerMode.isApplying }
            await settle()

            XCTAssertTrue(store.highPowerMode.isHighPowerMode)
            XCTAssertEqual(high.readCallCount, highReads)
            XCTAssertFalse(store.lowPowerMode.isLowPowerMode)
            store.stop()
        }
    }

    func testStoppedOrOptedOutStoreDoesNotRefreshForPowerEvents() async {
        for stopped in [false, true] {
            let battery = FakeBatterySource()
            let settings = makeSettings()
            settings.controlsLowPowerMode = true
            let readiness = FakeHelperReadiness(isReady: false)
            let low = RecordingLowPowerClient(reads: false)
            let high = RecordingHighPowerClient()
            let store = makeStore(battery: battery, client: low, readiness: readiness, highClient: high)
            store.bindLowPowerModeSettings(settings)
            store.start()
            await waitUntil { store.highPowerMode.hasProbed }
            if stopped { store.stop() } else { settings.controlsLowPowerMode = false }
            let lowReads = low.readCallCount
            let highReads = high.readCallCount
            readiness.isReady = true
            battery.send(batteryStatus(percent: 10, connectedToPower: true))
            NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
            await settle()

            XCTAssertEqual(low.readCallCount, lowReads)
            XCTAssertEqual(high.readCallCount, highReads)
            store.stop()
        }
    }

    // MARK: - Helpers

    private func makeStore(
        battery: FakeBatterySource,
        client: RecordingLowPowerClient,
        readiness: FakeHelperReadiness = FakeHelperReadiness(isReady: true),
        highClient: RecordingHighPowerClient = RecordingHighPowerClient(),
        notifications: FakePowerModeNotifications? = nil
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
            highPowerMode: HighPowerModeController(
                client: highClient,
                platformSupported: true
            ),
            helperReadiness: readiness,
            powerModeNotifications: notifications ?? PowerModeNotificationMonitor(names: [])
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

    private func batteryStatus(
        percent: Int,
        connectedToPower: Bool,
        isLowPowerMode: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percent,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: isLowPowerMode,
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
    var fails = false
    var setResult: Bool?
    var onSet: (() -> Void)?
    private(set) var readCallCount = 0
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(reads: Bool) {
        self.reads = reads
    }

    func readLowPowerMode() async throws -> Bool {
        readCallCount += 1
        return reads
    }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        setCallCount += 1
        lastSetValue = enabled
        if fails { throw NSError(domain: "test", code: 1) }
        onSet?()
        let observed = setResult ?? enabled
        reads = observed
        return observed
    }
}

private final class FakePowerModeNotifications:
    PowerModeNotificationMonitoring, @unchecked Sendable
{
    nonisolated(unsafe) private var handler: (@MainActor () -> Void)?

    func start(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    @MainActor
    func fire() {
        handler?()
    }
}

private final class RecordingHighPowerClient: HighPowerModeClienting, @unchecked Sendable {
    var isAvailable = true
    var reads = false
    var supported = true
    private(set) var readCallCount = 0

    func protocolVersion() async throws -> Int {
        guard isAvailable else { throw NSError(domain: "test", code: 1) }
        return 2
    }

    func highPowerModeSupported() async throws -> Bool {
        guard isAvailable else { throw NSError(domain: "test", code: 1) }
        return supported
    }

    func readHighPowerMode() async throws -> Bool {
        guard isAvailable else { throw NSError(domain: "test", code: 1) }
        readCallCount += 1
        return reads
    }

    func setHighPowerMode(_ enabled: Bool) async throws -> Bool {
        guard isAvailable else { throw NSError(domain: "test", code: 1) }
        reads = enabled
        return enabled
    }

    func canReadLowPowerMode() async -> Bool { isAvailable }
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
