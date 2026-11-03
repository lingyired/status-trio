import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class PresentationBaselineTests: XCTestCase {
    func testDotBucketAndSignalBucketBaseline() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -75), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.74, isMuted: false), 3)
    }

    func testSharedSnapshotFixtureKeepsItsPresentationInputs() {
        let snapshot = PresentationFixtures.snapshot(rssi: -79, scalar: 0.74, muted: true)

        XCTAssertEqual(snapshot.battery.rawPercentage, 68)
        XCTAssertEqual(snapshot.battery.isPresent, true)
        XCTAssertEqual(snapshot.wifi.state, .connected)
        XCTAssertEqual(snapshot.wifi.rssi, -79)
        XCTAssertEqual(snapshot.connection, .wifi)
        XCTAssertEqual(snapshot.volume.scalar, 0.74)
        XCTAssertEqual(snapshot.volume.isMuted, true)
        XCTAssertEqual(snapshot.volume.deviceName, "Output")
    }

    func testSharedBluetoothDeviceUsesSheetHardwareFixture() {
        XCTAssertEqual(PresentationFixtures.bluetoothDevice, SheetFixtures.bluetoothDevice)
        XCTAssertEqual(PresentationFixtures.bluetoothDevice.transport, .bluetooth)
    }

    func testPrioritizedNetworkErrorWinsOverBatteryPercentageAndBluetoothOutput() throws {
        let fixture = PresentationFixtures.snapshot()
        let snapshot = StatusSnapshot(
            battery: fixture.battery,
            wifi: WiFiStatus(state: .noInternet, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(
                scalar: fixture.volume.scalar,
                isMuted: fixture.volume.isMuted,
                deviceName: fixture.volume.deviceName,
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        let bluetoothWithNetworkErrorPriority = BluetoothAudioIconOptions()

        let batteryCenter = try renderedPixels(
            snapshot,
            centerSource: .batteryPercentage,
            bluetoothOptions: bluetoothWithNetworkErrorPriority
        )
        let batteryOnlyReference = try renderedPixels(
            snapshot,
            centerSource: .batteryPercentage,
            prioritizesNetworkErrors: false
        )
        let prioritizedNetworkError = try renderedPixels(
            snapshot,
            bluetoothOptions: bluetoothWithNetworkErrorPriority
        )

        XCTAssertEqual(centerSlotPixels(batteryCenter), centerSlotPixels(prioritizedNetworkError))
        XCTAssertNotEqual(centerSlotPixels(batteryCenter), centerSlotPixels(batteryOnlyReference))
    }

    func testAbsentBatteryPercentageCenterWinsOverBluetoothReplacement() throws {
        let fixture = PresentationFixtures.snapshot()
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: fixture.wifi,
            connection: fixture.connection,
            volume: VolumeStatus(
                scalar: fixture.volume.scalar,
                isMuted: fixture.volume.isMuted,
                deviceName: fixture.volume.deviceName,
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        let bluetoothReplacement = BluetoothAudioIconOptions()

        let enabledWithBatterySlot = try renderedPixels(
            snapshot,
            centerSource: .batteryPercentage,
            bluetoothOptions: bluetoothReplacement
        )
        let enabledWithoutBatterySlot = try renderedPixels(
            snapshot,
            bluetoothOptions: bluetoothReplacement
        )
        let standardNetwork = try renderedPixels(
            snapshot,
            centerSource: .batteryPercentage
        )

        // A no-battery Mac reports 100, so the battery-percentage slot draws the
        // number and wins over the Bluetooth replacement exactly as it does on a
        // battery Mac. The Bluetooth options therefore no longer change the
        // centre, while the plain automatic decision still shows the glyph.
        XCTAssertEqual(
            centerSlotPixels(enabledWithBatterySlot),
            centerSlotPixels(standardNetwork)
        )
        XCTAssertNotEqual(
            centerSlotPixels(enabledWithBatterySlot),
            centerSlotPixels(enabledWithoutBatterySlot)
        )
    }

    private func renderedPixels(
        _ snapshot: StatusSnapshot,
        centerSource: ConnectionCenterSource = .network,
        prioritizesNetworkErrors: Bool = true,
        bluetoothOptions: BluetoothAudioIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(renderMenuBarFixture(
                snapshot: snapshot,
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            connectionOptions: ConnectionIconOptions(
                centerSource: centerSource,
                prioritizesNetworkErrors: prioritizesNetworkErrors
            ),
            bluetoothAudioOptions: bluetoothOptions
        ))
        return try PixelBuffer(image: image)
    }

    private func centerSlotPixels(_ pixels: PixelBuffer) -> [UInt8] {
        let centerRegion = CGRect(x: 42, y: 72, width: 36, height: 20)
        let pixelsPerSVGUnit = CGFloat(pixels.width) / StatusIconGeometry.canvas.width
        let minX = Int((centerRegion.minX * pixelsPerSVGUnit).rounded(.down))
        let maxX = Int((centerRegion.maxX * pixelsPerSVGUnit).rounded(.up))
        let minY = Int((centerRegion.minY * pixelsPerSVGUnit).rounded(.down))
        let maxY = Int((centerRegion.maxY * pixelsPerSVGUnit).rounded(.up))

        return (minY..<maxY).flatMap { y in
            (minX..<maxX).flatMap { x in
                let start = (y * pixels.width + x) * 4
                return pixels.bytes[start..<(start + 4)]
            }
        }
    }
}
