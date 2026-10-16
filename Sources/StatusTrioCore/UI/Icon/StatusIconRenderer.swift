import AppKit
import CoreGraphics
import CoreText
import CoreFoundation

private final class CenterSizingMetricsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var heights: [String: CGFloat] = [:]
    private var insertionOrder: [String] = []
    private let limit = 256

    func value(for key: String) -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return heights[key]
    }

    func insert(_ height: CGFloat, for key: String) {
        guard height.isFinite, height > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard heights[key] == nil else { return }
        heights[key] = height
        insertionOrder.append(key)
        while insertionOrder.count > limit {
            heights[insertionOrder.removeFirst()] = nil
        }
    }
}

private struct ResolvedCenterImage {
    let image: NSImage
    let visibleHeightFraction: CGFloat
}

private final class CenterArtworkCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: MeasuredCenterArtwork] = [:]
    private var insertionOrder: [String] = []
    private let limit = 64

    func image(for key: String, create: () -> MeasuredCenterArtwork?) -> MeasuredCenterArtwork? {
        lock.lock()
        if let cached = images[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let artwork = create() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = images[key] { return cached }
        images[key] = artwork
        insertionOrder.append(key)
        while insertionOrder.count > limit {
            images[insertionOrder.removeFirst()] = nil
        }
        return artwork
    }
}

private final class OutputCenterScaleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CGFloat] = [:]
    private var keys: [String] = []
    private let limit = 256

    func value(for key: String, create: () -> CGFloat?) -> CGFloat? {
        lock.lock()
        if let value = values[key] { lock.unlock(); return value }
        lock.unlock()
        guard let value = create(), value.isFinite, value > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = values[key] { return cached }
        values[key] = value
        keys.append(key)
        while keys.count > limit { values[keys.removeFirst()] = nil }
        return value
    }
}

private struct MeasuredCenterArtwork {
    let image: CGImage
    let width: CGFloat
    let height: CGFloat
    let offsetFromAnchor: CGPoint
}

/// Reuses both decoded image data and its alpha measurement between the sizing
/// pass and draw pass. File metadata participates in identity so edited assets
/// naturally invalidate the cached entry.
private final class CenterImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ResolvedCenterImage] = [:]
    private var insertionOrder: [String] = []
    private let limit = 64

    func image(for url: URL) -> ResolvedCenterImage? {
        let identity = IconImageFileIdentity(url: url)
        let key = identity.cacheToken

        lock.lock()
        if let cached = values[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let image = IconImageDecodeCache.shared.decodedImage(for: identity) else { return nil }
        let visibleHeightFraction: CGFloat
        if image.size.height > 0, let bounds = StatusIconRenderer.visibleAlphaBoundsForCache(of: image) {
            visibleHeightFraction = bounds.height / image.size.height
        } else {
            visibleHeightFraction = 1
        }
        let resolved = ResolvedCenterImage(image: image, visibleHeightFraction: visibleHeightFraction)

        lock.lock()
        defer { lock.unlock() }
        if let cached = values[key] { return cached }
        values[key] = resolved
        insertionOrder.append(key)
        while insertionOrder.count > limit {
            values[insertionOrder.removeFirst()] = nil
        }
        return resolved
    }
}

/// Cache key for the measured ink offset of one SF Symbol configuration.
/// The layout box SF Symbols report is not centred on the glyph ink; the
/// offset lets the renderer anchor what the user sees, not the image's
/// bounding box. Measurement is keyed by every input that changes the shape.
private struct SymbolInkKey: Hashable {
    let name: String
    let variableValue: Double
    let pointSize: Double
}

/// A small locked cache because the renderer is called from animation frames
/// and from background-free previews. Measuring the ink involves a bitmap
/// draw, so it must happen once per distinct symbol configuration.
private final class SymbolInkOffsetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SymbolInkKey: CGFloat] = [:]

    func offsetX(for key: SymbolInkKey, measure: () -> CGFloat) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }
        let measured = measure()
        storage[key] = measured
        return measured
    }
}

/// The same ink measurement for an input source's own icon file, which is a
/// bitmap or PDF whose visible ink is not centred in the box `NSImage.size`
/// reports. Key by file identity so replacing an icon in place also refreshes
/// its measured offset.
private final class ImageInkOffsetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [IconImageFileIdentity: CGFloat] = [:]
    private var order: [IconImageFileIdentity] = []
    private let limit = 64

    func offsetX(for identity: IconImageFileIdentity, measure: () -> CGFloat) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[identity] { return cached }
        let measured = measure()
        storage[identity] = measured
        order.append(identity)
        while order.count > limit {
            storage[order.removeFirst()] = nil
        }
        return measured
    }
}

enum StatusIconRenderer {
    private static let symbolInkOffsetCache = SymbolInkOffsetCache()
    private static let imageInkOffsetCache = ImageInkOffsetCache()

    static let centerSymbolBasePointSize: CGFloat = 38
    private static let defaultBatteryValueTextScale = 1.8

    /// Anchored to the artwork's centre, not the canvas midpoint: the vector
    /// art is drawn on a 119-unit box centred at 59.5, so `canvas.midX` (60.0)
    /// puts every SF Symbol half a unit right of it. The symbol's ink is then
    /// measured and compensated separately; see issue #30 and
    /// `drawOfficialSymbol`.
    private static let wifiSymbolCenter = CGPoint(
        x: StatusIconGeometry.artworkCenterX,
        y: 64.0
    )

    private static let centerSizingMetrics = CenterSizingMetricsCache()
    private static let centerImages = CenterImageCache()
    private static let normalizedCenterArtwork = CenterArtworkCache()
    private static let outputCenterScales = OutputCenterScaleCache()
    private static let normalizedArtworkRasterScale: CGFloat = 8
    private static let normalizedArtworkRasterDimension = 512

    private static let bluetoothBlueOnLightBackground = CGColor(
        red: 0,
        green: 102.0 / 255.0,
        blue: 204.0 / 255.0,
        alpha: 1
    )
    private static let bluetoothBlueOnDarkBackground = CGColor(
        red: 77.0 / 255.0,
        green: 163.0 / 255.0,
        blue: 1,
        alpha: 1
    )




    /// Creates a transparent, correctly sized image to reserve the status-item
    /// button footprint while a Core Animation layer draws over it.
    @MainActor
    static func transparentMenuBarImage(size: CGFloat, scale: CGFloat) -> NSImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    /// Draws the status glyph into an existing context, using the renderer's
    /// canvas coordinates. Avoids the intermediate bitmap that `render` creates.






    private static func drawChargingEffect(
        _ frame: ChargingEffectFrame,
        highlightColor: CGColor,
        lineWidth: CGFloat,
        hasTopGap: Bool,
        topGapWidth: CGFloat,
        in context: CGContext
    ) {
        if let tailRange = frame.tailRange {
            let tailPath = StatusIconGeometry.batteryHighlight(
                from: tailRange.lowerBound,
                to: tailRange.upperBound,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
            let strokedTail = tailPath.copy(
                strokingWithWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            let transparent = highlightColor.copy(alpha: 0) ?? highlightColor
            let bright = highlightColor.copy(alpha: min(1, max(0, highlightColor.alpha * frame.tailAlpha))) ?? highlightColor
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [transparent, bright, transparent] as CFArray,
                locations: [0, 0.82, 1]
            ) {
                context.saveGState()
                context.addPath(strokedTail)
                context.clip()
                context.drawLinearGradient(
                    gradient,
                    start: StatusIconGeometry.batteryPoint(forProgress: tailRange.lowerBound),
                    end: StatusIconGeometry.batteryPoint(forProgress: tailRange.upperBound),
                    options: []
                )
                context.restoreGState()
            }
        }

        if frame.headIsVisible, frame.beadAlpha > 0 {
            let center = StatusIconGeometry.batteryPoint(forProgress: frame.headProgress)
            let radius = lineWidth * 0.5 * 1.18
            context.setFillColor(highlightColor.copy(alpha: min(1, highlightColor.alpha * frame.beadAlpha)) ?? highlightColor)
            context.fillEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }

        if frame.headIsVisible, frame.heartbeatAlpha > 0 {
            let center = StatusIconGeometry.batteryPoint(forProgress: frame.headProgress)
            let radius = lineWidth * 0.95 * frame.heartbeatScale
            context.setFillColor(highlightColor.copy(alpha: min(1, highlightColor.alpha * frame.heartbeatAlpha)) ?? highlightColor)
            context.fillEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
    }

    /// Draws the plug at the bolt's optical size and center, so the arc's top
    /// gap reads the same whichever indicator is showing.
    private static func drawBatteryPlug(
        boltScale: CGFloat,
        foreground: CGColor,
        in context: CGContext
    ) {
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = boltHeight * boltScale * StatusIconGeometry.batteryPlugHeightScale
        guard targetHeight.isFinite, targetHeight > 0 else { return }

        drawOfficialSymbol(
            name: StatusIconGeometry.batteryPlugSymbolName,
            pointSize: batteryPlugPointSize(targetHeight: targetHeight),
            center: StatusIconGeometry.batteryTopIndicatorCenter(boltScale: boltScale),
            foreground: foreground,
            in: context
        )
    }



    private static func usesDarkStatusPalette(foreground: CGColor) -> Bool {
        guard let color = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.brightnessComponent < 0.5
    }

    private static func bluetoothColor(foreground: CGColor) -> CGColor {
        usesDarkStatusPalette(foreground: foreground)
            ? bluetoothBlueOnLightBackground
            : bluetoothBlueOnDarkBackground
    }



    /// Where a label's visible ink is centred in the middle connection slot.
    ///
    /// Text shares the slot with the Wi-Fi, Ethernet, Bluetooth and input-source
    /// glyphs, so it is centred on the same point they are: the ink centre of
    /// `wifiSymbolCenter`, not a second anchor of its own.
    ///
    /// The historic `y = 87` anchor compensated the renderer's flipped text
    /// matrix with the wrong sign, so the drawn ink centre was
    /// `87 - 2 * bounds.midY` instead of `87`. That cancels only at the default
    /// percentage size: every larger label — a 160 % input-source marker above
    /// all — climbed up into the ring's charging indicator by twice its own
    /// half-height. Anchoring the ink centre itself makes the position
    /// independent of the text's size, which is what a label that follows the
    /// Wi-Fi size control needs.
    private static let centerTextInkCenter = wifiSymbolCenter

    /// Uses the middle connection position for a large, label-free percentage.


    private static func batteryValueFontSize(scale: Double) -> CGFloat {
        StatusIconGeometry.batteryValueBaseFontSize * CGFloat(scale)
    }

    static func batteryChargingBoltScale(textScale: Double) -> CGFloat {
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = batteryTopIndicatorHeight(textScale: textScale)
        guard boltHeight.isFinite, boltHeight > 0, targetHeight > 0 else {
            return CGFloat(textScale / defaultBatteryValueTextScale)
                * StatusIconGeometry.batteryChargingBoltCalibration
        }
        return targetHeight / boltHeight
    }

    /// Height shared by every top-gap glyph. The bolt is calibrated to match the
    /// percentage numerals, and the plug matches the bolt.
    private static func batteryTopIndicatorHeight(textScale: Double) -> CGFloat {
        let fontSize = batteryValueFontSize(scale: textScale)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "100",
                attributes: [.font: batteryValueFont(size: fontSize)]
            )
        )
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        guard glyphHeight.isFinite, glyphHeight > 0 else {
            return StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
                * CGFloat(textScale / defaultBatteryValueTextScale)
                * StatusIconGeometry.batteryChargingBoltCalibration
        }
        return CGFloat(glyphHeight) * StatusIconGeometry.batteryChargingBoltCalibration
    }

    /// Glyph height per point of symbol size, measured once. SF Symbols report
    /// sizes rounded to whole points, so this reference size stays large enough
    /// for the rounding to be negligible.
    private static let batteryPlugHeightPerPoint: CGFloat = {
        let referencePointSize: CGFloat = 200
        guard let height = configuredSymbol(
            name: StatusIconGeometry.batteryPlugSymbolName,
            pointSize: referencePointSize,
            foreground: .labelColor
        )?.image.size.height, height.isFinite, height > 0 else {
            return 1.34
        }
        return height / referencePointSize
    }()

    private static func batteryPlugPointSize(targetHeight: CGFloat) -> CGFloat {
        let fallbackPointSize: CGFloat = 38
        let pointSize = targetHeight / batteryPlugHeightPerPoint
        return pointSize.isFinite && pointSize > 0 ? pointSize : fallbackPointSize
    }

    static var defaultCriticalColor: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }

    private static func batteryValueFont(size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    private static func drawEthernet(
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setStrokeColor(foreground)
        context.setLineWidth(StatusIconGeometry.ethernetStrokeWidth)
        for path in StatusIconGeometry.ethernetChevrons() {
            context.addPath(path)
            context.strokePath()
        }

        context.setFillColor(foreground)
        let radius = StatusIconGeometry.ethernetDotRadius
        for point in StatusIconGeometry.ethernetDots() {
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }



    static func centerSymbolPointSize(for scale: Double) -> CGFloat {
        guard scale.isFinite, scale > 0 else {
            return centerSymbolBasePointSize
        }
        return centerSymbolBasePointSize * CGFloat(scale)
    }

    private static func drawTintedImage(
        _ image: NSImage,
        maxDimension: CGFloat,
        center: CGPoint,
        tint: CGColor,
        inkCenterOffsetX: CGFloat = 0,
        in context: CGContext
    ) {
        let sourceSize = image.size
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return
        }

        let scale = min(
            maxDimension / sourceSize.width,
            maxDimension / sourceSize.height
        )
        let size = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let targetRect = CGRect(
            x: center.x - size.width / 2 - inkCenterOffsetX * scale,
            y: -(center.y + size.height / 2),
            width: size.width,
            height: size.height
        )

        context.saveGState()
        defer { context.restoreGState() }
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext
        context.scaleBy(x: 1, y: -1)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(
            in: targetRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.setFillColor(tint)
        context.setBlendMode(.sourceIn)
        context.fill(targetRect)
        context.endTransparencyLayer()
    }



    private static func drawTemporaryConnectionMark(
        wifiScale: Double,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        applyWiFiScale(wifiScale, in: context)

        context.setFillColor(foreground)
        context.setStrokeColor(foreground)
        context.setLineWidth(7)
        context.addPath(StatusIconGeometry.temporaryWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(2.5)
        context.addPath(StatusIconGeometry.temporaryScreenOutline())
        context.strokePath()
        context.addPath(StatusIconGeometry.temporaryScreenStand())
        context.fillPath()
        context.restoreGState()
    }

    private static func drawSharedConnectionMark(
        wifiScale: Double,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        applyWiFiScale(wifiScale, in: context)

        context.setFillColor(foreground)
        context.setStrokeColor(foreground)
        context.setLineWidth(7)
        context.addPath(StatusIconGeometry.sharedWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.addPath(StatusIconGeometry.sharedArrowCutout())
        context.fillPath()
        context.restoreGState()
    }

    private static func applyWiFiScale(_ wifiScale: Double, in context: CGContext) {
        let scale = CGFloat(wifiScale)
        guard scale.isFinite, scale > 0, scale != 1 else { return }

        let pivot = wifiSymbolCenter
        context.translateBy(x: pivot.x, y: pivot.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }

    /// A Wi-Fi icon at full strength.
    ///
    /// "Use Wi-Fi icon for Ethernet" is a look, not a reading: the link is a
    /// cable, so there is no signal for the icon to report. Borrowing the Wi-Fi
    /// radio's RSSI anyway made the icon answer a question nobody asked — it
    /// went flat and grey with Wi-Fi off, and moved with the Wi-Fi signal beside
    /// a row that was on a cable.




    /// Draws an SF Symbol so its visible ink, not its layout box, lands on
    /// `center`.
    ///
    /// `NSImage`'s symbol box carries side bearings, and the ink is not
    /// symmetric inside it: `wifi` at the default size reports an 81-point box
    /// while its ink bbox centre sits 0.344 points left of the box centre.
    /// Centering the box therefore still leaves the glyph visibly left of the
    /// hand-drawn battery ring, which is the recurrence of #30. Measure and
    /// apply that bearing here, once per symbol configuration.
    private static func drawOfficialSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        center: CGPoint = wifiSymbolCenter,
        foreground: CGColor,
        in context: CGContext
    ) {
        guard let symbol = configuredSymbol(
            name: name,
            variableValue: variableValue,
            pointSize: pointSize,
            foreground: NSColor(cgColor: foreground) ?? .labelColor
        ) else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let gc = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = gc

        context.scaleBy(x: 1, y: -1)

        let targetRect = CGRect(
            x: center.x - symbol.image.size.width / 2 - symbol.inkCenterOffsetX,
            y: -(center.y + symbol.image.size.height / 2),
            width: symbol.image.size.width,
            height: symbol.image.size.height
        )
        symbol.image.draw(in: targetRect)
    }

    private struct ConfiguredSymbol {
        let image: NSImage
        let inkCenterOffsetX: CGFloat
    }

    private static func configuredSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        foreground: NSColor
    ) -> ConfiguredSymbol? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: foreground))

        guard let image = NSImage(
            systemSymbolName: name,
            variableValue: variableValue,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config) else {
            return nil
        }

        let key = SymbolInkKey(
            name: name,
            variableValue: variableValue,
            pointSize: Double(pointSize)
        )
        let offset = symbolInkOffsetCache.offsetX(for: key) {
            measureInkCenterOffsetX(of: image)
        }
        return ConfiguredSymbol(image: image, inkCenterOffsetX: offset)
    }

    /// Horizontal distance from the image's layout-box centre to the centre of
    /// its visible ink. Rasterising at 8x keeps the measurement well below the
    /// 0.25-point quantum of the 120-unit icon grid.
    private static func measureInkCenterOffsetX(of image: NSImage) -> CGFloat {
        let pixelScale: CGFloat = 8
        let width = Int((image.size.width * pixelScale).rounded(.up))
        let height = Int((image.size.height * pixelScale).rounded(.up))
        guard width > 0, height > 0,
              width <= 16_384, height <= 16_384,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return 0
        }

        context.scaleBy(x: pixelScale, y: pixelScale)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = context.data else { return 0 }
        let bytesPerRow = context.bytesPerRow
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var minX = width
        var maxX = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                guard bytes[row + x * 4 + 3] > 0 else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard minX <= maxX else { return 0 }

        let inkMidX = (CGFloat(minX) + CGFloat(maxX) + 1) / 2 / pixelScale
        return inkMidX - image.size.width / 2
    }

}

extension StatusIconRenderer {
    /// The two surfaces one menu bar icon is drawn on.
    struct MenuBarLayers {
        /// Template image for every monochrome primitive. The system tints it for
        /// the menu bar's current Space and keeps the tint live while a Space
        /// switch is dragged, and it also reserves the item's footprint.
        let base: NSImage
        /// Custom-colour raster for the primitives that carry a status colour, or
        /// `nil` when the icon is monochrome.
        let overlay: CGImage?

        init(base: NSImage, overlay: CGImage? = nil) {
            self.base = base
            self.overlay = overlay
        }
    }

    /// Splits a scene into the template base and the custom-colour overlay.
    ///
    /// The base carries every monochrome primitive, and the overlay carries the
    /// status colours on top of it, which is the order the renderer already
    /// paints in; compositing them reproduces the scene while letting the system
    /// re-tint the monochrome primitives for the Space that is on top (#112).
    @MainActor
    static func menuBarLayers(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?,
        phase: ChargingEffectPhase? = nil
    ) -> MenuBarLayers? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let templateRegions = scene.templateRegions
        let chromaticRegions = scene.chromaticRegions

        let base: NSImage
        if let image = image(
            scene: scene,
            size: size,
            scale: scale,
            appearance: appearance,
            phase: nil,
            regions: templateRegions
        ) {
            image.isTemplate = true
            base = image
        } else if chromaticRegions.isEmpty {
            return nil
        } else if let placeholder = transparentMenuBarImage(size: size, scale: scale) {
            placeholder.isTemplate = true
            base = placeholder
        } else {
            return nil
        }

        guard !chromaticRegions.isEmpty else {
            return MenuBarLayers(base: base, overlay: nil)
        }
        return MenuBarLayers(
            base: base,
            overlay: render(
                scene: scene,
                environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
                phase: phase,
                regions: chromaticRegions
            )
        )
    }

    /// Menu bar entry point.
    ///
    /// Renders the requested primitives and marks the result as a template image
    /// when none of them carries a status colour. Prefer `menuBarLayers`, which
    /// splits the monochrome primitives from the status colours so the system can
    /// keep re-tinting the monochrome ones during a Space drag (#112).
    static func menuBarImage(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance? = nil,
        phase: ChargingEffectPhase? = nil,
        regions: IconSceneRegion = .all
    ) -> NSImage? {
        guard let image = image(
            scene: scene,
            size: size,
            scale: scale,
            appearance: appearance,
            phase: phase,
            regions: regions
        ) else {
            return nil
        }
        return menuBarTemplateAdjusted(image, scene: scene, regions: regions)
    }

    /// Applies the menu bar's template rule to an already-rendered image. The
    /// decision is derived only from the scene's colour roles, so it is stable
    /// across appearances and matches the render cache, whose key already includes
    /// the scene.
    static func menuBarTemplateAdjusted(
        _ image: NSImage,
        scene: IconSceneState,
        regions: IconSceneRegion = .all
    ) -> NSImage {
        image.isTemplate = regions.isSubset(of: scene.templateRegions)
        return image
    }

    static func preRenderedMenuBarImage(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance,
        phase: ChargingEffectPhase,
        regions: IconSceneRegion = .all
    ) -> NSImage? {
        guard let cgImage = render(
            scene: scene,
            environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
            phase: phase,
            regions: regions
        ) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        return menuBarTemplateAdjusted(image, scene: scene, regions: regions)
    }

    static func render(
        scene: IconSceneState,
        environment: StatusIconRenderEnvironment,
        phase: ChargingEffectPhase? = nil,
        regions: IconSceneRegion = .all
    ) -> CGImage? {
        let size = environment.size
        let scale = environment.scale
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4,
              let context = CGContext(
                  data: nil,
                  width: pixelDimension,
                  height: pixelDimension,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelDimension * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        guard draw(
            scene: scene,
            in: context,
            size: size,
            foreground: environment.foreground,
            criticalColor: environment.criticalColor,
            phase: phase,
            regions: regions
        ) else {
            return nil
        }
        return context.makeImage()
    }

    static func image(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance? = nil,
        phase: ChargingEffectPhase? = nil,
        regions: IconSceneRegion = .all
    ) -> NSImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        // Validate the scene and dimensions synchronously while keeping an NSImage
        // drawing handler so automatic appearances resolve again on every draw.
        guard render(
            scene: scene,
            environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
            phase: phase,
            regions: regions
        ) != nil else {
            return nil
        }

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            var didDraw = false
            let draw = {
                guard let context = NSGraphicsContext.current?.cgContext,
                      let cgImage = render(
                          scene: scene,
                          environment: renderEnvironment(size: size, scale: scale, appearance: nil),
                          phase: phase,
                          regions: regions
                      ) else {
                    return
                }
                context.saveGState()
                context.draw(cgImage, in: rect)
                context.restoreGState()
                didDraw = true
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return didDraw
        }
    }

    private static func renderEnvironment(
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?
    ) -> StatusIconRenderEnvironment {
        var foreground = CGColor(gray: 1, alpha: 1)
        var criticalColor = defaultCriticalColor
        let resolveAppearance = {
            foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? defaultCriticalColor
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(resolveAppearance)
        } else {
            resolveAppearance()
        }
        return StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: criticalColor
        )
    }

    /// Draws only the resolved visual state. The current renderer supports the
    /// one continuous ring produced by the mapper; empty or segmented ring
    /// arrays return false so unsupported scenes cannot masquerade as blank or
    /// partial output.
    @discardableResult
    static func draw(
        scene: IconSceneState,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor,
        phase: ChargingEffectPhase? = nil,
        regions: IconSceneRegion = .all
    ) -> Bool {
        guard size.isFinite, size > 0, supports(scene) else { return false }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / StatusIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if let ring = scene.outerRing {
            drawSceneRing(
                ring,
                in: context,
                foreground: foreground,
                criticalColor: criticalColor,
                phase: phase,
                regions: regions
            )
        }
        if let center = scene.center, regions.contains(.center) {
            drawSceneCenter(center, in: context, foreground: foreground, criticalColor: criticalColor)
        }
        if let footer = scene.footer {
            drawSceneFooter(
                footer,
                in: context,
                foreground: foreground,
                criticalColor: criticalColor,
                regions: regions
            )
        }
        return true
    }

    private static func supports(_ scene: IconSceneState) -> Bool {
        if let ring = scene.outerRing {
            switch ring.layout {
            case .standard:
                guard ring.segments.count == 1 else { return false }
            case .leftRight:
                let positions = ring.segments.compactMap(\.position)
                guard ring.segments.count == 2,
                      positions.count == 2,
                      Set(positions) == Set([.left, .right]) else {
                    return false
                }
            }
        }
        if case let .dots(dots) = scene.footer,
           dots.count > StatusIconGeometry.volumeDots().count {
            return false
        }
        return true
    }

    private static func drawSceneRing(
        _ ring: OuterRingState,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor,
        phase: ChargingEffectPhase?,
        regions: IconSceneRegion
    ) {
        let drawsRing = !regions.isDisjoint(with: [.ringTrack, .ringFill, .ringEffect])
        let drawsAccessory = regions.contains(.ringAccessory) && ring.accessory != nil
        guard drawsRing || drawsAccessory else { return }

        if ring.layout == .leftRight {
            drawAirPodsRing(
                ring,
                in: context,
                foreground: foreground,
                criticalColor: criticalColor,
                regions: regions
            )
            return
        }
        guard let segment = ring.segments.first else { return }
        let hasTopGap = ring.gap != .closed
        let topGapWidth = ring.gap == .indicator
            ? StatusIconGeometry.batteryChargingBoltTopGapWidth
            : StatusIconGeometry.batteryValueTopGapWidth
        let lineWidth = 8 * CGFloat(ring.strokeScale)

        let arcColor = sceneColor(for: segment.color, foreground: foreground, criticalColor: criticalColor)
        let effectFrame = ring.effect.flatMap { _ in
            phase.flatMap {
                ChargingEffectPolicy.frame(
                    progress: segment.progress,
                    phase: $0,
                    hasTopGap: hasTopGap,
                    topGapWidth: topGapWidth
                )
            }
        }
        let effectHighlight = effectFrame.map { _ in ChargingEffectPalette.automaticHighlight(for: arcColor) }

        if regions.contains(.ringTrack) {
            context.setLineWidth(lineWidth)
            context.setStrokeColor(sceneColor(
                for: ring.inactiveColor,
                foreground: foreground,
                criticalColor: criticalColor
            ))
            context.addPath(StatusIconGeometry.batteryTrack(hasTopGap: hasTopGap, topGapWidth: topGapWidth))
            context.strokePath()
        }

        if regions.contains(.ringFill) {
            context.setLineWidth(lineWidth)
            context.setStrokeColor(arcColor)
            context.addPath(StatusIconGeometry.batteryFill(
                progress: segment.progress,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            ))
            context.strokePath()
        }

        if regions.contains(.ringEffect), let effectFrame, let effectHighlight {
            drawChargingEffect(
                effectFrame,
                highlightColor: effectHighlight,
                lineWidth: lineWidth,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth,
                in: context
            )
        }

        guard regions.contains(.ringAccessory), let accessory = ring.accessory else { return }
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        switch accessory {
        case let .text(text):
            drawSceneText(
                text.text,
                color: sceneColor(for: text.color, foreground: foreground, criticalColor: criticalColor),
                fontSize: batteryValueFontSize(scale: text.scale),
                baseline: StatusIconGeometry.batteryValueBaseline(fontSize: batteryValueFontSize(scale: text.scale)),
                in: context
            )
        case let .symbol(symbol):
            if case .primitive(.bolt) = symbol.source {
                let baseColor = sceneColor(for: symbol.color, foreground: foreground, criticalColor: criticalColor)
                let indicatorScale = batteryChargingBoltScale(textScale: symbol.scale)
                let heartbeatFrame = ring.effect?.pulsesAccessory == true ? effectFrame : nil
                let bolt = heartbeatFrame.map { frame in
                    StatusIconGeometry.batteryChargingBolt(
                        basePath: StatusIconGeometry.batteryChargingBolt(scale: indicatorScale),
                        centeredScale: CGFloat(frame.boltScale),
                        fitting: StatusIconGeometry.canvas
                    )
                } ?? StatusIconGeometry.batteryChargingBolt(scale: indicatorScale)
                var boltColor = baseColor
                if let heartbeatFrame {
                    let highlight = ring.effect?.tintsAccessory == true
                        ? ChargingEffectPalette.chargingBoltHighlight(for: arcColor, using: effectHighlight ?? arcColor)
                        : baseColor
                    boltColor = ChargingEffectPalette.blend(
                        baseColor,
                        with: highlight,
                        amount: heartbeatFrame.boltArcColorAmount
                    )
                }
                context.setFillColor(boltColor)
                context.addPath(bolt)
                context.fillPath()
            } else if case .primitive(.plug) = symbol.source {
                drawBatteryPlug(
                    boltScale: batteryChargingBoltScale(textScale: symbol.scale),
                    foreground: sceneColor(for: symbol.color, foreground: foreground, criticalColor: criticalColor),
                    in: context
                )
            } else {
                drawSceneSymbol(
                    symbol,
                    center: StatusIconGeometry.batteryTopIndicatorCenter(
                        boltScale: batteryChargingBoltScale(textScale: symbol.scale)
                    ),
                    foreground: foreground,
                    criticalColor: criticalColor,
                    in: context
                )
            }
        }
    }

    private static func drawAirPodsRing(
        _ ring: OuterRingState,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor,
        regions: IconSceneRegion
    ) {
        let lineWidth = min(12, 8 * CGFloat(ring.strokeScale))
        if regions.contains(.ringTrack) {
            context.setLineWidth(lineWidth)
            context.setStrokeColor(sceneColor(for: ring.inactiveColor, foreground: foreground, criticalColor: criticalColor))
            for position in [RingSegmentPosition.left, .right] {
                context.addPath(StatusIconGeometry.airPodsTrack(position: position))
            }
            context.strokePath()
        }

        if regions.contains(.ringFill) {
            for segment in ring.segments {
                guard let position = segment.position else { continue }
                context.setLineWidth(lineWidth)
                context.setStrokeColor(sceneColor(for: segment.color, foreground: foreground, criticalColor: criticalColor))
                context.addPath(StatusIconGeometry.airPodsArc(position: position, progress: segment.progress))
                context.strokePath()
            }
        }
    }

    private static func drawNormalizedCenterArtwork(
        _ center: CenterState,
        percentage: Double,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let referenceCenter = referenceCenterState(center)
        guard let reference = normalizedCenterArtwork(for: referenceCenter),
              let artwork = normalizedCenterArtwork(for: rawSizedCenterState(center)) else {
            drawSceneCenter(rawSizedCenterState(center), in: context,
                            foreground: foreground, criticalColor: criticalColor)
            return
        }

        let multiplier = resolveNormalizedCenterCalibration(
            referenceCenter: referenceCenter, reference: reference, percentage: percentage, in: context
        )?.multiplier ?? CGFloat(IconCenterSizingPolicy.drawingMultiplier(
            percentage: percentage, referenceVisibleHeight: Double(reference.height)
        ))

        // Only the stable reference is measured. Draw the live text/symbol and
        // its real color at the shared calibrated multiplier.
        drawNormalizedArtwork(artwork, center: center,
                              multiplier: multiplier, in: context,
                              foreground: foreground, criticalColor: criticalColor)
    }

    private static func resolveNormalizedCenterCalibration(
        referenceCenter: CenterState,
        reference: MeasuredCenterArtwork,
        percentage: Double,
        in context: CGContext
    ) -> (identity: String, multiplier: CGFloat)? {
        let legacyReference = CenterState.symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: nil, fallback: nil),
            color: .primary, scale: percentage
        ))
        let anchor = centerArtworkAnchor(for: referenceCenter)
        let transform = context.ctm
        let deviceAnchor = anchor.applying(transform)
        let calibrationKey = [
            normalizedArtworkCacheKey(for: referenceCenter), String(percentage.bitPattern, radix: 16),
            "\(context.width)x\(context.height)",
            String(transform.a.bitPattern, radix: 16), String(transform.b.bitPattern, radix: 16),
            String(transform.c.bitPattern, radix: 16), String(transform.d.bitPattern, radix: 16),
            String(Double(deviceAnchor.x - floor(deviceAnchor.x)).bitPattern, radix: 16),
            String(Double(deviceAnchor.y - floor(deviceAnchor.y)).bitPattern, radix: 16)
        ].joined(separator: "|")
        let initialMultiplier = CGFloat(IconCenterSizingPolicy.drawingMultiplier(
            percentage: percentage, referenceVisibleHeight: Double(reference.height)
        ))
        let multiplier = outputCenterScales.value(for: calibrationKey) {
            guard let targetHeight = outputRasterHeight(of: legacyReference, matching: context) else { return nil }
            var candidate = initialMultiplier
            var bestCandidate = candidate
            var bestHeightError = CGFloat.greatestFiniteMagnitude
            // Calibrate the stable text=100 / variable-symbol=1 reference, in
            // opaque white, at this exact output CTM and anchor pixel phase.
            for _ in 0..<7 {
                guard let probe = outputRasterImage(matching: context, drawing: { probeContext in
                    drawNormalizedArtwork(reference, center: referenceCenter, multiplier: candidate,
                                          in: probeContext, foreground: CGColor(gray: 1, alpha: 1),
                                          criticalColor: CGColor(gray: 1, alpha: 1))
                }),
                let measured = visibleAlphaBounds(of: probe, threshold: IconCenterSizingPolicy.visibleInkAlphaThreshold)
                else { return nil }
                if measured.height == targetHeight { return candidate }
                let heightError = abs(targetHeight - measured.height)
                if heightError < bestHeightError {
                    bestCandidate = candidate
                    bestHeightError = heightError
                }
                candidate *= CGFloat(targetHeight) / measured.height
            }
            return bestCandidate
        } ?? initialMultiplier
        return (calibrationKey, multiplier)
    }

    /// Internal test seam for verifying that live variable-symbol values share
    /// the production reference calibration without flattening their artwork.
    static func normalizedCenterCalibration(
        for center: CenterState,
        percentage: Double,
        environment: StatusIconRenderEnvironment
    ) -> (identity: String, multiplier: CGFloat)? {
        let pixelLength = (environment.size * environment.scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength), pixelDimension > 0,
              pixelDimension <= Int.max / 4,
              let context = CGContext(data: nil, width: pixelDimension, height: pixelDimension,
                                      bitsPerComponent: 8, bytesPerRow: pixelDimension * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let reference = normalizedCenterArtwork(for: referenceCenterState(center)) else { return nil }
        context.scaleBy(x: environment.scale, y: environment.scale)
        context.translateBy(x: 0, y: environment.size)
        let iconScale = environment.size / StatusIconGeometry.canvas.width
        context.scaleBy(x: iconScale, y: -iconScale)
        return resolveNormalizedCenterCalibration(
            referenceCenter: referenceCenterState(center), reference: reference,
            percentage: percentage, in: context
        )
    }

    private static func drawNormalizedArtwork(
        _ artwork: MeasuredCenterArtwork,
        center: CenterState,
        multiplier: CGFloat,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let height = artwork.height * multiplier
        let width = artwork.width * multiplier
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        let anchor = centerArtworkAnchor(for: center)
        let midpoint = CGPoint(x: anchor.x + artwork.offsetFromAnchor.x * multiplier,
                               y: anchor.y + artwork.offsetFromAnchor.y * multiplier)
        let rect = CGRect(x: midpoint.x - width / 2, y: midpoint.y - height / 2,
                          width: width, height: height)
        let tint = centerColor(for: center, foreground: foreground, criticalColor: criticalColor)
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(tint)
        context.fill(rect)
        context.setBlendMode(.destinationIn)
        context.draw(artwork.image, in: rect)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func outputRasterHeight(of center: CenterState, matching context: CGContext) -> CGFloat? {
        guard let image = outputRasterImage(matching: context, drawing: { probeContext in
            drawSceneCenter(center, in: probeContext,
                            foreground: CGColor(gray: 1, alpha: 1),
                            criticalColor: CGColor(gray: 1, alpha: 1))
        }),
        let bounds = visibleAlphaBounds(of: image, threshold: IconCenterSizingPolicy.visibleInkAlphaThreshold)
        else { return nil }
        return bounds.height
    }

    private static func outputRasterImage(matching context: CGContext, drawing: (CGContext) -> Void) -> CGImage? {
        let width = context.width
        let height = context.height
        guard width > 0, height > 0, width <= Int.max / 4,
              let probe = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        probe.concatenate(context.ctm)
        drawing(probe)
        return probe.makeImage()
    }

    private static func referenceCenterState(_ center: CenterState) -> CenterState {
        switch center {
        case .text:
            return .text(IconTextState(text: "100", color: .primary, scale: 1))
        case let .symbol(symbol):
            let source: IconSymbolSource
            switch symbol.source {
            case let .symbol(name, _, fallback):
                source = .symbol(name: name, variableValue: 1, fallback: fallback)
            case let .image(url, fallback):
                source = .image(url: url, fallbackSymbol: fallback)
            case let .primitive(primitive):
                source = .primitive(primitive)
            }
            return .symbol(IconSymbolState(source: source, color: .primary, scale: 1))
        }
    }

    private static func rawSizedCenterState(_ center: CenterState) -> CenterState {
        switch center {
        case let .text(text):
            return .text(IconTextState(text: text.text, color: .primary, scale: 1))
        case let .symbol(symbol):
            let source: IconSymbolSource
            switch symbol.source {
            case let .symbol(name, variableValue, fallback):
                source = .symbol(name: name, variableValue: variableValue, fallback: fallback)
            case let .image(url, fallback):
                source = .image(url: url, fallbackSymbol: fallback)
            case let .primitive(primitive):
                source = .primitive(primitive)
            }
            return .symbol(IconSymbolState(source: source, color: .primary, scale: 1))
        }
    }

    private static func centerArtworkAnchor(for center: CenterState) -> CGPoint {
        switch center {
        case .text, .symbol:
            return wifiSymbolCenter
        }
    }

    private static func normalizedCenterArtwork(for state: CenterState) -> MeasuredCenterArtwork? {
        let key = normalizedArtworkCacheKey(for: state)
        return normalizedCenterArtwork.image(for: key) {
            rasterizedCenterArtwork(for: state)
        }
    }

    private static func normalizedArtworkCacheKey(for state: CenterState) -> String {
        var assetIdentity = ""
        if case let .symbol(symbol) = state,
           case let .image(url, _) = symbol.source {
            assetIdentity = "|asset=\(IconImageFileIdentity(url: url).cacheToken)"
        }
        return "\(String(describing: state))\(assetIdentity)"
    }

    private static func centerColor(for center: CenterState, foreground: CGColor, criticalColor: CGColor) -> CGColor {
        switch center {
        case let .text(text):
            return sceneColor(for: text.color, foreground: foreground, criticalColor: criticalColor)
        case let .symbol(symbol):
            return sceneColor(for: symbol.color, foreground: foreground, criticalColor: criticalColor)
        }
    }

    private static func rasterizedCenterArtwork(for center: CenterState) -> MeasuredCenterArtwork? {
        let dimension = normalizedArtworkRasterDimension
        let scale = normalizedArtworkRasterScale
        guard let bitmap = CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
                                     bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        bitmap.translateBy(x: CGFloat(dimension) / 2 - wifiSymbolCenter.x * scale,
                           y: CGFloat(dimension) / 2 - wifiSymbolCenter.y * scale)
        bitmap.scaleBy(x: scale, y: scale)
        drawSceneCenter(center, in: bitmap, foreground: CGColor(gray: 1, alpha: 1),
                        criticalColor: CGColor(gray: 1, alpha: 1))
        guard let fullImage = bitmap.makeImage(),
              let bounds = visibleAlphaBounds(of: fullImage, threshold: IconCenterSizingPolicy.visibleInkAlphaThreshold),
              let cropped = fullImage.cropping(to: bounds.integral) else { return nil }
        let anchor = CGFloat(dimension) / 2
        return MeasuredCenterArtwork(
            image: cropped,
            width: CGFloat(cropped.width) / scale,
            height: CGFloat(cropped.height) / scale,
            offsetFromAnchor: CGPoint(x: (bounds.midX - anchor) / scale,
                                      y: (bounds.midY - anchor) / scale)
        )
    }

    private static func drawSceneCenter(
        _ center: CenterState,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        if let percentage = center.normalizedSizePercentageValue {
            drawNormalizedCenterArtwork(center, percentage: percentage, in: context,
                                        foreground: foreground, criticalColor: criticalColor)
            return
        }
        switch center {
        case let .text(text):
            let legacyScale = text.normalizedSizePercentage == nil ? text.scale : 1
            let fontSize = centerSymbolBasePointSize * CGFloat(legacyScale)
            let color = sceneColor(for: text.color, foreground: foreground, criticalColor: criticalColor)
            let referenceLine = sceneTextLine("100", color: color, fontSize: fontSize)
            let referenceHeight = CTLineGetBoundsWithOptions(referenceLine, [.useGlyphPathBounds]).height
            let multiplier = text.normalizedSizePercentage.map {
                CGFloat(IconCenterSizingPolicy.drawingMultiplier(
                    percentage: $0, referenceVisibleHeight: Double(referenceHeight)
                ))
            } ?? 1
            context.saveGState()
            defer { context.restoreGState() }
            applyCenteredScale(multiplier, center: centerTextInkCenter, in: context)

            let line = sceneTextLine(text.text, color: color, fontSize: fontSize)
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            context.setFillColor(color)
            // CoreText measures ink y-up while the text matrix flips glyphs, so
            // the baseline sits *below* the target by the bounds' own midY.
            // Subtracting it here is what pushed larger labels upwards.
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(
                x: centerTextInkCenter.x - bounds.midX,
                y: centerTextInkCenter.y + bounds.midY
            )
            CTLineDraw(line, context)
        case let .symbol(symbol):
            drawSceneSymbol(
                symbol,
                center: wifiSymbolCenter,
                foreground: foreground,
                criticalColor: criticalColor,
                in: context
            )
        }
    }

    private static func drawSceneSymbol(
        _ symbol: IconSymbolState,
        center: CGPoint,
        foreground: CGColor,
        criticalColor: CGColor,
        in context: CGContext
    ) {
        let tint = sceneColor(for: symbol.color, foreground: foreground, criticalColor: criticalColor)
        let legacyScale = symbol.normalizedSizePercentage == nil ? symbol.scale : 1
        let pointSize = centerSymbolPointSize(for: legacyScale)
        let multiplier = symbol.normalizedSizePercentage.map {
            CGFloat(IconCenterSizingPolicy.drawingMultiplier(
                percentage: $0,
                referenceVisibleHeight: Double(centerReferenceVisibleHeight(for: symbol, pointSize: pointSize))
            ))
        } ?? 1
        context.saveGState()
        defer { context.restoreGState() }
        applyCenteredScale(multiplier, center: center, in: context)

        switch symbol.source {
        case let .primitive(primitive):
            switch primitive {
            case .wiredPort:
                drawEthernet(in: context, foreground: tint)
            case .screenWedge:
                drawTemporaryConnectionMark(wifiScale: legacyScale, in: context, foreground: tint)
            case .arrowWedge:
                drawSharedConnectionMark(wifiScale: legacyScale, in: context, foreground: tint)
            case .bolt:
                let path = StatusIconGeometry.batteryChargingBolt(scale: CGFloat(legacyScale))
                context.setFillColor(tint)
                context.addPath(path)
                context.fillPath()
            case .plug:
                drawBatteryPlug(boltScale: CGFloat(legacyScale), foreground: tint, in: context)
            }
        case let .symbol(name, variableValue, fallback):
            let resolved = resolvedCenterSymbolName(name: name, fallback: fallback, color: symbol.color)
            let usesFallback = !availableSymbol(name)
            drawOfficialSymbol(
                name: resolved,
                variableValue: usesFallback ? 1 : (variableValue ?? 1),
                pointSize: pointSize,
                center: center,
                foreground: tint,
                in: context
            )
        case let .image(url, fallbackSymbol):
            let identity = IconImageFileIdentity(url: url)
            if let image = IconImageDecodeCache.shared.decodedImage(for: identity) {
                let inkOffsetX = imageInkOffsetCache.offsetX(for: identity) {
                    measureInkCenterOffsetX(of: image)
                }
                drawTintedImage(image, maxDimension: 42 * (pointSize / centerSymbolBasePointSize),
                                center: center, tint: tint, inkCenterOffsetX: inkOffsetX,
                                in: context)
            } else {
                let fallback = resolvedImageFallbackSymbol(fallbackSymbol)
                drawOfficialSymbol(name: fallback, pointSize: pointSize, center: center,
                                   foreground: tint, in: context)
            }
        }
    }

    private static func applyCenteredScale(_ scale: CGFloat, center: CGPoint, in context: CGContext) {
        guard scale.isFinite, scale > 0, scale != 1 else { return }
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -center.x, y: -center.y)
    }

    private static func resolvedImageFallbackSymbol(_ fallback: String) -> String {
        availableSymbol(fallback) ? fallback : BluetoothDeviceRowIcon.genericSymbol
    }

    private static func resolvedCenterSymbolName(name: String, fallback: String?, color: IconColorRole) -> String {
        if availableSymbol(name) { return name }
        if let fallback, availableSymbol(fallback) { return fallback }
        return color == .bluetooth ? BluetoothDeviceRowIcon.genericSymbol : "wifi"
    }

    /// Uses full/reference glyph metrics at variable value 1.0 so RSSI-driven
    /// variable symbols change their appearance without changing their size.
    private static func centerReferenceVisibleHeight(for state: IconSymbolState, pointSize: CGFloat) -> CGFloat {
        switch state.source {
        case let .symbol(name, _, fallback):
            let resolved = resolvedCenterSymbolName(name: name, fallback: fallback, color: state.color)
            let pointSizeKey = String(Double(pointSize).bitPattern, radix: 16)
            let key = "sf|\(resolved)|semibold|reference=1|pointSize=\(pointSizeKey)"
            let referenceHeight = cachedCenterMetric(for: key) {
                guard let image = configuredSymbol(
                    name: resolved, variableValue: 1, pointSize: pointSize, foreground: .white
                ) else { return nil }
                return visibleAlphaBoundsHeight(of: image.image)
            }
            return referenceHeight ?? pointSize * 0.7
        case let .image(url, fallbackSymbol):
            guard let resolvedImage = centerImages.image(for: url) else {
                let fallback = resolvedImageFallbackSymbol(fallbackSymbol)
                return centerReferenceVisibleHeight(for: IconSymbolState(
                    source: .symbol(name: fallback, variableValue: nil, fallback: nil),
                    color: state.color,
                    scale: state.normalizedSizePercentage == nil ? state.scale : 1
                ), pointSize: pointSize)
            }
            let image = resolvedImage.image
            guard image.size.width > 0, image.size.height > 0 else { return pointSize * 0.7 }
            let maxDimension = 42 * (pointSize / centerSymbolBasePointSize)
            let displayedHeight = min(maxDimension / image.size.width, maxDimension / image.size.height) * image.size.height
            return displayedHeight * resolvedImage.visibleHeightFraction
        case let .primitive(primitive):
            let legacyScale = state.normalizedSizePercentage == nil ? state.scale : 1
            let scaleKey = String(legacyScale.bitPattern, radix: 16)
            let key = "primitive|\(primitive)|\(scaleKey)|geometry-v1"
            return cachedCenterMetric(for: key) {
                switch primitive {
                case .wiredPort:
                    let paths = StatusIconGeometry.ethernetChevrons()
                    let pathBounds = paths.reduce(CGRect.null) { partial, path in
                        partial.union(path.copy(strokingWithWidth: StatusIconGeometry.ethernetStrokeWidth,
                                                lineCap: .butt, lineJoin: .miter, miterLimit: 10).boundingBoxOfPath)
                    }
                    let dotBounds = StatusIconGeometry.ethernetDots().reduce(CGRect.null) { partial, point in
                        let radius = StatusIconGeometry.ethernetDotRadius
                        return partial.union(CGRect(x: point.x - radius, y: point.y - radius,
                                                    width: radius * 2, height: radius * 2))
                    }
                    return pathBounds.union(dotBounds).height
                case .screenWedge:
                    return (StatusIconGeometry.temporaryWedge().boundingBoxOfPath.height + 7) * CGFloat(legacyScale)
                case .arrowWedge:
                    return (StatusIconGeometry.sharedWedge().boundingBoxOfPath.height + 7) * CGFloat(legacyScale)
                case .bolt:
                    return StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height * CGFloat(legacyScale)
                case .plug:
                    let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
                    return boltHeight * CGFloat(legacyScale) * StatusIconGeometry.batteryPlugHeightScale
                }
            } ?? (pointSize * 0.7)
        }
    }

    private static func cachedCenterMetric(for key: String, calculate: () -> CGFloat?) -> CGFloat? {
        if let cached = centerSizingMetrics.value(for: key) { return cached }
        guard let value = calculate(), value.isFinite, value > 0 else { return nil }
        centerSizingMetrics.insert(value, for: key)
        return value
    }

    private static func visibleAlphaBounds(of image: CGImage, threshold: UInt8) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else { return nil }
        let bytesPerRow = image.bytesPerRow
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[y * bytesPerRow + x * bytesPerPixel + 3] >= threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func visibleAlphaBoundsHeight(of image: NSImage) -> CGFloat {
        visibleAlphaBounds(of: image)?.height ?? image.size.height
    }

    fileprivate static func visibleAlphaBoundsForCache(of image: NSImage) -> CGRect? {
        visibleAlphaBounds(of: image)
    }

    private static func visibleAlphaBounds(of image: NSImage) -> CGRect? {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let measurementScale = min(24, 1_024 / max(size.width, size.height))
        let widthValue = (size.width * measurementScale).rounded(.up)
        let heightValue = (size.height * measurementScale).rounded(.up)
        guard let width = Int(exactly: widthValue), let height = Int(exactly: heightValue),
              width > 0, height > 0, width <= Int.max / 4,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: measurementScale, y: measurementScale)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        let visibleInkAlphaThreshold = IconCenterSizingPolicy.visibleInkAlphaThreshold
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] >= visibleInkAlphaThreshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX) / measurementScale, y: CGFloat(minY) / measurementScale,
                      width: CGFloat(maxX - minX + 1) / measurementScale,
                      height: CGFloat(maxY - minY + 1) / measurementScale)
    }

    private static func availableSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private static func drawSceneFooter(
        _ footer: FooterState,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor,
        regions: IconSceneRegion
    ) {
        guard !regions.isDisjoint(with: [.footerTrack, .footerFill]) else { return }

        switch footer {
        case let .dots(dots):
            let points = StatusIconGeometry.volumeDots()
            let dotRadiusScale = 1 + (dots.strokeScale - 1) * 0.5
            let radius = StatusIconGeometry.volumeDotRadius * CGFloat(dotRadiusScale)
            let active = sceneColor(for: dots.color, foreground: foreground, criticalColor: criticalColor)
            let inactive = sceneColor(for: dots.inactiveColor, foreground: foreground, criticalColor: criticalColor)
            for (index, point) in points.prefix(dots.count).enumerated() {
                let isActive = index < dots.activeCount
                guard isActive ? regions.contains(.footerFill) : regions.contains(.footerTrack) else {
                    continue
                }
                context.setFillColor(isActive ? active : inactive)
                context.fillEllipse(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        case let .arc(arc):
            let hidden = sceneColor(for: arc.inactiveColor, foreground: foreground, criticalColor: criticalColor)
            let active = sceneColor(for: arc.color, foreground: foreground, criticalColor: criticalColor)
            if regions.contains(.footerTrack) {
                context.setLineWidth(7 * CGFloat(arc.strokeScale))
                context.setLineCap(.round)
                context.setStrokeColor(hidden)
                context.addPath(StatusIconGeometry.volumeArcTrack())
                context.strokePath()
            }
            guard regions.contains(.footerFill), arc.progress > 0 else { return }
            context.setLineWidth(7 * CGFloat(arc.strokeScale))
            context.setLineCap(.round)
            context.setStrokeColor(active)
            context.addPath(StatusIconGeometry.volumeArcFill(progress: arc.progress))
            context.strokePath()
        }
    }

    private static func sceneColor(
        for role: IconColorRole,
        foreground: CGColor,
        criticalColor: CGColor
    ) -> CGColor {
        switch role {
        case .primary:
            foreground
        case .inactive:
            foreground.copy(alpha: IconColorRole.inactiveTrackOpacity) ?? foreground
        case .critical:
            criticalColor
        case .lowPower:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
            } else {
                CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
            }
        case .powered:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
            } else {
                CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            }
        case .bluetooth:
            bluetoothColor(foreground: foreground)
        case let .custom(color):
            CGColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.alpha))
        }
    }

    private static func drawSceneText(
        _ text: String,
        color: CGColor,
        fontSize: CGFloat,
        baseline: CGPoint,
        in context: CGContext
    ) {
        let line = sceneTextLine(text, color: color, fontSize: fontSize)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        context.setFillColor(color)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    private static func sceneTextLine(_ text: String, color: CGColor, fontSize: CGFloat) -> CTLine {
        let font = batteryValueFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: color) ?? .white
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
