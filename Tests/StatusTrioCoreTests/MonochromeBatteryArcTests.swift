import XCTest
@testable import StatusTrioCore

/// Issue #309: the "Monochrome battery arc" preset. The arc should draw in the
/// label colour in every battery state, and the preset must only flip the state
/// colouring off — the top marker, centre icon and bottom indicator keep their
/// own settings.
final class MonochromeBatteryArcTests: XCTestCase {
    private func battery(
        percentage: Int,
        charging: Bool = false,
        lowPower: Bool = false,
        connectedToPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: lowPower,
            isConnectedToPower: connectedToPower
        )
    }

    private func snapshot(_ battery: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(
            battery: battery,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .wifi,
            volume: .placeholder
        )
    }

    private func options(usesStatusColors: Bool) -> BatteryIconOptions {
        BatteryIconOptions(
            usesStatusColors: usesStatusColors,
            criticalThreshold: 20,
            connectedIndicator: .plug
        )
    }

    private func configuration(usesStatusColors: Bool) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: options(usesStatusColors: usesStatusColors),
            connection: .standard,
            volume: .standard,
            bluetooth: .standard
        )
    }

    func testMonochromeArcUsesForegroundInEveryBatteryState() {
        let config = configuration(usesStatusColors: false)
        let states = [
            battery(percentage: 80, charging: true, connectedToPower: true),
            battery(percentage: 10),
            battery(percentage: 80, lowPower: true),
        ]

        for state in states {
            let scene = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: snapshot(state), audioIcon: nil),
                configuration: config
            )
            XCTAssertEqual(
                scene.outerRing?.segments.first?.color,
                .primary,
                "monochrome arc must draw with the label colour for \(state)"
            )
        }
    }

    func testStatusColoursStillTintWhenEnabled() {
        // Guards the other side of the switch: with state colouring on, a charging
        // battery is powered-coloured, so the monochrome test above is meaningful.
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery(percentage: 80, charging: true, connectedToPower: true)),
                audioIcon: nil
            ),
            configuration: configuration(usesStatusColors: true)
        )
        XCTAssertEqual(scene.outerRing?.segments.first?.color, .powered)
    }

    func testMonochromeChargingDoesNotTintTheBolt() {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery(percentage: 80, charging: true, connectedToPower: true)),
                audioIcon: nil
            ),
            configuration: configuration(usesStatusColors: false)
        )
        XCTAssertEqual(scene.outerRing?.effect?.tintsAccessory, false)
    }

    @MainActor
    func testPresetOnlyTurnsOffStatusColours() {
        let name = "MonochromeBatteryArcTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        store.usesBatteryStatusColors = true
        store.showsChargingIndicator = true
        store.batteryConnectedIndicator = .plug
        store.showsBatteryPercentage = true

        store.applyMonochromeBatteryArcPreset()

        XCTAssertFalse(store.usesBatteryStatusColors)
        XCTAssertTrue(store.isMonochromeBatteryArcActive)
        // Everything else the user configured is untouched.
        XCTAssertTrue(store.showsChargingIndicator)
        XCTAssertEqual(store.batteryConnectedIndicator, .plug)
        XCTAssertTrue(store.showsBatteryPercentage)
        XCTAssertFalse(store.batteryIconOptions.usesStatusColors)
    }
}
