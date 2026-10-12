import AppKit
import SwiftUI

enum IconAppearanceColorConversion {
    static func color(from value: IconRGBA) -> Color {
        let color = value.normalized()
        return Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }

    static func iconRGBA(from color: Color) -> IconRGBA {
        let source = NSColor(color)
        guard let normalized = source.usingColorSpace(.sRGB) else {
            return .white
        }
        return IconRGBA(
            red: Double(normalized.redComponent),
            green: Double(normalized.greenComponent),
            blue: Double(normalized.blueComponent),
            alpha: Double(normalized.alphaComponent)
        ).normalized()
    }
}

enum IconAppearanceColorEditing {
    static func color(for style: SlotColorStyle, role: IconSemanticColorRole) -> IconRGBA {
        switch style {
        case .automatic:
            .white
        case let .fixed(color):
            color
        case let .semanticOverrides(colors):
            colors[role] ?? colors[.primary] ?? .white
        }
    }

    static func setColor(
        _ color: IconRGBA,
        role: IconSemanticColorRole,
        slot: IconSlot,
        in configuration: inout IconConfigurationV1
    ) {
        let style: SlotColorStyle
        switch slot {
        case .outerRing:
            style = configuration.appearance.outerRing.color
        case .center:
            style = configuration.appearance.center.color
        case .footer:
            style = configuration.appearance.footer.color
        }

        let updated: SlotColorStyle
        switch style {
        case .automatic, .fixed:
            updated = .fixed(color.normalized())
        case var .semanticOverrides(colors):
            colors[role] = color.normalized()
            updated = .semanticOverrides(colors)
        }

        switch slot {
        case .outerRing:
            configuration.appearance.outerRing.color = updated
        case .center:
            configuration.appearance.center.color = updated
        case .footer:
            configuration.appearance.footer.color = updated
        }
    }
}
