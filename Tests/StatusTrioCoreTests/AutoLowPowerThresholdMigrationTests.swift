import XCTest
@testable import StatusTrioCore

/// The automation threshold is independent of the critical colour threshold:
/// raising one must never move the other.
@MainActor
final class AutoLowPowerThresholdMigrationTests: XCTestCase {
    func testAnExplicitAutomationThresholdIsKept() {
        let defaults = makeDefaults()
        defaults.set(75.0, forKey: SettingsStore.autoLowPowerThresholdDefaultsKey)
        defaults.set(15.0, forKey: SettingsStore.batteryCriticalThresholdDefaultsKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.autoLowPowerThreshold, 75)
        XCTAssertEqual(store.batteryCriticalThreshold, 15)
    }

    func testDefaultCriticalThresholdKeepsBothDefaults() {
        let store = SettingsStore(defaults: makeDefaults())

        XCTAssertEqual(
            store.autoLowPowerThreshold,
            SettingsStore.defaultAutoLowPowerThreshold
        )
        XCTAssertEqual(
            store.batteryCriticalThreshold,
            SettingsStore.defaultBatteryCriticalThreshold
        )
    }

    func testAutomaticThresholdPersistsAndClamps() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.autoLowPowerThreshold = 88

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.autoLowPowerThreshold, 88)

        second.autoLowPowerThreshold = 500
        XCTAssertEqual(second.autoLowPowerThreshold, 100)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "StatusTrioCoreTests.AutoLowPowerThreshold.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}
