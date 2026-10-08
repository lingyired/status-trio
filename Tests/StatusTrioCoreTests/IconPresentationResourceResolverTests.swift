import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPresentationResourceResolverTests: XCTestCase {
    func testMissingDeviceIconUsesClassifiedFallbackSymbol() {
        let device = AudioOutputDevice(id: 1, name: "AirPods Pro", isCurrent: true,
                                       transport: .bluetooth, iconURL: URL(fileURLWithPath: "/missing/device.png"))
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: device),
            fileExists: { _ in false }, isSymbolAvailable: { $0 == "airpods.pro" })

        XCTAssertEqual(inputs.audioIcon, .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones"))
    }

    func testExistingDeviceImageIsCarriedWithRendererFallback() {
        let url = URL(fileURLWithPath: "/fixture/device.png")
        let device = AudioOutputDevice(id: 1, name: "Driver Audio", isCurrent: true,
                                       transport: .usb, iconURL: url)
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: device),
            fileExists: { $0 == url }, isSymbolAvailable: { _ in XCTFail("symbol lookup is unnecessary for an existing image"); return false })

        XCTAssertEqual(inputs.audioIcon, .image(url: url, fallbackSymbol: "headphones"))
    }

    func testNoCurrentDeviceHasNoAudioIcon() {
        let inputs = IconPresentationResourceResolver.inputs(snapshot: snapshot(device: nil),
            fileExists: { _ in XCTFail("file lookup is unnecessary without a current device"); return false },
            isSymbolAvailable: { _ in XCTFail("symbol lookup is unnecessary without a current device"); return false })
        XCTAssertNil(inputs.audioIcon)
    }

    func testAvailabilityDistinguishesConnectedDisconnectedAndUnknownSources() {
        let bluetooth = AudioOutputDevice(
            id: 1, name: "Bluetooth Output", isCurrent: true, transport: .bluetooth, iconURL: nil
        )
        let connected = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -40),
                connection: .wifi,
                volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: bluetooth.name, currentDevice: bluetooth)
            )
        )
        XCTAssertEqual(connected.availability["network"], .available)
        XCTAssertEqual(connected.availability["systemBattery"], .available)
        XCTAssertEqual(connected.availability["systemVolume"], .available)
        XCTAssertEqual(connected.availability["bluetoothAudioOutput"], .available)

        let disconnected = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                        isLowPowerMode: false, isConnectedToPower: false),
                wifi: WiFiStatus(state: .off, rssi: nil),
                connection: .offline,
                volume: .placeholder
            )
        )
        XCTAssertEqual(disconnected.availability["network"], .unavailable(.disconnected))
        XCTAssertEqual(disconnected.availability["systemBattery"], .unavailable(.disconnected))
        XCTAssertEqual(disconnected.availability["bluetoothAudioOutput"], .unavailable(.disconnected))

        let unknown = IconPresentationResourceResolver.sourceSnapshot(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                connection: .offline,
                volume: .placeholder
            )
        )
        XCTAssertEqual(unknown.availability["network"], .unavailable(.unknown))
    }

    private func snapshot(device: AudioOutputDevice?) -> StatusSnapshot {
        StatusSnapshot(battery: .placeholder, wifi: .placeholder, connection: .wifi,
                      volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: device?.name, currentDevice: device))
    }
}
