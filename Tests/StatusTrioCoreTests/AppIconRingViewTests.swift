import XCTest
@testable import StatusTrioCore

/// #315: the battery top marker is now chosen per power state — on battery,
/// charging, and connected-without-charging — instead of the older
/// percentage-toggle + charging-toggle + connected-choice trio.
@MainActor
final class AppIconRingViewTests: XCTestCase {
    func testMarkerOptionLists() {
        XCTAssertEqual(BatteryTopMarker.onBatteryOptions, [.percentage, .hidden])
        XCTAssertEqual(BatteryTopMarker.onPowerOptions, [.percentage, .bolt, .plug, .hidden])
        XCTAssertEqual(BatteryTopMarker.noBatteryOptions, [.plug, .bolt, .hidden])
    }

    func testOnBatteryStateUsesTheOnBatteryMarker() {
        let powerOff = battery(charging: false, onPower: false)
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                powerOff,
                options: options(onBattery: .percentage, charging: .bolt, connected: .plug)
            ),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                powerOff,
                options: options(onBattery: .hidden, charging: .bolt, connected: .plug)
            ),
            .empty
        )
    }

    func testChargingStateUsesTheChargingMarker() {
        let charging = battery(charging: true, onPower: true)
        XCTAssertEqual(gap(charging, charging: .bolt), .bolt)
        XCTAssertEqual(gap(charging, charging: .plug), .plug)
        XCTAssertEqual(gap(charging, charging: .percentage), .percentage)
        XCTAssertEqual(gap(charging, charging: .hidden), .empty)
    }

    func testConnectedStateUsesTheConnectedMarker() {
        let connected = battery(charging: false, onPower: true)
        XCTAssertEqual(gapConnected(connected, connected: .bolt), .bolt)
        XCTAssertEqual(gapConnected(connected, connected: .plug), .plug)
        XCTAssertEqual(gapConnected(connected, connected: .percentage), .percentage)
        XCTAssertEqual(gapConnected(connected, connected: .hidden), .empty)
    }

    func testBatteryLessMacFallsBackToPlugForAPercentageMarker() {
        let absent = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isCharged: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        func noBattery(_ marker: BatteryTopMarker) -> BatteryGapContent {
            StatusMappings.batteryGapContent(
                absent,
                options: BatteryIconOptions(noBatteryMarker: marker)
            )
        }
        XCTAssertEqual(noBattery(.bolt), .bolt)
        XCTAssertEqual(noBattery(.plug), .plug)
        XCTAssertEqual(noBattery(.percentage), .plug, "no battery never shows the placeholder percentage")
        XCTAssertEqual(noBattery(.hidden), .empty)
    }

    func testDefaultsKeepTheCurrentLook() {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.batteryOnBatteryMarker, .percentage)
        XCTAssertEqual(store.batteryChargingMarker, .bolt)
        XCTAssertEqual(store.batteryConnectedMarker, .plug)
        XCTAssertEqual(store.batteryNoBatteryMarker, .plug)
        XCTAssertEqual(store.batteryIconOptions, .standard)
    }

    func testLegacyTogglesMigrateToPerStateMarkers() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(false, forKey: SettingsStore.showsBatteryPercentageDefaultsKey)
        suite.defaults.set(false, forKey: SettingsStore.showsChargingIndicatorDefaultsKey)
        suite.defaults.set("bolt", forKey: SettingsStore.batteryConnectedIndicatorDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.batteryOnBatteryMarker, .hidden)
        XCTAssertEqual(store.batteryChargingMarker, .hidden)
        XCTAssertEqual(store.batteryConnectedMarker, .hidden)
        XCTAssertEqual(store.batteryNoBatteryMarker, .hidden)
    }

    func testChargingMarkerChoicePersists() {
        let suite = makeSuite()
        defer { clear(suite) }
        let first = SettingsStore(defaults: suite.defaults)
        first.batteryChargingMarker = .plug
        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.batteryChargingMarker, .plug)
    }

    // MARK: Helpers

    private func options(
        onBattery: BatteryTopMarker,
        charging: BatteryTopMarker,
        connected: BatteryTopMarker
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            onBatteryMarker: onBattery,
            chargingMarker: charging,
            connectedMarker: connected
        )
    }

    private func gap(_ battery: BatteryStatus, charging: BatteryTopMarker) -> BatteryGapContent {
        StatusMappings.batteryGapContent(
            battery,
            options: BatteryIconOptions(chargingMarker: charging)
        )
    }

    private func gapConnected(
        _ battery: BatteryStatus,
        connected: BatteryTopMarker
    ) -> BatteryGapContent {
        StatusMappings.batteryGapContent(
            battery,
            options: BatteryIconOptions(connectedMarker: connected)
        )
    }

    private func battery(charging: Bool, onPower: Bool) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 60,
            isPresent: true,
            isCharging: charging,
            isCharged: false,
            isLowPowerMode: false,
            isConnectedToPower: onPower
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "AppIconRingViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
