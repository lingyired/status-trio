import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// The arc's top gap carries the charging bolt, or a plug while the Mac is on
/// power without charging. Menu bar and Dock share the renderer, so both are
/// asserted here.
@MainActor
final class ConnectedPowerPlugIndicatorTests: XCTestCase {
    private let glyphRegion = CGRect(x: 45, y: 0, width: 30, height: 30)
    private let arcRegion = CGRect(x: 0, y: 40, width: 120, height: 80)

    func testMenuBarIconDrawsAPlugForConnectedPower() throws {
        let plug = try menuBarPixels(for: connectedBattery())
        let bolt = try menuBarPixels(for: chargingBattery())

        XCTAssertGreaterThan(plug.alphaSum(inSVGRect: glyphRegion, size: 20, scale: 8), 0)
        XCTAssertNotEqual(
            plug.bytes,
            bolt.bytes,
            "connected power must not fall back to the charging bolt"
        )
    }

    func testChargingAndConnectedPowerShareTheSameArc() throws {
        let plug = try menuBarPixels(for: connectedBattery())
        let bolt = try menuBarPixels(for: chargingBattery())

        // Everything outside the top gap stays pixel-identical, so the arc does
        // not shift when the Mac starts or stops charging.
        XCTAssertEqual(
            plug.alphaSum(inSVGRect: arcRegion, size: 20, scale: 8),
            bolt.alphaSum(inSVGRect: arcRegion, size: 20, scale: 8)
        )
    }

    func testPlugGlyphIsNarrowerThanTheBolt() throws {
        let plug = try XCTUnwrap(topGapInk(in: try menuBarPixels(for: connectedBattery())))
        let bolt = try XCTUnwrap(topGapInk(in: try menuBarPixels(for: chargingBattery())))

        XCTAssertLessThan(plug.width, bolt.width)
    }

    func testMenuBarIconDropsTheIndicatorWhenItIsDisabled() throws {
        let hidden = try menuBarPixels(
            for: connectedBattery(),
            options: BatteryIconOptions(
                showsPercentage: true,
                showsChargingIndicator: false,
                usesStatusColors: true,
                criticalThreshold: 20
            )
        )

        XCTAssertNotEqual(hidden.bytes, try menuBarPixels(for: connectedBattery()).bytes)
    }

    func testPlugGlyphIsNotSmallerThanTheBolt() throws {
        let plug = try XCTUnwrap(topGapInk(in: try menuBarPixels(for: connectedBattery())))
        let bolt = try XCTUnwrap(topGapInk(in: try menuBarPixels(for: chargingBattery())))

        XCTAssertGreaterThan(
            plug.height,
            bolt.height,
            "the plug reads smaller than the bolt because its strokes are thinner"
        )
    }

    func testPlugGlyphStaysInsideTheTopGap() throws {
        let plug = try XCTUnwrap(topGapInk(in: try menuBarPixels(for: connectedBattery())))

        XCTAssertGreaterThan(plug.minY, 0, "the plug must not clip at the top of the bitmap")
        XCTAssertLessThan(plug.maxY, 54, "the plug must stay clear of the Wi-Fi glyph")
        XCTAssertGreaterThan(plug.minX, 56, "the plug must stay clear of the arc")
        XCTAssertLessThan(plug.maxX, 104, "the plug must stay clear of the arc")
    }

    func testConnectedPowerShowsThePercentageWhenEnabled() throws {
        let plug = try menuBarPixels(for: connectedBattery())
        let percentage = try menuBarPixels(
            for: connectedBattery(),
            options: BatteryIconOptions(
                showsPercentage: true,
                showsChargingIndicator: true,
                usesStatusColors: true,
                criticalThreshold: 20,
                showsPercentageWhenConnected: true
            )
        )
        let onBattery = try menuBarPixels(for: onBatteryBattery())

        XCTAssertNotEqual(percentage.bytes, plug.bytes)
        XCTAssertEqual(
            percentage.alphaSum(inSVGRect: glyphRegion, size: 20, scale: 8),
            onBattery.alphaSum(inSVGRect: glyphRegion, size: 20, scale: 8),
            "the connected percentage must use the same numerals as the on-battery one"
        )
    }

    func testDockIconDrawsThePlugForConnectedPower() throws {
        let plug = try dockPixels(for: MenuBarStatus(snapshot: snapshot(for: connectedBattery())))
        let bolt = try dockPixels(for: MenuBarStatus(snapshot: snapshot(for: chargingBattery())))

        XCTAssertNotEqual(plug.bytes, bolt.bytes)
    }

    func testDockRenderKeyDistinguishesChargingFromConnectedPower() {
        let charging = DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: MenuBarStatus(snapshot: snapshot(for: chargingBattery()))
            ),
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )
        let connected = DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: MenuBarStatus(snapshot: snapshot(for: connectedBattery()))
            ),
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )

        guard case let .symbol(chargingSymbol)? = charging.scene.outerRing?.accessory,
              case let .symbol(connectedSymbol)? = connected.scene.outerRing?.accessory else {
            XCTFail("Expected charging accessories in both scenes.")
            return
        }
        XCTAssertEqual(chargingSymbol.source, .primitive(.bolt))
        XCTAssertEqual(connectedSymbol.source, .primitive(.plug))
    }

    private func connectedBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func chargingBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func onBatteryBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private func snapshot(for battery: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: .placeholder, volume: .placeholder)
    }

    private struct InkBounds {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int

        var height: Int { maxY - minY + 1 }
        var width: Int { maxX - minX + 1 }
    }

    /// Ink of the top-gap glyph alone: the window sits inside the arc's gap and
    /// above the Wi-Fi glyph drawn inside the arc.
    private func topGapInk(in pixels: PixelBuffer) -> InkBounds? {
        var points: [(x: Int, y: Int)] = []
        for y in 0..<min(54, pixels.height) {
            for x in 56..<min(104, pixels.width) where pixels.rgba(x: x, y: y).alpha > 120 {
                points.append((x, y))
            }
        }
        guard let first = points.first else { return nil }

        return points.dropFirst().reduce(
            InkBounds(minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { bounds, point in
            InkBounds(
                minX: min(bounds.minX, point.x),
                maxX: max(bounds.maxX, point.x),
                minY: min(bounds.minY, point.y),
                maxY: max(bounds.maxY, point.y)
            )
        }
    }

    private func menuBarPixels(
        for battery: BatteryStatus,
        options: BatteryIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(renderMenuBarFixture(
                snapshot: snapshot(for: battery),
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            options: options
        ))
        return try PixelBuffer(image: image)
    }

    private func dockPixels(
        for status: MenuBarStatus,
        options: BatteryIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(renderDockFixture(
                status: status,
            options: options,
            backgroundStyle: .dark
        ))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try XCTUnwrap(representation.cgImage))
    }
}
