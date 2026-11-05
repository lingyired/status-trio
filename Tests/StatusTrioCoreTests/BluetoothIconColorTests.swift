import XCTest
@testable import StatusTrioCore

/// #275: the centre Bluetooth glyph can stay blue (default) or follow the
/// system's primary colour, independently of the volume footer's Bluetooth
/// tint. Both the automatic glyph and an explicitly picked device must obey it.
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
        usesIconColor: Bool,
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
                usesIconColor: usesIconColor,
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

    func testIconColourDefaultsToBluetooth() {
        let scene = self.scene(usesIconColor: true)
        XCTAssertEqual(scene.center?.colorRole, .bluetooth)
    }

    func testTurningIconColourOffUsesPrimary() {
        let scene = self.scene(usesIconColor: false)
        XCTAssertEqual(scene.center?.colorRole, .primary)
    }

    func testExplicitDeviceFollowsIconColourSetting() {
        let blue = scene(usesIconColor: true, override: "headphones")
        let mono = scene(usesIconColor: false, override: "headphones")
        XCTAssertEqual(blue.center?.colorRole, .bluetooth)
        XCTAssertEqual(mono.center?.colorRole, .primary)
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
                usesIconColor: false,
                usesVolumeColor: true
            )
        )
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
        XCTAssertEqual(scene.center?.colorRole, .primary, "mono glyph")
        XCTAssertEqual(scene.footer?.colorRole, .bluetooth, "volume stays tinted")
    }
}
