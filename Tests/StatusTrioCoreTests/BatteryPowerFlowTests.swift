import AppKit
import Foundation
import SwiftUI
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
    func testPowerFlowSwitchDefaultsOnAndPersists() throws {
        let suite = "BatteryPowerFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.showsBatteryPowerFlow)
        XCTAssertFalse(settings.showsHighEnergyApps)
        settings.showsBatteryPowerFlow = false
        settings.showsHighEnergyApps = true
        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.showsBatteryPowerFlow)
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

    func testConnectedCardsKeepOriginalRoundedCorners() throws {
        func metric(_ watts: Double, _ kind: BatteryPowerFlowState.Kind, _ label: String)
            -> BatteryPowerFlowState.Metric {
            .init(label: label, value: "\(Int(watts))W", watts: watts, kind: kind)
        }
        // A tinted source (discharging pack) so the card fill is visible against
        // the white capture instead of the near-white silver adapter surface.
        let state = BatteryPowerFlowState(
            input: metric(100, .batterySource, "Battery"),
            destinations: [metric(20, .system, "System")]
        )
        let view = BatteryPowerFlowView(state: state)
            .frame(width: 330, height: 84)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 84)
        hosting.layoutSubtreeIfNeeded()
        let probe = try XCTUnwrap(SummaryActionAlignmentProbe(hosting))

        func isInk(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let px = Int((x * probe.scale).rounded())
            let py = Int((y * probe.scale).rounded())
            guard let color = probe.bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB)
            else { return false }
            let luminance = 0.299 * color.redComponent
                + 0.587 * color.greenComponent
                + 0.114 * color.blueComponent
            return luminance < 0.98
        }

        // #282: the 62x84 input card keeps its original rounded outline on all
        // four corners. The ribbon instead runs a few points underneath the card,
        // which is painted afterwards and covers the overlap. The two vertical
        // extremes are sampled so the assertion does not depend on the bitmap's
        // y origin.
        XCTAssertFalse(isInk(60, 2), "top-right corner must stay rounded")
        XCTAssertFalse(isInk(60, 82), "bottom-right corner must stay rounded")
        XCTAssertFalse(isInk(2, 2), "top-left corner must stay rounded")
        XCTAssertFalse(isInk(2, 82), "bottom-left corner must stay rounded")
        XCTAssertTrue(isInk(60, 42), "the card's straight right edge still reaches the ribbon")
        XCTAssertEqual(
            PowerFlowCardGeometry.ribbonStartX(inputCardRight: 62), 56,
            "the ribbon starts inside the input card"
        )
        XCTAssertEqual(
            PowerFlowCardGeometry.ribbonEndX(branchCardLeft: 236), 242,
            "the ribbon continues inside the branch card"
        )
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
                        showsCharging: charging, showsSystem: system, showsBreakdown: false)
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
