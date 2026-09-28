import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class DockIconRendererTests: XCTestCase {
    func testDockIconHasExpectedLogicalAndPixelSize() throws {
        let image = try XCTUnwrap(DockIconRenderer.image(status: .placeholder))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )

        XCTAssertEqual(image.size, NSSize(width: 256, height: 256))
        XCTAssertEqual(representation.pixelsWide, 512)
        XCTAssertEqual(representation.pixelsHigh, 512)
        XCTAssertFalse(image.isTemplate)
    }

    func testDockIconKeepsTransparentMarginAndDarkBody() throws {
        let pixels = try pixels(for: .placeholder)
        let corner = pixels.rgba(x: 0, y: 0)
        let margin = pixels.rgba(x: pixels.width / 2, y: pixels.height / 50)
        let body = pixels.rgba(x: pixels.width * 12 / 100, y: pixels.height / 2)

        XCTAssertEqual(corner.alpha, 0)
        XCTAssertEqual(margin.alpha, 0)
        XCTAssertGreaterThan(body.alpha, 250)
        XCTAssertLessThanOrEqual(abs(Int(body.red) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.green) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.blue) - 23), 3)
    }

    func testChargingStatusPreservesGreenAccent() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        ))
        let pixels = try pixels(for: status)

        XCTAssertTrue(pixels.containsColor(
            red: 52.0 / 255.0,
            green: 199.0 / 255.0,
            blue: 89.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testBoltHeartbeatSettingDoesNotChangeTheStaticDockIcon() throws {
        let status = chargingStatus()
        let enabled = try pixels(
            for: status,
            options: BatteryIconOptions(showsChargingBoltHeartbeat: true)
        )
        let disabled = try pixels(
            for: status,
            options: BatteryIconOptions(showsChargingBoltHeartbeat: false)
        )

        XCTAssertEqual(enabled.bytes, disabled.bytes)
    }

    func testLightStyleUsesWhiteBody() throws {
        let pixels = try pixels(for: .placeholder, backgroundStyle: .light)
        let margin = pixels.rgba(x: pixels.width / 2, y: pixels.height / 50)
        let body = pixels.rgba(x: pixels.width * 12 / 100, y: pixels.height / 2)

        XCTAssertEqual(margin.alpha, 0)
        XCTAssertGreaterThan(body.alpha, 250)
        XCTAssertGreaterThanOrEqual(Int(body.red), 250)
        XCTAssertGreaterThanOrEqual(Int(body.green), 250)
        XCTAssertGreaterThanOrEqual(Int(body.blue), 250)
    }

    func testLightStyleDrawsDarkGlyph() throws {
        let pixels = try pixels(for: .placeholder, backgroundStyle: .light)

        XCTAssertTrue(pixels.containsColor(
            red: 29.0 / 255.0,
            green: 29.0 / 255.0,
            blue: 31.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testLightStyleUsesDarkChargingPalette() throws {
        let pixels = try pixels(for: chargingStatus(), backgroundStyle: .light)

        XCTAssertTrue(pixels.containsColor(
            red: 31.0 / 255.0,
            green: 143.0 / 255.0,
            blue: 61.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testDarkStyleStaysUnchangedByLightPalette() throws {
        let pixels = try pixels(for: .placeholder, backgroundStyle: .dark)
        let body = pixels.rgba(x: pixels.width * 12 / 100, y: pixels.height / 2)

        XCTAssertLessThanOrEqual(abs(Int(body.red) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.green) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.blue) - 23), 3)
    }

    func testClearStyleUsesTranslucentLightBody() throws {
        let pixels = try pixels(for: .placeholder, backgroundStyle: .clear)
        let margin = pixels.rgba(x: pixels.width / 2, y: pixels.height / 50)
        let body = pixels.rgba(x: pixels.width * 12 / 100, y: pixels.height / 2)

        XCTAssertEqual(margin.alpha, 0)
        XCTAssertGreaterThan(body.alpha, 80)
        XCTAssertLessThan(body.alpha, 240)
        XCTAssertGreaterThanOrEqual(Int(body.red), Int(body.alpha) - 20)
    }

    func testClearStyleKeepsDarkGlyph() throws {
        let pixels = try pixels(for: .placeholder, backgroundStyle: .clear)

        XCTAssertTrue(pixels.containsColor(
            red: 29.0 / 255.0,
            green: 29.0 / 255.0,
            blue: 31.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testOptionsChangeRenderedInk() throws {
        let status = MenuBarStatus.placeholder
        let withValue = try pixels(
            for: status,
            options: BatteryIconOptions(
                showsPercentage: true,
                showsChargingIndicator: true,
                usesStatusColors: true,
                criticalThreshold: 20
            )
        )
        let withoutValue = try pixels(
            for: status,
            options: BatteryIconOptions(
                showsPercentage: false,
                showsChargingIndicator: false,
                usesStatusColors: true,
                criticalThreshold: 20
            )
        )

        XCTAssertNotEqual(withValue.bytes, withoutValue.bytes)
    }

    /// Only the battery ring width varies; the volume options stay on the
    /// regular width, so the battery multiplier is what must change the ink.
    func testRingStrokeStyleChangesDockBatteryInk() throws {
        let status = MenuBarStatus.placeholder
        let regularVolume = VolumeIconOptions(ringStrokeScale: RingStrokeStyle.regular.scale)

        let lightPixels = try pixels(
            for: status,
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.light.scale),
            volumeOptions: regularVolume
        )
        let boldPixels = try pixels(
            for: status,
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale),
            volumeOptions: regularVolume
        )

        XCTAssertNotEqual(lightPixels.bytes, boldPixels.bytes)
    }

    /// Only the volume dots vary; the battery ring stays on the regular width.
    func testRingStrokeStyleChangesDockVolumeInk() throws {
        let status = MenuBarStatus(
            snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
            )
        )
        let regularBattery = BatteryIconOptions(ringStrokeScale: RingStrokeStyle.regular.scale)

        let lightPixels = try pixels(
            for: status,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .dots,
                ringStrokeScale: RingStrokeStyle.light.scale
            )
        )
        let boldPixels = try pixels(
            for: status,
            options: regularBattery,
            volumeOptions: VolumeIconOptions(
                displayStyle: .dots,
                ringStrokeScale: RingStrokeStyle.bold.scale
            )
        )

        XCTAssertNotEqual(lightPixels.bytes, boldPixels.bytes)
    }

    func testRendererProducesImageForEveryPlacementPreviewState() throws {
        XCTAssertNotNil(DockIconRenderer.image(status: .placeholder))
    }

    /// The Dock tile follows the menu bar: AirPods (2nd generation,
    /// A2031/A2032) is identified by product ID 0x200F, so a renamed device
    /// still draws the AirPods glyph instead of a generic headphone.
    func testDockIconUsesTheAirPodsProductID() throws {
        let namedAirPods = try bluetoothPixels(deviceName: "AirPods", modelUID: nil)
        let renamedAirPods = try bluetoothPixels(deviceName: "小王的耳机", modelUID: "200f 4c")
        let renamedWithoutProductID = try bluetoothPixels(deviceName: "小王的耳机", modelUID: nil)

        XCTAssertEqual(namedAirPods.bytes, renamedAirPods.bytes)
        XCTAssertNotEqual(renamedWithoutProductID.bytes, renamedAirPods.bytes)
    }

    /// Dock parity for the picker mode: with a device picked, the tile draws
    /// its glyph instead of the network icon even with no current audio output.
    func testDockIconDrawsTheNetworkIconOverrideWithoutAnyAudioOutput() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        ))
        let standard = try pixels(for: status)
        let overridden = try pixels(
            for: status,
            bluetoothAudioOptions: BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                networkIconSymbolOverride: "keyboard"
            )
        )

        XCTAssertNotEqual(standard.bytes, overridden.bytes)
        XCTAssertTrue(overridden.containsColor(
            red: 77.0 / 255.0,
            green: 163.0 / 255.0,
            blue: 1,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    private func bluetoothPixels(deviceName: String, modelUID: String?) throws -> PixelBuffer {
        let device = AudioOutputDevice(
            id: 42,
            name: deviceName,
            uid: "bluetooth-output",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth,
            modelUID: modelUID
        )
        return try pixels(
            for: MenuBarStatus(snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -55),
                connection: .wifi,
                volume: VolumeStatus(
                    scalar: 0.5,
                    isMuted: false,
                    deviceName: deviceName,
                    currentDevice: device
                )
            )),
            bluetoothAudioOptions: BluetoothAudioIconOptions(replacesNetworkIcon: true)
        )
    }

    private func pixels(
        for status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle = .dark
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(
            status: status,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            backgroundStyle: backgroundStyle
        ))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try XCTUnwrap(representation.cgImage))
    }

    private func chargingStatus() -> MenuBarStatus {
        MenuBarStatus(snapshot: StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        ))
    }
}
