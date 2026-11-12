import XCTest
@testable import StatusTrioCore

/// Bottom-indicator data source: storage, mapper output for every source and
/// style, the scene-level volume classifier, and the guarantee that the source
/// stays independent from the stored display style.
@MainActor
final class BottomIndicatorSourceTests: XCTestCase {
    // MARK: Fixtures

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.BottomIndicatorSource.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return (defaults, name)
    }

    private func bluetoothDevice() -> AudioOutputDevice {
        AudioOutputDevice(
            id: 1,
            name: "AirPods",
            uid: "bottom-indicator.test.bluetooth",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth
        )
    }

    private func snapshot(
        battery: BatteryStatus = BatteryStatus(
            rawPercentage: 68,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ),
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -60),
        connection: NetworkConnection = .wifi,
        volume: VolumeStatus = VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Output")
    ) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }

    private func scene(
        source: BottomIndicatorSource,
        style: VolumeDisplayStyle = .dots,
        snapshot: StatusSnapshot? = nil,
        bluetoothOptions: BluetoothAudioIconOptions = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot ?? self.snapshot(),
                audioIcon: nil,
                bottomIndicatorSource: source
            ),
            configuration: IconPresentationConfiguration(
                battery: .standard,
                connection: .standard,
                volume: VolumeIconOptions(displayStyle: style),
                bluetooth: bluetoothOptions
            )
        )
    }

    // MARK: Storage

    func testDefaultsToVolumeAndPersists() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.bottomIndicatorSource, .volume)

        store.bottomIndicatorSource = .wifi
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).bottomIndicatorSource,
            .wifi,
            "The selected source must survive a relaunch."
        )
    }

    func testUnknownStoredValueFallsBackToVolume() {
        let suite = makeSuite()
        suite.defaults.set("not-a-source", forKey: SettingsStore.bottomIndicatorSourceDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).bottomIndicatorSource, .volume)
    }

    func testSourceAndStyleAreStoredIndependently() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.volumeDisplayStyle = .arc
        store.bottomIndicatorSource = .battery

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.volumeDisplayStyle, .arc)
        XCTAssertEqual(reopened.bottomIndicatorSource, .battery)
    }

    func testRuntimeOptionsCarryTheSource() {
        let suite = makeSuite()
        let store = SettingsStore(defaults: suite.defaults)
        store.bottomIndicatorSource = .battery
        XCTAssertEqual(store.iconRuntimePresentationOptions.bottomIndicatorSource, .battery)
    }

    func testEnumCapabilities() {
        XCTAssertEqual(BottomIndicatorSource.default, .volume)
        XCTAssertTrue(BottomIndicatorSource.volume.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.wifi.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.battery.supportsBluetoothVolumeColor)
        XCTAssertFalse(BottomIndicatorSource.hidden.showsStyleOptions)
        XCTAssertTrue(BottomIndicatorSource.volume.showsStyleOptions)
        XCTAssertEqual(BottomIndicatorSource.allCases.map(\.rawValue), ["volume", "wifi", "battery", "hidden"])
    }

    // MARK: Volume regression

    func testVolumeSourceKeepsExistingDotsAndArcBehaviour() {
        let dots = scene(source: .volume, style: .dots).footer
        guard case let .dots(d)? = dots else { return XCTFail("expected dots") }
        XCTAssertEqual(d.count, 4)
        XCTAssertEqual(d.activeCount, 3, "scalar 0.6 is three steps, unchanged from before")

        let arc = scene(source: .volume, style: .arc).footer
        guard case let .arc(a)? = arc else { return XCTFail("expected arc") }
        XCTAssertEqual(a.progress, 0.6, accuracy: 0.0001)
    }

    func testVolumeSourceKeepsBluetoothColour() {
        let device = bluetoothDevice()
        let volume = VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: device.name,
            currentDevice: device
        )
        let options = BluetoothAudioIconOptions(usesVolumeColor: true)
        let footer = scene(source: .volume, style: .dots, snapshot: snapshot(volume: volume),
                           bluetoothOptions: options).footer
        guard case let .dots(d)? = footer else { return XCTFail("expected dots") }
        XCTAssertEqual(d.color, .bluetooth)
    }

    // MARK: Wi-Fi

    func testWiFiBarsMapToDots() {
        let cases: [(Int, Int)] = [(-60, 3), (-75, 2), (-85, 1), (-95, 0)]
        for (rssi, bars) in cases {
            let footer = scene(source: .wifi, style: .dots,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: rssi))).footer
            guard case let .dots(d)? = footer else { return XCTFail("expected dots at \(rssi)") }
            XCTAssertEqual(d.count, 4)
            XCTAssertEqual(d.activeCount, bars, "rssi \(rssi) should be \(bars) bars")
        }
    }

    func testWiFiBarsMapToArcProgress() {
        for (rssi, bars) in [(-60, 3), (-75, 2), (-85, 1), (-95, 0)] {
            let footer = scene(source: .wifi, style: .arc,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: rssi))).footer
            guard case let .arc(a)? = footer else { return XCTFail("expected arc at \(rssi)") }
            XCTAssertEqual(a.progress, Double(bars) / 3.0, accuracy: 0.0001)
        }
    }

    func testWiFiUnknownOrUnavailableHidesFooter() {
        let states: [WiFiStatus] = [
            WiFiStatus(state: .connected, rssi: nil),   // unknown / invalid reading
            WiFiStatus(state: .connected, rssi: 12),    // invalid positive value
            WiFiStatus(state: .notAssociated, rssi: nil),
            WiFiStatus(state: .off, rssi: nil),
            WiFiStatus(state: .unavailable, rssi: nil)
        ]
        for wifi in states {
            XCTAssertNil(
                scene(source: .wifi, snapshot: snapshot(wifi: wifi)).footer,
                "\(wifi.state) with rssi \(String(describing: wifi.rssi)) should hide the footer"
            )
        }
    }

    func testWiFiSourceOnWiredNetworkHidesFooter() {
        // Wi-Fi radio off while the active link is Ethernet: nothing to report.
        let wired = snapshot(
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .ethernet
        )
        XCTAssertNil(scene(source: .wifi, snapshot: wired).footer)
    }

    // MARK: Battery

    func testBatteryLevelsMapToDots() {
        for (percentage, steps) in [(0, 0), (25, 1), (50, 2), (75, 3), (100, 4)] {
            let battery = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            )
            let footer = scene(source: .battery, style: .dots,
                               snapshot: snapshot(battery: battery)).footer
            guard case let .dots(d)? = footer else { return XCTFail("expected dots at \(percentage)") }
            XCTAssertEqual(d.activeCount, steps, "\(percentage)% should be \(steps) dots")
        }
    }

    func testBatteryLevelsMapToArcProgress() {
        for percentage in [0, 1, 37, 99, 100] {
            let battery = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            )
            let footer = scene(source: .battery, style: .arc,
                               snapshot: snapshot(battery: battery)).footer
            guard case let .arc(a)? = footer else { return XCTFail("expected arc at \(percentage)") }
            XCTAssertEqual(a.progress, Double(percentage) / 100.0, accuracy: 0.0001)
        }
    }

    func testBatterySourceWithoutBatteryHidesFooter() {
        XCTAssertNil(scene(source: .battery, snapshot: snapshot(battery: .absent)).footer)
    }

    // MARK: Hidden

    func testHiddenSourceReturnsNoFooter() {
        XCTAssertNil(scene(source: .hidden, style: .dots).footer)
        XCTAssertNil(scene(source: .hidden, style: .arc).footer)
    }

    // MARK: Dock cache

    func testDockRenderKeyDistinguishesSourcesEvenWithIdenticalFooter() {
        let sameFooter = DotsState(count: 4, activeCount: 0, color: .primary)
        let wifi = DockIconRenderKey(
            scene: IconSceneState(footer: .dots(sameFooter), bottomIndicatorSource: .wifi),
            backgroundStyle: .dark,
            pixelLength: 128
        )
        let battery = DockIconRenderKey(
            scene: IconSceneState(footer: .dots(sameFooter), bottomIndicatorSource: .battery),
            backgroundStyle: .dark,
            pixelLength: 128
        )
        XCTAssertNotEqual(wifi, battery, "A source change must invalidate the Dock cache.")

        var cache = DockIconRenderCache()
        XCTAssertTrue(cache.needsRender(wifi))
        cache.recordSuccessfulRender(wifi)
        XCTAssertTrue(cache.needsRender(battery))
    }

    // MARK: Scene + classifier

    func testSceneCarriesTheSource() {
        XCTAssertEqual(scene(source: .wifi).bottomIndicatorSource, .wifi)
        XCTAssertEqual(scene(source: .battery).bottomIndicatorSource, .battery)
        XCTAssertEqual(scene(source: .hidden).bottomIndicatorSource, .hidden)
    }

    func testOnlyVolumeSourceCountsAsVolumeValueChange() {
        let volumeLow = scene(source: .volume, style: .arc,
                              snapshot: snapshot(volume: VolumeStatus(scalar: 0.2, isMuted: false, deviceName: "Out")))
        let volumeHigh = scene(source: .volume, style: .arc,
                               snapshot: snapshot(volume: VolumeStatus(scalar: 0.8, isMuted: false, deviceName: "Out")))
        XCTAssertTrue(volumeHigh.isVolumeValueChange(from: volumeLow))

        let wifiWeak = scene(source: .wifi, style: .dots,
                             snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -85)))
        let wifiStrong = scene(source: .wifi, style: .dots,
                               snapshot: snapshot(wifi: WiFiStatus(state: .connected, rssi: -55)))
        XCTAssertFalse(wifiStrong.isVolumeValueChange(from: wifiWeak),
                       "A Wi-Fi signal update must not be rate-limited as a volume change.")

        let batteryLow = scene(source: .battery, style: .arc, snapshot: snapshot(battery: BatteryStatus(
            rawPercentage: 20, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)))
        let batteryHigh = scene(source: .battery, style: .arc, snapshot: snapshot(battery: BatteryStatus(
            rawPercentage: 90, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false)))
        XCTAssertFalse(batteryHigh.isVolumeValueChange(from: batteryLow),
                       "A battery update must not be rate-limited as a volume change.")

        // Switching source is a settings change even when the footer kind matches.
        let volumeArc = scene(source: .volume, style: .arc)
        XCTAssertFalse(volumeArc.isVolumeValueChange(from: wifiStrong))
    }
}
