import Foundation
import Testing
@testable import StatusTrioCore

/// #255: the two per-power-source refresh cadences and the power-source choice.
@MainActor
struct RefreshIntervalTests {
    @Test func defaultsAreFifteenSecondsForBothSources() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            #expect(store.refreshIntervalOnBatterySeconds == 15)
            #expect(store.refreshIntervalOnPowerSeconds == 15)
            #expect(store.refreshInterval(forPluggedIn: false) == .seconds(15))
            #expect(store.refreshInterval(forPluggedIn: true) == .seconds(15))
        }
    }

    @Test func selectionUsesBatteryOnlyWhenUnplugged() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.refreshIntervalOnBatterySeconds = 10
            store.refreshIntervalOnPowerSeconds = 30

            #expect(store.refreshInterval(forPluggedIn: false) == .seconds(10))
            #expect(store.refreshInterval(forPluggedIn: true) == .seconds(30))
        }
    }

    @Test func legacyValueMigratesToBothSources() {
        withIsolatedDefaults { defaults in
            defaults.set(25.0, forKey: SettingsStore.refreshIntervalDefaultsKey)

            let store = SettingsStore(defaults: defaults)

            #expect(store.refreshIntervalOnBatterySeconds == 25)
            #expect(store.refreshIntervalOnPowerSeconds == 25)
        }
    }

    @Test func eachSourceMigratesIndependentlyAndANewKeyWins() {
        withIsolatedDefaults { defaults in
            defaults.set(25.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
            defaults.set(40.0, forKey: SettingsStore.refreshIntervalOnBatteryDefaultsKey)

            let store = SettingsStore(defaults: defaults)

            #expect(store.refreshIntervalOnBatterySeconds == 40)
            #expect(store.refreshIntervalOnPowerSeconds == 25)
        }
    }

    @Test func changingOneSourceDoesNotOverwriteTheOtherMigratedSource() {
        withIsolatedDefaults { defaults in
            defaults.set(25.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
            let first = SettingsStore(defaults: defaults)
            first.refreshIntervalOnBatterySeconds = 30

            let second = SettingsStore(defaults: defaults)

            #expect(second.refreshIntervalOnBatterySeconds == 30)
            #expect(second.refreshIntervalOnPowerSeconds == 25)
            // The legacy key stays as the migration source and is not rewritten.
            #expect(
                (defaults.object(forKey: SettingsStore.refreshIntervalDefaultsKey) as? NSNumber)?
                    .doubleValue == 25
            )
        }
    }

    @Test func clampingUsesOneSecondStepAndRejectsNonFinite() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            store.refreshIntervalOnBatterySeconds = 7
            #expect(store.refreshIntervalOnBatterySeconds == 7)

            store.refreshIntervalOnPowerSeconds = 307
            #expect(store.refreshIntervalOnPowerSeconds == 60)

            store.refreshIntervalOnBatterySeconds = 4
            #expect(store.refreshIntervalOnBatterySeconds == 5)

            store.refreshIntervalOnPowerSeconds = .nan
            #expect(store.refreshIntervalOnPowerSeconds == 15)

            let reopened = SettingsStore(defaults: defaults)
            #expect(reopened.refreshIntervalOnBatterySeconds == 5)
            #expect(reopened.refreshIntervalOnPowerSeconds == 15)
        }
    }

    @Test func outOfRangeStoredNewValueIsClampedOnLoad() {
        withIsolatedDefaults { defaults in
            defaults.set(1000.0, forKey: SettingsStore.refreshIntervalOnPowerDefaultsKey)

            let store = SettingsStore(defaults: defaults)

            #expect(store.refreshIntervalOnPowerSeconds == 60)
        }
    }

    @Test func desktopAndUnpluggedLaptopSelectTheRightCadence() {
        let desktop = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let unplugged = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let plugged = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )

        #expect(StatusBarController.effectivePluggedIn(battery: desktop))
        // Charging state alone must not flip an unplugged Mac to wall power.
        #expect(!StatusBarController.effectivePluggedIn(battery: unplugged))
        #expect(StatusBarController.effectivePluggedIn(battery: plugged))
    }
}

@MainActor
private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
    let name = "StatusTrioCoreTests.RefreshInterval.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        Issue.record("could not create isolated user defaults suite")
        return
    }
    defer { defaults.removePersistentDomain(forName: name) }
    body(defaults)
}
