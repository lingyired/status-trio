import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// Regression for the faint rectangle that framed the centre artwork.
///
/// `drawNormalizedArtwork` tinted its artwork by filling the artwork's own
/// fractional bounding rect and then masking the artwork over it with
/// `destinationIn`. Both the fill and the image draw are antialiased at that
/// rect, and the product of the two partial coverages survived as a one-pixel
/// rectangle outline on the artwork's bounding box — visible even on rows the
/// artwork does not ink. The outline framed every normalized centre source
/// (Wi-Fi, text, Bluetooth) on the menu bar and the Dock.
///
/// The fix tints the artwork through a clip mask instead of a co-located fill,
/// so the artwork's bounding rect is no longer drawn as a shape in its own
/// right. These tests pin the outline away and pin the ink (including its
/// antialiased edges) in place.
@MainActor
final class IconCenterArtworkEdgeFringeTests: XCTestCase {
    private let strongInkAlpha: UInt8 = 120

    /// The reported defect: the artwork's own bounding rectangle left a faint
    /// one-pixel outline, so rows (or columns) the artwork does not ink were not
    /// transparent at the bounding box's edges.
    func testCenterArtworkBoundingBoxHasNoInkFreeFringe() throws {
        var observedInkFreeEdge = false
        for percentage in [100.0, 150.0] {
            for center in Self.centerSources {
                let measured = try measure(center: center, percentage: percentage)
                observedInkFreeEdge = observedInkFreeEdge
                    || !measured.inkFreeEdgeRows.isEmpty
                    || !measured.inkFreeEdgeColumns.isEmpty
                for row in measured.inkFreeEdgeRows {
                    XCTAssertEqual(
                        measured.buffer.rgba(x: measured.inkBounds.minX, y: row).alpha, 0,
                        "\(measured.label) at \(percentage)% leaves a fringe on the left edge at y=\(row)"
                    )
                    XCTAssertEqual(
                        measured.buffer.rgba(x: measured.inkBounds.maxX, y: row).alpha, 0,
                        "\(measured.label) at \(percentage)% leaves a fringe on the right edge at y=\(row)"
                    )
                }
                for column in measured.inkFreeEdgeColumns {
                    XCTAssertEqual(
                        measured.buffer.rgba(x: column, y: measured.inkBounds.minY).alpha, 0,
                        "\(measured.label) at \(percentage)% leaves a fringe on the top edge at x=\(column)"
                    )
                    XCTAssertEqual(
                        measured.buffer.rgba(x: column, y: measured.inkBounds.maxY).alpha, 0,
                        "\(measured.label) at \(percentage)% leaves a fringe on the bottom edge at x=\(column)"
                    )
                }
            }
        }
        XCTAssertTrue(
            observedInkFreeEdge,
            "no source drew an ink-free row or column, so the fringe check proved nothing"
        )
    }

    /// Source-agnostic form of the same invariant: the artwork must not paint
    /// faint ink far from its own solid ink. Antialiased edges sit on top of
    /// solid ink; the outline did not.
    func testCenterArtworkHasNoStrayFaintPixels() throws {
        for percentage in [100.0, 150.0] {
            for center in Self.centerSources {
                let measured = try measure(center: center, percentage: percentage)
                XCTAssertEqual(
                    measured.strayFaintPixelCount, 0,
                    "\(measured.label) at \(percentage)% paints faint ink away from its outline"
                )
            }
        }
    }

    /// The fix must not shrink, clip, or harden the artwork: its ink still
    /// reaches all four sides of its own bounding box and keeps antialiased
    /// edges.
    func testCenterArtworkInkIsPreserved() throws {
        for percentage in [100.0, 150.0] {
            for center in Self.centerSources {
                let measured = try measure(center: center, percentage: percentage)
                let bounds = measured.inkBounds
                XCTAssertTrue(
                    bounds.hasStrongInkOnLeftEdge(in: measured.buffer, threshold: strongInkAlpha),
                    "\(measured.label) at \(percentage)% lost strong ink on its left extreme"
                )
                XCTAssertTrue(
                    bounds.hasStrongInkOnRightEdge(in: measured.buffer, threshold: strongInkAlpha),
                    "\(measured.label) at \(percentage)% lost strong ink on its left/right extremes"
                )
                XCTAssertTrue(
                    bounds.hasStrongInkOnTopEdge(in: measured.buffer, threshold: strongInkAlpha),
                    "\(measured.label) at \(percentage)% lost strong ink on its top extreme"
                )
                XCTAssertTrue(
                    bounds.hasStrongInkOnBottomEdge(in: measured.buffer, threshold: strongInkAlpha),
                    "\(measured.label) at \(percentage)% lost strong ink on its top/bottom extremes"
                )
                XCTAssertGreaterThan(
                    measured.antialiasedPixelCount, 0,
                    "\(measured.label) at \(percentage)% lost its antialiased edges"
                )
            }
        }
    }

    // MARK: - Helpers

    private struct Measured {
        let label: String
        let buffer: PixelBuffer
        let inkBounds: InkBounds
        let inkFreeEdgeRows: [Int]
        let inkFreeEdgeColumns: [Int]
        let antialiasedPixelCount: Int
        let strayFaintPixelCount: Int
    }

    private struct InkBounds {
        let minX: Int, minY: Int, maxX: Int, maxY: Int

        func hasStrongInkOnLeftEdge(in buffer: PixelBuffer, threshold: UInt8) -> Bool {
            (minY...maxY).contains { y in buffer.rgba(x: minX, y: y).alpha >= threshold }
        }

        func hasStrongInkOnRightEdge(in buffer: PixelBuffer, threshold: UInt8) -> Bool {
            (minY...maxY).contains { y in buffer.rgba(x: maxX, y: y).alpha >= threshold }
        }

        func hasStrongInkOnTopEdge(in buffer: PixelBuffer, threshold: UInt8) -> Bool {
            (minX...maxX).contains { x in buffer.rgba(x: x, y: minY).alpha >= threshold }
        }

        func hasStrongInkOnBottomEdge(in buffer: PixelBuffer, threshold: UInt8) -> Bool {
            (minX...maxX).contains { x in buffer.rgba(x: x, y: maxY).alpha >= threshold }
        }
    }

    private func measure(center: CenterState, percentage: Double) throws -> Measured {
        let sizedCenter = Self.applying(percentage: percentage, to: center)
        let size: CGFloat = 120
        let scale: CGFloat = 4
        let image = try XCTUnwrap(StatusIconRenderer.render(
            scene: IconSceneState(center: sizedCenter),
            environment: StatusIconRenderEnvironment(
                size: size, scale: scale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))
        let buffer = try PixelBuffer(image: image)

        var minX = buffer.width, minY = buffer.height, maxX = -1, maxY = -1
        var antialiased = 0
        var strong = [[Bool]](
            repeating: [Bool](repeating: false, count: buffer.width),
            count: buffer.height
        )
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let alpha = buffer.rgba(x: x, y: y).alpha
                if alpha >= strongInkAlpha {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                    strong[y][x] = true
                } else if alpha > 0 && alpha < 240 {
                    antialiased += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX, "the centre artwork drew no ink")

        // Rows and columns inside the bounding box that the artwork does not
        // ink. At the box's edge the only possible pixel there is the outline.
        let inkFreeRows = (minY...maxY).filter { y in
            !(minX...maxX).contains { x in strong[y][x] }
        }
        let inkFreeColumns = (minX...maxX).filter { x in
            !(minY...maxY).contains { y in strong[y][x] }
        }

        // Faint pixels separated from every solid-ink pixel by more than the
        // antialiasing ramp that legitimately hugs the glyph.
        let ramp = 2
        var stray = 0
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let alpha = buffer.rgba(x: x, y: y).alpha
                guard alpha > 0, alpha < strongInkAlpha else { continue }
                var nearStrongInk = false
                for ny in max(0, y - ramp)...min(buffer.height - 1, y + ramp) where !nearStrongInk {
                    for nx in max(0, x - ramp)...min(buffer.width - 1, x + ramp) where strong[ny][nx] {
                        nearStrongInk = true
                        break
                    }
                }
                if !nearStrongInk { stray += 1 }
            }
        }

        return Measured(
            label: Self.label(for: sizedCenter),
            buffer: buffer,
            inkBounds: InkBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
            inkFreeEdgeRows: inkFreeRows,
            inkFreeEdgeColumns: inkFreeColumns,
            antialiasedPixelCount: antialiased,
            strayFaintPixelCount: stray
        )
    }

    private static let centerSources: [CenterState] = [
        .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil),
            color: .primary, scale: 1, normalizedSizePercentage: 100
        )),
        .symbol(IconSymbolState(
            source: .symbol(name: "headphones", variableValue: nil, fallback: nil),
            color: .primary, scale: 1, normalizedSizePercentage: 100
        )),
        .text(IconTextState(text: "100", color: .primary, scale: 1, normalizedSizePercentage: 100)),
    ]

    private static func label(for center: CenterState) -> String {
        switch center {
        case let .symbol(symbol): return "symbol \(symbol.source)"
        case let .text(text): return "text \"\(text.text)\""
        }
    }

    /// The fixtures carry the source only; the measured percentage is applied
    /// here so the 100% and 150% runs exercise different real scales.
    private static func applying(percentage: Double, to center: CenterState) -> CenterState {
        switch center {
        case let .symbol(symbol):
            return .symbol(IconSymbolState(
                source: symbol.source,
                color: symbol.color,
                scale: symbol.scale,
                normalizedSizePercentage: percentage
            ))
        case let .text(text):
            return .text(IconTextState(
                text: text.text,
                color: text.color,
                scale: text.scale,
                normalizedSizePercentage: percentage
            ))
        }
    }
}
