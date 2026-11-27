import AppKit

struct MenuBarRenderInput: Equatable {
    var instance: MenuBarInstance
    var readings: [MenuBarMetricID: MenuBarMetricReading]
    var colorOverrides: [HardwareMonitorMetric: IconRGBA] = [:]
}

struct MenuBarInstanceMeasurement: Equatable {
    var lineWidths: [Double]
    var contentWidth: Double
    var totalWidth: Double
    var lineHeights: [Double]
    var totalHeight: Double
}

enum MenuBarInstanceRenderer {
    static let columnGap: CGFloat = 3
    static let elementIconGap: CGFloat = 2

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
        let twoLine = instance.layoutMode == .doubleLine && instance.top != nil && instance.bottom != nil
        let lines: [MenuBarLine?] = twoLine ? [instance.top, instance.bottom] : [instance.top, nil]
        var lineWidths: [Double] = []
        var lineHeights: [Double] = []

        for line in lines {
            guard let line, !line.isEmpty else {
                lineWidths.append(0)
                lineHeights.append(0)
                continue
            }
            let style = style(for: line, twoLine: twoLine)
            lineWidths.append(Double(elementWidths(line: line, style: style, readings: input.readings).reduce(0, +)))
            lineHeights.append(Double(style.height))
        }

        let columnWidth: CGFloat = instance.leadingIcon == nil ? 0 : 18 + columnGap
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

    static func elementWidths(line: MenuBarLine, style: LineStyle, readings: [MenuBarMetricID: MenuBarMetricReading]) -> [CGFloat] {
        let attributes: [NSAttributedString.Key: Any] = [.font: style.font]
        return line.elements.map { element in
            switch element.content {
            case .metric, .text:
                let text = displayText(for: element.content, readings: readings)
                guard !text.isEmpty else { return 0 }
                return (text as NSString).size(withAttributes: attributes).width
            case .icon:
                return style.height + elementIconGap
            }
        }
    }

    static func displayText(
        for content: MenuBarElementContent,
        readings: [MenuBarMetricID: MenuBarMetricReading]
    ) -> String {
        switch content {
        case .text(let text): return text
        case .metric(let metric): return readings[metric]?.text ?? "--"
        case .icon: return ""
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
        let twoLine = instance.layoutMode == .doubleLine && instance.top != nil && instance.bottom != nil
        let lines: [MenuBarLine?] = twoLine ? [instance.top, instance.bottom] : [instance.top, nil]

        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        appearance.performAsCurrentDrawingAppearance {
            guard let context = NSGraphicsContext.current else { return }
            context.imageInterpolation = .high
            let columnWidth: CGFloat = instance.leadingIcon == nil ? 0 : 18 + columnGap
            let inner = CGFloat(instance.innerPadding)
            let contentX = inner + columnWidth
            let contentWidth = size.width - inner * 2 - columnWidth
            var y = size.height
            for line in lines {
                guard let line, !line.isEmpty else { continue }
                let style = style(for: line, twoLine: twoLine)
                y -= style.height
                let lineRect = NSRect(x: contentX, y: y, width: contentWidth, height: style.height)
                draw(line: line, in: lineRect, style: style, input: input)
            }
            if let leading = instance.leadingIcon {
                let box = NSSize(width: 18, height: 18)
                let rect = NSRect(x: inner, y: (size.height - box.height) / 2, width: box.width, height: box.height)
                drawIcon(leading, in: rect, tintColor: NSColor.labelColor)
            }
        }
        return image
    }

    private static func draw(line: MenuBarLine, in rect: NSRect, style: LineStyle, input: MenuBarRenderInput) {
        let widths = elementWidths(line: line, style: style, readings: input.readings)
        let totalWidth = widths.reduce(0, +)
        var cursor = rect.minX
        switch line.alignment {
        case .leading: break
        case .center: cursor += max(0, (rect.width - totalWidth) / 2)
        case .trailing: cursor += max(0, rect.width - totalWidth)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: style.font]
        for (index, element) in line.elements.enumerated() {
            let width = widths[index]
            switch element.content {
            case .metric, .text:
                let text = displayText(for: element.content, readings: input.readings)
                guard !text.isEmpty else { continue }
                let color = color(for: element, line: line, input: input)
                let attributed = NSAttributedString(string: text, attributes: attributes.merging([.foregroundColor: color]) { _, new in new })
                let textSize = attributed.size()
                attributed.draw(at: NSPoint(x: cursor, y: rect.minY + (rect.height - textSize.height) / 2))
            case .icon(let icon):
                let iconRect = NSRect(x: cursor, y: rect.minY, width: style.height, height: style.height)
                drawIcon(icon, in: iconRect, tintColor: color(for: element, line: line, input: input))
            }
            cursor += width
        }
    }

    private static func color(for element: MenuBarElement, line: MenuBarLine, input: MenuBarRenderInput) -> NSColor {
        switch element.content {
        case .text:
            return nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: nil)) ?? NSColor.labelColor
        case .icon:
            return nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: nil)) ?? NSColor.labelColor
        case .metric(let metric):
            let level = input.readings[.batteryLevel]?.value
            let source = MenuBarMetricColorResolver.sourceColor(for: metric, overrides: input.colorOverrides, batteryLevel: level)
            return nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: source)) ?? NSColor.labelColor
        }
    }

    static func nsColor(for rgba: IconRGBA?) -> NSColor? {
        guard let rgba else { return nil }
        return NSColor(srgbRed: CGFloat(rgba.red), green: CGFloat(rgba.green), blue: CGFloat(rgba.blue), alpha: CGFloat(rgba.alpha))
    }

    private static func drawIcon(_ spec: MenuBarIconSpec, in rect: NSRect, tintColor: NSColor) {
        switch spec.source {
        case .sfSymbol(let name):
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            symbol.isTemplate = spec.tint
            if spec.tint { tintColor.set() }
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
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
