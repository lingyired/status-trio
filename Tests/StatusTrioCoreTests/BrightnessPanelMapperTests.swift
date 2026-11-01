import XCTest
@testable import StatusTrioCore

@MainActor
final class BrightnessPanelMapperTests: XCTestCase {
    func testMapsAdjustableDisplayWithPercentageAndAccessibility() throws {
        let status = BrightnessStatus(
            displays: [
                DisplayBrightness(
                    id: "uuid-1",
                    name: "Built-in",
                    isBuiltin: true,
                    scalar: 0.42,
                    canAdjust: true,
                    backend: .betterDisplay,
                    source: .betterDisplay
                )
            ]
        )

        let state = BrightnessPanelMapper.map(status, localization: makeLocalization(.english))

        XCTAssertEqual(state.rows.count, 1)
        let row = try XCTUnwrap(state.rows.first)
        XCTAssertEqual(row.percentageText, "42%")
        XCTAssertTrue(row.canAdjust)
        XCTAssertNil(row.unavailableText)
        XCTAssertFalse(row.accessibilityLabel.isEmpty)
    }

    func testUnavailableDisplayCarriesReasonTextAndNoScalar() {
        let status = BrightnessStatus(
            displays: [
                DisplayBrightness(
                    id: "uuid-2",
                    name: "External",
                    isBuiltin: false,
                    scalar: 0.5,
                    canAdjust: false,
                    backend: .directDDC,
                    source: .unavailable(.resolveFailed)
                )
            ]
        )

        let state = BrightnessPanelMapper.map(status, localization: makeLocalization(.english))

        XCTAssertNil(state.rows.first?.scalar)
        XCTAssertEqual(state.rows.first?.canAdjust, false)
        XCTAssertNotNil(state.rows.first?.unavailableText)
    }

    func testPercentageClampsAndRounds() {
        XCTAssertEqual(BrightnessPanelMapper.percentText(-1), "0%")
        XCTAssertEqual(BrightnessPanelMapper.percentText(2), "100%")
        XCTAssertEqual(BrightnessPanelMapper.percentText(0.005), "1%")
    }

    func testPlaceholderMapsToEmptyRows() {
        let state = BrightnessPanelMapper.map(.placeholder, localization: makeLocalization(.english))
        XCTAssertTrue(state.isEmpty)
    }

    func testDirectDDCConfigurationSanitizesAwayUUID() {
        let configuration = ExternalBrightnessConfiguration(
            backend: .directDDC,
            betterDisplayUUID: "ignored"
        )
        XCTAssertEqual(configuration.sanitized(), .default)
    }

    func testBetterDisplayConfigurationTrimsUUID() {
        let configuration = ExternalBrightnessConfiguration(
            backend: .betterDisplay,
            betterDisplayUUID: "  abc  "
        )
        XCTAssertEqual(configuration.sanitized()?.betterDisplayUUID, "abc")
        XCTAssertEqual(configuration.sanitized()?.backend, .betterDisplay)
    }

    func testBetterDisplayConfigurationWithBlankUUIDKeepsBackend() {
        let configuration = ExternalBrightnessConfiguration(
            backend: .betterDisplay,
            betterDisplayUUID: "   "
        )
        XCTAssertEqual(configuration.sanitized()?.backend, .betterDisplay)
        XCTAssertNil(configuration.sanitized()?.betterDisplayUUID)
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "BrightnessPanelMapperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }
}
