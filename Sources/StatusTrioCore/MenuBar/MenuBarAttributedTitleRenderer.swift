import AppKit

/// Output of the attributed-title renderer spike. The runtime may use this as an
/// alternative to the raster image: text/values are laid out by AppKit's own
/// text system, a leading column icon travels separately as `leadingImage`.
struct MenuBarRenderedContent {
    var attributedTitle: NSAttributedString
    var leadingImage: NSImage?
    var accessibilityLabel: String
    var measuredWidth: CGFloat
    var measuredHeight: CGFloat
}

/// AppKit-native text rendering used to validate the CodexBar-style
/// `NSStatusBarButton.attributedTitle` path without replacing the proven raster
/// renderer yet. Kept side-effect free and unit-testable.
enum MenuBarAttributedTitleRenderer {
    static func render(_ input: MenuBarRenderInput, appearance: NSAppearance) -> MenuBarRenderedContent? {
        let instance = input.instance
        let twoLine = instance.layoutMode == .doubleLine && instance.top != nil && instance.bottom != nil
        let lines: [MenuBarLine] = twoLine ? [instance.top, instance.bottom].compactMap { $0 } : [instance.top].compactMap { $0 }
        guard !lines.isEmpty else { return nil }

        let result = NSMutableAttributedString()
        var accessibilityParts: [String] = []
        var maxWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for (index, line) in lines.enumerated() {
            let style = MenuBarInstanceRenderer.style(for: line, twoLine: twoLine)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = nstextAlignment(line.alignment)
            paragraph.minimumLineHeight = style.height
            paragraph.maximumLineHeight = style.height

            let lineString = NSMutableAttributedString()
            var textParts: [String] = []
            for element in line.elements {
                switch element.content {
                case .text(let text):
                    lineString.append(NSAttributedString(string: text, attributes: attributes(style: style, color: color(for: element, line: line, input: input), paragraph: paragraph)))
                    textParts.append(text)
                case .metric(let metric):
                    let text = input.readings[metric]?.text ?? "--"
                    lineString.append(NSAttributedString(string: text, attributes: attributes(style: style, color: color(for: element, line: line, input: input), paragraph: paragraph)))
                    textParts.append(text)
                case .icon(let icon):
                    if let attachment = attachment(for: icon, height: style.height) {
                        lineString.append(NSAttributedString(attachment: attachment))
                    }
                }
            }
            if lineString.length == 0 { continue }
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: attributes(style: style, color: NSColor.labelColor, paragraph: paragraph))) }
            result.append(lineString)
            accessibilityParts.append(textParts.joined())
            let width = lineString.boundingRect(with: NSSize(width: .greatestFiniteMagnitude, height: style.height),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading]).width
            maxWidth = max(maxWidth, width)
            totalHeight += style.height
        }

        let leading = instance.leadingIcon.flatMap { image(for: $0, height: 18) }
        let margins = CGFloat(instance.innerPadding * 2 + instance.outerMargin * 2)
        return MenuBarRenderedContent(
            attributedTitle: result,
            leadingImage: leading,
            accessibilityLabel: accessibilityParts.joined(separator: " / "),
            measuredWidth: maxWidth + margins + (leading == nil ? 0 : 21),
            measuredHeight: totalHeight
        )
    }

    private static func attributes(style: MenuBarInstanceRenderer.LineStyle, color: NSColor, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private static func color(for element: MenuBarElement, line: MenuBarLine, input: MenuBarRenderInput) -> NSColor {
        switch element.content {
        case .metric(let metric):
            let level = input.readings[.batteryLevel]?.value
            let source = MenuBarMetricColorResolver.sourceColor(for: metric, overrides: input.colorOverrides, batteryLevel: level)
            return MenuBarInstanceRenderer.nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: source)) ?? NSColor.labelColor
        default:
            return MenuBarInstanceRenderer.nsColor(for: MenuBarMetricColorResolver.appliedColor(line: line.color, source: nil)) ?? NSColor.labelColor
        }
    }

    private static func nstextAlignment(_ alignment: LineAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    private static func image(for icon: MenuBarIconSpec, height: CGFloat) -> NSImage? {
        switch icon.source {
        case .sfSymbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = icon.tint
            return image
        case .asset(let name):
            return NSImage(named: name)
        case .character, .emoji:
            return nil
        }
    }

    private static func attachment(for icon: MenuBarIconSpec, height: CGFloat) -> NSTextAttachment? {
        guard let image = image(for: icon, height: height) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 0, width: height, height: height)
        return attachment
    }
}
