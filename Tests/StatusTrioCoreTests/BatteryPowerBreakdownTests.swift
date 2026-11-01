import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

final class BatteryPowerBreakdownTests: XCTestCase {
    private let now = Date()

    private func sample(_ watts: Double, at offset: TimeInterval = 0) -> SystemPowerSample {
        SystemPowerSample(watts: watts, readAt: now.addingTimeInterval(offset))
    }

    private func usb(_ watts: Double, at offset: TimeInterval = 0) -> USBOutputSample {
        USBOutputSample(watts: watts, readAt: now.addingTimeInterval(offset), portCount: 1)
    }

    func testSplitsAdapterInputIntoMeasuredBranchesAndSystemResidual() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60, at: -1), charging: 10, discharge: nil,
            display: sample(8, at: -1), usb: usb(5, at: -1), now: now))
        XCTAssertEqual(split.source, .adapter)
        XCTAssertEqual(split.sourceWatts, 60)
        XCTAssertEqual(split.display?.watts, 8)
        XCTAssertEqual(split.usb?.watts, 5)
        // The residual carries the SoC and every unmeasured DC load.
        XCTAssertEqual(split.system.watts, 37, accuracy: 0.0001)
    }

    func testRejectsResidualThatCannotBeRounding() {
        // 20 W cannot pay for 4 W of charging, 8 W of backlight and 30 W of USB.
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(20), charging: 4, discharge: nil,
            display: sample(8), usb: usb(30), now: now))
    }

    func testTreatsSmallNegativeResidualAsRounding() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(43.6), charging: 0, discharge: nil,
            display: sample(8), usb: usb(36), now: now))
        XCTAssertEqual(split.system.watts, 0)
    }

    func testRequiresEveryBranchToShareOneWindow() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60, at: -120), charging: 0, discharge: nil,
            display: sample(8), usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60), charging: 0, discharge: nil,
            display: sample(8, at: -120), usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60), charging: 0, discharge: nil,
            display: sample(8), usb: usb(4, at: -120), now: now))
    }

    func testMissingAnchorsProduceNoSplit() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: nil, charging: 0, discharge: nil,
            display: sample(8), usb: nil, now: now))
        // An unread charge rail would silently inflate the residual.
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60), charging: nil, discharge: nil,
            display: sample(8), usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(0), charging: 0, discharge: nil,
            display: sample(8), usb: nil, now: now))
    }

    func testUnreadableDisplayStillLeavesACoherentSplit() throws {
        // Without PDBR the backlight disappears into the residual instead of
        // being invented from the system total.
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(50), charging: 0, discharge: nil,
            display: nil, usb: nil, now: now))
        XCTAssertNil(split.display)
        XCTAssertEqual(split.system.watts, 50, accuracy: 0.0001)
    }

    func testUsesBatteryWhenTheAdapterIsNotSupplying() throws {
        // With the charger effectively idle the pack runs the Mac; the flow
        // has to start at the battery instead of disappearing.
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(0.17, at: -1), charging: 0, discharge: 54,
            display: sample(3.09, at: -1), usb: usb(2.45, at: -1), now: now))
        XCTAssertEqual(split.source, .battery)
        XCTAssertEqual(split.sourceWatts, 54, accuracy: 0.0001)
        XCTAssertEqual(split.system.watts, 48.46, accuracy: 0.0001)
    }

    func testPrefersTheAdapterWhileItSuppliesPower() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(60, at: -1), charging: 0, discharge: 12,
            display: sample(8, at: -1), usb: nil, now: now))
        XCTAssertEqual(split.source, .adapter)
        XCTAssertEqual(split.sourceWatts, 60, accuracy: 0.0001)
    }

    func testBatteryResidualThatCannotBeRoundingProducesNoSplit() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(0.17), charging: 0, discharge: 5,
            display: sample(8), usb: usb(4), now: now))
    }

    func testNoSplitWhenNeitherTheAdapterNorTheBatterySuppliesPower() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            adapterInput: sample(0.17), charging: 0, discharge: 0.4,
            display: sample(3), usb: nil, now: now))
    }

    func testUSBOutputReaderSumsMeasuredPortsAndIgnoresNegotiatedBudget() {
        let registry: [String: Any] = ["PowerOutDetails": [
            ["PortIndex": 1, "Watts": 7_000],
            // `PDPowermW` is the negotiated PD contract, not a measured output:
            // on this Mac a 5V × 3A port reports 15000 mW while `Watts` says 2461.
            ["PortIndex": 2, "PDPowermW": 5_000]
        ]]
        XCTAssertEqual(USBOutputReader.parse(registry: registry)?.watts, 7)
        XCTAssertEqual(USBOutputReader.parse(registry: registry)?.portCount, 1)
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["PortIndex": 2, "PDPowermW": 5_000]]]),
                     "a contract value alone is not a measured output")
        XCTAssertNil(USBOutputReader.parse(registry: [:]), "no key means nothing is attached")
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": []]))
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["PortIndex": 1]]]),
                     "a port without a power value is not a zero-watt output")
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["Watts": 900_000]]]))
    }
}

@MainActor
final class BatteryPowerBreakdownPresentationTests: XCTestCase {
    private func localization() throws -> (Localization, UserDefaults, String) {
        let suite = "BatteryPowerBreakdownPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (Localization(defaults: defaults, preferredLanguages: ["en"]), defaults, suite)
    }

    private func details(breakdown: BatteryPowerBreakdown?) -> BatteryDetails {
        let now = Date()
        return BatteryDetails(
            power: BatteryPowerSample(volts: 12, amps: 0.5, updatedAt: now),
            systemPower: SystemPowerSample(watts: 25, readAt: now),
            inputPower: SystemPowerSample(watts: 60, readAt: now),
            breakdown: breakdown
        )
    }

    private func breakdown() -> BatteryPowerBreakdown {
        let now = Date()
        let input = SystemPowerSample(watts: 60, readAt: now)
        return BatteryPowerBreakdown(
            source: .adapter,
            sourceWatts: 60,
            display: .init(watts: 8, readAt: now),
            usb: .init(watts: 5, readAt: now),
            system: .init(watts: 41, readAt: now),
            readAt: now
        )
    }

    func testSplitReplacesTheSystemNodeWithFourBranches() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: breakdown()),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        let flow = try XCTUnwrap(state.powerFlow)
        XCTAssertEqual(flow.destinations.map(\.kind), [.charging, .display, .usb, .system])
        XCTAssertEqual(flow.destinations.map(\.watts), [6, 8, 5, 41])
        XCTAssertEqual(flow.input?.watts, 60)
        // Branch widths share one scale, bounded by the measured sum, not the
        // lagging system total.
        XCTAssertEqual(try XCTUnwrap(flow.flowFraction(for: flow.destinations[3])), 41.0 / 60.0, accuracy: 0.0001)
    }

    func testBatterySourceNamesTheLeftNodeAndDropsTheChargingBranch() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let now = Date()
        let onBattery = BatteryPowerBreakdown(
            source: .battery,
            sourceWatts: 40,
            display: .init(watts: 3, readAt: now),
            usb: .init(watts: 2, readAt: now),
            system: .init(watts: 35, readAt: now),
            readAt: now)
        let status = BatteryStatus(rawPercentage: 60, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: onBattery),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        let flow = try XCTUnwrap(state.powerFlow)
        XCTAssertEqual(flow.input?.label, "Battery")
        XCTAssertEqual(flow.input?.watts, 40)
        XCTAssertEqual(flow.destinations.map(\.kind), [.display, .usb, .system])
    }

    func testSystemBranchCarriesTheLongerNameAsHelp() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: breakdown()),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        let system = try XCTUnwrap(state.powerFlow?.destinations.first { $0.kind == .system })
        XCTAssertEqual(system.label, "System power")
        XCTAssertEqual(system.help, localization.string(.batteryPowerSystemHelp))
    }

    func testSwitchOffOrMissingSplitKeepsTheLegacyDiagram() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)

        let switchedOff = PanelDetailMapper.battery(status: status,
            details: details(breakdown: breakdown()), localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: false))
        XCTAssertEqual(switchedOff.powerFlow?.destinations.map(\.kind), [.charging, .system])
        XCTAssertEqual(switchedOff.powerFlow?.system?.watts, 25)

        let unavailable = PanelDetailMapper.battery(status: status,
            details: details(breakdown: nil), localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        XCTAssertEqual(unavailable.powerFlow?.destinations.map(\.kind), [.charging, .system])

        // The lagging system total must not be dressed up as a measured branch.
        XCTAssertEqual(unavailable.powerFlow?.destinations.map(\.kind), [.charging, .system])
    }

    func testPowerFlowSwitchIsPersisted() throws {
        let (_, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showsBatteryPowerFlow)
        store.showsBatteryPowerFlow = false
        XCTAssertFalse(SettingsStore(defaults: defaults).showsBatteryPowerFlow)
    }
}

@MainActor
final class BatteryPowerFlowLayoutTests: XCTestCase {
    /// Four branches must stay inside a compact column: tall enough to separate
    /// the nodes, short enough that the page below still fits the popover.
    func testFourBranchDiagramUsesCompactHeight() {
        let metrics = (0..<4).map { index in
            BatteryPowerFlowState.Metric(label: "L\(index)", value: "\(index) W",
                                        watts: [41.21, 8.07, 4.5, 2.72][index],
                                        kind: [BatteryPowerFlowState.Kind.charging, .display, .usb, .system][index])
        }
        let state = BatteryPowerFlowState(
            input: .init(label: "in", value: "67 W", watts: 67),
            destinations: metrics)
        let hosting = NSHostingView(rootView: BatteryPowerFlowView(state: state).frame(width: 302))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.fittingSize.height, 140, accuracy: 0.5)
    }
}
