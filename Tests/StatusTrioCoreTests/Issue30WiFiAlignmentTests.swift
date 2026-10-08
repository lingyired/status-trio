import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// Regression coverage for #30: the Wi-Fi glyph must be centred on the
/// artwork's centre line, not on the canvas midpoint.
///
/// History: the first fix for #30 replaced a hardcoded `59.5` with
/// `StatusIconGeometry.canvas.midX`, which is `60.0`. That moved every SF
/// Symbol half a unit right of the hand-drawn art. The original test could not
/// catch it: it measured a window that also contained the hand-drawn Wi-Fi dot
/// (centred at 59.5), so the two errors partly cancelled, and its tolerance
/// (0.45) was the same order as the defect (0.5).
///
/// Rasterised measurement turned out to be too coarse to pin a half-unit
/// offset — the Wi-Fi dot and the arcs dominate any band the symbol also
/// occupies. The tests below therefore assert the geometry contract directly,
/// and use rasterisation only for the coarse "is it in the middle" check.
@MainActor
final class Issue30WiFiAlignmentTests: XCTestCase {
    /// The shipped default scale, plus both ends of the range users can pick.
    private let scales: [Double] = [1.0, 1.6, 1.8]

    /// `artworkCenterX` is the artwork's true centre — the SVG battery arc runs
    /// from `x = 15.5` to `x = 103.5`, so its midpoint is 59.5. It must not be
    /// the canvas midpoint, which is 60.0 and is the #30 defect.
    func testArtworkCenterIsTheSVGMidpointNotTheCanvasMidpoint() {
        XCTAssertEqual(StatusIconGeometry.artworkCenterX, 59.5, accuracy: 0.0001)
        XCTAssertEqual(StatusIconGeometry.canvas.midX, 60.0, accuracy: 0.0001)
        XCTAssertNotEqual(
            StatusIconGeometry.canvas.midX,
            StatusIconGeometry.artworkCenterX,
            "canvas.midX is 60.0; anchoring to it is the #30 defect"
        )
    }

    /// Every hand-drawn element must share the one centre line. This is the
    /// contract the first fix broke, and it is exact rather than rasterised.
    func testHandDrawnElementsShareTheArtworkCenterLine() {
        let center = StatusIconGeometry.artworkCenterX

        XCTAssertEqual(
            StatusIconGeometry.batteryValueBaseline(fontSize: 20).x,
            center,
            accuracy: 0.0001,
            "battery value baseline"
        )
        XCTAssertEqual(
            StatusIconGeometry.batteryChargingBoltPivot.x,
            center,
            accuracy: 0.0001,
            "charging bolt pivot"
        )
        XCTAssertEqual(
            StatusIconGeometry.wifiOuterArc().boundingBoxOfPath.midX,
            center,
            accuracy: 0.01,
            "hand-drawn Wi-Fi outer arc"
        )
        XCTAssertEqual(
            StatusIconGeometry.wifiDot().boundingBoxOfPath.midX,
            center,
            accuracy: 0.01,
            "hand-drawn Wi-Fi dot"
        )
        XCTAssertEqual(
            StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.midX,
            center,
            accuracy: 0.6,
            "charging bolt body"
        )
    }

    /// Full-composite check: with the battery and volume also drawn, the Wi-Fi
    /// glyph still lands on the artwork centre.
    func testWiFiGlyphIsHorizontallyCenteredInMenuBarIcon() throws {
        for scale in scales {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -50),
                volume: .placeholder
            )
            let image = try XCTUnwrap(renderMenuBarFixture(
                snapshot: snapshot,
                size: 120,
                scale: 4,
                foreground: CGColor(gray: 1, alpha: 1),
                connectionOptions: ConnectionIconOptions(wifiScale: scale)
            ))
            let pixels = try PixelBuffer(image: image)
            let visibleCenterX = try XCTUnwrap(
                pixels.horizontalAlphaCenter(
                    inSVGRect: CGRect(x: 30, y: 40, width: 60, height: 38),
                    size: 120,
                    scale: 4
                )
            )

            XCTAssertEqual(
                visibleCenterX,
                StatusIconGeometry.artworkCenterX,
                accuracy: 0.45,
                "Wi-Fi ink should be centered on the artwork at wifiScale \(scale)"
            )
        }
    }

}

private extension PixelBuffer {
    func horizontalAlphaCenter(
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> CGFloat? {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * pixelsPerSVGUnit).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * pixelsPerSVGUnit).rounded(.up)))
        let minY = max(0, Int((rect.minY * pixelsPerSVGUnit).rounded(.down)))
        let maxY = min(height, Int((rect.maxY * pixelsPerSVGUnit).rounded(.up)))

        guard minX < maxX, minY < maxY else { return nil }

        var weightedX = 0.0
        var totalAlpha = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let alpha = Double(rgba(x: x, y: y).alpha)
                guard alpha > 0 else { continue }
                weightedX += (Double(x) + 0.5) / Double(pixelsPerSVGUnit) * alpha
                totalAlpha += alpha
            }
        }

        guard totalAlpha > 0 else { return nil }
        return CGFloat(weightedX / totalAlpha)
    }
}
