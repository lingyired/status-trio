import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BatteryDischargePresentationTests {
    @Test(arguments: [false, true], [false, true])
    func dischargeRemainsVisibleWhenSystemFlowIsHidden(showsInput: Bool, showsCharging: Bool) throws {
        let suite = "BatteryDischargePresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)
        let details = BatteryDetails(power: BatteryPowerSample(volts: 12, amps: -1, updatedAt: Date()),
            powerAvailability: .available)

        let state = PanelDetailMapper.battery(status: status, details: details,
            localization: localization, powerOptions: BatteryPowerDisplayOptions(
                showsInput: showsInput, showsCharging: showsCharging, showsSystem: false))

        let discharge = try #require(state.rows.first { $0.id == LocalizationKey.batteryDetailsDischarging.rawValue })
        #expect(discharge.value == "12.0 W")
        #expect(state.rows.contains { $0.id == LocalizationKey.batteryDetailsSampled.rawValue })
        #expect(state.rows.contains { $0.id == LocalizationKey.batteryDetailsSystemPower.rawValue } == false)
        #expect(state.powerFlow == nil)
    }

    @Test(arguments: [false, true])
    func connectedSystemReadingFollowsItsSelection(showsSystem: Bool) throws {
        let suite = "BatteryDischargePresentationTests.Connected.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: true)
        let details = BatteryDetails(systemPower: SystemPowerSample(watts: 25.5, readAt: Date()))

        let state = PanelDetailMapper.battery(status: status, details: details,
            localization: localization, powerOptions: BatteryPowerDisplayOptions(showsSystem: showsSystem))

        #expect(state.rows.contains { $0.id == LocalizationKey.batteryDetailsSystemPower.rawValue } == showsSystem)
        #expect(state.rows.contains { $0.id == LocalizationKey.batteryDetailsSystemReadAt.rawValue } == showsSystem)
        #expect(state.rows.contains { $0.id == LocalizationKey.batteryDetailsDischarging.rawValue } == false)
    }
}
