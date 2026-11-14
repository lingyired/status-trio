import Combine
import XCTest
@testable import StatusTrioCore

private final class FakeDisplayAssertion: DisplaySleepAsserting {
    var acquireResult = true
    private(set) var isHeld = false
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0

    func acquire() -> Bool {
        acquireCount += 1
        if acquireResult { isHeld = true }
        return acquireResult
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        releaseCount += 1
    }
}

private final class FakeDisableSleepClient: DisableSleepClienting, @unchecked Sendable {
    enum Failure: Error { case failed }

    var disableSleep: Bool
    var version: Int
    var shouldThrow = false
    private(set) var setCalls: [Bool] = []
    private(set) var readCalls = 0

    init(disableSleep: Bool = false, version: Int = 3) {
        self.disableSleep = disableSleep
        self.version = version
    }

    func protocolVersion() async throws -> Int { version }

    func readDisableSleep() async throws -> Bool {
        readCalls += 1
        return disableSleep
    }

    func setDisableSleep(_ enabled: Bool) async throws -> Bool {
        if shouldThrow { throw Failure.failed }
        setCalls.append(enabled)
        disableSleep = enabled
        return enabled
    }
}

@MainActor
private final class FakeHelperReadiness: HelperReadinessProviding {
    var isReady: Bool
    private let subject: CurrentValueSubject<Bool, Never>

    var readinessPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    init(isReady: Bool) {
        self.isReady = isReady
        subject = CurrentValueSubject(isReady)
    }

    func setReady(_ value: Bool) {
        isReady = value
        subject.send(value)
    }
}

private final class FakeOwnership: SleepOwnershipStoring {
    var ownsDisableSleep: Bool

    init(owns: Bool = false) { ownsDisableSleep = owns }
}

@MainActor
final class SleepControlControllerTests: XCTestCase {
    private func make(
        assertion: FakeDisplayAssertion = FakeDisplayAssertion(),
        client: FakeDisableSleepClient = FakeDisableSleepClient(),
        readiness: FakeHelperReadiness = FakeHelperReadiness(isReady: true),
        ownership: FakeOwnership = FakeOwnership()
    ) -> SleepControlController {
        SleepControlController(
            assertion: assertion,
            client: client,
            helperReadiness: readiness,
            ownership: ownership
        )
    }

    private func battery(
        present: Bool = true,
        connected: Bool,
        percentage: Int = 50,
        charging: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: present,
            isCharging: charging,
            isLowPowerMode: false,
            isConnectedToPower: connected
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeoutIterations: Int = 300
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: - Display

    func testDisplayToggleAcquiresAndReleasesAssertion() {
        let assertion = FakeDisplayAssertion()
        let control = make(assertion: assertion)

        control.setDisplaySleep(true)
        XCTAssertTrue(control.isPreventingDisplaySleep)
        XCTAssertTrue(assertion.isHeld)

        control.setDisplaySleep(false)
        XCTAssertFalse(control.isPreventingDisplaySleep)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertEqual(assertion.releaseCount, 1)
    }

    func testDisplayAssertionFailureLeavesToggleOff() {
        let assertion = FakeDisplayAssertion()
        assertion.acquireResult = false
        let control = make(assertion: assertion)

        control.setDisplaySleep(true)
        XCTAssertFalse(control.isPreventingDisplaySleep)
        XCTAssertNotNil(control.lastError)
    }

    func testFiniteTimerSetsExpiryAndFiringTurnsOff() {
        let control = make()
        control.setDisplaySleep(true)
        control.setDisplayTimer(.thirtyMinutes)
        XCTAssertNotNil(control.displayExpiry)

        control.displayTimerFired()
        XCTAssertFalse(control.isPreventingDisplaySleep)
        XCTAssertNil(control.displayExpiry)
        XCTAssertEqual(control.notice, .timerEnded)
    }

    func testUnlimitedTimerClearsExpiry() {
        let control = make()
        control.setDisplaySleep(true)
        control.setDisplayTimer(.oneHour)
        XCTAssertNotNil(control.displayExpiry)

        control.setDisplayTimer(.unlimited)
        XCTAssertNil(control.displayExpiry)
        XCTAssertTrue(control.isPreventingDisplaySleep)
    }

    // MARK: - Lid

    func testLidUnavailableWithoutHelper() {
        let control = make(readiness: FakeHelperReadiness(isReady: false))
        XCTAssertEqual(control.lidUnavailableReason, .helperUnavailable)

        control.setLidSleep(true)
        XCTAssertFalse(control.isPreventingLidSleep)
    }

    func testLidUnavailableWithoutExternalPower() {
        let control = make()
        control.updatePowerState(battery: battery(connected: false))
        XCTAssertEqual(control.lidUnavailableReason, .requiresPower)

        control.setLidSleep(true)
        XCTAssertFalse(control.isPreventingLidSleep)
    }

    func testLidEnableWritesHelperAndMarker() async {
        let client = FakeDisableSleepClient()
        let ownership = FakeOwnership()
        let control = make(client: client, ownership: ownership)
        control.updatePowerState(battery: battery(connected: true))

        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }

        XCTAssertTrue(control.isPreventingLidSleep)
        XCTAssertEqual(client.setCalls.last, true)
        XCTAssertTrue(ownership.ownsDisableSleep)
    }

    func testLidDisableClearsMarker() async {
        let client = FakeDisableSleepClient()
        let ownership = FakeOwnership()
        let control = make(client: client, ownership: ownership)
        control.updatePowerState(battery: battery(connected: true))

        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }
        control.setLidSleep(false)
        await waitUntil { !control.isPreventingLidSleep }

        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(ownership.ownsDisableSleep)
        XCTAssertEqual(client.setCalls.last, false)
    }

    func testUnplugTurnsLidOffWithNotice() async {
        let client = FakeDisableSleepClient()
        let ownership = FakeOwnership()
        let control = make(client: client, ownership: ownership)
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }

        control.updatePowerState(battery: battery(connected: false))
        await waitUntil { !control.isPreventingLidSleep }

        XCTAssertFalse(control.isPreventingLidSleep)
        XCTAssertFalse(ownership.ownsDisableSleep)
        XCTAssertEqual(control.notice, .turnedOffUnplugged)
    }

    func testLowBatteryTurnsLidOffWithNotice() async {
        let control = make()
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }

        control.updatePowerState(battery: battery(connected: false, percentage: 12))
        await waitUntil { !control.isPreventingLidSleep }

        XCTAssertEqual(control.notice, .turnedOffLowBattery)
    }

    func testLidTimerFiringTurnsOff() async {
        let client = FakeDisableSleepClient()
        let control = make(client: client)
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }

        control.setLidTimer(.oneHour)
        XCTAssertNotNil(control.lidExpiry)

        control.lidTimerFired()
        await waitUntil { !control.isPreventingLidSleep }
        XCTAssertEqual(control.notice, .timerEnded)
    }

    // MARK: - Residual recovery / shutdown

    func testRecoveryClearsOnlyOwnedResidual() async {
        let client = FakeDisableSleepClient(disableSleep: true)
        let ownership = FakeOwnership(owns: true)
        let control = make(client: client, ownership: ownership)

        control.start()
        await waitUntil { client.setCalls.contains(false) }

        XCTAssertFalse(client.disableSleep)
        XCTAssertFalse(ownership.ownsDisableSleep)
    }

    func testRecoveryLeavesForeignDisableSleepAlone() async {
        let client = FakeDisableSleepClient(disableSleep: true)
        let ownership = FakeOwnership(owns: false)
        let control = make(client: client, ownership: ownership)

        control.start()
        // Give the probe a chance to run; nothing should be written.
        await waitUntil { client.readCalls > 0 }
        await Task.yield()

        XCTAssertTrue(client.disableSleep)
        XCTAssertTrue(client.setCalls.isEmpty)
        XCTAssertFalse(ownership.ownsDisableSleep)
    }

    func testRecoveryRetriesWhenHelperNotReadyYet() async {
        let client = FakeDisableSleepClient(disableSleep: true)
        let ownership = FakeOwnership(owns: true)
        let readiness = FakeHelperReadiness(isReady: false)
        let control = make(client: client, readiness: readiness, ownership: ownership)

        control.start()
        await Task.yield()
        XCTAssertTrue(client.disableSleep)

        readiness.setReady(true)
        await waitUntil { client.setCalls.contains(false) }
        XCTAssertFalse(client.disableSleep)
    }

    func testShutdownResetsOwnedDisableSleep() async {
        let client = FakeDisableSleepClient()
        let ownership = FakeOwnership()
        let control = make(client: client, ownership: ownership)
        control.updatePowerState(battery: battery(connected: true))
        control.setLidSleep(true)
        await waitUntil { control.isPreventingLidSleep }

        await control.shutdown()
        XCTAssertFalse(client.disableSleep)
        XCTAssertFalse(ownership.ownsDisableSleep)
    }

    // MARK: - Four-hour timer / restarting a countdown

    func testFourHourTimerUsesConfiguredExpiry() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let control = SleepControlController(
            assertion: FakeDisplayAssertion(),
            client: FakeDisableSleepClient(),
            helperReadiness: FakeHelperReadiness(isReady: true),
            ownership: FakeOwnership(),
            now: { fixed }
        )

        control.setDisplaySleep(true)
        control.setDisplayTimer(.fourHours)

        XCTAssertEqual(control.displayExpiry, fixed.addingTimeInterval(4 * 60 * 60))
    }

    func testSelectingNewDurationRestartsCountdownFromNow() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let control = SleepControlController(
            assertion: FakeDisplayAssertion(),
            client: FakeDisableSleepClient(),
            helperReadiness: FakeHelperReadiness(isReady: true),
            ownership: FakeOwnership(),
            now: { fixed }
        )

        control.setDisplaySleep(true)
        control.setDisplayTimer(.oneHour)
        XCTAssertEqual(control.displayExpiry, fixed.addingTimeInterval(60 * 60))

        control.setDisplayTimer(.thirtyMinutes)
        XCTAssertEqual(control.displayExpiry, fixed.addingTimeInterval(30 * 60))
        XCTAssertTrue(control.isPreventingDisplaySleep)
    }
}
