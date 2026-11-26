import AppKit

/// Everything needed to render one instance: the persisted configuration plus
/// the current readings for the metrics it shows.
struct MenuBarRenderInput: Equatable {
    var instance: MenuBarInstance
    var readings: [MenuBarMetricID: MenuBarMetricReading]
}

struct MenuBarInstanceMeasurement: Equatable {
    var lineWidths: [Double]
    var contentWidth: Double
    var totalWidth: Double
    var lineHeights: [Double]
    var totalHeight: Double
}

/// Pure(ish) renderer: measurement is deterministic; drawing only reads AppKit
/// fonts/colours and never touches a status item or sampling.
enum MenuBarInstanceRenderer {
    static let columnGap: CGFloat = 3
    static let rowIconGap: CGFloat = 3

    // MARK: - Fonts

    struct LineStyle: Equatable {
        var font: NSFont
        var height: CGFloat
    }

    static func style(for line: MenuBarLine?, twoLine: Bool) -> LineStyle {
        let baseSize: CGFloat = twoLine ? 9 : 12
        let size = CGFloat(line?.fontSize ?? Double(baseSize))
        let weight: NSFont.Weight = (line?.isBold ?? false) ? .bold : .regular
        let font: NSFont
        if line?.usesMonospacedDigits ?? true {
            font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            font = .systemFont(ofSize: size, weight: weight)
        }
        return LineStyle(font: font, height: ceil(font.ascender - font.descender + font.leading) + 1)
    }

    // MARK: - Measurement

    static func measure(_ input: MenuBarRenderInput, appearance: NSAppearance) -> MenuBarInstanceMeasurement {
        let instance = input.instance
        let twoLine = instance.top != nil && instance.bottom != nil
        let lines = [instance.top, instance.bottom]
        var lineWidths: [Double] = []
        var lineHeights: [Double] = []

        for line in lines {
            guard let line, !line.isEmpty else {
                lineWidths.append(0)
                lineHeights.append(0)
                continue
            }
            let style = style(for: line, twoLine: twoLine)
            var width: CGFloat = 0
            if let icon = line.icon {
                width += style.height + rowIconGap
                _ = icon
            }
            width += textWidth(of: line, style: style, readings: input.readings)
            lineWidths.append(Double(width))
            lineHeights.append(Double(style.height))
        }

        let columnWidth: CGFloat = instance.leadingIcon == nil ? 0 : (twoLine ? 18 : 18) + columnGap
        let contentWidth = (lineWidths.max() ?? 0).cgFloat + columnWidth
        let totalWidth = contentWidth + CGFloat(instance.innerPadding * 2) + CGFloat(instance.outerMargin * 2)
        let totalHeight = max(1, lineHeights.reduce(0, +))
        return MenuBarInstanceMeasurement(
            lineWidths: lineWidths,
            contentWidth: Double(contentWidth),
            totalWidth: Double(totalWidth),
            lineHeights: lineHeights,
            totalHeight: Double(totalHeight)
        )
    }

    static func textWidth(of line: MenuBarLine, style: LineStyle, readings: [MenuBarMetricID: MenuBarMetricReading]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: style.font]
        var width: CGFloat = 0
        for segment in line.segments {
            let text = displayText(for: segment, readings: readings)
            guard !text.isEmpty else { continue }
            width += (text as NSString).size(withAttributes: attributes).width
        }
        return width
    }

    static func displayText(
        for segment: MenuBarLineSegment,
        readings: [MenuBarMetricID: MenuBarMetricReading]
    ) -> String {
        switch segment {
        case .text(let text):
            return text
        case .metric(let metric):
            return readings[metric]?.text ?? "--"
        }
    }

    // MARK: - Drawing

    static func render(
        _ input: MenuBarRenderInput,
        appearance: NSAppearance,
        scale: CGFloat
    ) -> NSImage? {
        let measurement = measure(input, appearance: appearance)
        let size = NSSize(width: CGFloat(measurement.totalWidth), height: CGFloat(measurement.totalHeight))
        guard size.width > 0, size.height > 0 else { return nil }
        let instance = input.instance
        let twoLine = instance.top != nil && instance.bottom != nil

        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            guard let context = NSGraphicsContext.current else { return }
            context.imageInterpolation = .high
            let inner = CGFloat(instance.innerPadding)
            let contentRect = NSRect(
                x: inner,
                y: 0,
                width: size.width - inner * 2,
                height: size.height
            )
            let lines = [instance.top, instance.bottom]
            var y = size.height
            for line in lines {
                guard let line, !line.isEmpty else { continue }
                let style = style(for: line, twoLine: twoLine)
                y -= style.height
                let lineRect = NSRect(x: contentRect.minX, y: y, width: contentRect.width, height: style.height)
                draw(line: line, in: lineRect, style: style, input: input, appearance: appearance)
            }
            if let leading = instance.leadingIcon {
                let box = NSSize(width: 18, height: 18)
                let rect = NSRect(
                    x: contentRect.minX,
                    y: (size.height - box.height) / 2,
                    width: box.width,
                    height: box.height
                )
                drawIcon(leading, in: rect, tintColor: NSColor.labelColor)
            }
        }
        return image
    }

    private static func draw(
        line: MenuBarLine,
        in rect: NSRect,
        style: LineStyle,
        input: MenuBarRenderInput,
        appearance: NSAppearance
    ) {
        var cursor = rect.minX
        let rowIconHeight = style.height
        if let icon = line.icon {
            let rect = NSRect(x: cursor, y: rect.minY, width: rowIconHeight, height: rowIconHeight)
            drawIcon(icon, in: rect, tintColor: NSColor.labelColor)
            cursor += rowIconHeight + rowIconGap
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: style.font]
        let totalTextWidth = textWidth(of: line, style: style, readings: input.readings)
        let available = rect.maxX - cursor
        switch line.alignment {
        case .leading:
            break
        case .center:
            cursor += max(0, (available - totalTextWidth) / 2)
        case .trailing:
            cursor += max(0, available - totalTextWidth)
        }

        for segment in line.segments {
            let text = displayText(for: segment, readings: input.readings)
            guard !text.isEmpty else { continue }
            let color = color(for: segment, line: line, readings: input.readings)
            let attributed = NSAttributedString(string: text, attributes: attributes.merging([.foregroundColor: color]) { _, new in new })
            let size = attributed.size()
            attributed.draw(at: NSPoint(x: cursor, y: rect.minY + (rect.height - size.height) / 2))
            cursor += size.width
        }
        _ = appearance
    }

    private static func color(
        for segment: MenuBarLineSegment,
        line: MenuBarLine,
        readings: [MenuBarMetricID: MenuBarMetricReading]
    ) -> NSColor {
        guard case .metric(let metric) = segment else {
            return nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: nil)) ?? NSColor.labelColor
        }
        let level = readings[.batteryLevel]?.value
        let source = MenuBarMetricColorResolver.sourceColor(for: metric, overrides: [:], batteryLevel: level)
        let applied = MenuBarMetricColorResolver.appliedColor(line: line.color, source: source)
        return nsColor(for: applied) ?? NSColor.labelColor
    }

    static func nsColor(for rgba: IconRGBA?) -> NSColor? {
        guard let rgba else { return nil }
        return NSColor(
            srgbRed: CGFloat(rgba.red),
            green: CGFloat(rgba.green),
            blue: CGFloat(rgba.blue),
            alpha: CGFloat(rgba.alpha)
        )
    }

    private static func drawIcon(_ spec: MenuBarIconSpec, in rect: NSRect, tintColor: NSColor) {
        switch spec.source {
        case .sfSymbol(let name):
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            symbol.isTemplate = spec.tint
            if spec.tint { tintColor.set() }
            symbol.draw(in: rect, from: .zero, operation: spec.tint ? .sourceOver : .sourceOver, fraction: 1)
        case .asset(let name):
            guard let asset = NSImage(named: name) else { return }
            asset.isTemplate = spec.tint
            asset.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        case .emoji(let emoji):
            let font = NSFont.systemFont(ofSize: rect.height)
            let attributed = NSAttributedString(string: emoji, attributes: [.font: font])
            let size = attributed.size()
            attributed.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }
}

private extension Double {
    var cgFloat: CGFloat { CGFloat(self) }
}
