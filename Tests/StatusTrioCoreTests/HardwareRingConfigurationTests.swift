import XCTest
@testable import StatusTrioCore

final class HardwareRingConfigurationTests: XCTestCase {
    func testCodableRoundTripPreservesAllParts() throws {
        let configuration = HardwareRingConfiguration(
            layout: .dual,
            primaryMetric: .cpuUsage,
            secondaryMetric: .gpuUsage,
            topContent: .value(.cpuTemperature),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true),
            overrides: [
                .cpuUsage: HardwareMetricRingOptions(
                    displayMinimum: 0, displayMaximum: 100,
                    warningThreshold: 70, criticalThreshold: 85
                )
            ]
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(HardwareRingConfiguration.self, from: data)
        XCTAssertEqual(decoded, configuration)
    }

    func testTopContentTaggedCoding() throws {
        let cases: [HardwareRingTopContent] = [
            .automatic, .hidden, .symbol(.gpuUsage), .value(.fan)
        ]
        for content in cases {
            let data = try JSONEncoder().encode(content)
            let decoded = try JSONDecoder().decode(HardwareRingTopContent.self, from: data)
            XCTAssertEqual(decoded, content)
        }
    }

    func testMissingFieldsDecodeToDefaults() throws {
        let json = Data(#"{"layout":"dual","primaryMetric":"fan"}"#.utf8)
        let decoded = try JSONDecoder().decode(HardwareRingConfiguration.self, from: json)
        XCTAssertEqual(decoded.layout, .dual)
        XCTAssertEqual(decoded.primaryMetric, .fan)
        XCTAssertEqual(decoded.topContent, .automatic)
        XCTAssertFalse(decoded.color.monochrome)
        XCTAssertFalse(decoded.color.thresholdColors)
        XCTAssertTrue(decoded.overrides.isEmpty)
    }

    func testLegacyColorModeMigratesToTwoToggles() throws {
        func decode(_ mode: String) throws -> HardwareRingColorConfiguration {
            let json = Data("{\"mode\":\"\(mode)\"}".utf8)
            return try JSONDecoder().decode(HardwareRingColorConfiguration.self, from: json)
        }
        XCTAssertEqual(try decode("status"), HardwareRingColorConfiguration(monochrome: false, thresholdColors: true))
        XCTAssertEqual(try decode("fixed"), HardwareRingColorConfiguration(monochrome: false, thresholdColors: false))
        XCTAssertEqual(try decode("monochrome"), HardwareRingColorConfiguration(monochrome: true, thresholdColors: false))
    }

    func testUnknownLayoutStringFallsBackToDefault() throws {
        let json = Data(#"{"layout":"hyper","primaryMetric":"cpuUsage"}"#.utf8)
        let decoded = try JSONDecoder().decode(HardwareRingConfiguration.self, from: json)
        XCTAssertEqual(decoded.layout, .single)
        XCTAssertEqual(decoded.primaryMetric, .cpuUsage)
    }

    func testPercentageMetricsForceFixedRange() {
        let options = HardwareMetricRingOptions(
            displayMinimum: 10, displayMaximum: 200,
            warningThreshold: 90, criticalThreshold: 80
        ).normalized(for: .gpuUsage)
        XCTAssertEqual(options.displayMinimum, 0)
        XCTAssertEqual(options.displayMaximum, 100)
        // warning >= critical is invalid, so both reset to defaults.
        XCTAssertEqual(options.warningThreshold, 80)
        XCTAssertEqual(options.criticalThreshold, 95)
    }

    func testSingleLayoutClearsSecondaryMetric() {
        let configuration = HardwareRingConfiguration(
            layout: .single, primaryMetric: .cpuUsage, secondaryMetric: .gpuUsage
        ).normalized()
        XCTAssertNil(configuration.secondaryMetric)
        XCTAssertEqual(configuration.referencedMetrics, [.cpuUsage])
    }

    func testDualLayoutEnsuresDistinctSecondary() {
        let configuration = HardwareRingConfiguration(
            layout: .dual, primaryMetric: .cpuUsage, secondaryMetric: .cpuUsage
        ).normalized()
        XCTAssertNotEqual(configuration.normalizedSecondaryMetric, .cpuUsage)
        XCTAssertEqual(configuration.referencedMetrics.count, 2)
        XCTAssertEqual(Set(configuration.referencedMetrics).count, 2)
    }

    func testReferencedMetricsIncludePinnedTopMetric() {
        let configuration = HardwareRingConfiguration(
            layout: .single,
            primaryMetric: .cpuUsage,
            topContent: .value(.cpuTemperature)
        )
        XCTAssertEqual(configuration.referencedMetrics, [.cpuUsage, .cpuTemperature])
    }

    func testTemperatureRangePreservedButBogusRepaired() {
        let options = HardwareMetricRingOptions(
            displayMinimum: 20, displayMaximum: 90,
            warningThreshold: 70, criticalThreshold: 85
        ).normalized(for: .cpuTemperature)
        XCTAssertEqual(options.displayMinimum, 20)
        XCTAssertEqual(options.displayMaximum, 90)

        let bogus = HardwareMetricRingOptions(
            displayMinimum: 80, displayMaximum: 40,
            warningThreshold: 70, criticalThreshold: 85
        ).normalized(for: .cpuTemperature)
        XCTAssertLessThan(bogus.displayMinimum, bogus.displayMaximum)
    }

    func testFanDynamicSentinelKept() {
        let options = HardwareMetricRingOptions.default(for: .fan).normalized(for: .fan)
        XCTAssertEqual(options.displayMinimum, 0)
        XCTAssertEqual(options.displayMaximum, 0)
    }

    func testTopMarkerScaleClampsAndDefaultsOnDecode() throws {
        XCTAssertEqual(HardwareRingConfiguration(topMarkerScale: 5).topMarkerScale, 1.6)
        XCTAssertEqual(HardwareRingConfiguration(topMarkerScale: 0.1).topMarkerScale, 0.6)
        let json = Data(#"{"layout":"single","primaryMetric":"cpuUsage"}"#.utf8)
        let decoded = try JSONDecoder().decode(HardwareRingConfiguration.self, from: json)
        XCTAssertEqual(decoded.topMarkerScale, 1.0)
    }
}

extension HardwareRingConfigurationTests {
    func testLegacyTopIconModesMigrateToValue() {
        let automatic = HardwareRingConfiguration(layout: .single, primaryMetric: .gpuUsage, topContent: .automatic)
        XCTAssertEqual(automatic.migratingLegacyTopIcon().topContent, .value(.gpuUsage))

        let symbol = HardwareRingConfiguration(layout: .single, primaryMetric: .cpuUsage, topContent: .symbol(.fan))
        XCTAssertEqual(symbol.migratingLegacyTopIcon().topContent, .value(.fan))

        let hidden = HardwareRingConfiguration(layout: .single, topContent: .hidden)
        XCTAssertEqual(hidden.migratingLegacyTopIcon().topContent, .hidden)

        let value = HardwareRingConfiguration(layout: .single, topContent: .value(.cpuTemperature))
        XCTAssertEqual(value.migratingLegacyTopIcon().topContent, .value(.cpuTemperature))
    }
}
