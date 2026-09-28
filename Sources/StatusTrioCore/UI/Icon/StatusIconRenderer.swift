import AppKit
import CoreGraphics
import CoreText

enum StatusIconRenderer {
    static let centerSymbolBasePointSize: CGFloat = 38

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

    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        phase: ChargingEffectPhase? = nil
    ) -> NSImage {
        image(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            phase: phase
        )
    }

    static func image(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        appearance: NSAppearance? = nil,
        phase: ChargingEffectPhase? = nil
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
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: bluetoothAudioOptions,
                in: context,
                size: size,
                foreground: foreground,
                criticalColor: criticalColor,
                phase: phase
            )
            return true
        }
    }

    static func wifiImage(
        wifi: WiFiStatus,
        size: CGFloat,
        options: ConnectionIconOptions = .standard
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / 56.0
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(
            x: -(wifiSymbolCenter.x - 28.0),
            y: -(wifiSymbolCenter.y - 28.0)
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawWiFi(
            wifi,
            options: options,
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
        criticalColor: CGColor? = nil,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        phase: ChargingEffectPhase? = nil
    ) -> CGImage? {
        render(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: criticalColor,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            phase: phase
        )
    }

    static func render(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor? = nil,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        phase: ChargingEffectPhase? = nil
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
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: criticalColor ?? defaultCriticalColor,
            phase: phase
        )
        return context.makeImage()
    }

    /// Creates a fully rasterized menu-bar image for reuse across animation ticks.
    @MainActor
    static func preRenderedMenuBarImage(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance,
        phase: ChargingEffectPhase,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) -> NSImage? {
        var foreground = CGColor(gray: 1, alpha: 1)
        var criticalColor = Self.defaultCriticalColor
        appearance.performAsCurrentDrawingAppearance {
            foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? Self.defaultCriticalColor
        }

        guard let cgImage = render(
            menuBarStatus: menuBarStatus,
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: criticalColor,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            phase: phase
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

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
    static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        foreground: CGColor,
        in context: CGContext,
        origin: CGPoint,
        size: CGFloat,
        phase: ChargingEffectPhase? = nil
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: origin.x, y: origin.y)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor,
            phase: phase
        )
    }

    private static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions,
        bluetoothAudioOptions: BluetoothAudioIconOptions,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor,
        phase: ChargingEffectPhase?
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
            criticalColor: criticalColor,
            phase: phase
        )
        if StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: menuBarStatus.volume.currentDevice,
            wifi: menuBarStatus.wifi,
            connection: menuBarStatus.connection,
            options: bluetoothAudioOptions
        ) {
            drawBluetoothAudioDevice(
                menuBarStatus.volume.currentDevice,
                symbolOverride: bluetoothAudioOptions.networkIconSymbolOverride,
                options: bluetoothAudioOptions,
                in: context,
                foreground: foreground
            )
        } else if menuBarStatus.connection == .ethernet {
            if connectionOptions.showsWiFiIconForEthernet {
                drawFullWiFi(
                    wifiScale: connectionOptions.wifiScale,
                    in: context,
                    foreground: foreground
                )
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
        drawVolume(
            menuBarStatus.volume,
            options: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            foreground: foreground
        )
    }

    private static func drawBattery(
        _ battery: BatteryStatus,
        options: BatteryIconOptions,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor,
        phase: ChargingEffectPhase?
    ) {
        let gapContent = StatusMappings.batteryGapContent(battery, options: options)
        let hasTopGap = gapContent != .empty
        let topGapWidth = switch gapContent {
        case .bolt, .plug: StatusIconGeometry.batteryChargingBoltTopGapWidth
        case .percentage, .empty: StatusIconGeometry.batteryValueTopGapWidth
        }

        context.setLineWidth(8 * CGFloat(options.ringStrokeScale))
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

        let chargingEffectFrame: ChargingEffectFrame? = {
            guard options.showsChargingEffect,
                  battery.isPresent,
                  battery.isCharging,
                  !battery.isCharged,
                  let phase else {
                return nil
            }
            return ChargingEffectPolicy.frame(
                progress: StatusMappings.batteryProgress(battery),
                phase: phase,
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth
            )
        }()
        if let chargingEffectFrame {
            drawChargingEffect(
                chargingEffectFrame,
                fillColor: arcColor,
                lineWidth: 8 * CGFloat(options.ringStrokeScale),
                hasTopGap: hasTopGap,
                topGapWidth: topGapWidth,
                in: context
            )
        }

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        let indicatorScale = batteryChargingBoltScale(textScale: options.textScale)

        switch gapContent {
        case .bolt:
            let bolt = StatusIconGeometry.batteryChargingBolt(
                scale: indicatorScale * CGFloat(chargingEffectFrame?.boltScale ?? 1)
            )
            context.setFillColor(
                chargingEffectFrame?.boltUsesArcColor == true ? arcColor : foreground
            )
            context.addPath(bolt)
            context.fillPath()
        case .plug:
            drawBatteryPlug(
                boltScale: indicatorScale,
                foreground: foreground,
                in: context
            )
        case .percentage:
            drawBatteryPercentage(
                battery.percentage,
                color: foreground,
                fontSize: batteryValueFontSize(scale: options.textScale),
                in: context
            )
        case .empty:
            break
        }
    }

    private static func drawChargingEffect(
        _ frame: ChargingEffectFrame,
        fillColor: CGColor,
        lineWidth: CGFloat,
        hasTopGap: Bool,
        topGapWidth: CGFloat,
        in context: CGContext
    ) {
        let highlight = ChargingEffectPalette.automaticHighlight(for: fillColor)

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
            let transparent = highlight.copy(alpha: 0) ?? highlight
            let bright = highlight.copy(alpha: min(1, max(0, frame.tailAlpha))) ?? highlight
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
            context.setFillColor(highlight.copy(alpha: min(1, frame.beadAlpha)) ?? highlight)
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
            context.setFillColor(highlight.copy(alpha: min(1, frame.heartbeatAlpha)) ?? highlight)
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

    private static func bluetoothColor(foreground: CGColor) -> CGColor {
        usesDarkStatusPalette(foreground: foreground)
            ? bluetoothBlueOnLightBackground
            : bluetoothBlueOnDarkBackground
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
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = batteryTopIndicatorHeight(textScale: textScale)
        guard boltHeight.isFinite, boltHeight > 0, targetHeight > 0 else {
            return CGFloat(textScale / BatteryIconOptions.defaultTextScale)
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
                * CGFloat(textScale / BatteryIconOptions.defaultTextScale)
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

    private static func drawBluetoothAudioDevice(
        _ device: AudioOutputDevice?,
        symbolOverride: String?,
        options: BluetoothAudioIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let tint = bluetoothColor(foreground: foreground)
        let pointSize = centerSymbolPointSize(for: options.symbolScale)
        let scale = pointSize / centerSymbolBasePointSize
        let maxDimension = 42 * scale

        // A picked device draws the symbol it resolved to at pick time; the
        // availability check reroutes a symbol the running system does not ship
        // to the generic Bluetooth glyph, the same fallback a device row uses.
        if let symbolOverride {
            let available = NSImage(systemSymbolName: symbolOverride, accessibilityDescription: nil) != nil
            drawOfficialSymbol(
                name: available ? symbolOverride : BluetoothDeviceRowIcon.genericSymbol,
                pointSize: pointSize,
                foreground: tint,
                in: context
            )
            return
        }

        guard let device else { return }
        switch AudioOutputDeviceIcon.source(for: device) {
        case let .symbol(name):
            drawOfficialSymbol(
                name: name,
                pointSize: pointSize,
                foreground: tint,
                in: context
            )
        case let .image(url):
            guard let image = NSImage(contentsOf: url) else {
                drawOfficialSymbol(
                    name: "headphones",
                    pointSize: pointSize,
                    foreground: tint,
                    in: context
                )
                return
            }
            drawTintedImage(
                image,
                maxDimension: maxDimension,
                center: wifiSymbolCenter,
                tint: tint,
                in: context
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

    private static func drawWiFi(
        _ wifi: WiFiStatus,
        options: ConnectionIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let symbolPointSize = centerSymbolPointSize(for: options.wifiScale)

        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .notAssociated:
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .off, .unavailable:
            drawOfficialSymbol(
                name: "wifi.slash",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .noInternet:
            drawOfficialSymbol(
                name: "wifi.exclamationmark",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .hotspot where options.showsWiFiIconForHotspot:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .hotspot:
            drawOfficialSymbol(
                name: "personalhotspot",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .temporary where options.showsWiFiIconForTemporaryConnection:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .temporary:
            drawTemporaryConnectionMark(
                wifiScale: options.wifiScale,
                in: context,
                foreground: foreground
            )
        case .shared where options.showsWiFiIconForInternetSharing:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .shared:
            drawSharedConnectionMark(
                wifiScale: options.wifiScale,
                in: context,
                foreground: foreground
            )
        }
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
    private static func drawFullWiFi(
        wifiScale: Double,
        in context: CGContext,
        foreground: CGColor
    ) {
        drawOfficialSymbol(
            name: "wifi",
            variableValue: 1.0,
            pointSize: centerSymbolPointSize(for: wifiScale),
            foreground: foreground,
            in: context
        )
    }

    private static func drawStandardWiFi(
        _ wifi: WiFiStatus,
        wifiScale: Double = 1.0,
        in context: CGContext,
        foreground: CGColor
    ) {
        let symbolPointSize = centerSymbolPointSize(for: wifiScale)
        let bars = StatusMappings.wifiBars(rssi: wifi.rssi)
        if bars == 0 {
            let mutedColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: mutedColor,
                in: context
            )
        } else {
            let variableValue: Double = switch bars {
            case 3: 1.0
            case 2: 0.66
            case 1: 0.33
            default: 0.0
            }
            drawOfficialSymbol(
                name: "wifi",
                variableValue: variableValue,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        }
    }

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

    private static func drawVolume(
        _ volume: MenuBarVolumeStatus,
        options: VolumeIconOptions,
        bluetoothAudioOptions: BluetoothAudioIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let hiddenColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
        let activeColor = bluetoothAudioOptions.usesVolumeColor
            && volume.currentDevice?.isBluetoothAudio == true
            ? bluetoothColor(foreground: foreground)
            : foreground

        switch options.displayStyle {
        case .dots:
            let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
            let radius = StatusIconGeometry.volumeDotRadius * CGFloat(options.dotRadiusScale)
            for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
                context.setFillColor(index < level ? activeColor : hiddenColor)
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        case .arc:
            // Continuous arc bounded between Dot 0 (left, ~122°) and Dot 3 (right, ~59°)
            context.setLineWidth(7 * CGFloat(options.ringStrokeScale))
            context.setLineCap(.round)
            context.setStrokeColor(hiddenColor)
            context.addPath(StatusIconGeometry.volumeArcTrack())
            context.strokePath()

            guard !volume.isMuted, let scalar = volume.scalar, scalar > 0 else { return }
            context.setStrokeColor(activeColor)
            context.addPath(StatusIconGeometry.volumeArcFill(progress: scalar))
            context.strokePath()
        }
    }
}
