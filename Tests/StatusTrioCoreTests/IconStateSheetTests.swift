import XCTest
@testable import StatusTrioCore

/// Writes the icon state sheet used by the READMEs.
///
/// The test is skipped unless an output path is provided, so CI never writes
/// files:
///
/// ```bash
/// STATUS_TRIO_ICON_SHEET=/tmp/status-trio-icon-states.png \
/// STATUS_TRIO_ICON_SHEET_DARK=/tmp/status-trio-icon-states-dark.png \
///   swift test --filter IconStateSheetTests
/// ```
@MainActor
final class IconStateSheetTests: XCTestCase {
    func testMenuBarArtifactFixtureUsesResolvedAirPodsSymbol() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: SheetFixtures.bluetoothDevice.name,
                currentDevice: SheetFixtures.bluetoothDevice
            )
        )
        let status = MenuBarStatus(snapshot: snapshot)
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(replacesNetworkIcon: true)
        )
        let resolvedInputs = IconPresentationResourceResolver.inputs(snapshot: snapshot)
        let canonicalScene = IconPresentationMapper.scene(inputs: resolvedInputs, configuration: configuration)
        guard case let .symbol(resolvedSymbol)? = canonicalScene.center else {
            return XCTFail("Bluetooth replacement must resolve the artifact center glyph")
        }
        XCTAssertEqual(
            resolvedSymbol.source,
            .symbol(name: "airpods.pro", variableValue: nil, fallback: "headphones")
        )

        let artifact = try XCTUnwrap(renderMenuBarFixture(
            menuBarStatus: status,
            size: 28,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            bluetoothAudioOptions: configuration.bluetooth
        ))
        let expected = try XCTUnwrap(StatusIconRenderer.render(
            scene: canonicalScene,
            environment: StatusIconRenderEnvironment(
                size: 28,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))
        XCTAssertEqual(try PixelBuffer(image: artifact).bytes, try PixelBuffer(image: expected).bytes)

        guard NSImage(systemSymbolName: "airpods.pro", accessibilityDescription: nil) != nil else {
            throw XCTSkip("This macOS release does not provide the AirPods Pro symbol")
        }
        let genericScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: configuration
        )
        let generic = try XCTUnwrap(StatusIconRenderer.render(
            scene: genericScene,
            environment: StatusIconRenderEnvironment(
                size: 28,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))
        XCTAssertNotEqual(try PixelBuffer(image: artifact).bytes, try PixelBuffer(image: generic).bytes)
    }

    func testWritesIconStateSheet() throws {
        let environment = ProcessInfo.processInfo.environment
        let targets = [
            (environment["STATUS_TRIO_ICON_SHEET"], IconStateSheet.Appearance.light),
            (environment["STATUS_TRIO_ICON_SHEET_DARK"], IconStateSheet.Appearance.dark)
        ]

        let requested = targets.compactMap { path, appearance in
            path.map { ($0, appearance) }
        }

        guard !requested.isEmpty else {
            throw XCTSkip("Set STATUS_TRIO_ICON_SHEET or STATUS_TRIO_ICON_SHEET_DARK.")
        }

        for (outputPath, appearance) in requested {
            let data = try IconStateSheet.pngData(appearance: appearance)
            XCTAssertGreaterThan(data.count, 10_000)
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("Wrote \(data.count) bytes to \(outputPath)")
        }
    }

    func testSheetCoversEachZone() {
        let sections = IconStateSheet.sections
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(
            sections.map(\.zh),
            ["电池（顶部）", "Wi-Fi（中部）", "蓝牙音频（中部与底部）", "音量（底部）"]
        )
        XCTAssertEqual(sections.map(\.zone).count, 4)
        for section in sections {
            XCTAssertGreaterThanOrEqual(section.entries.count, 6, section.zh)
            for entry in section.entries {
                XCTAssertFalse(entry.zh.isEmpty)
                XCTAssertFalse(entry.en.isEmpty)
            }
        }
    }
}
