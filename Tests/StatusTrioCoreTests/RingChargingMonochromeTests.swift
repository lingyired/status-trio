import XCTest
@testable import StatusTrioCore

/// Issue #309: the "black & white when charging / on power" switch. Low/High
/// Power Mode and critical keep their own colours; a battery-less Mac defaults to
/// black/white unless the user explicitly opts into the connected colour.
final class RingChargingMonochromeTests: XCTestCase {
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

    private func options(
        usesStatusColors: Bool = true,
        monochromeCharging: Bool? = nil
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            usesStatusColors: usesStatusColors,
            criticalThreshold: 20,
            connectedIndicator: .bolt,
            monochromeCharging: monochromeCharging
        )
    }

    private func ringColor(
        _ battery: BatteryStatus,
        options: BatteryIconOptions,
        highPower: Bool = false
    ) -> IconColorRole? {
        let configuration = IconPresentationConfiguration(
            battery: options,
            connection: .standard,
            volume: .standard,
            bluetooth: .standard
        )
        return IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot(battery), audioIcon: nil, isHighPowerMode: highPower
            ),
            configuration: configuration
        ).outerRing?.segments.first?.color
    }

    func testChargingAndConnectedUseMonochromeWhenOn() {
        XCTAssertEqual(
            ringColor(battery(percentage: 80, charging: true, connectedToPower: true),
                      options: options(monochromeCharging: true)),
            .primary
        )
        XCTAssertEqual(
            ringColor(battery(percentage: 80, connectedToPower: true),
                      options: options(monochromeCharging: true)),
            .primary
        )
    }

    func testChargingAndConnectedUseChargingColourWhenOff() {
        XCTAssertEqual(
            ringColor(battery(percentage: 80, charging: true, connectedToPower: true),
                      options: options(monochromeCharging: false)),
            .powered
        )
        XCTAssertEqual(
            ringColor(battery(percentage: 80, connectedToPower: true),
                      options: options(monochromeCharging: false)),
            .powered
        )
    }

    func testBatteryLessDefaultsToMonochrome() {
        XCTAssertEqual(
            ringColor(.absent, options: options(monochromeCharging: nil)),
            .primary
        )
    }

    func testBatteryLessExplicitOffUsesConnectedColour() {
        XCTAssertEqual(
            ringColor(.absent, options: options(monochromeCharging: false)),
            .powered
        )
    }

    func testLowAndHighPowerModeBeatMonochrome() {
        XCTAssertEqual(
            ringColor(battery(percentage: 80, lowPower: true),
                      options: options(monochromeCharging: true)),
            .lowPower
        )
        XCTAssertEqual(
            ringColor(.absent, options: options(monochromeCharging: true), highPower: true),
            .highPower
        )
    }

    func testCriticalBeatsMonochrome() {
        XCTAssertEqual(
            ringColor(battery(percentage: 10),
                      options: options(monochromeCharging: true)),
            .critical
        )
    }

    /// The settings preview must carry High Power Mode too, or the ring looks
    /// white there even when the mode is on (the preview does not use the live
    /// icon view model).
    @MainActor
    func testPreviewSceneHonoursHighPowerMode() {
        let configuration = IconPresentationConfiguration(
            battery: options(monochromeCharging: true),
            connection: .standard,
            volume: .standard,
            bluetooth: .standard
        )
        let scene = IconPreviewScene.make(
            status: MenuBarStatus(snapshot: snapshot(.absent)),
            configuration: configuration,
            isHighPowerMode: true
        )
        XCTAssertEqual(scene.outerRing?.segments.first?.color, .highPower)
    }

    @MainActor
    func testSettingDefaultsNilAndPersistsExplicitChoice() {
        let name = "RingChargingMonochromeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.monochromeChargingRing)
        XCTAssertNil(store.batteryIconOptions.monochromeCharging)

        store.monochromeChargingRing = true
        XCTAssertEqual(SettingsStore(defaults: defaults).monochromeChargingRing, true)
        XCTAssertEqual(store.batteryIconOptions.monochromeCharging, true)

        store.monochromeChargingRing = false
        XCTAssertEqual(SettingsStore(defaults: defaults).monochromeChargingRing, false)
        XCTAssertEqual(store.batteryIconOptions.monochromeCharging, false)
    }
}
