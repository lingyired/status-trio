import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class ChargeToFullNowControllerTests: XCTestCase {
    func testButtonRequiresEveryLiveCondition() {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand())
        XCTAssertEqual(controller.presentation, .available)

        let hiddenDemands = [
            demand(popoverVisible: false),
            demand(batterySectionVisible: false),
            demand(connectedToPower: false),
            demand(percentage: 100),
            demand(isCharged: true)
        ]
        for hiddenDemand in hiddenDemands {
            controller.update(hiddenDemand)
            XCTAssertEqual(controller.presentation, .hidden)
        }
    }

    func testPausedChargeWithoutNativeLimitOffersTheAction() {
        // #292: macOS shows its own "Charge to Full Now" while Optimized Battery
        // Charging pauses at ~80% with the charge limit still at 100%. Status
        // Trio must not require a sub-100% native limit to offer the action.
        let backend = StubBatteryChargeController(deviceState: .noActiveLimit)
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand(isCharging: false))

        XCTAssertEqual(controller.presentation, .available)
    }

    func testChargingNormallyWithoutNativeLimitHidesTheAction() {
        let backend = StubBatteryChargeController(deviceState: .noActiveLimit)
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand(isCharging: true))

        XCTAssertEqual(controller.presentation, .hidden)
    }

    func testUnrecognizedRawStateStaysHiddenWhenPaused() {
        let backend = StubBatteryChargeController(
            deviceState: ChargeToFullNowDeviceState(
                mclEnabledRawValue: 9,
                mclLimit: 80,
                chargingOverrideAllowed: false
            )
        )
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand(isCharging: false))

        XCTAssertEqual(controller.presentation, .hidden)
    }

    func testChargingTowardNativeLimitStillOffersTheAction() {
        // The existing charge-limit flow must not regress: while charging
        // toward a sub-100% limit the button stays available.
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand(percentage: 50, isCharging: true))

        XCTAssertEqual(controller.presentation, .available)
    }

    func testPausedChargeWithoutNativeLimitStartsTheWrite() async {
        let backend = StubBatteryChargeController(deviceState: .noActiveLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand(isCharging: false))
        XCTAssertEqual(controller.presentation, .available)

        controller.performPrimaryAction()
        await backend.waitUntilWriteStarts()
        XCTAssertEqual(backend.writeCount, 1)

        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }
    }

    func testUnsupportedCapabilityNeverReadsOrShowsTheButton() {
        let backend = StubBatteryChargeController(
            capability: .unavailable(.unsupportedSystem),
            deviceState: .activeLimit
        )
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand())

        XCTAssertEqual(controller.presentation, .hidden)
        XCTAssertEqual(backend.readCount, 0)
    }

    func testSettingsVisibilityFollowsCapabilityNotBatteryState() {
        let unsupported = ChargeToFullNowController(
            backend: StubBatteryChargeController(
                capability: .unavailable(.unsupportedSystem),
                deviceState: .activeLimit
            )
        )
        let supported = ChargeToFullNowController(
            backend: StubBatteryChargeController(deviceState: .activeLimit)
        )

        unsupported.update(demand(popoverVisible: false))
        supported.update(demand(percentage: 100))

        XCTAssertFalse(unsupported.isSettingAvailable)
        XCTAssertTrue(supported.isSettingAvailable)
    }

    func testSystemStartedOverrideHidesWhenTheBatteryIsAlreadyFull() {
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 80 }
        )

        controller.update(demand(percentage: 100, isCharged: true))

        XCTAssertEqual(controller.presentation, .hidden)
    }

    func testSystemStartedOverrideOffersCancelWithoutAStoredLimit() {
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 80 }
        )

        controller.update(demand(percentage: 90, isCharging: true))

        XCTAssertEqual(controller.presentation, .chargingToFull)
        XCTAssertTrue(controller.presentation.showsButton)
    }

    func testSystemStartedOverrideCancelRestoresTheConfiguredLimit() async {
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 95 }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        backend.restoreState = activeLimit(95)

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 95)
        }

        XCTAssertEqual(backend.restoreTargets, [95])
        XCTAssertEqual(backend.restoreCount, 1)
    }

    func testCancelAfterRelaunchRestoresTheInitiallySavedSystemLimit() async throws {
        let suite = "ChargeToFullNowControllerTests.RestoreAfterRelaunch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { TestUserDefaults.removeSuite(named: suite) }
        let first = SettingsStore(defaults: defaults, systemChargeLimit: { 80 })
        XCTAssertEqual(first.chargeToFullRestoreLimit, 80, accuracy: 0.001)
        let reopened = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        backend.restoreState = activeLimit(80)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { Int(reopened.chargeToFullRestoreLimit.rounded()) }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        XCTAssertEqual(controller.presentation, .chargingToFull)

        controller.performPrimaryAction()
        await waitUntil { backend.restoreCount == 1 }

        XCTAssertEqual(backend.restoreTargets, [80])
        await waitUntil { controller.presentation == .limitRestored(limit: 80) }
    }

    func testClosingThePanelClearsTheRestoredLimitNotice() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 80 }
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(80)

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        controller.clearDemand()
        XCTAssertEqual(controller.presentation, .hidden)

        backend.deviceState = activeLimit(80)
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .available)
    }

    func testCancelPassesTheSessionOriginalLimitToTheRestoreWrite() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 95 }
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(95)

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 95)
        }

        XCTAssertEqual(backend.restoreTargets, [95])
        XCTAssertEqual(backend.restoreExpectedLimits, [80])
    }

    func testCancelWithASessionReportsAnExternalLimitChange() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(90)
        backend.restoreResult = ChargeToFullNowWriteResult(
            succeeded: false,
            errorMessage: "The charge limit changed.",
            failure: .limitChanged
        )

        controller.performPrimaryAction()
        await waitUntil {
            if case .cancelFailed = controller.presentation { return true }
            return false
        }

        XCTAssertEqual(
            controller.presentation,
            .cancelFailed(reason: .limitChanged)
        )
        XCTAssertEqual(backend.restoreExpectedLimits, [80])
    }

    func testSystemStartedOverrideAsksBeforeReplacingADifferentLimit() async {
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 80 }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        backend.restoreResult = ChargeToFullNowWriteResult(
            succeeded: false,
            errorMessage: "The charge limit changed.",
            failure: .limitChanged
        )
        backend.restoreState = activeLimit(90)

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation
                == .cancelLimitChangedConfirmation(current: 90, target: 80)
        }
        XCTAssertEqual(backend.restoreExpectedLimits, [nil])

        // Live battery ticks must not replace the explicit confirmation.
        controller.update(demand(percentage: 86, isCharging: true))
        XCTAssertEqual(
            controller.presentation,
            .cancelLimitChangedConfirmation(current: 90, target: 80)
        )

        backend.restoreResult = .success
        backend.restoreState = activeLimit(80)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        XCTAssertEqual(backend.restoreTargets, [80, 80])
        XCTAssertEqual(backend.restoreExpectedLimits, [nil, 90])
    }

    func testRestoreVerificationAcceptsADisengagedLimitAfterTheWrite() {
        XCTAssertTrue(
            ChargeToFullNowController.restoreIsVerified(
                limit: 80,
                state: ChargeToFullNowDeviceState(
                    mclEnabledRawValue: 0,
                    mclLimit: 80,
                    chargingOverrideAllowed: false
                )
            )
        )
    }

    func testRestoreSucceedsWhenMCLDisengagesAfterTheWrite() async {
        let backend = StubBatteryChargeController(deviceState: activeLimit(95))
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 80 }
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0,
            mclLimit: 80,
            chargingOverrideAllowed: false
        )

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        XCTAssertEqual(backend.restoreTargets, [80])
        XCTAssertEqual(backend.restoreExpectedLimits, [95])
    }

    func testConfiguredRestoreLimitSnapsToTheStandardSteps() async {
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 87 }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        backend.restoreState = activeLimit(85)

        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 85)
        }

        XCTAssertEqual(backend.restoreTargets, [85])
    }


    func testRestoredLimitHoldsUntilTheBatteryReachesIt() async {
        let backend = StubBatteryChargeController(deviceState: activeLimit(95))
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 95 }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        XCTAssertEqual(controller.presentation, .available)
        await beginCharge(controller, backend)

        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(95)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 95)
        }

        controller.update(demand(percentage: 88, isCharging: true))
        XCTAssertEqual(
            controller.presentation,
            .limitRestored(limit: 95)
        )
        XCTAssertFalse(controller.presentation.showsButton)

        controller.update(demand(percentage: 95, isCharging: false))
        XCTAssertEqual(controller.presentation, .available)
    }

    func testRestoredLimitReleasesWhenChargingStopsBeforeIt() async {
        let backend = StubBatteryChargeController(deviceState: activeLimit(95))
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 95 }
        )
        controller.update(demand(percentage: 85, isCharging: true))
        await beginCharge(controller, backend)

        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(95)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 95)
        }

        controller.update(demand(percentage: 88, isCharging: true))
        XCTAssertEqual(
            controller.presentation,
            .limitRestored(limit: 95)
        )

        controller.update(demand(percentage: 89, isCharging: false))
        XCTAssertEqual(controller.presentation, .available)
    }

    func testStateReadFailureShowsUnavailableWithoutWriting() {
        let backend = StubBatteryChargeController(
            deviceState: ChargeToFullNowDeviceState(
                mclEnabledRawValue: 1,
                mclLimit: 80,
                chargingOverrideAllowed: false,
                errorMessage: "State read failed."
            )
        )
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand())
        controller.requestChargeToFullNow()

        XCTAssertEqual(controller.presentation, .unavailable)
        XCTAssertEqual(backend.writeCount, 0)
    }

    func testUnavailableStateRecoversOnTheNextSuccessfulRead() {
        let backend = StubBatteryChargeController(
            deviceState: ChargeToFullNowDeviceState(
                mclEnabledRawValue: 1,
                mclLimit: 80,
                chargingOverrideAllowed: false,
                errorMessage: "State read failed."
            )
        )
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .unavailable)

        backend.deviceState = .activeLimit
        controller.update(demand())

        XCTAssertEqual(controller.presentation, .available)
    }

    func testOverrideAllowedFalseDoesNotHideTheNativeAction() {
        let backend = StubBatteryChargeController(
            deviceState: ChargeToFullNowDeviceState(
                mclEnabledRawValue: 1,
                mclLimit: 80,
                chargingOverrideAllowed: false
            )
        )
        let controller = ChargeToFullNowController(backend: backend)

        controller.update(demand())

        XCTAssertEqual(controller.presentation, .available)
    }

    func testRequestRechecksStateAndPreventsDuplicateWritesWhileApplying() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()

        XCTAssertEqual(controller.presentation, .applying)
        XCTAssertEqual(backend.writeCount, 1)
        XCTAssertGreaterThanOrEqual(backend.readCount, 2)

        controller.requestChargeToFullNow()
        await Task.yield()
        XCTAssertEqual(backend.writeCount, 1)

        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }
        XCTAssertTrue(backend.writeCount == 1)
    }

    func testSuccessfulChargeStatusPersistsUntilFullOrDisconnected() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }

        backend.deviceState = .temporaryOverride
        controller.update(demand(percentage: 90))
        XCTAssertEqual(controller.presentation, .chargingToFull)

        controller.update(demand(percentage: 100))
        XCTAssertEqual(controller.presentation, .chargingToFull)

        backend.deviceState = .activeLimit
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .available)
    }

    func testSuccessfulChargeStatusSurvivesPanelClose() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }

        backend.deviceState = .temporaryOverride
        controller.clearDemand()
        XCTAssertEqual(controller.presentation, .hidden)

        controller.update(demand(percentage: 90))
        XCTAssertEqual(controller.presentation, .chargingToFull)
    }

    func testChargingToFullDoesNotAcceptDuplicateRequests() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }

        controller.requestChargeToFullNow()
        await Task.yield()

        XCTAssertEqual(backend.writeCount, 1)
        XCTAssertEqual(controller.presentation, .chargingToFull)
    }

    func testRestoredChargeLimitReplacesChargingStatusWithButton() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }

        backend.deviceState = .temporaryOverride
        controller.update(demand(percentage: 90))
        XCTAssertEqual(controller.presentation, .chargingToFull)

        backend.deviceState = .activeLimit
        controller.update(demand(percentage: 90))

        XCTAssertEqual(controller.presentation, .available)
        controller.requestChargeToFullNow()
        await waitUntil { backend.writeCount == 2 }
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }
    }

    func testReopeningPanelWithRestoredLimitDoesNotRequireObservingOverrideFirst() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        var instant = Date(timeIntervalSince1970: 1_000)
        let controller = ChargeToFullNowController(backend: backend, now: { instant })
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }

        controller.clearDemand()
        instant = instant.addingTimeInterval(30)
        controller.update(demand(percentage: 90))
        XCTAssertEqual(controller.presentation, .available)
    }

    func testRequestDoesNotWriteWhenTheLimitBecameInactive() {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 3,
            mclLimit: 100,
            chargingOverrideAllowed: false
        )

        controller.requestChargeToFullNow()

        XCTAssertEqual(controller.presentation, .hidden)
        XCTAssertEqual(backend.writeCount, 0)
    }

    func testWriteFailureStaysVisibleWithLocalizedFailureState() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())

        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.failure)
        await waitUntil { controller.presentation == .failed }

        XCTAssertEqual(controller.presentation, .failed)
        XCTAssertTrue(controller.presentation.showsButton)
    }

    func testClearingDemandDropsTheButtonAndPreventsFurtherReads() {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        let readsAfterActivation = backend.readCount

        controller.clearDemand()
        controller.update(demand(popoverVisible: false))

        XCTAssertEqual(controller.presentation, .hidden)
        XCTAssertEqual(backend.readCount, readsAfterActivation)
    }

    func testQuickToggleStartsChargeWhenAvailable() async {
        let backend = StubBatteryChargeController(deviceState: activeLimit(80))
        let controller = ChargeToFullNowController(backend: backend, restoreLimit: { 80 })

        let didAct = controller.performQuickToggle(battery: demand(percentage: 80).battery)
        XCTAssertTrue(didAct)

        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }
    }

    func testQuickToggleCancelsWhenChargingToFull() async {
        let backend = StubBatteryChargeController(deviceState: activeLimit(80))
        let controller = ChargeToFullNowController(backend: backend, restoreLimit: { 80 })

        controller.update(demand())
        await beginCharge(controller, backend)

        backend.deviceState = .temporaryOverride
        backend.restoreState = activeLimit(80)

        let didAct = controller.performQuickToggle(battery: demand().battery)
        XCTAssertTrue(didAct)
        await waitUntil { controller.presentation == .limitRestored(limit: 80) }
        XCTAssertEqual(backend.restoreTargets, [80])
    }

    func testQuickToggleReturnsFalseWhenNothingToCharge() {
        let backend = StubBatteryChargeController(deviceState: activeLimit(80))
        let controller = ChargeToFullNowController(backend: backend, restoreLimit: { 80 })

        let didAct = controller.performQuickToggle(
            battery: demand(connectedToPower: false).battery
        )

        XCTAssertFalse(didAct)
        XCTAssertEqual(controller.presentation, .hidden)
    }

    func testQuickToggleReturnsFalseForUnsupportedCapabilityWithoutReading() {
        let backend = StubBatteryChargeController(
            capability: .unavailable(.unsupportedSystem),
            deviceState: activeLimit(80)
        )
        let controller = ChargeToFullNowController(backend: backend)

        XCTAssertFalse(controller.performQuickToggle(battery: demand().battery))
        XCTAssertEqual(backend.readCount, 0)
    }

    func testCancelRestoresEverySupportedConfiguredLimit() async {
        for limit in [80, 85, 90, 95] {
            let backend = StubBatteryChargeController(
                deviceState: activeLimit(limit)
            )
            let store = VolatileChargeToFullNowSessionStore()
            let controller = ChargeToFullNowController(
                backend: backend,
                sessionStore: store,
                restoreLimit: { limit }
            )
            controller.update(demand())
            await beginCharge(controller, backend)

            backend.deviceState = .temporaryOverride
            backend.restoreState = activeLimit(limit)
            controller.performPrimaryAction()
            await waitUntil {
                controller.presentation == .limitRestored(limit: limit)
            }

            XCTAssertEqual(backend.restoreTargets, [limit])
            XCTAssertNil(store.load())
        }
    }

    func testCancelRestoresTheConfiguredLimitDuringOverride() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 90 }
        )
        controller.update(demand())
        await beginCharge(controller, backend)

        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 3,
            mclLimit: 100,
            chargingOverrideAllowed: false
        )
        backend.restoreState = activeLimit(90)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 90)
        }

        XCTAssertEqual(backend.restoreTargets, [90])
    }

    func testCancelUsesTheConfiguredLimitWhenOverrideReportsOneHundred() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)

        backend.deviceState = .temporaryOverride
        backend.restoreState = .activeLimit
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        XCTAssertEqual(backend.restoreTargets, [80])
    }

    func testCancelUsesTheSessionSnapshotWhenStateReadFails() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)

        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0,
            mclLimit: nil,
            chargingOverrideAllowed: nil,
            errorMessage: "Temporary read failure."
        )
        backend.restoreState = .activeLimit
        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 80)
        )
        XCTAssertEqual(backend.restoreCount, 0)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        XCTAssertEqual(backend.restoreTargets, [80])
    }

    func testReadFailureAfterReopeningKeepsTheCancelAction() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        controller.clearDemand()
        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0,
            mclLimit: nil,
            chargingOverrideAllowed: nil,
            errorMessage: "Temporary read failure."
        )
        controller.update(demand())

        XCTAssertTrue(controller.presentation.showsButton)
        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 80)
        )
        XCTAssertEqual(backend.restoreCount, 0)
    }

    func testCancelConfirmationUsesTheConfiguredLimitDuringReadErrors() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            restoreLimit: { 90 }
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0,
            mclLimit: 90,
            chargingOverrideAllowed: nil,
            errorMessage: "MCL enabled state unavailable."
        )

        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 90)
        )
        XCTAssertEqual(backend.restoreCount, 0)
    }

    func testCancelDuringStaleActiveReadKeepsTheSession() async {
        let store = VolatileChargeToFullNowSessionStore()
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        controller.performPrimaryAction()

        XCTAssertNotNil(store.load())
        XCTAssertEqual(backend.restoreCount, 0)
        XCTAssertNotEqual(controller.presentation, .available)
        XCTAssertTrue(controller.presentation.showsButton)

        backend.deviceState = .temporaryOverride
        backend.restoreState = .activeLimit
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }
    }

    func testChargeCompletionAfterReopeningKeepsTheCancelAction() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        controller.clearDemand()
        controller.update(demand())
        backend.finishWrite(.success)

        await waitUntil { controller.presentation == .chargingToFull }
    }

    func testCancelFailureAfterReopeningKeepsTheRetryAction() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.suspendsRestore = true
        controller.performPrimaryAction()
        await waitUntil { backend.restoreCount == 1 }
        controller.clearDemand()
        controller.update(demand())
        backend.finishRestore(.failure)

        await waitUntil {
            if case .cancelFailed = controller.presentation { return true }
            return false
        }
        XCTAssertTrue(controller.presentation.showsButton)
    }

    func testRestartRequiresConfirmationBeforeRestoringTheConfiguredLimit() async {
        let store = VolatileChargeToFullNowSessionStore(
            session: ChargeToFullNowSession(
                originalLimit: 90,
                acceptedAt: Date()
            )
        )
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store,
            restoreLimit: { 90 }
        )
        controller.update(demand(percentage: 95))
        XCTAssertEqual(controller.presentation, .chargingToFull)

        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 90)
        )
        XCTAssertEqual(backend.restoreCount, 0)

        backend.restoreState = activeLimit(90)
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 90)
        }
        XCTAssertEqual(backend.restoreTargets, [90])
    }

    func testRestartConfirmsBeforeRestoringTheConfiguredLimit() async {
        let store = VolatileChargeToFullNowSessionStore(
            session: ChargeToFullNowSession(
                originalLimit: nil,
                acceptedAt: Date()
            )
        )
        let backend = StubBatteryChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store
        )
        controller.update(demand())

        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 80)
        )
        XCTAssertEqual(backend.restoreCount, 0)

        backend.restoreState = .activeLimit
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }
        XCTAssertEqual(backend.restoreTargets, [80])
    }

    func testVerificationFailureKeepsTheSessionAndAllowsRetry() async {
        let store = VolatileChargeToFullNowSessionStore()
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreResult = ChargeToFullNowWriteResult(
            succeeded: true,
            errorMessage: nil
        )
        backend.restoreState = .temporaryOverride

        controller.performPrimaryAction()
        await waitUntil {
            if case .cancelFailed = controller.presentation { return true }
            return false
        }
        XCTAssertNotNil(store.load())

        backend.restoreState = .activeLimit
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }
        XCTAssertEqual(backend.restoreTargets, [80, 80])
        XCTAssertNil(store.load())
    }

    func testExternalActiveLimitClearsTheSessionWithoutWriting() async {
        let store = VolatileChargeToFullNowSessionStore()
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store
        )
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .chargingToFull)

        backend.deviceState = activeLimit(90)
        controller.update(demand())

        XCTAssertEqual(controller.presentation, .available)
        XCTAssertEqual(backend.restoreCount, 0)
        XCTAssertNil(store.load())
    }

    func testExternalManualLimitOfOneHundredRequiresConfirmation() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = ChargeToFullNowDeviceState(
            mclEnabledRawValue: 1,
            mclLimit: 100,
            chargingOverrideAllowed: false
        )
        controller.update(demand())

        controller.performPrimaryAction()

        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 80)
        )
        XCTAssertEqual(backend.restoreCount, 0)
    }

    func testImmediateActiveLimitReadDoesNotRaceTheAcceptedOverride() async {
        let store = VolatileChargeToFullNowSessionStore()
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        var instant = Date(timeIntervalSince1970: 1_000)
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store,
            now: { instant }
        )
        controller.update(demand())
        await beginCharge(controller, backend)

        controller.update(demand())
        XCTAssertEqual(controller.presentation, .chargingToFull)
        XCTAssertNotNil(store.load())

        instant = instant.addingTimeInterval(10)
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .chargingToFull)
        XCTAssertNotNil(store.load())

        instant = instant.addingTimeInterval(6)
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .available)
        XCTAssertNil(store.load())
    }

    func testCancelRemainsAvailableWhenFullOrUnplugged() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride

        controller.clearDemand()
        controller.update(
            demand(
                connectedToPower: false,
                percentage: 100,
                isCharged: true
            )
        )

        XCTAssertEqual(controller.presentation, .chargingToFull)
        XCTAssertTrue(controller.presentation.showsButton)
    }

    func testDuplicateCancelClicksProduceOneRestoreRequest() async {
        let backend = StubBatteryChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        await beginCharge(controller, backend)
        backend.deviceState = .temporaryOverride
        backend.restoreState = .activeLimit

        controller.performPrimaryAction()
        controller.performPrimaryAction()
        await waitUntil {
            controller.presentation == .limitRestored(limit: 80)
        }

        XCTAssertEqual(backend.restoreCount, 1)
    }

    func testReportedLimitValidationRejectsOneHundredAndUnsupportedSteps() {
        XCTAssertNil(
            ChargeToFullNowDeviceState(
                mclEnabledRawValue: 0,
                mclLimit: 80,
                availableChargeLimits: [100],
                chargingOverrideAllowed: false
            ).reportedChargeLimit
        )
        XCTAssertNil(
            ChargeToFullNowDeviceState(
                mclEnabledRawValue: 3,
                mclLimit: 100,
                chargingOverrideAllowed: false
            ).reportedChargeLimit
        )
        XCTAssertNil(
            ChargeToFullNowDeviceState(
                mclEnabledRawValue: 1,
                mclLimit: 82,
                chargingOverrideAllowed: false
            ).reportedChargeLimit
        )
        XCTAssertEqual(
            ChargeToFullNowDeviceState(
                mclEnabledRawValue: 1,
                mclLimit: 85,
                availableChargeLimits: [80, 85, 90, 95, 100],
                chargingOverrideAllowed: false
            ).reportedChargeLimit,
            85
        )
    }

    func testUserDefaultsSessionStoreRoundTripsAndClears() throws {
        let suite = "StatusTrioCoreTests.ChargeSession.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = ChargeToFullNowSession(
            originalLimit: 90,
            acceptedAt: Date(timeIntervalSince1970: 1_000)
        )

        UserDefaultsChargeToFullNowSessionStore(defaults: defaults)
            .save(session)
        XCTAssertEqual(
            UserDefaultsChargeToFullNowSessionStore(defaults: defaults).load(),
            session
        )

        UserDefaultsChargeToFullNowSessionStore(defaults: defaults).clear()
        XCTAssertNil(
            UserDefaultsChargeToFullNowSessionStore(defaults: defaults).load()
        )
    }

    private func beginCharge(
        _ controller: ChargeToFullNowController,
        _ backend: StubBatteryChargeController
    ) async {
        controller.requestChargeToFullNow()
        await backend.waitUntilWriteStarts()
        backend.finishWrite(.success)
        await waitUntil { controller.presentation == .chargingToFull }
    }

    private func activeLimit(_ limit: Int) -> ChargeToFullNowDeviceState {
        ChargeToFullNowDeviceState(
            mclEnabledRawValue: 1,
            mclLimit: limit,
            chargingOverrideAllowed: false
        )
    }

    private func demand(
        popoverVisible: Bool = true,
        batterySectionVisible: Bool = true,
        connectedToPower: Bool = true,
        percentage: Int = 80,
        isCharged: Bool = false,
        isCharging: Bool = false
    ) -> ChargeToFullNowDemand {
        ChargeToFullNowDemand(
            popoverVisible: popoverVisible,
            batterySectionVisible: batterySectionVisible,
            battery: BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: isCharging,
                isCharged: isCharged,
                isLowPowerMode: false,
                isConnectedToPower: connectedToPower
            )
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class StubBatteryChargeController: BatteryChargeControlling {
    let capability: ChargeToFullNowCapability
    var deviceState: ChargeToFullNowDeviceState
    var restoreResult = ChargeToFullNowWriteResult.success
    var restoreState: ChargeToFullNowDeviceState?
    var suspendsRestore = false
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var restoreCount = 0
    private(set) var restoreTargets: [Int] = []
    private(set) var restoreExpectedLimits: [Int?] = []
    private var writeContinuation: CheckedContinuation<ChargeToFullNowWriteResult, Never>?
    private var restoreContinuation: CheckedContinuation<ChargeToFullNowWriteResult, Never>?
    private var writeStartObservers: [CheckedContinuation<Void, Never>] = []

    init(
        capability: ChargeToFullNowCapability = .available,
        deviceState: ChargeToFullNowDeviceState
    ) {
        self.capability = capability
        self.deviceState = deviceState
    }

    func readState() -> ChargeToFullNowDeviceState {
        readCount += 1
        return deviceState
    }

    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        writeCount += 1
        let observers = writeStartObservers
        writeStartObservers.removeAll()
        for observer in observers {
            observer.resume()
        }
        return await withCheckedContinuation { continuation in
            writeContinuation = continuation
        }
    }

    func waitUntilWriteStarts() async {
        guard writeCount == 0 else { return }
        await withCheckedContinuation { continuation in
            writeStartObservers.append(continuation)
        }
    }

    func finishWrite(_ result: ChargeToFullNowWriteResult) {
        writeContinuation?.resume(returning: result)
        writeContinuation = nil
    }

    func restoreChargeLimit(
        to limit: Int,
        expectedLimit: Int?
    ) async -> ChargeToFullNowWriteResult {
        restoreCount += 1
        restoreTargets.append(limit)
        restoreExpectedLimits.append(expectedLimit)
        if suspendsRestore {
            return await withCheckedContinuation { continuation in
                restoreContinuation = continuation
            }
        }
        if let restoreState {
            deviceState = restoreState
        }
        return restoreResult
    }

    func finishRestore(_ result: ChargeToFullNowWriteResult) {
        restoreContinuation?.resume(returning: result)
        restoreContinuation = nil
    }
}

private extension ChargeToFullNowDeviceState {
    static let activeLimit = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 1,
        mclLimit: 80,
        chargingOverrideAllowed: false
    )

    /// Optimized Battery Charging paused the charge with no sub-100% native
    /// limit: MCL reports "not enabled" and no limit.
    static let noActiveLimit = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 0,
        mclLimit: nil,
        chargingOverrideAllowed: false
    )

    static let temporaryOverride = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 3,
        mclLimit: 100,
        chargingOverrideAllowed: false
    )

    static let temporaryOverrideWithStoredLimit = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 3,
        mclLimit: 80,
        chargingOverrideAllowed: false
    )
}
