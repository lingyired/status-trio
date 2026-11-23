import XCTest
@testable import StatusTrioCore

/// The helper is shared by two independent consumer intents (battery power
/// controls + lid-sleep), enabled while EITHER is on and only disabled when both
/// are off. These tests pin that OR model and the removal of the old one-way
/// mirror (helper state no longer drives the battery toggle).
@MainActor
final class LowPowerModeControlSynchronizerTests: XCTestCase {
    func testHelperEnabledWhenLidConsumerOnByDefault() {
        let suite = makeSuite(); defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults) // lid button defaults on
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let helper = PrivilegedHelperManager(service: service)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)
        XCTAssertTrue(helper.isEnabled, "lid consumer is on by default, so the helper is enabled")
        synchronizer.stop()
    }

    func testBothConsumersOffDisablesHelperWithoutUnregistering() {
        let suite = makeSuite(); defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(false, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        defaults.set(false, forKey: SettingsStore.showsLidSleepButtonDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        let service = FakePrivilegedHelperService(status: .enabled)
        let helper = PrivilegedHelperManager(service: service)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)

        XCTAssertFalse(helper.isEnabled)
        XCTAssertEqual(service.status, .enabled, "disabling contact must not unregister")
        XCTAssertEqual(service.unregisterCallCount, 0)
        synchronizer.stop()
    }

    func testTurningOffBatteryKeepsHelperWhileLidStillOn() {
        let suite = makeSuite(); defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(true, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        defaults.set(true, forKey: SettingsStore.showsLidSleepButtonDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .enabled))
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)
        XCTAssertTrue(helper.isEnabled)

        settings.controlsLowPowerMode = false
        XCTAssertTrue(helper.isEnabled, "lid consumer keeps the helper enabled")

        settings.showsLidSleepButton = false
        XCTAssertFalse(helper.isEnabled, "only when both are off does the helper disable")
        synchronizer.stop()
    }

    func testTurningOffLidKeepsHelperWhileBatteryStillOn() {
        let suite = makeSuite(); defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(true, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .enabled))
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)

        settings.showsLidSleepButton = false
        XCTAssertTrue(helper.isEnabled, "battery consumer keeps the helper enabled")
        synchronizer.stop()
    }

    func testHelperStateNoLongerMirrorsIntoBatteryToggle() {
        let suite = makeSuite(); defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(false, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        defaults.set(false, forKey: SettingsStore.showsLidSleepButtonDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)

        helper.setEnabled(true)
        XCTAssertFalse(settings.controlsLowPowerMode, "helper state must not drive the battery intent")
        synchronizer.stop()
    }

    func testRelaunchPreservesIntent() {
        let suite = makeSuite(); defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(true, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        defaults.set(false, forKey: SettingsStore.showsLidSleepButtonDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        LowPowerModeControlSynchronizer().start(settings: settings, helper: helper)
        XCTAssertTrue(helper.isEnabled)

        let relaunchSettings = SettingsStore(defaults: defaults)
        let relaunchHelper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        let sync2 = LowPowerModeControlSynchronizer()
        sync2.start(settings: relaunchSettings, helper: relaunchHelper)
        XCTAssertTrue(relaunchHelper.isEnabled)
        sync2.stop()
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.LowPowerModeControlSynchronizer.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
