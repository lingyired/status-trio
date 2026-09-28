import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectSettingsTests {
    @Test func chargingEffectDefaultsOnAndPersistsThroughIconOptions() throws {
        let domain = "ChargingEffectSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(defaults.object(forKey: SettingsStore.showsChargingEffectDefaultsKey) == nil)
        let first = SettingsStore(defaults: defaults)
        #expect(first.showsChargingEffect)
        #expect(first.batteryIconOptions.showsChargingEffect)

        first.showsChargingEffect = false
        #expect(defaults.object(forKey: SettingsStore.showsChargingEffectDefaultsKey) as? Bool == false)
        let restored = SettingsStore(defaults: defaults)
        #expect(restored.showsChargingEffect == false)
        #expect(restored.batteryIconOptions.showsChargingEffect == false)

        restored.showsChargingEffect = true
        #expect(SettingsStore(defaults: defaults).batteryIconOptions.showsChargingEffect)
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

    @Test func testAnimationSwitchStartsTheEffectWithoutPersistingTestMode() throws {
        let domain = "ChargingEffectTestMode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: SettingsStore.showsChargingEffectDefaultsKey)

        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.testsChargingEffect)
        settings.setChargingEffectTestEnabled(true)
        #expect(settings.testsChargingEffect)
        #expect(settings.showsChargingEffect)

        let reopened = SettingsStore(defaults: defaults)
        #expect(!reopened.testsChargingEffect)
        #expect(reopened.showsChargingEffect)

        settings.setChargingEffectTestEnabled(false)
        #expect(!settings.testsChargingEffect)

        settings.setChargingEffectTestEnabled(true)
        settings.showsChargingEffect = false
        #expect(!settings.testsChargingEffect)
    }
}
