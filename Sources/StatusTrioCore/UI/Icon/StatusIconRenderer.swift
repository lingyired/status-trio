import AppKit
import CoreGraphics
import CoreText

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
    private var order: [SymbolInkKey] = []

    func offsetX(for key: SymbolInkKey, measure: () -> CGFloat) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return cached
        }
        let measured = measure()
        storage[key] = measured
        order.append(key)
        if order.count > 256 { storage[order.removeFirst()] = nil }
        return measured
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }
}

/// The same ink measurement for an input source's own icon file, which is a
/// bitmap or PDF whose visible ink is not centred in the box `NSImage.size`
/// reports. The normalized pixel dimensions are part of the key because the
/// same file can be decoded at more than one bounded size; ink measured in one
/// pixel space must never be reused for another.
private final class ImageInkOffsetCache: @unchecked Sendable {
    private struct Key: Hashable {
        let url: URL
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private struct Entry {
        weak var image: NSImage?
        let offsetX: CGFloat
    }

    private let lock = NSLock()
    private var storage: [Key: Entry] = [:]
    private var order: [Key] = []
    private let maximumEntries = 64

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    func offsetX(
        for url: URL,
        image: NSImage,
        pixelWidth: Int,
        pixelHeight: Int,
        measure: () -> CGFloat
    ) -> CGFloat {
        let key = Key(url: url, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key], cached.image === image {
            touch(key)
            return cached.offsetX
        }
        let measured = measure()
        storage[key] = Entry(image: image, offsetX: measured)
        order.append(key)
        while order.count > maximumEntries {
            storage[order.removeFirst()] = nil
        }
        return measured
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

enum StatusIconRenderer {
    private static let symbolInkOffsetCache = SymbolInkOffsetCache()
    private static let imageInkOffsetCache = ImageInkOffsetCache()

    static func resetInkOffsetCaches() {
        symbolInkOffsetCache.reset()
        imageInkOffsetCache.reset()
    }

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

    /// Unified optical alpha for all inactive tracks (battery groove, Wi-Fi muted signal, volume hidden dots).
    private static let inactiveTrackAlpha: CGFloat = 0.22
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
            let bright = highlightColor.copy(alpha: min(1, max(0, frame.tailAlpha))) ?? highlightColor
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
            context.setFillColor(highlightColor.copy(alpha: min(1, frame.beadAlpha)) ?? highlightColor)
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
            context.setFillColor(highlightColor.copy(alpha: min(1, frame.heartbeatAlpha)) ?? highlightColor)
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
    /// for the rounding to be negligible. This calibration asks only for the
    /// symbol's layout height; measuring ink here would rasterize a 200-point
    /// glyph at the previous path's 8x sampling and retain millions of bytes
    /// for an offset this path never reads.
    private static let batteryPlugHeightPerPoint: CGFloat = {
        let referencePointSize: CGFloat = 200
        let image = configuredSymbolImage(
            name: StatusIconGeometry.batteryPlugSymbolName,
            pointSize: referencePointSize,
            foreground: .labelColor
        )
        guard let image else { return 1.34 }
        let height = image.size.height
        guard height.isFinite, height > 0 else { return 1.34 }
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
        guard let image = configuredSymbolImage(
            name: name,
            variableValue: variableValue,
            pointSize: pointSize,
            foreground: foreground
        ) else { return nil }

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

    private static func configuredSymbolImage(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        foreground: NSColor
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: foreground))
        return NSImage(
            systemSymbolName: name,
            variableValue: variableValue,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
    }

    /// Horizontal distance from the image's layout-box centre to the centre of
    /// its visible ink. Rasterising at 6x keeps the measurement below the
    /// 0.25-point quantum of the 120-unit icon grid. Imported files cap their
    /// measurement context independently because their logical point size can
    /// be much larger than their bounded decoded bitmap.
    private static func measureInkCenterOffsetX(
        of image: NSImage,
        maximumPixelLength: Int? = nil
    ) -> CGFloat {
        let defaultPixelScale: CGFloat = 6
        let pixelScale: CGFloat
        if let maximumPixelLength {
            let largestLogicalDimension = max(image.size.width, image.size.height)
            guard maximumPixelLength > 0,
                  largestLogicalDimension.isFinite,
                  largestLogicalDimension > 0 else {
                return 0
            }
            pixelScale = min(
                defaultPixelScale,
                CGFloat(maximumPixelLength) / largestLogicalDimension
            )
        } else {
            pixelScale = defaultPixelScale
        }
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

        let base: NSImage
        if let templateBase = menuBarTemplateBase(
            scene: scene,
            size: size,
            scale: scale,
            appearance: appearance
        ) {
            base = templateBase
        } else if !scene.chromaticRegions.isEmpty,
                  let placeholder = transparentMenuBarImage(size: size, scale: scale) {
            // The monochrome primitives could not be rasterized but the scene
            // still carries status colours: keep the item's footprint so the
            // chromatic overlay is still visible.
            placeholder.isTemplate = true
            base = placeholder
        } else {
            return nil
        }

        return MenuBarLayers(
            base: base,
            overlay: menuBarChromaticImage(
                scene: scene,
                size: size,
                scale: scale,
                appearance: appearance,
                phase: phase
            )
        )
    }

    /// The template base alone: every monochrome primitive, marked so the system
    /// re-tints it for the Space that is on top.
    ///
    /// This is the half of `menuBarLayers` that changes only when the icon state
    /// does, so the animation path can leave it installed across ticks and
    /// rasterize the overlay on its own. `nil` means the primitives could not be
    /// produced; callers keep the icon they are already showing and retry on the
    /// next state change.
    @MainActor
    static func menuBarTemplateBase(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?
    ) -> NSImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }
        guard let image = image(
            scene: scene,
            size: size,
            scale: scale,
            appearance: appearance,
            phase: nil,
            regions: scene.templateRegions
        ) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    /// The custom-colour half of the same split, or `nil` when the scene draws
    /// with the label colour alone and there is nothing to overlay.
    ///
    /// The animated overlay is built through this entry point so a 20-Hz tick
    /// never re-rasterizes the monochrome primitives.
    @MainActor
    static func menuBarChromaticImage(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?,
        phase: ChargingEffectPhase? = nil
    ) -> CGImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }
        let regions = scene.chromaticRegions
        guard !regions.isEmpty else { return nil }
        return render(
            scene: scene,
            environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
            phase: phase,
            regions: regions
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
            statusPalette: environment.statusPalette,
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

    static func renderEnvironment(
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?
    ) -> StatusIconRenderEnvironment {
        let resolvedAppearance = appearance ?? NSAppearance.currentDrawing()
        let match = resolvedAppearance.bestMatch(from: [.aqua, .darkAqua])
        var isDark = match == .darkAqua
        if match == nil {
            // No aqua/darkAqua match (e.g. a vibrant appearance): fall back to
            // the label colour's own brightness so dark bars still get white
            // ink instead of an invisible black.
            var labelBrightness: CGFloat = 0
            resolvedAppearance.performAsCurrentDrawingAppearance {
                labelBrightness = NSColor.labelColor.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
            }
            isDark = labelBrightness > 0.5
        }
        let palette = BatteryStatusColorPalette.resolved(appearance: resolvedAppearance)
        return StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: CGColor(gray: isDark ? 1 : 0, alpha: 1),
            criticalColor: palette.critical,
            statusPalette: palette
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
        statusPalette: BatteryStatusColorPalette? = nil,
        phase: ChargingEffectPhase? = nil,
        regions: IconSceneRegion = .all
    ) -> Bool {
        guard size.isFinite, size > 0, supports(scene) else { return false }
        let darkInk = (NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) >= 0.5
        let palette = (statusPalette ?? .inferred(foreground: foreground, critical: criticalColor))
            .applying(scene.statusColors, darkAppearance: darkInk)

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
                statusPalette: palette,
                phase: phase,
                regions: regions
            )
        }
        if let center = scene.center, regions.contains(.center) {
            drawSceneCenter(center, in: context, foreground: foreground, statusPalette: palette)
        }
        if let footer = scene.footer {
            drawSceneFooter(
                footer,
                in: context,
                foreground: foreground,
                statusPalette: palette,
                regions: regions
            )
        }
        return true
    }

    private static func supports(_ scene: IconSceneState) -> Bool {
        if let ring = scene.outerRing, ring.segments.count != 1 { return false }
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
        statusPalette: BatteryStatusColorPalette,
        phase: ChargingEffectPhase?,
        regions: IconSceneRegion
    ) {
        let drawsRing = !regions.isDisjoint(with: [.ringTrack, .ringFill, .ringEffect])
        let drawsAccessory = regions.contains(.ringAccessory) && ring.accessory != nil
        guard drawsRing || drawsAccessory else { return }

        guard let segment = ring.segments.first else { return }
        let hasTopGap = ring.gap != .closed
        let topGapWidth = ring.gap == .indicator
            ? StatusIconGeometry.batteryChargingBoltTopGapWidth
            : StatusIconGeometry.batteryValueTopGapWidth
        let lineWidth = 8 * CGFloat(ring.strokeScale)

        let arcColor = sceneColor(for: segment.color, foreground: foreground, statusPalette: statusPalette)
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
            context.setStrokeColor(foreground.copy(alpha: inactiveTrackAlpha) ?? foreground)
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
                color: sceneColor(for: text.color, foreground: foreground, statusPalette: statusPalette),
                fontSize: batteryValueFontSize(scale: text.scale),
                baseline: StatusIconGeometry.batteryValueBaseline(fontSize: batteryValueFontSize(scale: text.scale)),
                in: context
            )
        case let .symbol(symbol):
            if case .primitive(.bolt) = symbol.source {
                let baseColor = sceneColor(for: symbol.color, foreground: foreground, statusPalette: statusPalette)
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
                    foreground: sceneColor(for: symbol.color, foreground: foreground, statusPalette: statusPalette),
                    in: context
                )
            } else {
                drawSceneSymbol(
                    symbol,
                    center: StatusIconGeometry.batteryTopIndicatorCenter(
                        boltScale: batteryChargingBoltScale(textScale: symbol.scale)
                    ),
                    foreground: foreground,
                    statusPalette: statusPalette,
                    in: context
                )
            }
        }
    }

    private static func drawSceneCenter(
        _ center: CenterState,
        in context: CGContext,
        foreground: CGColor,
        statusPalette: BatteryStatusColorPalette
    ) {
        switch center {
        case let .text(text):
            let fontSize = centerSymbolBasePointSize * CGFloat(text.scale)
            let color = sceneColor(for: text.color, foreground: foreground, statusPalette: statusPalette)
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
                statusPalette: statusPalette,
                in: context
            )
        }
    }

    private static func drawSceneSymbol(
        _ symbol: IconSymbolState,
        center: CGPoint,
        foreground: CGColor,
        statusPalette: BatteryStatusColorPalette,
        in context: CGContext
    ) {
        let tint = sceneColor(for: symbol.color, foreground: foreground, statusPalette: statusPalette)
        let pointSize = centerSymbolPointSize(for: symbol.scale)
        switch symbol.source {
        case let .primitive(primitive):
            switch primitive {
            case .wiredPort:
                drawEthernet(in: context, foreground: tint)
            case .screenWedge:
                drawTemporaryConnectionMark(wifiScale: symbol.scale, in: context, foreground: tint)
            case .arrowWedge:
                drawSharedConnectionMark(wifiScale: symbol.scale, in: context, foreground: tint)
            case .bolt:
                let path = StatusIconGeometry.batteryChargingBolt(scale: CGFloat(symbol.scale))
                context.setFillColor(tint)
                context.addPath(path)
                context.fillPath()
            case .plug:
                drawBatteryPlug(boltScale: CGFloat(symbol.scale), foreground: tint, in: context)
            }
        case let .symbol(name, variableValue, fallback):
            let chosen = availableSymbol(name) ? name : fallback.flatMap { availableSymbol($0) ? $0 : nil }
            let resolved = chosen ?? (symbol.color == .bluetooth ? BluetoothDeviceRowIcon.genericSymbol : "wifi")
            drawOfficialSymbol(
                name: resolved,
                variableValue: chosen == nil ? 1 : (variableValue ?? 1),
                pointSize: pointSize,
                center: center,
                foreground: tint,
                in: context
            )
        case let .image(url, fallbackSymbol):
            if let image = IconImageDecodeCache.shared.decodedImage(for: url) {
                guard let representation = image.representations.first else { return }
                let inkOffsetX = imageInkOffsetCache.offsetX(
                    for: url,
                    image: image,
                    pixelWidth: representation.pixelsWide,
                    pixelHeight: representation.pixelsHigh
                ) {
                    measureInkCenterOffsetX(
                        of: image,
                        maximumPixelLength: 1024
                    )
                }
                drawTintedImage(image,
                                maxDimension: 42 * (pointSize / centerSymbolBasePointSize),
                                center: center,
                                tint: tint,
                                inkCenterOffsetX: inkOffsetX,
                                in: context)
            } else {
                let fallback = availableSymbol(fallbackSymbol)
                    ? fallbackSymbol
                    : BluetoothDeviceRowIcon.genericSymbol
                drawOfficialSymbol(name: fallback, pointSize: pointSize, center: center,
                                   foreground: tint, in: context)
            }
        }
    }

    private static func availableSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private static func drawSceneFooter(
        _ footer: FooterState,
        in context: CGContext,
        foreground: CGColor,
        statusPalette: BatteryStatusColorPalette,
        regions: IconSceneRegion
    ) {
        guard !regions.isDisjoint(with: [.footerTrack, .footerFill]) else { return }

        switch footer {
        case let .dots(dots):
            let points = StatusIconGeometry.volumeDots()
            let dotRadiusScale = 1 + (dots.strokeScale - 1) * 0.5
            let radius = StatusIconGeometry.volumeDotRadius * CGFloat(dotRadiusScale)
            let active = sceneColor(for: dots.color, foreground: foreground, statusPalette: statusPalette)
            let inactive = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
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
            let hidden = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            let active = sceneColor(for: arc.color, foreground: foreground, statusPalette: statusPalette)
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
        statusPalette: BatteryStatusColorPalette
    ) -> CGColor {
        switch role {
        case .primary:
            foreground
        case .inactive:
            foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
        case .critical:
            statusPalette.critical
        case .lowPower:
            statusPalette.lowPower
        case .powered:
            statusPalette.charging
        case .bluetooth:
            bluetoothColor(foreground: foreground)
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
