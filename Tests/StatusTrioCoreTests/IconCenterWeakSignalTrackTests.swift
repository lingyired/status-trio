import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

/// Regression for the weak-signal Wi-Fi glyph.
///
/// The percentage ("normalized") centre sizing path rasterises the live centre
/// artwork, crops that mask to its *visible* ink and draws the crop. A
/// variable-value SF Symbol paints the part it has not filled yet in a muted
/// tint: `wifi` measures 77/255 for its unlit arcs, which is well below
/// `IconCenterSizingPolicy.visibleInkAlphaThreshold`. The crop therefore kept
/// only the arcs the current reading had already lit, so a two-bar RSSI drew a
/// single arc plus the dot and a one-bar RSSI drew a lone dot. The symbol must
/// keep the whole shape and mute the arcs it has not reached, exactly as the
/// legacy (non-percentage) path already does.
@MainActor
struct IconCenterWeakSignalTrackTests {
    /// Alpha floor that keeps SF Symbols' ~30 % unfilled track while ignoring
    /// nothing else the one-pass drawing paints.
    private let trackAlpha: UInt8 = 40

    /// The percentage the reported configuration stores (`normalizedSizePercentage`).
    private let percentage = 1.3

    @Test(arguments: [0.0, 0.33, 0.66])
    func weakWiFiKeepsTheSameGlyphFootprintAsAFullSignal(variableValue: Double) throws {
        let full = try inkBounds(of: try renderCenter(variableValue: 1.0, size: 120, scale: 4))
        let weak = try inkBounds(of: try renderCenter(
            variableValue: variableValue, size: 120, scale: 4
        ))

        #expect(abs(weak.width - full.width) <= 4,
                "The Wi-Fi glyph lost width at variable value \(variableValue)")
        #expect(abs(weak.height - full.height) <= 4,
                "The Wi-Fi glyph lost height at variable value \(variableValue)")
        #expect(abs(weak.maxY - full.maxY) <= 2,
                "The unlit outer arc above the lit part went missing at variable value \(variableValue)")
    }

    @Test func unlitWiFiArcsKeepTheirMutedTrack() throws {
        let full = try PixelBuffer(image: try renderCenter(variableValue: 1.0, size: 120, scale: 4))
        let twoBars = try PixelBuffer(
            image: try renderCenter(variableValue: 0.66, size: 120, scale: 4)
        )
        // The outer, weakest arc is the top band of the glyph and is the arc a
        // two-bar reading has not reached. 24 rows is 6 SVG units at this 4x
        // raster, comfortably inside the arc and clear of the lit inner one.
        let topRow = Int(try inkBounds(
            of: try renderCenter(variableValue: 1.0, size: 120, scale: 4)
        ).minY)
        let outerArcRows = topRow..<(topRow + 24)
        let lit = maximumAlpha(full, rows: outerArcRows)
        let track = maximumAlpha(twoBars, rows: outerArcRows)

        #expect(lit >= 200, "the full-signal outer arc must be fully lit")
        #expect(track >= trackAlpha, "The unlit outer arc must still paint a visible track")
        #expect(Double(track) <= Double(lit) * 0.6,
                "The unlit outer arc must stay muted against a lit arc")
    }

    @Test func weakWiFiKeepsTheTrackOnTheShippedMenuBarRaster() throws {
        let full = try inkBounds(of: try renderCenter(variableValue: 1.0, size: 24, scale: 2))
        let twoBars = try inkBounds(of: try renderCenter(variableValue: 0.66, size: 24, scale: 2))

        #expect(abs(twoBars.height - full.height) <= 1,
                "The shipped 24pt menu bar raster lost the unlit arcs")
    }

    @Test func weakWiFiKeepsTheTrackOnTheDockRaster() throws {
        let full = try dockInkBounds(of: try renderDock(variableValue: 1.0))
        let twoBars = try dockInkBounds(of: try renderDock(variableValue: 0.66))

        #expect(abs(twoBars.height - full.height) <= 4,
                "The Dock raster lost the unlit arcs")
        #expect(abs(twoBars.width - full.width) <= 4,
                "The Dock raster lost the unlit arcs")
    }

    private func renderCenter(
        variableValue: Double,
        size: CGFloat,
        scale: CGFloat
    ) throws -> CGImage {
        try #require(StatusIconRenderer.render(
            scene: IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: variableValue, fallback: nil),
                color: .primary,
                scale: 1,
                normalizedSizePercentage: percentage
            ))),
            environment: StatusIconRenderEnvironment(
                size: size,
                scale: scale,
                foreground: CGColor(gray: 1, alpha: 1),
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))
    }

    private func renderDock(variableValue: Double) throws -> CGImage {
        let image = try #require(DockIconRenderer.image(
            scene: IconSceneState(center: .symbol(IconSymbolState(
                source: .symbol(name: "wifi", variableValue: variableValue, fallback: nil),
                color: .primary,
                scale: 1,
                normalizedSizePercentage: percentage
            ))),
            pixelLength: 512
        ))
        return try #require((image.representations.first as? NSBitmapImageRep)?.cgImage)
    }

    private func inkBounds(of image: CGImage) throws -> CGRect {
        try alphaBounds(try PixelBuffer(image: image), threshold: trackAlpha)
    }

    /// The Dock raster carries an opaque plate, so the track is measured as a
    /// lift above the plate colour rather than as alpha. The plate is sampled a
    /// eighth of the way in, clear of both the transparent corner and the glyph.
    private func dockInkBounds(of image: CGImage) throws -> CGRect {
        let pixels = try PixelBuffer(image: image)
        let plate = pixels.rgba(x: pixels.width / 8, y: pixels.height / 8)
        func isInk(_ pixel: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) -> Bool {
            Int(pixel.green) - Int(plate.green) >= 40
        }
        var minX = pixels.width, maxX = -1, minY = pixels.height, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where isInk(pixels.rgba(x: x, y: y)) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return try #require(boundsRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
    }

    private func alphaBounds(_ pixels: PixelBuffer, threshold: UInt8) throws -> CGRect {
        var minX = pixels.width, maxX = -1, minY = pixels.height, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgba(x: x, y: y).alpha >= threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return try #require(boundsRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
    }

    private func maximumAlpha(_ pixels: PixelBuffer, rows: Range<Int>) -> UInt8 {
        rows.reduce(UInt8(0)) { current, row in
            (0..<pixels.width).reduce(current) { inner, x in
                max(inner, pixels.rgba(x: x, y: row).alpha)
            }
        }
    }

    private func boundsRect(minX: Int, minY: Int, maxX: Int, maxY: Int) -> CGRect? {
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
