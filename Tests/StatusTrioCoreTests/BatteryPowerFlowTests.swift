import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryPowerFlowTests: XCTestCase {
    func testRibbonWidthsStayQuantitativeWhenAnotherDestinationIsHidden() throws {
        func metric(_ watts: Double?) -> BatteryPowerFlowState.Metric {
            .init(label: "", value: "", watts: watts)
        }
        let one = BatteryPowerFlowState(input: metric(100), battery: metric(1), system: nil)
        let fifty = BatteryPowerFlowState(input: metric(100), battery: metric(50), system: nil)
        XCTAssertEqual(try XCTUnwrap(one.batteryFlowFraction), 0.01, accuracy: 0.000001)
        XCTAssertEqual(fifty.batteryFlowFraction, 0.5)
        XCTAssertEqual(BatteryPowerFlowState(input: metric(100), battery: metric(0), system: metric(25)).batteryFlowFraction, 0)
        XCTAssertNil(BatteryPowerFlowState(input: metric(nil), battery: metric(50), system: nil).batteryFlowFraction)
    }
    func testSettingsKeepIndependentSelectionsAcrossLaunches() throws {
        let suite = "BatteryPowerFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.showsChargerInputPower)
        XCTAssertTrue(settings.showsBatteryChargingPower)
        XCTAssertTrue(settings.showsSystemPower)
        XCTAssertFalse(settings.showsHighEnergyApps)
        settings.showsChargerInputPower = true
        settings.showsBatteryChargingPower = false
        settings.showsSystemPower = false
        settings.showsHighEnergyApps = true
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.showsChargerInputPower)
        XCTAssertFalse(restored.showsBatteryChargingPower)
        XCTAssertFalse(restored.showsSystemPower)
        XCTAssertTrue(restored.showsHighEnergyApps)
    }

    func testHighEnergyAppsSettingsExplainBackgroundSamplingAndExposeItsInterval() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("if store.showsHighEnergyApps"))
        XCTAssertTrue(source.contains("title: localization.string(.settingsBatteryEnergyRefreshInterval)"))
        XCTAssertTrue(source.contains(".settingsBatteryEnergyRefreshIntervalDescription"))
        XCTAssertTrue(source.contains("in: SettingsStore.highEnergyAppsRefreshIntervalRange"))
    }

    func testActualInputNeverUsesAdapterRatingAndRejectsStaleOrDisconnectedTelemetry() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let connected = BatteryPowerState(BatteryStatus(rawPercentage: 80, isPresent: true,
            isCharging: true, isLowPowerMode: false, isConnectedToPower: true))
        var values: [String: Any] = ["ExternalConnected": true, "IsCharging": true,
            "Voltage": 12000, "Amperage": 2000, "UpdateTime": now.timeIntervalSince1970,
            "PowerTelemetryData": ["SystemPowerIn": 67000]]
        func parse(_ state: BatteryPowerState = connected) -> BatteryDetails {
            BatteryDetailsReader.parse(registry: values, adapterWatts: 140,
                remainingSeconds: -1, state: state, now: now)
        }
        XCTAssertEqual(parse().inputPower?.watts, 67)
        values["PowerTelemetryData"] = [:]
        XCTAssertNil(parse().inputPower, "140 W adapter capability is not live input")
        for invalid: Any in [true, -1, Double.nan, Double.infinity, 1_000_001] {
            values["PowerTelemetryData"] = ["SystemPowerIn": invalid]
            XCTAssertNil(parse().inputPower)
        }
        values["PowerTelemetryData"] = ["SystemPowerIn": 67000]
        values["UpdateTime"] = now.addingTimeInterval(-91).timeIntervalSince1970
        XCTAssertNil(parse().inputPower)
        values["UpdateTime"] = now.timeIntervalSince1970
        let unplugged = BatteryPowerState(BatteryStatus(rawPercentage: 80, isPresent: true,
            isCharging: false, isLowPowerMode: false, isConnectedToPower: false))
        XCTAssertNil(parse(unplugged).inputPower)
    }

    func testPowerFlowHonorsEachSwitchAndPreservesIndependentMeasuredValues() throws {
        let suite = "BatteryPowerFlowTests.Mapper.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let details = BatteryDetails(power: BatteryPowerSample(volts: 12, amps: 3.5, updatedAt: Date()),
            systemPower: SystemPowerSample(watts: 25.59, readAt: Date()),
            inputPower: SystemPowerSample(watts: 67, readAt: Date()))
        for input in [false, true] {
            for charging in [false, true] {
                for system in [false, true] {
                    let options = BatteryPowerDisplayOptions(showsInput: input,
                        showsCharging: charging, showsSystem: system)
                    let state = PanelDetailMapper.battery(status: status, details: details,
                        localization: localization, powerOptions: options)
                    XCTAssertEqual(state.powerFlow?.input?.watts, input ? 67 : nil)
                    XCTAssertEqual(state.powerFlow?.battery?.watts, charging ? 42 : nil)
                    XCTAssertEqual(state.powerFlow?.system?.watts, system ? 25.59 : nil)
                    XCTAssertEqual(state.powerFlow == nil, !input && !charging && !system)
                }
            }
        }
    }
}
