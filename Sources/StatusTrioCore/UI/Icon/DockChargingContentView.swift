import AppKit

/// The Dock tile's content view while the charging animation plays.
///
/// The Dock owns the drawing of a `contentView`, so the presenter hands the
/// view two cached rasters and asks the tile to redraw; a tick never builds a
/// bitmap here. The base is the whole tile with the animating regions left out,
/// and the overlay is the effect slice the clock's phase selects.
@MainActor
final class DockChargingContentView: NSView {
    /// The static tile, drawn over the view's bounds.
    var baseImage: CGImage?
    /// The charging effect, drawn at `overlayUnitRect`.
    var overlayImage: CGImage?
    /// Where the effect raster belongs, in tile units (`0...1`), so the view
    /// does not need to know which pixel length the rasters were built at.
    var overlayUnitRect: CGRect = .zero

    /// How many times the Dock asked for a redraw, for tests.
    private(set) var drawCount = 0

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high

        if let baseImage {
            context.draw(baseImage, in: bounds)
        }
        if let overlayImage, overlayUnitRect.width > 0, overlayUnitRect.height > 0 {
            context.draw(overlayImage, in: overlayRect)
        }
    }

    private var overlayRect: CGRect {
        CGRect(
            x: bounds.minX + overlayUnitRect.minX * bounds.width,
            y: bounds.minY + overlayUnitRect.minY * bounds.height,
            width: overlayUnitRect.width * bounds.width,
            height: overlayUnitRect.height * bounds.height
        )
    }
}
