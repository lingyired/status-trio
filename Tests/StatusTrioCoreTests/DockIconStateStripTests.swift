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
    }

    func testStripHasEightAlternatingBackgroundStates() {
        let states = DockIconStateStrip.states

        XCTAssertEqual(states.count, 8)
        XCTAssertEqual(
            states.map(\.backgroundStyle),
            [.dark, .light, .dark, .light, .dark, .light, .dark, .light]
        )
        XCTAssertEqual(
            states.map(\.volumeStyle),
            [.dots, .arc, .dots, .dots, .dots, .arc, .dots, .arc]
        )
        XCTAssertEqual(states.filter(\.usesBluetoothAudio).count, 3)
        XCTAssertTrue(states[5].usesBluetoothVolumeColor)
        XCTAssertTrue(states[6].usesBluetoothVolumeColor)
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

    func testTwoRowDesignStripHasEightPerRowAndFourEachAppearance() throws {
        let rows = DockIconStateStrip.twoRowTiles

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.count == 8 }, "Every row must hold eight tiles")
        XCTAssertEqual(
            rows.map { $0.filter { $0.backgroundStyle == .dark }.count },
            [4, 4]
        )
        XCTAssertEqual(
            rows.map { $0.filter { $0.backgroundStyle == .light }.count },
            [4, 4]
        )

        let data = try DockIconStateStrip.twoRowPNGData(scale: 1)
        XCTAssertGreaterThan(data.count, 10_000)
    }

    func testWritesTwoRowOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_DOCK_STATE_STRIP_TWOROW"] else {
            throw XCTSkip("Set STATUS_TRIO_DOCK_STATE_STRIP_TWOROW to write the two-row Dock state strip.")
        }

        let data = try DockIconStateStrip.twoRowPNGData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
