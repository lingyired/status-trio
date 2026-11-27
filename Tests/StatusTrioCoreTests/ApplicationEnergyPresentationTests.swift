import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class ApplicationEnergyPresentationTests: XCTestCase {
    func testCPUEnergyUsesMilliwattsAndLargeValuesUseWatts() throws {
        let suite = "ApplicationEnergyPresentationTests.Format.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        XCTAssertEqual(
            ApplicationEnergyPresentation.valueText(
                for: 0.01234,
                basis: .cpuEnergy,
                localization: localization
            ),
            "12.3 mW"
        )
        XCTAssertEqual(
            ApplicationEnergyPresentation.valueText(
                for: 1.234,
                basis: .cpuEnergy,
                localization: localization
            ),
            "1.23 W"
        )
    }

    func testCPUActivityFallsBackToPercent() throws {
        let suite = "ApplicationEnergyPresentationTests.Activity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        XCTAssertEqual(
            ApplicationEnergyPresentation.valueText(
                for: 0.032,
                basis: .cpuActivity,
                localization: localization
            ),
            "3.2%"
        )
    }

    func testBasisTitlesAreExplicit() throws {
        let suite = "ApplicationEnergyPresentationTests.BasisTitles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.english))
        XCTAssertEqual(localization.string(ApplicationEnergyPresentation.titleKey(for: .cpuAndGPU)),
                       "App Energy · Last 1 Minute")
        XCTAssertEqual(localization.string(ApplicationEnergyPresentation.titleKey(for: .cpuEnergy)),
                       "CPU Energy · Last 1 Minute")
        XCTAssertEqual(localization.string(ApplicationEnergyPresentation.titleKey(for: .gpuEnergy)),
                       "GPU Energy · Last 1 Minute")
        XCTAssertEqual(localization.string(ApplicationEnergyPresentation.titleKey(for: .cpuActivity)),
                       "CPU Activity")
    }

    func testListTitleNamesAppEnergyImpact() throws {
        let suite = "ApplicationEnergyPresentationTests.Title.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        localization.setPreference(.language(.english))
        XCTAssertEqual(
            localization.string(.batteryHighEnergyApps),
            "App Energy Impact"
        )

        localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(
            localization.string(.batteryHighEnergyApps),
            "应用能耗影响"
        )
    }
}
