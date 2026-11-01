import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class ManagedChargeLimitControllerTests: XCTestCase {
    func testDefaultSystemManagementDoesNoBackgroundReadsOrWrites() async {
        let backend = ManagedChargeBackend()
        let controller = ManagedChargeLimitController(backend: backend)
        controller.start(batteries: Just(battery()).eraseToAnyPublisher())
        await controller.updateBattery(battery())
        await controller.handleWake()
        XCTAssertNil(controller.selectedLimit)
        XCTAssertEqual(backend.reads, 0)
        XCTAssertTrue(backend.targets.isEmpty)
        controller.stop()
    }

    func testChoicesComeFromSystemAndAreValidated() async {
        let backend = ManagedChargeBackend()
        backend.state.availableChargeLimits = [95, 90, 90, 50, 120]
        let controller = ManagedChargeLimitController(backend: backend)
        controller.refresh()
        XCTAssertEqual(controller.availableLimits, [90, 95])
        await controller.selectLimit(85)
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertNil(controller.selectedLimit)
        XCTAssertEqual(controller.status, .failed)
    }

    func testSelectionWritesRealLimitAndPersistsOriginalOnlyOnce() async {
        let backend = ManagedChargeBackend()
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.selectLimit(90)
        XCTAssertEqual(backend.targets, [90])
        XCTAssertEqual(controller.status, .active(90))
        XCTAssertEqual(store.session?.originalLimit, 80)
        await controller.selectLimit(95)
        XCTAssertEqual(store.session?.originalLimit, 80)
        XCTAssertEqual(store.session?.limit, 95)
        XCTAssertEqual(backend.targets, [90, 95])
    }

    func testSystemManagementRestoresBaselineAndClearsOwnership() async {
        let backend = ManagedChargeBackend()
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.selectLimit(90)
        await controller.selectLimit(nil)
        XCTAssertEqual(backend.targets, [90, 80])
        XCTAssertNil(store.session)
        XCTAssertNil(controller.selectedLimit)
        XCTAssertEqual(controller.status, .systemManaged)
        let reads = backend.reads
        await controller.handleWake()
        XCTAssertEqual(backend.reads, reads)
    }

    func testNoCapBaselineRestoresOneHundred() async {
        let backend = ManagedChargeBackend()
        backend.limit = 100
        let controller = ManagedChargeLimitController(backend: backend)
        await controller.selectLimit(90)
        backend.state.availableChargeLimits = []
        await controller.selectLimit(nil)
        XCTAssertEqual(backend.targets, [90, 100])
    }

    func testWriteFailureOrUnconfirmedWriteDoesNotClaimSuccess() async {
        for succeedsWithoutApplying in [false, true] {
            let backend = ManagedChargeBackend()
            backend.succeeds = succeedsWithoutApplying
            backend.applies = false
            let store = MemoryManagedChargeStore()
            let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
            await controller.selectLimit(90)
            XCTAssertEqual(store.session?.originalLimit, 80)
            XCTAssertEqual(controller.selectedLimit, 90)
            XCTAssertEqual(controller.status, .failed)
        }
    }

    func testReadFailureAndUnsupportedCapabilityNeverWrite() async {
        let backend = ManagedChargeBackend()
        backend.state.errorMessage = "read failed"
        let controller = ManagedChargeLimitController(backend: backend)
        await controller.selectLimit(90)
        XCTAssertTrue(backend.targets.isEmpty)
        backend.capability = .unavailable(.unsupportedSystem)
        let reads = backend.reads
        await controller.selectLimit(90)
        XCTAssertEqual(backend.reads, reads)
        XCTAssertTrue(backend.targets.isEmpty)
    }

    func testWakeReappliesSavedLimitAfterSystemResetWithoutPanel() async {
        let backend = ManagedChargeBackend()
        backend.limit = 100
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80))
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.handleWake()
        XCTAssertEqual(backend.targets, [90])
        XCTAssertEqual(controller.status, .active(90))
    }

    func testExternalActiveLimitPausesAutomaticWritesUntilExplicitReapply() async {
        let backend = ManagedChargeBackend()
        backend.limit = 85
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80))
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.handleWake()
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertEqual(controller.status, .externalChange)
        XCTAssertEqual(store.session?.isPaused, true)
        await controller.handleWake()
        XCTAssertTrue(backend.targets.isEmpty)
        await controller.reapply()
        XCTAssertEqual(backend.targets, [90])
        XCTAssertEqual(store.session?.isPaused, false)
    }

    func testTemporaryFullOverrideSuspendsUntilCancel() async {
        let backend = ManagedChargeBackend()
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.selectLimit(90)
        let override = await controller.chargeToFullNow()
        XCTAssertTrue(override.succeeded)
        XCTAssertEqual(controller.status, .temporarilyOverridden(90))
        await controller.updateBattery(battery())
        await controller.handleWake()
        XCTAssertEqual(backend.targets, [90])
        let result = await controller.restoreChargeLimit(to: 80)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(backend.targets, [90, 90])
        XCTAssertEqual(store.session?.isTemporarilyOverridden, false)
    }

    func testAdvertisedNonStandardStepCancelsToExactManagedTarget() async {
        let backend = ManagedChargeBackend()
        backend.options = [80, 82, 90]
        let managed = ManagedChargeLimitController(backend: backend)
        await managed.selectLimit(82)
        let panel = ChargeToFullNowController(backend: managed,
            managedRestoreLimit: { managed.managedRestoreLimit })
        panel.update(ChargeToFullNowDemand(settingEnabled: true, popoverVisible: true,
            batterySectionVisible: true, battery: battery()))
        panel.requestChargeToFullNow()
        await settle { panel.presentation == .chargingToFull }
        panel.requestCancelChargeToFullNow()
        await settle { panel.presentation == .limitRestored(limit: 82) }
        XCTAssertEqual(backend.state.mclLimit, 82)
    }

    func testStaleReadAfterAcceptedOverrideKeepsSuspension() async {
        let backend = ManagedChargeBackend()
        backend.overridePropagatesImmediately = false
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.selectLimit(90)
        _ = await controller.chargeToFullNow()
        await controller.handleWake()
        XCTAssertEqual(store.session?.isTemporarilyOverridden, true)
        XCTAssertEqual(controller.status, .temporarilyOverridden(90))
        XCTAssertEqual(backend.targets, [90])
    }

    func testNativeCancellationAfterPropagationGraceEndsSuspension() async {
        let backend = ManagedChargeBackend()
        backend.overridePropagatesImmediately = false
        var date = Date(timeIntervalSince1970: 100)
        let controller = ManagedChargeLimitController(backend: backend, now: { date })
        await controller.selectLimit(90)
        _ = await controller.chargeToFullNow()
        date.addTimeInterval(16)
        await controller.handleWake()
        XCTAssertEqual(controller.status, .active(90))
        backend.limit = 100
        await controller.handleWake()
        XCTAssertEqual(backend.targets, [90, 90])
    }

    func testInterruptedSystemRestoreCannotReactivateManagedPolicy() async {
        for original in [80, 100] {
            let backend = ManagedChargeBackend()
            backend.limit = original
            let store = MemoryManagedChargeStore()
            let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
            await controller.selectLimit(90)
            backend.suspends = true
            let restore = Task { await controller.selectLimit(nil) }
            await settle { backend.pendingWrite != nil }
            controller.stop()
            backend.pendingWrite?.resume()
            backend.pendingWrite = nil
            await restore.value
            let relaunched = ManagedChargeLimitController(backend: backend, sessionStore: store)
            await relaunched.handleWake()
            XCTAssertEqual(backend.targets, [90, original])
            XCTAssertNil(store.session)
            XCTAssertNil(relaunched.selectedLimit)
            XCTAssertEqual(relaunched.status, .systemManaged)
        }
    }

    func testUnsupportedOriginalRestorationFailsWithoutLosingRecoveryRecord() async {
        let backend = ManagedChargeBackend()
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.selectLimit(90)
        backend.state.availableChargeLimits = []
        await controller.selectLimit(nil)
        XCTAssertEqual(backend.targets, [90])
        XCTAssertEqual(store.session?.originalLimit, 80)
        XCTAssertEqual(controller.status, .failed)
    }

    func testCompletionAndReplugResumeCustomLimit() async {
        for complete in [false, true] {
            let backend = ManagedChargeBackend()
            let controller = ManagedChargeLimitController(backend: backend)
            await controller.selectLimit(90)
            await controller.updateBattery(battery())
            _ = await controller.chargeToFullNow()
            await controller.updateBattery(battery(connected: complete, full: complete))
            if !complete { await controller.updateBattery(battery()) }
            XCTAssertEqual(backend.state.mclLimit, 90)
            XCTAssertEqual(controller.status, .active(90))
        }
    }

    func testOrdinaryBatteryTicksDoNotPollPowerUI() async {
        let backend = ManagedChargeBackend()
        let controller = ManagedChargeLimitController(backend: backend)
        await controller.selectLimit(90)
        await controller.updateBattery(battery())
        let reads = backend.reads
        for _ in 0..<20 { await controller.updateBattery(battery()) }
        XCTAssertEqual(backend.reads, reads)
    }

    func testStopPreventsFurtherAutomaticWrites() async {
        let backend = ManagedChargeBackend()
        let controller = ManagedChargeLimitController(backend: backend)
        await controller.selectLimit(90)
        controller.stop()
        backend.limit = 100
        let reads = backend.reads
        await controller.handleWake()
        await controller.updateBattery(battery())
        await controller.selectLimit(95)
        XCTAssertEqual(backend.reads, reads)
        XCTAssertEqual(backend.targets, [90])
    }

    func testSessionSurvivesRelaunchAndInvalidDataIsIgnored() async throws {
        let name = "ManagedChargeLimitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsManagedChargeLimitSessionStore(defaults: defaults)
        let session = ManagedChargeLimitSession(limit: 90, originalLimit: 80)
        store.save(session)
        XCTAssertEqual(UserDefaultsManagedChargeLimitSessionStore(defaults: defaults).load(), session)
        store.clear()
        XCTAssertNil(store.load())
        store.save(.init(limit: 7, originalLimit: 80))
        XCTAssertNil(store.load())
    }

    func testSettingsRefreshClassifiesActualStateWithoutWriting() async {
        let backend = ManagedChargeBackend()
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80))
        backend.limit = 90
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        controller.refresh()
        XCTAssertEqual(controller.status, .active(90))
        backend.limit = 85
        controller.refresh()
        XCTAssertEqual(controller.status, .externalChange)
        XCTAssertEqual(store.session?.isPaused, true)
        XCTAssertTrue(backend.targets.isEmpty)
    }

    func testExternalLimitStillPausesWhenItIsNoLongerAdvertised() async {
        let backend = ManagedChargeBackend()
        backend.limit = 85
        backend.state.availableChargeLimits = [90, 95]
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80))
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await controller.handleWake()
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertEqual(controller.status, .externalChange)
    }

    func testTemporaryFullDoesNotResumeExternallyPausedOwnership() async {
        let backend = ManagedChargeBackend()
        backend.limit = 85
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80, isPaused: true))
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        _ = await controller.chargeToFullNow()
        await controller.updateBattery(battery(full: true))
        XCTAssertEqual(store.session?.isPaused, true)
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertEqual(controller.status, .externalChange)
    }

    func testSavedPolicyStartsFromRealBatteryPublisherAndStopsSubscriptions() async {
        let backend = ManagedChargeBackend()
        backend.limit = 100
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 80))
        let publisher = PassthroughSubject<BatteryStatus, Never>()
        let center = NotificationCenter()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store, notificationCenter: center)
        controller.start(batteries: publisher.eraseToAnyPublisher())
        publisher.send(battery())
        await settle { backend.targets == [90] }
        XCTAssertEqual(backend.targets, [90])
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()
        backend.limit = 100
        publisher.send(battery(connected: false))
        await Task.yield()
        XCTAssertEqual(backend.targets, [90])
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await settle { backend.targets.count == 2 }
        XCTAssertEqual(backend.targets, [90, 90])
        controller.stop()
        let reads = backend.reads
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        publisher.send(battery())
        await Task.yield()
        XCTAssertEqual(backend.reads, reads)
    }

    func testInterruptedWriteKeepsBaselineAndNeverRetriesAutomatically() async {
        let backend = ManagedChargeBackend()
        backend.suspends = true
        let store = MemoryManagedChargeStore()
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)
        let request = Task { await controller.selectLimit(90) }
        await settle { backend.pendingWrite != nil }
        XCTAssertEqual(store.session?.originalLimit, 80)
        await controller.selectLimit(95)
        XCTAssertEqual(backend.targets, [90])
        controller.stop()
        backend.pendingWrite?.resume()
        backend.pendingWrite = nil
        await request.value
        let relaunched = ManagedChargeLimitController(backend: backend, sessionStore: store)
        backend.limit = 100
        await relaunched.handleWake()
        XCTAssertEqual(backend.targets, [90])
        XCTAssertEqual(relaunched.status, .failed)
        await relaunched.selectLimit(nil)
        XCTAssertEqual(backend.targets, [90, 80])
        XCTAssertNil(store.session)
    }

    // MARK: - Charge to Full Now × managed limit integration

    private func demand(connected: Bool = true, full: Bool = false) -> ChargeToFullNowDemand {
        ChargeToFullNowDemand(
            settingEnabled: true,
            popoverVisible: true,
            batterySectionVisible: true,
            battery: battery(connected: connected, full: full)
        )
    }

    /// End-to-end: select a managed limit, run Charge to Full Now, cancel, and
    /// confirm the managed limit (not the legacy slider) is what gets restored.
    func testChargeToFullCancelRestoresActiveManagedLimit() async {
        let backend = ManagedChargeBackend()
        backend.state = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0, mclLimit: 100,
            availableChargeLimits: [80, 85, 90, 95], chargingOverrideAllowed: true
        )
        let store = MemoryManagedChargeStore()
        let managed = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await managed.selectLimit(90)
        XCTAssertEqual(managed.status, .active(90))
        XCTAssertEqual(store.session?.originalLimit, 100)

        let charge = ChargeToFullNowController(
            backend: managed,
            managedRestoreLimit: { managed.managedRestoreLimit }
        )
        charge.update(demand())
        XCTAssertEqual(charge.presentation, .available)

        charge.requestChargeToFullNow()
        await settle { charge.presentation == .chargingToFull }
        charge.update(demand())
        XCTAssertEqual(charge.presentation, .chargingToFull)

        charge.performPrimaryAction()
        await settle { charge.presentation == .limitRestored(limit: 90) }

        XCTAssertEqual(charge.presentation, .limitRestored(limit: 90))
        // Selection wrote 90 once; cancelling re-applied 90 through the managed
        // controller. No legacy restore call was made.
        XCTAssertEqual(backend.targets, [90, 90])
        XCTAssertTrue(backend.restoreTargets.isEmpty)
        XCTAssertEqual(managed.status, .active(90))
        XCTAssertEqual(store.session?.limit, 90)
        XCTAssertEqual(store.session?.originalLimit, 100)
        XCTAssertEqual(store.session?.isTemporarilyOverridden, false)
    }

    /// Regression: with System Managed (no managed limit), Charge to Full Now
    /// keeps the legacy slider target and never writes through the policy.
    func testSystemManagedChargeToFullRestoresLegacySliderLimit() async {
        let backend = ManagedChargeBackend()
        backend.state = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 1, mclLimit: 80,
            availableChargeLimits: [80, 85, 90, 95], chargingOverrideAllowed: true
        )
        let store = MemoryManagedChargeStore()
        let managed = ManagedChargeLimitController(backend: backend, sessionStore: store)
        XCTAssertNil(managed.managedRestoreLimit)

        let charge = ChargeToFullNowController(
            backend: managed,
            restoreLimit: { 85 },
            managedRestoreLimit: { managed.managedRestoreLimit }
        )
        charge.update(demand())
        XCTAssertEqual(charge.presentation, .available)

        charge.requestChargeToFullNow()
        await settle { charge.presentation == .chargingToFull }
        charge.update(demand())
        charge.performPrimaryAction()
        await settle { charge.presentation == .limitRestored(limit: 85) }

        XCTAssertEqual(charge.presentation, .limitRestored(limit: 85))
        XCTAssertEqual(backend.restoreTargets, [85])
        XCTAssertTrue(backend.targets.isEmpty)
        XCTAssertNil(store.session)
    }

    /// A power-state tick during a temporary full charge must preserve the
    /// override instead of silently re-applying (ending) the managed cap.
    func testBatteryTickDuringTemporaryOverrideDoesNotReapplyManagedLimit() async {
        let backend = ManagedChargeBackend()
        backend.state = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0, mclLimit: 100,
            availableChargeLimits: [80, 85, 90, 95], chargingOverrideAllowed: true
        )
        let store = MemoryManagedChargeStore()
        let managed = ManagedChargeLimitController(backend: backend, sessionStore: store)
        await managed.selectLimit(90)
        let writesAfterSelection = backend.targets.count

        _ = await managed.chargeToFullNow()
        XCTAssertEqual(backend.state.mclEnabledRawValue, 3)

        await managed.updateBattery(battery(connected: true))

        XCTAssertEqual(backend.targets.count, writesAfterSelection)
        XCTAssertEqual(managed.status, .temporarilyOverridden(90))
    }

    /// A saved policy that is no longer applied must read as reapply-needed
    /// (`failed`), never as a permanent `checking` spinner.
    func testRefreshFlagsUnappliedManagedLimitAsFailedForReapply() async {
        let backend = ManagedChargeBackend()
        backend.state = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 1, mclLimit: 100,
            availableChargeLimits: [80, 85, 90, 95], chargingOverrideAllowed: true
        )
        let store = MemoryManagedChargeStore(session: .init(limit: 90, originalLimit: 100))
        let controller = ManagedChargeLimitController(backend: backend, sessionStore: store)

        controller.refresh()

        XCTAssertEqual(controller.status, .failed)
        XCTAssertTrue(backend.targets.isEmpty)
    }

    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<100 where !predicate() { await Task.yield() }
        XCTAssertTrue(predicate())
    }

    private func battery(connected: Bool = true, full: Bool = false) -> BatteryStatus {
        BatteryStatus(rawPercentage: full ? 100 : 50, isPresent: true,
                      isCharging: !full && connected, isCharged: full,
                      isLowPowerMode: false, isConnectedToPower: connected)
    }
}

@MainActor
private final class MemoryManagedChargeStore: ManagedChargeLimitSessionStoring {
    var session: ManagedChargeLimitSession?
    init(session: ManagedChargeLimitSession? = nil) { self.session = session }
    func load() -> ManagedChargeLimitSession? { session }
    func save(_ session: ManagedChargeLimitSession) { self.session = session }
    func clear() { session = nil }
}

@MainActor
private final class ManagedChargeBackend: BatteryChargeControlling {
    var capability: ChargeToFullNowCapability = .available
    var state = ChargeToFullNowDeviceState(mclEnabledRawValue: 1, mclLimit: 80,
        availableChargeLimits: [80, 85, 90, 95], chargingOverrideAllowed: true)
    var limit: Int {
        get { state.mclLimit ?? 100 }
        set {
            state = ChargeToFullNowDeviceState(mclEnabledRawValue: state.mclEnabledRawValue,
                mclLimit: newValue, availableChargeLimits: state.availableChargeLimits,
                chargingOverrideAllowed: state.chargingOverrideAllowed, errorMessage: state.errorMessage)
        }
    }
    var reads = 0
    var targets: [Int] = []
    var restoreTargets: [Int] = []
    var succeeds = true
    var applies = true
    var options: [Int] = [80, 85, 90, 95] {
        didSet { state.availableChargeLimits = options }
    }
    var overridePropagatesImmediately = true
    var suspends = false
    var pendingWrite: CheckedContinuation<Void, Never>?
    func readState() -> ChargeToFullNowDeviceState { reads += 1; return state }
    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        if overridePropagatesImmediately {
            state = ChargeToFullNowDeviceState(mclEnabledRawValue: 3, mclLimit: 100,
                availableChargeLimits: options, chargingOverrideAllowed: false)
        }
        return .success
    }
    func setChargeLimit(to limit: Int, expectedState: ChargeToFullNowDeviceState) async -> ChargeToFullNowWriteResult {
        targets.append(limit)
        if suspends {
            suspends = false
            await withCheckedContinuation { pendingWrite = $0 }
        }
        guard succeeds, expectedState == state else { return .failure }
        if applies {
            state = ChargeToFullNowDeviceState(mclEnabledRawValue: 1, mclLimit: limit,
                availableChargeLimits: options, chargingOverrideAllowed: true)
        }
        return .success
    }
    func restoreChargeLimit(to limit: Int) async -> ChargeToFullNowWriteResult {
        restoreTargets.append(limit)
        guard succeeds else { return .failure }
        state = ChargeToFullNowDeviceState(mclEnabledRawValue: 1, mclLimit: limit,
            availableChargeLimits: options, chargingOverrideAllowed: true)
        return .success
    }
}
