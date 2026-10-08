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
        guard pixelLength > 0, pixelLength <= pixelSize else { return nil }

        let palette = palette(for: backgroundStyle)
        let canvasLength = CGFloat(pixelLength)
        guard let context = scratchContext(pixelLength: pixelLength) else { return nil }

        context.saveGState()
        defer { context.restoreGState() }
        context.clear(CGRect(x: 0, y: 0, width: canvasLength, height: canvasLength))
        context.scaleBy(
            x: canvasLength / DockIconGlyphLayout.designLength,
            y: canvasLength / DockIconGlyphLayout.designLength
        )
        context.addPath(roundedRect(bodyRect, cornerRadius: bodyCornerRadius))
        context.setFillColor(palette.body)
        context.fillPath()
        context.addPath(roundedRect(borderRect, cornerRadius: borderCornerRadius))
        context.setStrokeColor(palette.border)
        context.setLineWidth(2)
        context.strokePath()

        context.saveGState()
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
            phase: nil
        )
        context.restoreGState()
        guard didDraw, let output = context.makeImage() else { return nil }

        let logicalLength = CGFloat(pixelLength) / Self.scale
        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalLength, height: logicalLength)
        let image = NSImage(size: NSSize(width: logicalLength, height: logicalLength))
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }

    /// One reusable bitmap per pixel length: the Dock icon is redrawn on every
    /// status change and a preview tile is redrawn whenever its pane
    /// re-evaluates, so allocating a fresh buffer each time leaves the freed
    /// pages in the process.
    private static var reusedContexts: [Int: CGContext] = [:]
    private static var reusedContextOrder: [Int] = []
    /// The 512 px Dock raster plus the handful of preview lengths the Settings
    /// pane and the icon guide use.
    private static let maximumReusedContexts = 6

    private static func scratchContext(pixelLength: Int) -> CGContext? {
        if let reused = reusedContexts[pixelLength] {
            touchScratchContext(pixelLength)
            return reused
        }

        let context = CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: pixelLength * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return nil }

        reusedContexts[pixelLength] = context
        touchScratchContext(pixelLength)

        while reusedContextOrder.count > maximumReusedContexts {
            let oldest = reusedContextOrder.removeFirst()
            reusedContexts[oldest] = nil
        }
        return context
    }

    private static func touchScratchContext(_ pixelLength: Int) {
        reusedContextOrder.removeAll { $0 == pixelLength }
        reusedContextOrder.append(pixelLength)
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
