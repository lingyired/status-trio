import AppKit
import CoreGraphics

enum DockIconGlyphLayout {
    static let designLength: CGFloat = 1024
    static let glyphSVGOrigin = CGPoint(x: 194.8, y: 171.84)
    static let glyphSVGSize: CGFloat = 672

    static func frame(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        return CGRect(
            x: bounds.minX + glyphSVGOrigin.x / designLength * bounds.width,
            y: bounds.minY
                + (designLength - glyphSVGOrigin.y - glyphSVGSize)
                / designLength
                * bounds.height,
            width: glyphSVGSize / designLength * bounds.width,
            height: glyphSVGSize / designLength * bounds.height
        )
    }
}

@MainActor
enum DockIconRenderer {
    /// The real Dock icon is a 512 px bitmap presented as a 256 pt 2x asset.
    static let scale: CGFloat = 2
    static let logicalSize: CGFloat = 256
    nonisolated static let pixelSize = 512
    /// The bundle icon's Icon Composer artwork is authored at 1024 px.
    nonisolated static let appIconArtworkPixelSize = 1024

    /// How the tile draws its own background.
    ///
    /// The Dock tile is a rounded body with a hairline border because it is a
    /// free-standing bitmap. The bundle icon is composed by Icon Composer and
    /// clipped to the system's icon shape, so its artwork is a square: a
    /// second rounded edge drawn inside that shape would double the border.
    private enum TileBody {
        case rounded
        case square
    }

    // Geometry mirrors Support/AppIcon.svg.
    private static let bodyRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    private static let bodyCornerRadius: CGFloat = 210
    private static let borderRect = CGRect(x: 65, y: 65, width: 894, height: 894)
    private static let borderCornerRadius: CGFloat = 209

    // Build colors in the bitmap's own space so AppIcon.svg's hex values survive
    // without a Generic RGB to Device RGB conversion.
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private static func color(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) -> CGColor {
        CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, alpha]
        ) ?? CGColor(gray: 0, alpha: 1)
    }

    private struct Palette {
        let body: CGColor
        let border: CGColor
        let foreground: CGColor
    }

    private static func palette(for style: DockIconBackgroundStyle) -> Palette {
        switch style {
        case .dark:
            Palette(
                body: color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 23.0 / 255.0),
                border: color(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 61.0 / 255.0),
                foreground: color(red: 1, green: 1, blue: 1)
            )
        case .light:
            Palette(
                body: color(red: 1, green: 1, blue: 1),
                border: color(red: 210.0 / 255.0, green: 210.0 / 255.0, blue: 215.0 / 255.0),
                foreground: color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0)
            )
        case .clear:
            // Approximation of the system's "clear" glass: a translucent light
            // tile with a bright rim so the Dock shows through.
            Palette(
                body: color(red: 1, green: 1, blue: 1, alpha: 0.55),
                border: color(red: 1, green: 1, blue: 1, alpha: 0.8),
                foreground: color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0)
            )
        }
    }

    static func image(
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle = .dark,
        pixelLength: Int = DockIconRenderer.pixelSize
    ) -> NSImage? {
        guard let output = tileImage(
            scene: scene,
            backgroundStyle: backgroundStyle,
            pixelLength: pixelLength
        ) else { return nil }

        let logicalLength = CGFloat(pixelLength) / Self.scale
        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalLength, height: logicalLength)
        let image = NSImage(size: NSSize(width: logicalLength, height: logicalLength))
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }

    /// The whole tile as one raster.
    ///
    /// The static Dock path wraps this in an `NSImage`; the charging animation
    /// keeps the `CGImage` so a tick never round-trips through `NSImage`.
    static func tileImage(
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int = DockIconRenderer.pixelSize,
        phase: ChargingEffectPhase? = nil
    ) -> CGImage? {
        render(
            scene: scene,
            backgroundStyle: backgroundStyle,
            phase: phase,
            regions: .all,
            pixelLength: pixelLength,
            crop: nil,
            drawsTileBackground: true
        )
    }

    /// The bundle icon's artwork for one appearance.
    ///
    /// The Icon Composer document owns the system icon shape, so this variant
    /// is a full-bleed square without the Dock tile's rounded body and border.
    /// Only the icon build and its preview test call it.
    static func appIconArtwork(
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int = DockIconRenderer.appIconArtworkPixelSize
    ) -> CGImage? {
        render(
            scene: scene,
            backgroundStyle: backgroundStyle,
            phase: nil,
            regions: .all,
            pixelLength: pixelLength,
            crop: nil,
            drawsTileBackground: true,
            body: .square
        )
    }

    /// The static tile the charging animation draws beneath its effect raster.
    ///
    /// The ring's accessory is deliberately left out: the effect raster carries
    /// the charging bolt because its heartbeat scales it, and drawing the bolt
    /// here as well would double its drop shadow and pin its scale.
    static func animationBaseImage(
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> CGImage? {
        render(
            scene: scene,
            backgroundStyle: backgroundStyle,
            phase: nil,
            regions: IconSceneRegion.all.subtracting(.ringAccessory),
            pixelLength: pixelLength,
            crop: nil,
            drawsTileBackground: true
        )
    }

    /// The slice of the tile the charging effect can paint in, in tile pixels.
    ///
    /// The effect's ink is bounded by the battery arc plus the largest
    /// heartbeat halo, so the animation rasterizes this rect instead of a full
    /// 512-px square per frame. `nil` means the scene has no charging effect to
    /// draw at all.
    static func chargingEffectRect(
        scene: IconSceneState,
        pixelLength: Int
    ) -> CGRect? {
        guard pixelLength > 0, pixelLength <= pixelSize,
              let ring = scene.outerRing, ring.effect != nil
        else { return nil }

        let margin = chargingEffectInkMargin(strokeScale: ring.strokeScale)
        let ink = StatusIconGeometry.batteryTrack()
            .boundingBoxOfPath
            .insetBy(dx: -margin, dy: -margin)
        let tile = CGRect(x: 0, y: 0, width: CGFloat(pixelLength), height: CGFloat(pixelLength))
        let rect = tileRect(forCanvasRect: ink, pixelLength: pixelLength)
        .integral
        .intersection(tile)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return rect
    }

    /// Maps a rect in the renderer's 120-unit canvas space to tile pixels,
    /// following the same transform `render` applies: the tile scale and glyph
    /// origin first, then the renderer's own y-flip.
    static func tileRect(forCanvasRect canvasRect: CGRect, pixelLength: Int) -> CGRect {
        guard pixelLength > 0 else { return .zero }
        let tileScale = CGFloat(pixelLength) / DockIconGlyphLayout.designLength
        let glyphScale = DockIconGlyphLayout.glyphSVGSize / StatusIconGeometry.canvas.width
        let glyphTop = DockIconGlyphLayout.designLength
            - DockIconGlyphLayout.glyphSVGOrigin.y
        let x = DockIconGlyphLayout.glyphSVGOrigin.x
        let lower = CGPoint(
            x: tileScale * (x + glyphScale * canvasRect.minX),
            y: tileScale * (glyphTop - glyphScale * canvasRect.maxY)
        )
        let upper = CGPoint(
            x: tileScale * (x + glyphScale * canvasRect.maxX),
            y: tileScale * (glyphTop - glyphScale * canvasRect.minY)
        )
        return CGRect(
            x: lower.x,
            y: lower.y,
            width: upper.x - lower.x,
            height: upper.y - lower.y
        )
    }

    /// The farthest the effect's ink can sit from the arc's centre line: the
    /// heartbeat halo is `lineWidth * 0.95 * 1.55 * 1.35` at its largest, and
    /// half a unit of headroom absorbs the antialiased edge.
    static func chargingEffectInkMargin(strokeScale: Double) -> CGFloat {
        let lineWidth = 8 * CGFloat(strokeScale)
        return max(lineWidth * 0.5, lineWidth * 0.95 * 1.55 * 1.35) + 0.5
    }

    /// The effect's own raster: the charging comet, heartbeat halo and bolt,
    /// with everything that does not animate left to `animationBaseImage`.
    static func chargingEffectImage(
        scene: IconSceneState,
        phase: ChargingEffectPhase,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> CGImage? {
        guard let crop = chargingEffectRect(scene: scene, pixelLength: pixelLength) else {
            return nil
        }
        return render(
            scene: scene,
            backgroundStyle: backgroundStyle,
            phase: phase,
            regions: [.ringEffect, .ringAccessory],
            pixelLength: pixelLength,
            crop: crop,
            drawsTileBackground: false
        )
    }

    /// Renders `regions` in the tile's own space, optionally cropped to `crop`
    /// (tile pixels, bottom-left origin). A crop produces a bitmap that is
    /// exactly the slice a caller draws back at the same tile rect.
    private static func render(
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        phase: ChargingEffectPhase?,
        regions: IconSceneRegion,
        pixelLength: Int,
        crop: CGRect?,
        drawsTileBackground: Bool,
        body: TileBody = .rounded
    ) -> CGImage? {
        let maximumPixelLength = body == .square ? appIconArtworkPixelSize : pixelSize
        guard pixelLength > 0, pixelLength <= maximumPixelLength else { return nil }

        let tileLength = CGFloat(pixelLength)
        let bitmap = crop ?? CGRect(x: 0, y: 0, width: tileLength, height: tileLength)
        guard bitmap.minX >= 0, bitmap.minY >= 0,
              bitmap.maxX <= tileLength, bitmap.maxY <= tileLength,
              let width = Int(exactly: bitmap.width.rounded()),
              let height = Int(exactly: bitmap.height.rounded()),
              width > 0, height > 0,
              let context = scratchContext(width: width, height: height)
        else { return nil }

        let palette = palette(for: backgroundStyle)
        context.saveGState()
        defer { context.restoreGState() }
        context.clear(CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        // A crop is expressed in the tile's pixels, so remove it before the
        // tile transform is applied.
        context.translateBy(x: -bitmap.minX, y: -bitmap.minY)
        context.scaleBy(
            x: tileLength / DockIconGlyphLayout.designLength,
            y: tileLength / DockIconGlyphLayout.designLength
        )

        if drawsTileBackground {
            switch body {
            case .rounded:
                context.addPath(roundedRect(bodyRect, cornerRadius: bodyCornerRadius))
                context.setFillColor(palette.body)
                context.fillPath()
                context.addPath(roundedRect(borderRect, cornerRadius: borderCornerRadius))
                context.setStrokeColor(palette.border)
                context.setLineWidth(2)
                context.strokePath()
            case .square:
                context.setFillColor(palette.body)
                context.fill(CGRect(
                    x: 0,
                    y: 0,
                    width: DockIconGlyphLayout.designLength,
                    height: DockIconGlyphLayout.designLength
                ))
            }
        }

        context.saveGState()
        if body == .square {
            // The Dock tile is 896 of the 1024-unit canvas; the bundle icon's
            // tile is the whole canvas, so the glyph is scaled about the tile
            // centre to keep the artwork's proportion to the tile itself.
            let glyphScale = DockIconGlyphLayout.designLength / bodyRect.width
            let center = CGPoint(x: bodyRect.midX, y: bodyRect.midY)
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: glyphScale, y: glyphScale)
            context.translateBy(x: -center.x, y: -center.y)
        }
        context.translateBy(
            x: DockIconGlyphLayout.glyphSVGOrigin.x,
            y: DockIconGlyphLayout.designLength
                - DockIconGlyphLayout.glyphSVGOrigin.y
                - DockIconGlyphLayout.glyphSVGSize
        )
        let didDraw = StatusIconRenderer.draw(
            scene: scene,
            in: context,
            size: DockIconGlyphLayout.glyphSVGSize,
            foreground: palette.foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor,
            statusPalette: .resolved(dark: backgroundStyle == .dark),
            phase: phase,
            regions: regions
        )
        context.restoreGState()
        guard didDraw, let output = context.makeImage() else { return nil }
        return output
    }

    /// One reusable bitmap per size: the Dock icon is redrawn on every
    /// status change and a preview tile is redrawn whenever its pane
    /// re-evaluates, so allocating a fresh buffer each time leaves the freed
    /// pages in the process.
    private struct ScratchKey: Hashable {
        let width: Int
        let height: Int
    }

    private static var reusedContexts: [ScratchKey: CGContext] = [:]
    private static var reusedContextOrder: [ScratchKey] = []
    /// The 512 px Dock raster plus the handful of preview lengths the Settings
    /// pane and the icon guide use, and the effect slices the Dock animation
    /// caches.
    private static let maximumReusedContexts = 6
    private static let maximumScratchBytes = 4 * 1024 * 1024

    static var scratchResidentByteCount: Int {
        reusedContexts.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    static func resetScratchContexts() {
        reusedContexts.removeAll(keepingCapacity: false)
        reusedContextOrder.removeAll(keepingCapacity: false)
    }

    private static func scratchContext(width: Int, height: Int) -> CGContext? {
        let key = ScratchKey(width: width, height: height)
        if let reused = reusedContexts[key] {
            touchScratchContext(key)
            return reused
        }

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return nil }

        guard context.bytesPerRow * context.height <= maximumScratchBytes else { return context }

        reusedContexts[key] = context
        touchScratchContext(key)

        while reusedContextOrder.count > maximumReusedContexts || scratchResidentByteCount > maximumScratchBytes {
            let oldest = reusedContextOrder.removeFirst()
            reusedContexts[oldest] = nil
        }
        return context
    }

    private static func touchScratchContext(_ key: ScratchKey) {
        reusedContextOrder.removeAll { $0 == key }
        reusedContextOrder.append(key)
    }

    private static func roundedRect(_ rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}
