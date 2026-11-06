import XCTest
@testable import StatusTrioCore

/// Writes the text-free, one-line Dock icon strip used for visual sharing.
///
/// ```bash
/// STATUS_TRIO_DOCK_STATE_STRIP=/tmp/status-trio-dock-state-strip.png \
///   swift test --filter DockIconStateStripTests
/// ```
@MainActor
final class DockIconStateStripTests: XCTestCase {
    func testSymmetricStripReordersOnlyBackgroundStyles() {
        let originalStates = DockIconStateStrip.states
        let symmetricStates = DockIconStateStrip.symmetricStates

        XCTAssertEqual(symmetricStates.map(\.backgroundStyle), [.dark, .light, .dark, .light, .light, .dark, .light, .dark])
        XCTAssertEqual(symmetricStates.map(\.status), originalStates.map(\.status))
        XCTAssertEqual(symmetricStates.map(\.batteryOptions), originalStates.map(\.batteryOptions))
        XCTAssertEqual(symmetricStates.map(\.connectionOptions), originalStates.map(\.connectionOptions))
        XCTAssertEqual(symmetricStates.map(\.volumeOptions), originalStates.map(\.volumeOptions))
        XCTAssertEqual(symmetricStates.map(\.bluetoothAudioOptions), originalStates.map(\.bluetoothAudioOptions))
        XCTAssertEqual(symmetricStates.map(\.inputSource), originalStates.map(\.inputSource))
        XCTAssertEqual(symmetricStates.map(\.systemPower), originalStates.map(\.systemPower))
    }

    func testStripHasEightAlternatingBackgroundStates() {
        let states = DockIconStateStrip.states

        XCTAssertEqual(states.count, 8)
        XCTAssertEqual(
            states.map(\.backgroundStyle),
            [.dark, .light, .dark, .light, .dark, .light, .dark, .light]
        )
        XCTAssertEqual(
            DockIconStateStrip.symmetricStates.map(\.backgroundStyle),
            [.dark, .light, .dark, .light, .light, .dark, .light, .dark]
        )
        XCTAssertEqual(
            states.map(\.volumeStyle),
            [.dots, .arc, .dots, .dots, .arc, .arc, .dots, .dots]
        )
        XCTAssertEqual(states.filter(\.usesBluetoothAudio).count, 1)
        XCTAssertTrue(states[5].usesBluetoothVolumeColor)
    }

    func testStripCoversNewMiddleIconSources() {
        let states = DockIconStateStrip.states

        XCTAssertEqual(
            states.map(\.connectionOptions.centerSource),
            [.network, .power, .inputSource, .chargingStatus, .network, .bluetoothDevice, .network, .network]
        )
        XCTAssertEqual(states[1].systemPower?.watts, 23.6)
        XCTAssertTrue(states[1].status.battery.isCharging)
        XCTAssertEqual(states[2].inputSource?.shortLabel, "拼")
        XCTAssertEqual(states[4].batteryOptions.connectedIndicator, .percentage)
        XCTAssertTrue(states[3].status.battery.isCharging)
    }

    func testWritesLandscapeStripWithoutText() throws {
        let data = try DockIconStateStrip.pngData(scale: 1)
        XCTAssertGreaterThan(data.count, 10_000)

        let image = try XCTUnwrap(NSImage(data: data))
        XCTAssertGreaterThan(image.size.width, image.size.height * 4)
    }

    func testWritesSymmetricOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_DOCK_STATE_STRIP_SYMMETRIC"] else {
            throw XCTSkip("Set STATUS_TRIO_DOCK_STATE_STRIP_SYMMETRIC to write the symmetric Dock state strip.")
        }

        let data = try DockIconStateStrip.pngData(
            for: DockIconStateStrip.symmetricStates,
            cornerRadius: 18
        )
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }

    func testRoundedOutputHasTransparentCorners() throws {
        let data = try DockIconStateStrip.pngData(
            for: DockIconStateStrip.symmetricStates,
            scale: 1,
            cornerRadius: 18
        )
        let image = try XCTUnwrap(NSImage(data: data))
        var proposed = CGRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        let bitmapData = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        let alphaAt: (Int, Int) -> UInt8 = { x, y in
            let bytesPerPixel = cgImage.bitsPerPixel / 8
            return bitmapData[y * cgImage.bytesPerRow + x * bytesPerPixel + 3]
        }

        XCTAssertTrue(cgImage.alphaInfo == .last || cgImage.alphaInfo == .premultipliedLast)
        XCTAssertEqual(alphaAt(0, 0), 0)
        XCTAssertGreaterThan(alphaAt(cgImage.width / 2, cgImage.height / 2), 0)
    }

    func testWritesRequestedOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_DOCK_STATE_STRIP"] else {
            throw XCTSkip("Set STATUS_TRIO_DOCK_STATE_STRIP to write the Dock state strip.")
        }

        let data = try DockIconStateStrip.pngData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
