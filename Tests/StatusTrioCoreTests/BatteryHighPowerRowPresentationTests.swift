import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BatteryHighPowerRowPresentationTests {
    private func localization(_ language: AppLanguage = .english) throws -> Localization {
        let suite = "BatteryHighPowerRowPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removeTestSuite(named: suite)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    @Test func probedSupportedStateShowsOnOrOff() throws {
        let l10n = try localization()
        #expect(BatteryHighPowerRowPresentation.value(
            hasProbed: true, isSupported: true, isHighPowerMode: true,
            showsControl: true, localization: l10n
        ) == l10n.string(.batteryDetailsOn))
        #expect(BatteryHighPowerRowPresentation.value(
            hasProbed: true, isSupported: true, isHighPowerMode: false,
            showsControl: true, localization: l10n
        ) == l10n.string(.batteryDetailsOff))
    }

    @Test func unavailableStatesAreExplicit() throws {
        let l10n = try localization()
        #expect(BatteryHighPowerRowPresentation.value(
            hasProbed: true, isSupported: false, isHighPowerMode: false,
            showsControl: true, localization: l10n
        ) == l10n.string(.batteryDetailsHighPowerUnsupported))
        #expect(BatteryHighPowerRowPresentation.value(
            hasProbed: false, isSupported: false, isHighPowerMode: false,
            showsControl: false, localization: l10n
        ) == l10n.string(.batteryDetailsHighPowerDisabled))
        #expect(BatteryHighPowerRowPresentation.value(
            hasProbed: false, isSupported: false, isHighPowerMode: false,
            showsControl: true, localization: l10n
        ) == l10n.string(.batteryDetailsLoading))
    }
}
