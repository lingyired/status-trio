import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// Geometry at the logical sizes a real status item uses (16–36 pt), rendered at
/// a high raster scale so the assertion measures the *vector* centre rather than
/// display-pixel quantisation. The legacy #30 tests render the 120 pt canvas and
/// never exercise the small logical sizes where a size-dependent symbol scale
/// error would hide; and they render at scale 8, where a half-unit error is
/// invisible. These run at scale 8 too, but across the real 16–36 pt range and
/// with the ring/circle-centre contract measured independently from the glyph.
///
/// Real display-pixel behaviour at 1×/2× (anti-aliasing and whole/half pixel
/// placement) is measured from actual Agent Desktop screenshots, not here: at a
/// 22 pt item one physical pixel is 0.5 pt and bbox-midpoint noise from 2 px
/// strokes reaches a whole pixel, so a deterministic unit assertion at that
/// resolution would be dishonest. See `docs/issue-30-alignment-verification.md`.
@MainActor
final class StatusBarIconLayoutTests: XCTestCase {

    /// Real menu-bar icon sizes in points.
    private let sizes: [CGFloat] = [16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36]
    /// High raster scale: measures the vector centre, not the 1×/2× pixel grid.
    private let rasterScale: CGFloat = 8

    private struct InkBounds {
        let minX: Int
        let maxX: Int
        let midPx: Double
        let width: Int
        /// Centre expressed as a fraction of the image width (0…1).
        var midFraction: Double { midPx / Double(width) }
    }

    /// Horizontal ink extent at high resolution. A low alpha threshold keeps the
    /// faint full-circle ring track so the ring bounds span the whole circle; a
    /// high threshold would drop the track and leave only the partial progress
    /// arc, biasing the midpoint. Near-transparent fringe (< 16/255) is ignored.
    private func inkBounds(_ image: CGImage) throws -> InkBounds {
        let pixels = try PixelBuffer(image: image)
        var minX = pixels.width
        var maxX = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgba(x: x, y: y).alpha > 16 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        XCTAssertLessThanOrEqual(minX, maxX, "expected at least one ink column")
        return InkBounds(
            minX: minX,
            maxX: maxX,
            midPx: (Double(minX) + Double(maxX) + 1) / 2,
            width: pixels.width
        )
    }

    private func renderRingOnly(size: CGFloat) -> CGImage? {
        let ring = OuterRingState(
            segments: [RingSegmentState(progress: 0.62, color: .primary)],
            gap: .closed
        )
        return StatusIconRenderer.render(
            scene: IconSceneState(outerRing: ring),
            environment: StatusIconRenderEnvironment(
                size: size,
                scale: rasterScale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        )
    }

    private func renderSymbolOnly(
        size: CGFloat,
        name: String = "wifi",
        variableValue: Double = 1.0
    ) -> CGImage? {
        let symbol = IconSymbolState(
            source: .symbol(name: name, variableValue: variableValue, fallback: nil),
            color: .primary,
            scale: 1.0
        )
        return StatusIconRenderer.render(
            scene: IconSceneState(center: .symbol(symbol)),
            environment: StatusIconRenderEnvironment(
                size: size,
                scale: rasterScale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        )
    }

    /// The centre glyph's ink must land on the ring's geometric centre at every
    /// real menu-bar size. Tolerance is 0.5 physical px at scale 8, i.e. 0.0625
    /// pt — far stricter than the display-pixel contract, so this catches a
    /// size-dependent drift that a 120 pt test would miss.
    /// Vector contract at high resolution, tolerance expressed in *points* so it
    /// matches "half a physical pixel at 2x" = 0.25 pt regardless of the raster
    /// scale (0.5 px at scale 8 would be an unrealistic 0.0625 pt).
    private func assertWithinQuarterPoint(_ px: Double, _ message: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let pt = px / Double(rasterScale)
        XCTAssertLessThanOrEqual(abs(pt), 0.25 + 1e-9, "\(message) = \(pt) pt", file: file, line: line)
    }

    func testSymbolInkLandsOnRingCentreAtEveryRealSize() throws {
        for size in sizes {
            let delta = try inkBounds(XCTUnwrap(renderSymbolOnly(size: size))).midPx
                - inkBounds(XCTUnwrap(renderRingOnly(size: size))).midPx
            print(String(format: "VEC-ALIGN size=%4.1f symMid-ringMid=%+.2f px", size, delta))
            assertWithinQuarterPoint(delta, "size \(size) glyph vs ring")
        }
    }

    func testRingSitsOnArtworkCentreAtEveryRealSize() throws {
        for size in sizes {
            let ring = try inkBounds(XCTUnwrap(renderRingOnly(size: size)))
            let expected = StatusIconGeometry.artworkCenterX / StatusIconGeometry.canvas.width * Double(ring.width)
            assertWithinQuarterPoint(ring.midPx - expected, "size \(size) ring vs artwork centre")
        }
    }

    func testSymbolOffsetDoesNotGrowWithIconSize() throws {
        func delta(_ size: CGFloat) throws -> Double {
            try inkBounds(XCTUnwrap(renderSymbolOnly(size: size))).midPx
                - inkBounds(XCTUnwrap(renderRingOnly(size: size))).midPx
        }
        assertWithinQuarterPoint(try delta(36) - delta(16), "offset growth 16->36 pt")
    }

    private func renderMenuBarOnly(size: CGFloat, scale: CGFloat, center: Bool) -> CGImage? {
        let scene: IconSceneState
        if center {
            let symbol = IconSymbolState(
                source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1.6)
            scene = IconSceneState(center: .symbol(symbol))
        } else {
            let ring = OuterRingState(segments: [RingSegmentState(progress: 1, color: .powered)], gap: .closed)
            scene = IconSceneState(outerRing: ring)
        }
        return StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: size, scale: scale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor,
                supersample: 2))
    }

    private func alphaCentroidX(_ image: CGImage) throws -> Double {
        let pixels = try PixelBuffer(image: image)
        var weight = 0.0
        var sumX = 0.0
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let a = Double(pixels.rgba(x: x, y: y).alpha)
                if a > 0 { weight += a; sumX += a * (Double(x) + 0.5) }
            }
        }
        return weight > 0 ? sumX / weight : 0
    }
}
