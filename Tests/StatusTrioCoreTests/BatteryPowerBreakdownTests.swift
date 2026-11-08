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
        USBOutputSample(watts: watts, readAt: now.addingTimeInterval(offset), ports: [USBPortOutput(channel: 1, watts: watts)])
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
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["PortIndex": 2, "Watts": 143]]]),
                     "a registry port below the idle floor is quiescent current, not an output")
    }

    func testIdleAdapterKeepsItsPortOnABatterySourceSplit() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            adapterInput: sample(0.17), charging: 0, discharge: 12,
            display: sample(3), usb: nil, inputPortType: "MagSafe 3", now: now))
        XCTAssertEqual(split.source, .battery)
        XCTAssertEqual(split.inputPortType, "MagSafe 3")
    }

    func testLivePortRailsReplaceAFrozenRegistryReading() {
        let frozen: [String: Any] = ["PowerOutDetails": [["PortIndex": 1, "Watts": 9_000]]]
        let readAt = Date(timeIntervalSince1970: 1_000)
        let live = USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 1, watts: 4.208), PortRail(channel: 2, watts: 0.14), PortRail(channel: 3, watts: 0.07)], readAt: readAt), registry: frozen)
        XCTAssertEqual(live?.watts ?? -1, 4.208, accuracy: 0.0001)
        XCTAssertEqual(live?.portCount, 1)
        XCTAssertEqual(live?.readAt, readAt, "a measured rail keeps the SMC read time")
        XCTAssertNil(USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 1, watts: 0.05), PortRail(channel: 2, watts: 0.14)], readAt: readAt), registry: frozen),
            "an answered idle rail must not fall back to a frozen registry value")
        XCTAssertEqual(USBOutputReader.resolve(portRails: .unavailable, registry: [
            "PowerOutDetails": [["PortIndex": 1, "Watts": 7_000]]
        ])?.watts, 7)
    }

    func testMeasuredRailStalenessUsesSMCReadTimeNotObservationTime() {
        // A refresh whose SMC read stalled: the measurement is 120 s old, but a
        // caller stamping `now` would call it fresh. It must be rejected.
        let readAt = Date(timeIntervalSince1970: 1_000)
        let observedAt = readAt.addingTimeInterval(120)
        let sample = USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 1, watts: 4.2)], readAt: readAt), registry: [:], now: observedAt)
        XCTAssertEqual(sample?.readAt, readAt)
        XCTAssertEqual(sample?.isFresh(at: observedAt), false,
                       "a rail read 120 s ago must not pass the freshness window")
    }
}

final class USBPortOutputTests: XCTestCase {
    private let readAt = Date(timeIntervalSince1970: 1_000)

    /// Mac16,1 as measured: Watch charger on @1, display adapter on @2 (with a
    /// Billboard device), the Fanxiang SSD on @4, adapter on MagSafe.
    private func topology(input: USBPortTopology.PortNode? = .init(
        portDescription: "Port-MagSafe 3@1", portNumber: 1, typeDescription: "MagSafe 3")) -> USBPortTopology {
        let ports: [USBPortTopology.PortNode] = [
            .init(portDescription: "Port-USB-C@4", portNumber: 4, typeDescription: "USB-C"),
            .init(portDescription: "Port-USB-C@1", portNumber: 1, typeDescription: "USB-C"),
            .init(portDescription: "Port-USB-C@2", portNumber: 2, typeDescription: "USB-C")
        ]
        let devices: [USBPortTopology.DeviceNode] = [
            .init(portDescription: "Port-USB-C@1", name: "Apple Watch Magnetic Charging Cable",
                  deviceClass: 0, locationID: 0x0010_0000),
            .init(portDescription: "Port-USB-C@2", name: "Generic Billboard Device",
                  deviceClass: 0x11, locationID: 0x0110_0000),
            .init(portDescription: "Port-USB-C@4", name: "RB", deviceClass: 0, locationID: 0x0320_0000)
        ]
        return USBPortTopology.make(usbCPorts: ports, devices: devices, inputPort: input)
    }

    func testChannelsFollowUSBCPortNumberOrder() {
        let topology = topology()
        XCTAssertEqual(topology.ports.map(\.portDescription), ["Port-USB-C@1", "Port-USB-C@2", "Port-USB-C@4"])
        XCTAssertEqual(topology.ports.map(\.channel), [1, 2, 3])
        XCTAssertEqual(topology.name(forChannel: 1), "Apple Watch Magnetic Charging Cable")
        XCTAssertNil(topology.name(forChannel: 2), "a Billboard device is plumbing, not the accessory")
        XCTAssertEqual(topology.name(forChannel: 3), "RB")
        XCTAssertNil(topology.name(forChannel: 4))
        XCTAssertEqual(topology.inputPortType, "MagSafe 3")
        XCTAssertNil(topology.inputChannel, "MagSafe is not an output channel")
    }

    func testHubChildrenCollapseIntoOneNameWithACount() {
        let topology = USBPortTopology.make(
            usbCPorts: [.init(portDescription: "Port-USB-C@1", portNumber: 1, typeDescription: "USB-C")],
            devices: [
                .init(portDescription: "Port-USB-C@1", name: "USB3.1 Hub", deviceClass: 9, locationID: 1),
                .init(portDescription: "Port-USB-C@1", name: "Portable SSD", deviceClass: 0, locationID: 2),
                .init(portDescription: "Port-USB-C@1", name: "Keyboard", deviceClass: 0, locationID: 3)
            ],
            inputPort: nil)
        XCTAssertEqual(topology.name(forChannel: 1), "Portable SSD +1")
        XCTAssertNil(topology.inputPortType)
    }

    func testRailsKeepTheirChannelAndPickUpAccessoryNames() throws {
        let sample = try XCTUnwrap(USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 1, watts: 5.12), PortRail(channel: 2, watts: 0.13),
                                         PortRail(channel: 3, watts: 0.85), PortRail(channel: 4, watts: 0)],
                                 readAt: readAt),
            registry: [:], topology: topology()))
        XCTAssertEqual(sample.ports, [
            USBPortOutput(channel: 1, watts: 5.12, name: "Apple Watch Magnetic Charging Cable"),
            USBPortOutput(channel: 3, watts: 0.85, name: "RB")
        ], "idle rails stay hidden; each live rail keeps its own reading")
        XCTAssertEqual(sample.watts, 5.97, accuracy: 0.0001)
        XCTAssertEqual(sample.readAt, readAt)
    }

    func testTheChargingUSBCPortIsNotAnOutput() throws {
        let charger = USBPortTopology.PortNode(portDescription: "Port-USB-C@4", portNumber: 4, typeDescription: "USB-C")
        let topology = topology(input: charger)
        XCTAssertEqual(topology.inputChannel, 3)
        let sample = try XCTUnwrap(USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 1, watts: 5), PortRail(channel: 3, watts: 9)],
                                 readAt: readAt),
            registry: [:], topology: topology))
        XCTAssertEqual(sample.ports.map(\.channel), [1])
        XCTAssertEqual(sample.watts, 5)
        XCTAssertNil(USBOutputReader.resolve(
            portRails: .measured(rails: [PortRail(channel: 3, watts: 9)], readAt: readAt),
            registry: [:], topology: topology), "only the sink port answered, so nothing is output")
    }

    func testRegistryFallbackUsesPortIndexAsTheChannel() throws {
        let sample = try XCTUnwrap(USBOutputReader.resolve(portRails: .unavailable, registry: [
            "PowerOutDetails": [["PortIndex": 3, "Watts": 850], ["PortIndex": 1, "Watts": 4_762]]
        ], topology: topology()))
        XCTAssertEqual(sample.ports.map(\.channel), [3, 1])
        XCTAssertEqual(sample.ports.map(\.name), ["RB", "Apple Watch Magnetic Charging Cable"])
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

    func testEachPoweredPortGetsItsOwnBranchAndNamedRow() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        var split = breakdown()
        split.usbPorts = [
            USBPortOutput(channel: 1, watts: 4.15, name: "Apple Watch Magnetic Charging Cable"),
            USBPortOutput(channel: 3, watts: 0.85, name: "RB"),
            USBPortOutput(channel: 2, watts: 0.4)
        ]
        split.inputPortType = "MagSafe 3"
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: split),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        let flow = try XCTUnwrap(state.powerFlow)
        XCTAssertEqual(flow.destinations.map(\.kind), [.charging, .display, .usb, .usb, .usb, .system])
        let usb = flow.destinations.filter { $0.kind == .usb }
        XCTAssertEqual(usb.map(\.watts), [4.15, 0.85, 0.4])
        XCTAssertEqual(usb.map(\.label), ["Apple Watch Magnetic Charging Cable", "RB", "USB out"])
        XCTAssertEqual(usb.map(\.help), ["USB out · Apple Watch Magnetic Charging Cable", "USB out · RB", "USB out"])
        XCTAssertEqual(flow.input?.detail, "MagSafe 3")

        let rows = state.rows.map { "\($0.label)=\($0.value)" }
        XCTAssertTrue(rows.contains("Charging port=MagSafe 3"), "\(rows)")
        XCTAssertTrue(rows.contains("USB out · RB=0.85 W"), "\(rows)")
        XCTAssertTrue(rows.contains("USB out · Apple Watch Magnetic Charging Cable=4.15 W"), "\(rows)")
        XCTAssertEqual(Set(state.rows.map(\.id)).count, state.rows.count, "row ids stay unique per port")
    }

    func testConnectedIdleAdapterStillListsItsChargingPort() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let now = Date()
        var onBattery = BatteryPowerBreakdown(
            source: .battery, sourceWatts: 12,
            display: .init(watts: 3, readAt: now), usb: nil,
            system: .init(watts: 9, readAt: now), readAt: now)
        onBattery.inputPortType = "MagSafe 3"
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: onBattery),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        XCTAssertTrue(state.rows.contains { $0.label == "Charging port" && $0.value == "MagSafe 3" })
        XCTAssertNil(state.powerFlow?.input?.detail, "the left node is the battery, not the adapter port")
    }

    func testSplitWithoutPortDataKeepsTheSummedUSBNode() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: breakdown()),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        XCTAssertEqual(state.powerFlow?.destinations.filter { $0.kind == .usb }.map(\.label), ["USB out"])
        XCTAssertNil(state.powerFlow?.input?.detail)
        XCTAssertFalse(state.rows.contains { $0.label == "Charging port" })
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

    /// A two-branch diagram must also size each card by its share: a tiny
    /// display branch can no longer occupy a full fixed-height card next to the
    /// system load. The old fixed two-card column was 132 pt tall.
    func testTwoBranchDiagramSizesCardsByShare() {
        let metrics = [
            BatteryPowerFlowState.Metric(label: "显示器", value: "0.08 W", watts: 0.08, kind: .display),
            BatteryPowerFlowState.Metric(label: "系统功耗", value: "28.03 W", watts: 28.03, kind: .system)
        ]
        let state = BatteryPowerFlowState(
            input: .init(label: "充电器输入", value: "28.11 W", watts: 28.11),
            destinations: metrics)
        let hosting = NSHostingView(rootView: BatteryPowerFlowView(state: state).frame(width: 302))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertLessThan(hosting.fittingSize.height, 120,
                          "A 0.3% branch must shrink instead of holding a full fixed card")
        XCTAssertGreaterThan(hosting.fittingSize.height, 90)
    }
}
