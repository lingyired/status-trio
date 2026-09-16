import AppKit
import CoreGraphics
import CoreText

enum StatusIconRenderer {
    // Keep the 7pt rounded Wi-Fi strokes fully inside the bitmap.
    private static let wifiCanvasBounds = CGRect(
        x: 31.5,
        y: 34.4,
        width: 56,
        height: 56
    )

    /// Unified optical alpha for all inactive tracks (battery groove, Wi-Fi muted signal, volume hidden dots).
    private static let inactiveTrackAlpha: CGFloat = 0.22

    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> NSImage {
        image(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            options: options,
            connectionOptions: connectionOptions
        )
    }

    static func image(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        // Resolve colors while AppKit draws into each menu bar. A pre-rendered
        // bitmap would keep the first display's light or dark foreground.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            var foreground: CGColor = CGColor(gray: 1, alpha: 1)
            var criticalColor: CGColor = Self.defaultCriticalColor

            if let appearance {
                appearance.performAsCurrentDrawingAppearance {
                    foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                        ?? CGColor(gray: 1, alpha: 1)
                    criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                        ?? Self.defaultCriticalColor
                }
            } else {
                foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                    ?? CGColor(gray: 1, alpha: 1)
                criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                    ?? Self.defaultCriticalColor
            }

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(
                menuBarStatus: menuBarStatus,
                options: options,
                connectionOptions: connectionOptions,
                in: context,
                size: size,
                foreground: foreground,
                criticalColor: criticalColor
            )
            return true
        }
    }

    static func wifiImage(wifi: WiFiStatus, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / wifiCanvasBounds.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -wifiCanvasBounds.minX, y: -wifiCanvasBounds.minY)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawWiFi(
            wifi,
            options: .standard,
            in: context,
            foreground: CGColor(gray: 1, alpha: 1)
        )
        image.isTemplate = true
        return image
    }

    static func render(
        snapshot: StatusSnapshot,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> CGImage? {
        render(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            scale: scale,
            foreground: foreground,
            options: options,
            connectionOptions: connectionOptions
        )
    }

    static func render(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> CGImage? {
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

        context.scaleBy(x: scale, y: scale)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor
        )
        return context.makeImage()
    }

    /// Draws the status glyph into an existing context, using the renderer's
    /// canvas coordinates. Avoids the intermediate bitmap that `render` creates.
    static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        foreground: CGColor,
        in context: CGContext,
        origin: CGPoint,
        size: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: origin.x, y: origin.y)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor
        )
    }

    private static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / StatusIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBattery(
            menuBarStatus.battery,
            options: options,
            in: context,
            foreground: foreground,
            criticalColor: criticalColor
        )
        if menuBarStatus.connection == .ethernet {
            if connectionOptions.showsWiFiIconForEthernet {
                drawStandardWiFi(menuBarStatus.wifi, in: context, foreground: foreground)
            } else {
                drawEthernet(in: context, foreground: foreground)
            }
        } else {
            drawWiFi(
                menuBarStatus.wifi,
                options: connectionOptions,
                in: context,
                foreground: foreground
            )
        }
        drawVolume(menuBarStatus.volume, in: context, foreground: foreground)
    }

    private static func drawBattery(
        _ battery: BatteryStatus,
        options: BatteryIconOptions,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let showsChargingBolt = battery.isPresent
            && (battery.isCharging || battery.isConnectedToPower)
            && options.showsChargingIndicator
        let hasTopGap = showsChargingBolt || options.showsPercentage
        let topGapWidth = showsChargingBolt
            ? StatusIconGeometry.batteryChargingBoltTopGapWidth
            : StatusIconGeometry.batteryValueTopGapWidth

        context.setLineWidth(8)
        context.setStrokeColor(foreground.copy(alpha: inactiveTrackAlpha) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack(
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        let role = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        let arcColor = color(
            for: role,
            foreground: foreground,
            criticalColor: criticalColor
        )

        context.setStrokeColor(arcColor)
        context.addPath(StatusIconGeometry.batteryFill(
            progress: StatusMappings.batteryProgress(battery),
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        if showsChargingBolt {
            context.setFillColor(foreground)
            context.addPath(StatusIconGeometry.batteryChargingBolt(
                scale: batteryChargingBoltScale(textScale: options.textScale)
            ))
            context.fillPath()
        } else if options.showsPercentage {
            drawBatteryPercentage(
                battery.percentage,
                color: foreground,
                fontSize: batteryValueFontSize(scale: options.textScale),
                in: context
            )
        }
    }

    private static func color(
        for role: BatteryColorRole,
        foreground: CGColor,
        criticalColor: CGColor
    ) -> CGColor {
        switch role {
        case .foreground:
            foreground
        case .critical:
            criticalColor
        case .charging:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
            } else {
                CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            }
        case .lowPower:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
            } else {
                CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
            }
        }
    }

    private static func usesDarkStatusPalette(foreground: CGColor) -> Bool {
        guard let color = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.brightnessComponent < 0.5
    }

    private static func drawBatteryPercentage(
        _ percentage: Int,
        color: CGColor,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = batteryValueFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: color) ?? .white
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(percentage), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = StatusIconGeometry.batteryValueBaseline(fontSize: fontSize)

        context.setFillColor(color)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    private static func batteryValueFontSize(scale: Double) -> CGFloat {
        StatusIconGeometry.batteryValueBaseFontSize * CGFloat(scale)
    }

    private static func batteryChargingBoltScale(textScale: Double) -> CGFloat {
        let fontSize = batteryValueFontSize(scale: textScale)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "100",
                attributes: [.font: batteryValueFont(size: fontSize)]
            )
        )
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        guard glyphHeight.isFinite,
              glyphHeight > 0,
              boltHeight.isFinite,
              boltHeight > 0
        else {
            return CGFloat(textScale / BatteryIconOptions.defaultTextScale)
                * StatusIconGeometry.batteryChargingBoltCalibration
        }
        return CGFloat(glyphHeight) / boltHeight
            * StatusIconGeometry.batteryChargingBoltCalibration
    }

    private static var defaultCriticalColor: CGColor {
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

    private static func drawWiFi(
        _ wifi: WiFiStatus,
        options: ConnectionIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let mutedColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground

        context.setLineWidth(7)

        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .notAssociated, .off, .unavailable:
            drawWiFiSignal(level: 3, color: mutedColor, in: context)

            if wifi.state == .off || wifi.state == .unavailable {
                context.setStrokeColor(mutedColor)
                context.setLineWidth(6)
                context.addPath(StatusIconGeometry.wifiOffSlash())
                context.strokePath()
            }
        case .noInternet:
            drawWiFiSignal(level: 3, color: mutedColor, includeDot: false, in: context)

            let overlay = StatusIconGeometry.noInternetOverlay()
            context.setStrokeColor(mutedColor)
            context.setLineWidth(5)
            context.addPath(overlay.stem)
            context.strokePath()

            context.setFillColor(mutedColor)
            context.addPath(overlay.dot)
            context.fillPath()
        case .hotspot where options.showsWiFiIconForHotspot:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .hotspot:
            context.setStrokeColor(foreground)
            context.setLineWidth(5)
            for path in StatusIconGeometry.hotspotOverlay() {
                context.addPath(path)
                context.strokePath()
            }
        case .temporary where options.showsWiFiIconForTemporaryConnection:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .temporary:
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
        case .shared where options.showsWiFiIconForInternetSharing:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .shared:
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
    }

    private static func drawStandardWiFi(
        _ wifi: WiFiStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setLineWidth(7)
        let bars = StatusMappings.wifiBars(rssi: wifi.rssi)
        let mutedColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground

        // Always draw the complete 3-bar signal track in muted color so the icon geometry
        // remains balanced even when signal is low, matching battery and volume tracks.
        drawWiFiSignal(level: 3, color: mutedColor, in: context)

        // Overlay active signal bars in solid foreground
        if bars > 0 {
            drawWiFiSignal(level: bars, color: foreground, in: context)
        }
    }

    private static func drawWiFiSignal(
        level: Int,
        color: CGColor,
        includeDot: Bool = true,
        in context: CGContext
    ) {
        context.setStrokeColor(color)
        for path in StatusIconGeometry.wifiArcs(level: level) {
            context.addPath(path)
            context.strokePath()
        }

        guard includeDot else { return }
        context.setFillColor(color)
        context.addPath(StatusIconGeometry.wifiDot())
        context.fillPath()
    }

    private static func drawVolume(
        _ volume: MenuBarVolumeStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
        let hiddenColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground

        for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
            context.setFillColor(index < level ? foreground : hiddenColor)
            let radius = StatusIconGeometry.volumeDotRadius
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
}
