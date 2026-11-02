import XCTest
@testable import StatusTrioCore

/// Writes the Dock icon sheet used by the READMEs.
///
/// Skipped unless an output path is provided, so CI never writes files:
///
/// ```bash
/// STATUS_TRIO_DOCK_SHEET=/tmp/status-trio-dock-icons.png \
///   swift test --filter DockIconSheetTests
/// ```
@MainActor
final class DockIconSheetTests: XCTestCase {
    func testWritesDockIconSheet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_DOCK_SHEET"] else {
            throw XCTSkip("Set STATUS_TRIO_DOCK_SHEET to write the Dock icon sheet.")
        }

        let data = try DockIconSheet.pngData()
        XCTAssertGreaterThan(data.count, 10_000)
        try data.write(to: URL(fileURLWithPath: outputPath))
        print("Wrote \(data.count) bytes to \(outputPath)")
    }

    func testSheetCoversEveryBackgroundStyle() {
        XCTAssertEqual(DockIconSheet.variants.map(\.style), [.dark, .light, .clear])
        XCTAssertEqual(DockIconSheet.variants.map(\.zh), ["深色背景", "浅色背景", "透明背景"])
    }

    func testSheetCoversWiFiAndBluetoothRows() {
        let rows = DockIconSheet.rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.zh), ["Wi-Fi 状态", "蓝牙音频取代 Wi-Fi 图标"])
        XCTAssertEqual(rows[0].bluetoothAudioOptions, .standard)
        XCTAssertEqual(rows[1].connectionOptions.centerSource, .bluetoothDevice)
        XCTAssertTrue(rows[1].bluetoothAudioOptions.usesVolumeColor)
        XCTAssertEqual(rows[0].status.volume.currentDevice, nil)
        XCTAssertEqual(rows[1].status.volume.currentDevice, SheetFixtures.bluetoothDevice)
        for row in rows {
            XCTAssertFalse(row.zh.isEmpty)
            XCTAssertFalse(row.en.isEmpty)
        }
    }
}
