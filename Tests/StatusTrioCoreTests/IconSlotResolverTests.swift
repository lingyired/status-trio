import XCTest
@testable import StatusTrioCore

final class IconSlotResolverTests: XCTestCase {
    func testChooseSourceSelectsAvailablePrimary() {
        let result = chooseSource(
            SlotSelection<RingSource>(primary: .systemBattery, fallback: nil), none: .none
        ) { _ in .available(true) }

        XCTAssertEqual(result.source, .systemBattery)
        XCTAssertEqual(result.role, .primary)
        XCTAssertNil(result.primaryFailure)
    }

    func testChooseSourceUsesFallbackAfterPrimaryFailure() {
        let result = chooseSource(
            SlotSelection<CenterSource>(primary: .bluetoothAudioOutput, fallback: .network), none: .none
        ) { source in
            source == .bluetoothAudioOutput ? .unavailable(.disconnected) : .available(true)
        }

        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.role, .fallback)
        XCTAssertEqual(result.primaryFailure, .disconnected)
    }

    func testChooseSourceReportsUnavailableWhenBothSourcesFail() {
        let result = chooseSource(
            SlotSelection<CenterSource>(primary: .bluetoothAudioOutput, fallback: .network), none: .none
        ) { _ in .unavailable(.permissionDenied) }

        XCTAssertNil(result.source)
        XCTAssertEqual(result.role, .none)
        XCTAssertEqual(result.primaryFailure, .permissionDenied)
    }

    func testExplicitNoneDoesNotConsultFallback() {
        var queried = false
        let result = chooseSource(
            SlotSelection<RingSource>(primary: .none, fallback: .systemBattery), none: .none
        ) { _ in
            queried = true
            return .available(true)
        }

        XCTAssertNil(result.source)
        XCTAssertEqual(result.role, .none)
        XCTAssertFalse(queried)
    }

    func testClassicRingAndFooterKeepZeroAsAvailableData() {
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.systemVolumeFooter.displayStyle = .arc
        let battery = BatteryStatus(rawPercentage: 0, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let snapshot = StatusSnapshot(
            battery: battery, wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: "Output")
        )

        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: .empty
            ),
            configuration: configuration
        )

        XCTAssertEqual(output.scene.outerRing?.segments.first?.progress, 0)
        XCTAssertEqual(output.scene.footer, .arc(ArcState(
            progress: 0, color: .primary, strokeScale: configuration.appearance.footer.strokeScale
        )))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.slash", variableValue: 1, fallback: nil), color: .primary, scale: 1.0
        )))
    }

    func testClassicPercentageStillPreemptsBluetoothAndNetworkError() {
        let battery = BatteryStatus(rawPercentage: 45, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let snapshot = StatusSnapshot(
            battery: battery, wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        var configuration = IconConfigurationV1.classic
        configuration.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = true
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true

        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.scene.center, .text(IconTextState(text: "45", color: .primary, scale: 1)))
        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)
    }

    func testExplicitBluetoothPrimaryFallsBackToNetworkAndTracesFailure() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        let snapshot = StatusSnapshot(
            battery: .placeholder, wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let output = resolve(
            snapshot,
            configuration: configuration,
            sources: IconSourceSnapshot(availability: [
                CenterSource.bluetoothAudioOutput.rawValue: .unavailable(.disconnected)
            ])
        )

        XCTAssertEqual(output.trace.center.selectedSourceID, CenterSource.network.rawValue)
        XCTAssertEqual(output.trace.center.role, .fallback)
        XCTAssertEqual(output.trace.center.primaryFailure, .disconnected)
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1.0
        )))
    }

    func testNetworkErrorOverrideOnlyAppliesToExplicitBluetoothPrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        configuration.behaviors.bluetoothAudioCenter.replacesNetworkIcon = true
        let snapshot = StatusSnapshot(
            battery: .placeholder, wifi: WiFiStatus(state: .noInternet, rssi: -45),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        )
        let output = resolve(snapshot, configuration: configuration)

        XCTAssertEqual(output.trace.center.reason, .overridden(.networkProblem))
        XCTAssertEqual(output.scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "wifi.exclamationmark", variableValue: 1, fallback: nil),
            color: .primary, scale: 1.0
        )))

        configuration.composition.center = SlotSelection(primary: .automaticLegacy)
        let legacy = resolve(snapshot, configuration: configuration)
        XCTAssertEqual(legacy.trace.center.reason, .primary)
        XCTAssertEqual(legacy.trace.center.selectedSourceID, CenterSource.automaticLegacy.rawValue)
        XCTAssertEqual(legacy.scene.center, IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: .standard
        ).center)
    }

    private func resolve(
        _ snapshot: StatusSnapshot,
        configuration: IconConfigurationV1,
        sources: IconSourceSnapshot = .empty
    ) -> IconResolutionOutput {
        IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
                sources: sources
            ),
            configuration: configuration
        )
    }
}
