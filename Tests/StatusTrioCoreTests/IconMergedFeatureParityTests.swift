import XCTest
@testable import StatusTrioCore

/// Pins the merged main features onto the V1 resolution path actually used at
/// runtime (`AppEnvironment.mapScene` -> `IconCompositionResolver`), so a
/// feature cannot silently regress by only working through the legacy mapper.
final class IconMergedFeatureParityTests: XCTestCase {
    private func inputs(
        snapshot: StatusSnapshot,
        isHighPowerMode: Bool = false,
        systemPower: SystemPowerSample? = nil
    ) -> IconResolutionInputs {
        IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: nil,
                isHighPowerMode: isHighPowerMode,
                sources: .empty
            ),
            sources: .empty
        )
    }

    private func onBatterySnapshot() -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 80,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output", currentDevice: nil)
        )
    }

    /// #235: High Power Mode colour must reach the ring through the V1 resolver.
    func testHighPowerModeColoursTheRingThroughTheV1Resolver() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.behaviors.systemBatteryRing.usesStatusColors = true

        let normal = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot(), isHighPowerMode: false),
            configuration: configuration
        )
        let highPower = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot(), isHighPowerMode: true),
            configuration: configuration
        )

        XCTAssertNotNil(normal.scene.outerRing?.segments.first)
        XCTAssertEqual(highPower.scene.outerRing?.segments.first?.color, .highPower)
        XCTAssertNotEqual(normal.scene.outerRing?.segments.first?.color, .highPower)
    }

    /// #205: the split-gap mode must reach the resolved ring.
    func testSplitGapProgressReachesTheResolvedRing() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.behaviors.splitGapProgress = true

        let output = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot()),
            configuration: configuration
        )
        XCTAssertEqual(output.scene.outerRing?.gapProgressMode, .split)

        configuration.behaviors.splitGapProgress = false
        let legacy = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot()),
            configuration: configuration
        )
        XCTAssertEqual(legacy.scene.outerRing?.gapProgressMode, .absorbed)
    }

    /// #315: per-power-state markers must drive the ring's top-gap accessory.
    func testBatteryMarkersReachTheResolvedRingAccessory() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
        configuration.behaviors.batteryMarkers = BatteryMarkerBehavior(
            onBattery: .percentage,
            charging: .bolt,
            connected: .plug,
            noBattery: .plug
        )

        let output = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot()),
            configuration: configuration
        )
        guard case let .text(text)? = output.scene.outerRing?.accessory else {
            return XCTFail("On-battery `.percentage` marker should draw the level text")
        }
        XCTAssertEqual(text.text, "80")

        configuration.behaviors.batteryMarkers.onBattery = .hidden
        let hidden = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot()),
            configuration: configuration
        )
        XCTAssertNil(hidden.scene.outerRing?.accessory)
    }

    /// #275: the Bluetooth icon colour rides the resolved scene.
    func testBluetoothIconColourRidesTheResolvedScene() {
        var configuration = IconConfigurationV1.classic
        configuration.appearance.bluetoothIconColor = BluetoothIconColorConfiguration(storageValue: "primary")

        let output = IconCompositionResolver.resolve(
            inputs: inputs(snapshot: onBatterySnapshot()),
            configuration: configuration
        )
        XCTAssertEqual(output.scene.bluetoothIconColor, .primary)
    }
}
