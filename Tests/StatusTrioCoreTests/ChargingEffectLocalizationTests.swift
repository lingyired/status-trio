import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectLocalizationTests {
    @Test func everyLocaleHasChargingEffectAndBoltHeartbeatStrings() throws {
        let keys: [LocalizationKey] = [
            .settingsBatteryChargingEffect,
            .settingsBatteryChargingEffectDescription,
            .settingsBatteryChargingBoltHeartbeat,
            .settingsBatteryChargingBoltHeartbeatDescription,
            .settingsBatteryChargingEffectTest,
            .settingsBatteryChargingEffectTestDescription
        ]

        for language in AppLanguage.allCases {
            let bundle = try #require(Localization.resourceBundle(for: language))
            for key in keys {
                let value = bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
                #expect(!value.isEmpty)
                #expect(value != key.rawValue)
            }
        }
    }
}
