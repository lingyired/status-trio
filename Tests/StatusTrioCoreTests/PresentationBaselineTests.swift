import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class PresentationBaselineTests: XCTestCase {
    func testDotBucketAndSignalBucketBaseline() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -62), 2)
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

    func testPresentBatteryPercentageWinsOverPrioritizedNetworkErrorAndBluetoothOutput() throws {
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
        let bluetoothWithNetworkErrorPriority = BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            prioritizesNetworkErrors: true
        )

        let batteryCenter = try renderedPixels(
            snapshot,
            showsBatteryPercentageInConnectionSlot: true,
            bluetoothOptions: bluetoothWithNetworkErrorPriority
        )
        let batteryOnlyReference = try renderedPixels(
            snapshot,
            showsBatteryPercentageInConnectionSlot: true
        )
        let prioritizedNetworkError = try renderedPixels(
            snapshot,
            bluetoothOptions: bluetoothWithNetworkErrorPriority
        )

        XCTAssertEqual(centerSlotPixels(batteryCenter), centerSlotPixels(batteryOnlyReference))
        XCTAssertNotEqual(centerSlotPixels(batteryCenter), centerSlotPixels(prioritizedNetworkError))
    }

    func testAbsentBatteryFallsThroughToEnabledBluetoothReplacement() throws {
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
        let bluetoothReplacement = BluetoothAudioIconOptions(replacesNetworkIcon: true)

        let enabledWithBatterySlot = try renderedPixels(
            snapshot,
            showsBatteryPercentageInConnectionSlot: true,
            bluetoothOptions: bluetoothReplacement
        )
        let enabledWithoutBatterySlot = try renderedPixels(
            snapshot,
            bluetoothOptions: bluetoothReplacement
        )
        let standardNetwork = try renderedPixels(
            snapshot,
            showsBatteryPercentageInConnectionSlot: true
        )

        XCTAssertEqual(
            centerSlotPixels(enabledWithBatterySlot),
            centerSlotPixels(enabledWithoutBatterySlot)
        )
        XCTAssertNotEqual(centerSlotPixels(enabledWithBatterySlot), centerSlotPixels(standardNetwork))
    }

    private func renderedPixels(
        _ snapshot: StatusSnapshot,
        showsBatteryPercentageInConnectionSlot: Bool = false,
        bluetoothOptions: BluetoothAudioIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(renderMenuBarFixture(
                snapshot: snapshot,
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            connectionOptions: ConnectionIconOptions(
                showsBatteryPercentageInConnectionSlot: showsBatteryPercentageInConnectionSlot
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
