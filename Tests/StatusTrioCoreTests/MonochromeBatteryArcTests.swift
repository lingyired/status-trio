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

        // The preset is reversible: cancelling turns the state colouring back on
        // so the row's button is not a one-way switch.
        store.clearMonochromeBatteryArcPreset()
        XCTAssertTrue(store.usesBatteryStatusColors)
        XCTAssertFalse(store.isMonochromeBatteryArcActive)
        XCTAssertTrue(store.batteryIconOptions.usesStatusColors)
    }

    func testNoBatteryRingFollowsConnectedAndPowerModeColours() {
        // A battery-less ring follows the state palette: connected-to-power by
        // default (a Mac without a battery is always on AC), Low/High Power Mode
        // when those are on, and the foreground colour when monochrome is chosen.
        let connected = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot(.absent), audioIcon: nil),
            configuration: configuration(usesStatusColors: true)
        )
        XCTAssertEqual(connected.outerRing?.segments.first?.color, .powered)

        let highPower = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(.absent), audioIcon: nil, isHighPowerMode: true
            ),
            configuration: configuration(usesStatusColors: true)
        )
        XCTAssertEqual(highPower.outerRing?.segments.first?.color, .highPower)

        let monochrome = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot(.absent), audioIcon: nil),
            configuration: configuration(usesStatusColors: false)
        )
        XCTAssertEqual(monochrome.outerRing?.segments.first?.color, .primary)
    }

    @MainActor
    func testNoBatterySimulationOnlyRunsInDevelopmentBuilds() {
        let name = "NoBatterySimulationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        // A packaged release must ignore a stale value and scrub the key.
        defaults.set(true, forKey: SettingsStore.simulatesNoBatteryDefaultsKey)
        let release = SettingsStore(defaults: defaults, isDevelopmentBuild: false)
        XCTAssertFalse(release.simulatesNoBattery)
        XCTAssertFalse(release.isNoBatterySimulationActive)
        XCTAssertNil(defaults.object(forKey: SettingsStore.simulatesNoBatteryDefaultsKey))

        // A development build honours the toggle.
        defaults.set(true, forKey: SettingsStore.simulatesNoBatteryDefaultsKey)
        let dev = SettingsStore(defaults: defaults, isDevelopmentBuild: true)
        XCTAssertTrue(dev.simulatesNoBattery)
        XCTAssertTrue(dev.isNoBatterySimulationActive)
    }

    /// End-to-end through the real store: the ring colour the icon draws for a
    /// connected-to-power battery follows the state colours, and the monochrome
    /// preset turns it into the plain foreground colour.
    @MainActor
    func testStoreOptionsDriveConnectedColourAndMonochrome() {
        let name = "MonochromeStoreIntegration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        store.usesBatteryStatusColors = true
        let connected = battery(percentage: 80, connectedToPower: true)

        func ringColor() -> IconColorRole? {
            let config = IconPresentationConfiguration(
                battery: store.batteryIconOptions,
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            )
            let scene = IconPresentationMapper.scene(
                inputs: IconPresentationInputs(snapshot: snapshot(connected), audioIcon: nil),
                configuration: config
            )
            return scene.outerRing?.segments.first?.color
        }

        XCTAssertEqual(ringColor(), .powered, "connected to power uses the charging colour")

        store.applyMonochromeBatteryArcPreset()
        XCTAssertEqual(ringColor(), .primary, "monochrome preset forces the foreground colour")
    }
}
