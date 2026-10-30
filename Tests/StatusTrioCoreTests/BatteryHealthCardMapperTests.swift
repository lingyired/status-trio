import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryHealthCardMapperTests: XCTestCase {
    private func localized(_ language: String = "en") -> Localization {
        let suite = "BatteryHealthCardMapperTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite) ?? .standard,
                            preferredLanguages: [language])
    }

    private func battery(connected: Bool = true, charging: Bool = true) -> BatteryStatus {
        BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: charging,
                      isLowPowerMode: false, isConnectedToPower: connected)
    }

    private func details(
        health: BatteryHealthSnapshot?,
        cycleCount: Int? = 52,
        power: BatteryPowerSample? = nil
    ) -> BatteryDetails {
        var details = BatteryDetails(cycleCount: cycleCount, powerAvailability: .available)
        details.health = health
        details.power = power
        return details
    }

    private let fullHealth = BatteryHealthSnapshot(
        designCapacityMAh: 8_579,
        maximumCapacityMAh: 8_413,
        healthPercent: 98.07,
        temperatureCelsius: 36.0,
        chargeTime: .estimated(minutes: 80)
    )

    func testHealthCardCarriesEveryMetricAndMovesTheCycleRow() throws {
        let localization = localized()
        let state = PanelDetailMapper.battery(
            status: battery(),
            details: details(health: fullHealth),
            localization: localization)

        let card = try XCTUnwrap(state.batteryHealth)
        XCTAssertEqual(card.title, localization.string(.batteryHealthTitle))
        XCTAssertEqual(card.metrics.map(\.id), ["maximum", "health", "design", "cycles", "temperature"])
        XCTAssertEqual(card.metrics[0].value, "8,413 mAh")
        XCTAssertEqual(card.metrics[1].label, localization.string(.batteryHealthEstimate))
        XCTAssertEqual(card.metrics[1].value, "98%")
        XCTAssertEqual(card.metrics[2].value, "8,579 mAh")
        XCTAssertEqual(card.metrics[3].value, "52")
        XCTAssertEqual(card.metrics[4].value, "36.0 °C")
        XCTAssertEqual(card.chargeTimeValue, "About 1 h 20 min to full")
        XCTAssertEqual(card.footnote, localization.string(.batteryHealthEstimateNote))

        // The cycle count lives in the card now, exactly once.
        let cycleKey = LocalizationKey.batteryDetailsCycles.rawValue
        XCTAssertFalse(state.rows.contains { $0.id == cycleKey },
                       "the cycle count must not be rendered twice")
        let rowValues = state.rows.map(\.value)
        XCTAssertFalse(rowValues.contains("52"))
    }

    func testPartialHealthOnlyDegradesTheMissingMetric() throws {
        let localization = localized()
        let partial = BatteryHealthSnapshot(
            designCapacityMAh: 8_579,
            maximumCapacityMAh: 8_413,
            healthPercent: BatteryHealthParser.healthPercent(maximumMAh: 8_413, designMAh: 8_579),
            temperatureCelsius: nil,
            chargeTime: .unavailable)
        var base = details(health: partial,
                           power: BatteryPowerSample(volts: 12.28, amps: -1.53,
                                                     updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        base.adapterWatts = 90
        let state = PanelDetailMapper.battery(
            status: battery(connected: false, charging: false),
            details: base,
            localization: localization)
        let card = try XCTUnwrap(state.batteryHealth)
        XCTAssertEqual(card.metrics.first { $0.id == "temperature" }?.value,
                       localization.string(.batteryHealthValueUnavailable))
        XCTAssertEqual(card.metrics.first { $0.id == "maximum" }?.value, "8,413 mAh")
        XCTAssertEqual(card.chargeTimeValue, localization.string(.batteryDetailsUnavailable))
        // Existing power rows are untouched by the card.
        XCTAssertTrue(state.rows.contains { $0.id == LocalizationKey.batteryDetailsVoltage.rawValue })
        XCTAssertTrue(state.rows.contains { $0.id == LocalizationKey.batteryDetailsCurrent.rawValue })
        XCTAssertTrue(state.rows.contains { $0.id == LocalizationKey.batteryDetailsAdapter.rawValue })
        XCTAssertTrue(state.rows.contains { $0.id == LocalizationKey.batteryDetailsLowPower.rawValue })
    }

    func testCardIsHiddenWithoutHealthMetricsAndTheCycleRowReturns() throws {
        let localization = localized()
        let state = PanelDetailMapper.battery(
            status: battery(),
            details: details(health: BatteryHealthSnapshot(chargeTime: .paused)),
            localization: localization)
        XCTAssertNil(state.batteryHealth)
        let row = try XCTUnwrap(state.rows.first { $0.id == LocalizationKey.batteryDetailsCycles.rawValue })
        XCTAssertEqual(row.value, "52")
    }

    func testChargeTimeAloneCanJustifyTheCard() throws {
        let localization = localized()
        let state = PanelDetailMapper.battery(
            status: battery(),
            details: details(health: BatteryHealthSnapshot(chargeTime: .calculating), cycleCount: nil),
            localization: localization)
        let card = try XCTUnwrap(state.batteryHealth)
        XCTAssertEqual(card.chargeTimeValue,
                       localization.string(.batteryStateCalculatingTimeToFull))
        XCTAssertEqual(card.metrics.map(\.id), ["maximum", "health", "design", "temperature"])
        XCTAssertEqual(card.metrics[0].value, localization.string(.batteryHealthValueUnavailable))
        XCTAssertNil(card.footnote)
    }

    func testChargeTimeStatesMapToLocalizedText() throws {
        let localization = localized()
        let cases: [(BatteryHealthSnapshot.ChargeTimeState, LocalizationKey)] = [
            (.calculating, .batteryStateCalculatingTimeToFull),
            (.charged, .batteryStateCharged),
            (.paused, .batteryHealthChargePaused),
            (.unavailable, .batteryDetailsUnavailable)
        ]
        for (chargeTime, key) in cases {
            let state = PanelDetailMapper.battery(
                status: battery(),
                details: details(health: BatteryHealthSnapshot(
                    designCapacityMAh: 8_579, chargeTime: chargeTime)),
                localization: localization)
            XCTAssertEqual(try XCTUnwrap(state.batteryHealth).chargeTimeValue,
                           localization.string(key), "\(chargeTime)")
        }
    }

    func testHealthAboveOneHundredPercentIsShownAsMeasured() throws {
        let localization = localized()
        let state = PanelDetailMapper.battery(
            status: battery(),
            details: details(health: BatteryHealthSnapshot(
                designCapacityMAh: 8_579, maximumCapacityMAh: 8_700,
                healthPercent: BatteryHealthParser.healthPercent(maximumMAh: 8_700, designMAh: 8_579))),
            localization: localization)
        XCTAssertEqual(try XCTUnwrap(state.batteryHealth).metrics[1].value, "101%")
    }

    func testHealthCardIsLocalizedAndNeverEmptyInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let localization = localized(language.rawValue)
            let state = PanelDetailMapper.battery(
                status: battery(),
                details: details(health: fullHealth),
                localization: localization)
            let card = try XCTUnwrap(state.batteryHealth, language.rawValue)
            XCTAssertFalse(card.title.isEmpty, language.rawValue)
            for metric in card.metrics {
                XCTAssertFalse(metric.label.isEmpty, "\(language.rawValue) \(metric.id)")
                XCTAssertFalse(metric.value.isEmpty, "\(language.rawValue) \(metric.id)")
            }
            XCTAssertFalse(card.chargeTimeLabel.isEmpty, language.rawValue)
            XCTAssertFalse(card.chargeTimeValue.isEmpty, language.rawValue)
        }
    }
}
