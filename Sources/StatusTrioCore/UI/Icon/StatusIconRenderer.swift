import AppKit
import CoreGraphics
import CoreText

enum StatusIconRenderer {
    static let centerSymbolBasePointSize: CGFloat = 38
    private static let defaultBatteryValueTextScale = 1.8

    /// Anchored to the artwork's centre, not the canvas midpoint: the vector
    /// art is drawn on a 119-unit box centred at 59.5, so `canvas.midX` (60.0)
    /// puts every SF Symbol half a unit right of it. See issue #30.
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



    /// Centre of the middle connection slot, which the Wi-Fi, Ethernet and
    /// Bluetooth glyphs all share.
    ///
    /// `y` is not `wifiSymbolCenter.y`: the Wi-Fi glyph's dense strokes sit
    /// below the geometric middle of the slot, so text drawn from a centred
    /// baseline reads low against them.
    private static let connectionSlotCenter = CGPoint(
        x: StatusIconGeometry.artworkCenterX,
        y: 87
    )

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
        )?.size.height, height.isFinite, height > 0 else {
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
            x: center.x - size.width / 2,
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
            x: center.x - symbol.size.width / 2,
            y: -(center.y + symbol.size.height / 2),
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: targetRect)
    }

    private static func configuredSymbol(
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
}

extension StatusIconRenderer {
    static func preRenderedMenuBarImage(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance,
        phase: ChargingEffectPhase
    ) -> NSImage? {
        guard let cgImage = render(
            scene: scene,
            environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
            phase: phase
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    static func render(
        scene: IconSceneState,
        environment: StatusIconRenderEnvironment,
        phase: ChargingEffectPhase? = nil
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
            phase: phase
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
        phase: ChargingEffectPhase? = nil
    ) -> NSImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        // Validate the scene and dimensions synchronously while keeping an NSImage
        // drawing handler so automatic appearances resolve again on every draw.
        guard render(
            scene: scene,
            environment: renderEnvironment(size: size, scale: scale, appearance: appearance),
            phase: phase
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
                          phase: phase
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
        phase: ChargingEffectPhase? = nil
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
            drawSceneRing(ring, in: context, foreground: foreground, criticalColor: criticalColor, phase: phase)
        }
        if let center = scene.center {
            drawSceneCenter(center, in: context, foreground: foreground, criticalColor: criticalColor)
        }
        if let footer = scene.footer {
            drawSceneFooter(footer, in: context, foreground: foreground, criticalColor: criticalColor)
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
        criticalColor: CGColor,
        phase: ChargingEffectPhase?
    ) {
        guard let segment = ring.segments.first else { return }
        let hasTopGap = ring.gap != .closed
        let topGapWidth = ring.gap == .indicator
            ? StatusIconGeometry.batteryChargingBoltTopGapWidth
            : StatusIconGeometry.batteryValueTopGapWidth
        let lineWidth = 8 * CGFloat(ring.strokeScale)

        context.setLineWidth(lineWidth)
        context.setStrokeColor(foreground.copy(alpha: inactiveTrackAlpha) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack(hasTopGap: hasTopGap, topGapWidth: topGapWidth))
        context.strokePath()

        let arcColor = sceneColor(for: segment.color, foreground: foreground, criticalColor: criticalColor)
        context.setStrokeColor(arcColor)
        context.addPath(StatusIconGeometry.batteryFill(
            progress: segment.progress,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

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
        if let effectFrame, let effectHighlight {
            drawChargingEffect(
                effectFrame,
                highlightColor: effectHighlight,
                lineWidth: lineWidth,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth,
                in: context
            )
        }

        guard let accessory = ring.accessory else { return }
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

    private static func drawSceneCenter(
        _ center: CenterState,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        switch center {
        case let .text(text):
            let fontSize = centerSymbolBasePointSize * CGFloat(text.scale)
            let color = sceneColor(for: text.color, foreground: foreground, criticalColor: criticalColor)
            let line = sceneTextLine(text.text, color: color, fontSize: fontSize)
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            context.setFillColor(color)
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(
                x: connectionSlotCenter.x - bounds.midX,
                y: connectionSlotCenter.y - bounds.midY
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
            if let image = NSImage(contentsOf: url) {
                drawTintedImage(image, maxDimension: 42 * (pointSize / centerSymbolBasePointSize),
                                center: center, tint: tint, in: context)
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
        criticalColor: CGColor
    ) {
        switch footer {
        case let .dots(dots):
            let points = StatusIconGeometry.volumeDots()
            let dotRadiusScale = 1 + (dots.strokeScale - 1) * 0.5
            let radius = StatusIconGeometry.volumeDotRadius * CGFloat(dotRadiusScale)
            let active = sceneColor(for: dots.color, foreground: foreground, criticalColor: criticalColor)
            let inactive = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            for (index, point) in points.prefix(dots.count).enumerated() {
                context.setFillColor(index < dots.activeCount ? active : inactive)
                context.fillEllipse(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        case let .arc(arc):
            let hidden = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            let active = sceneColor(for: arc.color, foreground: foreground, criticalColor: criticalColor)
            context.setLineWidth(7 * CGFloat(arc.strokeScale))
            context.setLineCap(.round)
            context.setStrokeColor(hidden)
            context.addPath(StatusIconGeometry.volumeArcTrack())
            context.strokePath()
            guard arc.progress > 0 else { return }
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
            foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
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
