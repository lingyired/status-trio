import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectSettingsTests {
    @Test func surfaceChargingEffectsDefaultOnPersistIndependentlyAndDriveTheIconOptions() throws {
        let domain = "ChargingEffectSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(defaults.object(forKey: SettingsStore.showsMenuBarChargingEffectDefaultsKey) == nil)
        #expect(defaults.object(forKey: SettingsStore.showsDockChargingEffectDefaultsKey) == nil)
        let first = SettingsStore(defaults: defaults)
        #expect(first.showsMenuBarChargingEffect)
        #expect(first.showsDockChargingEffect)
        #expect(first.showsChargingEffect, "The aggregate feeds the shared icon scene.")
        #expect(first.batteryIconOptions.showsChargingEffect)

        first.showsMenuBarChargingEffect = false
        #expect(
            defaults.object(forKey: SettingsStore.showsMenuBarChargingEffectDefaultsKey) as? Bool
                == false
        )
        #expect(
            defaults.object(forKey: SettingsStore.showsDockChargingEffectDefaultsKey) as? Bool
                == true
        )
        #expect(first.showsDockChargingEffect)
        #expect(first.batteryIconOptions.showsChargingEffect)

        first.showsDockChargingEffect = false
        #expect(
            defaults.object(forKey: SettingsStore.showsDockChargingEffectDefaultsKey) as? Bool
                == false
        )
        #expect(!first.showsChargingEffect)
        #expect(!first.batteryIconOptions.showsChargingEffect)

        let restored = SettingsStore(defaults: defaults)
        #expect(!restored.showsMenuBarChargingEffect)
        #expect(!restored.showsDockChargingEffect)
        #expect(!restored.showsChargingEffect)

        restored.showsMenuBarChargingEffect = true
        #expect(restored.showsChargingEffect)
        #expect(restored.batteryIconOptions.showsChargingEffect)
        #expect(!restored.showsDockChargingEffect)
    }

    @Test func legacyChargingEffectMigratesToBothSurfacesUnlessANewKeyAlreadyExists() throws {
        let migrationDomain = "ChargingEffectSettingsMigration.\(UUID().uuidString)"
        let migrationDefaults = try #require(UserDefaults(suiteName: migrationDomain))
        defer { migrationDefaults.removePersistentDomain(forName: migrationDomain) }
        migrationDefaults.set(false, forKey: SettingsStore.showsChargingEffectDefaultsKey)

        let migrated = SettingsStore(defaults: migrationDefaults)
        #expect(!migrated.showsMenuBarChargingEffect)
        #expect(!migrated.showsDockChargingEffect)
        #expect(!migrated.showsChargingEffect)

        let overrideDomain = "ChargingEffectSettingsOverride.\(UUID().uuidString)"
        let overrideDefaults = try #require(UserDefaults(suiteName: overrideDomain))
        defer { overrideDefaults.removePersistentDomain(forName: overrideDomain) }
        overrideDefaults.set(false, forKey: SettingsStore.showsChargingEffectDefaultsKey)
        overrideDefaults.set(true, forKey: SettingsStore.showsMenuBarChargingEffectDefaultsKey)

        let overridden = SettingsStore(defaults: overrideDefaults)
        #expect(overridden.showsMenuBarChargingEffect)
        #expect(!overridden.showsDockChargingEffect)
    }

    @Test func chargingBoltHeartbeatDefaultsOnAndPersistsThroughIconOptions() throws {
        let domain = "ChargingBoltHeartbeatSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(defaults.object(forKey: SettingsStore.showsChargingBoltHeartbeatDefaultsKey) == nil)
        let first = SettingsStore(defaults: defaults)
        #expect(first.showsChargingBoltHeartbeat)
        #expect(first.batteryIconOptions.showsChargingBoltHeartbeat)

        first.showsChargingBoltHeartbeat = false
        #expect(defaults.object(forKey: SettingsStore.showsChargingBoltHeartbeatDefaultsKey) as? Bool == false)
        let restored = SettingsStore(defaults: defaults)
        #expect(!restored.showsChargingBoltHeartbeat)
        #expect(!restored.batteryIconOptions.showsChargingBoltHeartbeat)

        restored.showsChargingEffect = false
        #expect(!restored.showsChargingBoltHeartbeat)
        restored.showsChargingEffect = true
        restored.showsChargingIndicator = false
        #expect(!restored.showsChargingBoltHeartbeat)
    }

    @Test func testAnimationSwitchDoesNotEnableSurfacesAndDoesNotPersistTestMode() throws {
        let domain = "ChargingEffectTestMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: SettingsStore.showsChargingEffectDefaultsKey)

        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.testsChargingEffect)
        settings.setChargingEffectTestEnabled(true)
        #expect(settings.testsChargingEffect)
        #expect(!settings.showsMenuBarChargingEffect)
        #expect(!settings.showsDockChargingEffect)

        let reopened = SettingsStore(defaults: defaults)
        #expect(!reopened.testsChargingEffect)
        #expect(!reopened.showsMenuBarChargingEffect)
        #expect(!reopened.showsDockChargingEffect)

        settings.setChargingEffectTestEnabled(false)
        #expect(!settings.testsChargingEffect)

        settings.setChargingEffectTestEnabled(true)
        settings.showsMenuBarChargingEffect = true
        settings.showsDockChargingEffect = false
        settings.showsMenuBarChargingEffect = false
        #expect(!settings.testsChargingEffect)
    }

    @Test func theTestInputDoesNotOverrideSurfaceSwitches() throws {
        let domain = "ChargingEffectTestModeSurfaces.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let settings = SettingsStore(defaults: defaults)
        settings.showsMenuBarChargingEffect = false
        settings.showsDockChargingEffect = false
        settings.setChargingEffectTestEnabled(true)

        #expect(settings.testsChargingEffect)
        #expect(!settings.showsMenuBarChargingEffect)
        #expect(!settings.showsDockChargingEffect)
    }

    /// Turning the effect off must clear the test input, but turning it back on
    /// must leave the test switch exactly where the user put it. A setting
    /// toggle that flips from off to on used to zero the test input on the
    /// first half of the write and leave the UI showing a stale "on".
    @Test func reenablingTheEffectDoesNotSilentlyDisableTheTestInput() throws {
        let domain = "ChargingEffectTestMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let settings = SettingsStore(defaults: defaults)
        settings.setChargingEffectTestEnabled(true)
        settings.showsChargingEffect = false
        #expect(!settings.testsChargingEffect)

        settings.showsChargingEffect = true
        #expect(!settings.testsChargingEffect, "Re-enabling the effect must not invent a test input.")
    }
}
