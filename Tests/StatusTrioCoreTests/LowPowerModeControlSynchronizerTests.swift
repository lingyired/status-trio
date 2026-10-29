import XCTest
@testable import StatusTrioCore

@MainActor
final class LowPowerModeControlSynchronizerTests: XCTestCase {
    func testRelaunchPreservesOptOutWhileHelperRemainsRegistered() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .enabled)
        let helper = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: helper)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: facade)
        helper.setEnabled(false)
        synchronizer.stop()

        let relaunchedSettings = SettingsStore(defaults: suite.defaults)
        let relaunchedHelper = PrivilegedHelperManager(service: service)
        let relaunchedFacade = PrivilegedHelperFacade(service: relaunchedHelper)
        synchronizer.start(settings: relaunchedSettings, helper: relaunchedFacade)

        XCTAssertFalse(relaunchedHelper.isEnabled)
        XCTAssertFalse(relaunchedSettings.controlsLowPowerMode)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
        synchronizer.stop()
    }

    func testRelaunchPreservesOptInAfterFailedRegistration() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let helper = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: helper)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: facade)
        service.registerError = NSError(domain: "test", code: 1)
        helper.setEnabled(true)
        synchronizer.stop()

        let relaunchedSettings = SettingsStore(defaults: suite.defaults)
        let relaunchedHelper = PrivilegedHelperManager(service: service)
        let relaunchedFacade = PrivilegedHelperFacade(service: relaunchedHelper)
        synchronizer.start(settings: relaunchedSettings, helper: relaunchedFacade)

        XCTAssertTrue(relaunchedHelper.isEnabled)
        XCTAssertTrue(relaunchedSettings.controlsLowPowerMode)
        XCTAssertEqual(service.registerCallCount, 1)
        synchronizer.stop()
    }

    func testRegistrationMirrorsIntoThePersistedFlag() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        let facade = PrivilegedHelperFacade(service: helper)
        let synchronizer = LowPowerModeControlSynchronizer()

        synchronizer.start(settings: settings, helper: facade)
        XCTAssertFalse(settings.controlsLowPowerMode)

        helper.setEnabled(true)

        XCTAssertTrue(settings.controlsLowPowerMode)
    }

    func testOptOutClearsThePersistedFlagWithoutUnregistering() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .enabled)
        let helper = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: helper)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: facade)
        XCTAssertTrue(settings.controlsLowPowerMode)
        XCTAssertTrue(helper.isAvailable)

        helper.setEnabled(false)

        XCTAssertFalse(helper.isEnabled)
        XCTAssertFalse(facade.isEnabled)
        XCTAssertFalse(settings.controlsLowPowerMode)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testPendingApprovalStillCountsAsOn() {
        // The user asked for the feature; a registration awaiting approval must
        // not flip the persisted flag back off while they go approve it.
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let helper = PrivilegedHelperManager(service: service)
        let facade = PrivilegedHelperFacade(service: helper)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: facade)

        helper.setEnabled(true)

        XCTAssertTrue(settings.controlsLowPowerMode)
    }

    func testSavedOptInIsPreservedWhenTheHelperIsGone() {
        // Preserve user intent even if the system has lost the registration.
        let suite = makeSuite()
        defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(true, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.controlsLowPowerMode)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        let facade = PrivilegedHelperFacade(service: helper)

        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: facade)

        XCTAssertTrue(settings.controlsLowPowerMode)
        XCTAssertTrue(helper.isEnabled)
        synchronizer.stop()
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.LowPowerModeControlSynchronizer.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
