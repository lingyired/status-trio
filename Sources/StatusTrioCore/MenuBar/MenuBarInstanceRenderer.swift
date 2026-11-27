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
        style(for: line, baseSize: twoLine ? 9 : 12)
    }

    static func style(for line: MenuBarLine?, baseSize: CGFloat) -> LineStyle {
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
        let twoLine = instance.layoutMode.isDoubleLine && instance.top != nil && instance.bottom != nil
        let lines: [MenuBarLine?] = twoLine ? [instance.top, instance.bottom] : [instance.top, nil]
        var lineWidths: [Double] = []
        var lineHeights: [Double] = []

        for (index, line) in lines.enumerated() {
            guard let line else {
                lineWidths.append(0)
                lineHeights.append(0)
                continue
            }
            if line.isEmpty && line.leadingIcon == nil {
                lineWidths.append(0)
                lineHeights.append(0)
                continue
            }
            let defaultSize = instance.layoutMode.defaultFontSize(isTopRow: index == 0)
            let style = style(for: line, baseSize: CGFloat(defaultSize))
            let iconHeight = line.leadingIcon == nil ? 0 : CGFloat(line.leadingIconSize)
            lineWidths.append(Double(elementWidths(line: line, style: style, readings: input.readings).reduce(0, +)))
            lineHeights.append(Double(max(style.height, iconHeight)))
        }

        let hasLeadingIcon = lines.contains { $0?.leadingIcon != nil }
        let maxIconSize = lines.compactMap { $0?.leadingIcon == nil ? nil : $0?.leadingIconSize }.max() ?? 16
        let columnWidth: CGFloat = hasLeadingIcon ? CGFloat(max(10, maxIconSize)) + columnGap : 0
        let contentWidth = (lineWidths.max() ?? 0).cgFloat + columnWidth
        // `outerMargin` is no longer exposed in the editor: at render time it
        // only widened the item asymmetrically instead of separating it from
        // neighbouring status items. Keep the stored field for compatibility,
        // but do not let it inflate the measured width.
        var totalWidth = contentWidth + CGFloat(instance.innerPadding * 2)
        if let fixed = instance.minimumWidth {
            // The editor labels this "固定宽度": use it verbatim so a changing
            // memory/reading string cannot resize the status item.
            totalWidth = CGFloat(fixed)
        }
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
        let twoLine = instance.layoutMode.isDoubleLine && instance.top != nil && instance.bottom != nil
        let lines: [MenuBarLine?] = twoLine ? [instance.top, instance.bottom] : [instance.top, nil]

        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        appearance.performAsCurrentDrawingAppearance {
            guard let context = NSGraphicsContext.current else { return }
            context.imageInterpolation = .high
            let hasLeadingIcon = lines.contains { $0?.leadingIcon != nil }
            let maxIconSize = lines.compactMap { $0?.leadingIcon == nil ? nil : $0?.leadingIconSize }.max() ?? 16
            let columnWidth: CGFloat = hasLeadingIcon ? CGFloat(max(10, maxIconSize)) + columnGap : 0
            let inner = CGFloat(instance.innerPadding)
            let contentX = inner + columnWidth
            let contentWidth = size.width - inner * 2 - columnWidth
            var y = size.height
            for (index, line) in lines.enumerated() {
                guard let line else { continue }
                if line.isEmpty && line.leadingIcon == nil { continue }
                let defaultSize = instance.layoutMode.defaultFontSize(isTopRow: index == 0)
                let style = style(for: line, baseSize: CGFloat(defaultSize))
                let iconSize = line.leadingIcon == nil ? 0 : CGFloat(line.leadingIconSize)
                let rowHeight = max(style.height, iconSize)
                y -= rowHeight

                if let leading = line.leadingIcon {
                    let rect = NSRect(
                        x: inner,
                        y: y + (rowHeight - iconSize) / 2,
                        width: iconSize,
                        height: iconSize
                    )
                    let tint: NSColor
                    if let fixed = line.leadingIconColor {
                        tint = NSColor(
                            srgbRed: CGFloat(fixed.red),
                            green: CGFloat(fixed.green),
                            blue: CGFloat(fixed.blue),
                            alpha: CGFloat(fixed.alpha)
                        )
                    } else {
                        tint = nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: nil))
                            ?? NSColor.labelColor
                    }
                    drawIcon(leading, in: rect, tintColor: tint)
                }

                let lineRect = NSRect(
                    x: contentX,
                    y: y + (rowHeight - style.height) / 2,
                    width: contentWidth,
                    height: style.height
                )
                draw(line: line, in: lineRect, style: style, input: input)
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

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        color.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private static func drawIcon(_ spec: MenuBarIconSpec, in rect: NSRect, tintColor: NSColor) {
        switch spec.source {
        case .sfSymbol(let name):
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            let image: NSImage
            if spec.tint {
                let config = NSImage.SymbolConfiguration(paletteColors: [tintColor])
                image = symbol.withSymbolConfiguration(config) ?? symbol
            } else {
                image = symbol
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        case .asset(let name):
            guard let asset = NSImage(named: name) else { return }
            let image = spec.tint ? tinted(asset, color: tintColor) : asset
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        case .character(let value):
            let font = NSFont.systemFont(ofSize: rect.height)
            let attributed = NSAttributedString(
                string: String(value.prefix(1)),
                attributes: [.font: font, .foregroundColor: tintColor]
            )
            let size = attributed.size()
            attributed.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
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
