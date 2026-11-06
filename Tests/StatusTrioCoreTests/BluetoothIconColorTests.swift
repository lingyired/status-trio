import AppKit
import XCTest
@testable import StatusTrioCore

/// #275: the middle Bluetooth glyph is blue by default, can follow the system
/// label colour, or use a custom colour, independently of the volume footer.
final class BluetoothIconColorTests: XCTestCase {
    private let bluetoothDevice = AudioOutputDevice(
        id: 42,
        name: "AirPods Pro",
        uid: "bt-output",
        isCurrent: true,
        volume: 0.6,
        transport: .bluetooth
    )

    private func scene(
        _ iconColor: BluetoothIconColorSelection,
        override: String? = nil,
        iconChoice: BluetoothAudioIconChoice = .automatic
    ) -> IconSceneState {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: bluetoothDevice.name,
                currentDevice: bluetoothDevice
            )
        )
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: ConnectionIconOptions(centerSource: .bluetoothDevice),
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(
                iconColor: iconColor,
                usesVolumeColor: false,
                networkIconSymbolOverride: override,
                iconChoice: iconChoice
            )
        )
        return IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
    }

    func testDefaultIsBlueAndRidesTheScene() {
        let scene = self.scene(.systemBlue)
        XCTAssertEqual(scene.center?.colorRole, .bluetoothIcon)
        XCTAssertEqual(scene.bluetoothIconColor, .systemBlue)
    }

    func testPrimaryUsesTheAdaptiveRole() {
        let scene = self.scene(.primary)
        XCTAssertEqual(scene.center?.colorRole, .primary)
        XCTAssertEqual(scene.bluetoothIconColor, .primary)
    }

    func testCustomColourRidesTheSceneEvenForAPickedDevice() {
        let components = BatteryStatusColorComponents(hue: 0.8, saturation: 0.9, brightness: 0.8)
        let scene = self.scene(.custom(components), override: "headphones")
        XCTAssertEqual(scene.center?.colorRole, .bluetoothIcon)
        XCTAssertEqual(scene.bluetoothIconColor, .custom(components))
    }

    func testIconColourIsIndependentOfVolumeColour() {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: bluetoothDevice.name,
                currentDevice: bluetoothDevice
            )
        )
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: ConnectionIconOptions(centerSource: .bluetoothDevice),
            volume: VolumeIconOptions(displayStyle: .arc),
            bluetooth: BluetoothAudioIconOptions(
                iconColor: .primary,
                usesVolumeColor: true
            )
        )
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
        XCTAssertEqual(scene.center?.colorRole, .primary, "mono icon")
        XCTAssertEqual(scene.footer?.colorRole, .bluetooth, "volume stays tinted")
    }

    func testResolverMapsTheThreeModes() {
        let foreground = CGColor(gray: 0, alpha: 1)
        let blue = BluetoothIconColorResolver.resolve(.systemBlue, foreground: foreground, darkAppearance: false)
        XCTAssertEqual(blue, StatusIconRenderer.bluetoothColor(foreground: foreground))
        XCTAssertEqual(
            BluetoothIconColorResolver.resolve(.primary, foreground: foreground, darkAppearance: false),
            foreground
        )
        let custom = BluetoothIconColorResolver.resolve(
            .custom(BatteryStatusColorComponents(hue: 0.75, saturation: 0.9, brightness: 0.8)),
            foreground: foreground,
            darkAppearance: false
        )
        XCTAssertNotEqual(custom, blue)
        XCTAssertNotEqual(custom, foreground)
    }

    func testStorageRoundTripsAllModes() {
        for selection: BluetoothIconColorSelection in [
            .systemBlue,
            .primary,
            .custom(BatteryStatusColorComponents(hue: 0.4, saturation: 0.6, brightness: 0.7))
        ] {
            XCTAssertEqual(
                BluetoothIconColorSelection(storageValue: selection.storageValue),
                selection
            )
        }
        XCTAssertEqual(BluetoothIconColorSelection(storageValue: "garbage"), .systemBlue)
    }
}
