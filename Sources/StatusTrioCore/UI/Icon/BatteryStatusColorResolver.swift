import AppKit

/// One role's colour after the user selection is applied.
struct BatteryStatusColorResolution: Equatable {
    let color: CGColor
    /// Worst-case WCAG contrast against the reference backgrounds and tracks.
    /// A reference floor, not a guarantee for a translucent menu bar or an
    /// arbitrary wallpaper.
    let referenceContrast: Double
    /// True when a custom colour had to be lifted to reach the visibility floor.
    let wasAdjusted: Bool
}

/// Resolves a role's user selection into a drawable colour.
///
/// `system` keeps the semantic baseline. `preset` is a fixed light/dark HSB
/// pair. `custom` is the picker's colour used as-is unless its worst-case
/// contrast against the reference menu-bar backgrounds and their 22% ink track
/// falls below the visibility floor, in which case it is mixed toward black or
/// white just far enough to pass. The original selection is always preserved
/// for persistence; only the drawn colour moves.
enum BatteryStatusColorResolver {
    static let minimumReferenceContrast: Double = 1.2

    /// Reference menu-bar backgrounds (light, dark) and the 22% ink track drawn
    /// over each. Worst case for a sRGB fill drawn on top.
    private static let references: [RGB] = [
        RGB(1, 1, 1),
        RGB(0, 0, 0),
        RGB(0.78, 0.78, 0.78),
        RGB(0.22, 0.22, 0.22)
    ]

    static func resolution(
        for role: BatteryStatusColorRole,
        selection: BatteryStatusColorSelection,
        darkAppearance: Bool
    ) -> BatteryStatusColorResolution {
        let baseline = BatteryStatusColorPalette.resolved(dark: darkAppearance).color(for: role)
        return resolve(selection: selection, systemBaseline: baseline, darkAppearance: darkAppearance)
    }

    static func resolve(
        selection: BatteryStatusColorSelection,
        systemBaseline: CGColor,
        darkAppearance: Bool
    ) -> BatteryStatusColorResolution {
        switch selection {
        case .system:
            return BatteryStatusColorResolution(
                color: systemBaseline,
                referenceContrast: minimumContrast(of: systemBaseline),
                wasAdjusted: false
            )
        case .preset(let preset):
            let color = presetColor(preset, darkAppearance: darkAppearance)
            return BatteryStatusColorResolution(
                color: color,
                referenceContrast: minimumContrast(of: color),
                wasAdjusted: false
            )
        case .custom(let components):
            return customResolution(components)
        }
    }

    static func presetColor(_ preset: BatteryStatusColorPreset, darkAppearance: Bool) -> CGColor {
        let components = presetComponents(preset, darkAppearance: darkAppearance)
        return color(from: components)
    }

    static func customComponents(from color: NSColor) -> BatteryStatusColorComponents {
        let hsb = color.usingColorSpace(.deviceRGB) ?? color
        return BatteryStatusColorComponents(
            hue: Double(hsb.hueComponent),
            saturation: Double(hsb.saturationComponent),
            brightness: Double(hsb.brightnessComponent)
        )
    }

    static func nsColor(from components: BatteryStatusColorComponents) -> NSColor {
        NSColor(
            hue: CGFloat(components.hue),
            saturation: CGFloat(components.saturation),
            brightness: CGFloat(components.brightness),
            alpha: 1
        )
    }

    static func color(from components: BatteryStatusColorComponents) -> CGColor {
        nsColor(from: components).usingColorSpace(.deviceRGB)?.cgColor
            ?? CGColor(gray: 1, alpha: 1)
    }

    // MARK: - Presets

    /// Fixed HSB pairs chosen so each preset is visible on its own appearance.
    private static func presetComponents(
        _ preset: BatteryStatusColorPreset,
        darkAppearance: Bool
    ) -> BatteryStatusColorComponents {
        switch preset {
        case .mint:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.44, saturation: 0.65, brightness: 0.82)
                : BatteryStatusColorComponents(hue: 0.44, saturation: 0.55, brightness: 0.55)
        case .sky:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.55, saturation: 0.70, brightness: 0.85)
                : BatteryStatusColorComponents(hue: 0.55, saturation: 0.60, brightness: 0.55)
        case .lavender:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.72, saturation: 0.55, brightness: 0.85)
                : BatteryStatusColorComponents(hue: 0.72, saturation: 0.45, brightness: 0.60)
        case .amber:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.10, saturation: 0.85, brightness: 0.95)
                : BatteryStatusColorComponents(hue: 0.10, saturation: 0.80, brightness: 0.70)
        case .rose:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.95, saturation: 0.65, brightness: 0.88)
                : BatteryStatusColorComponents(hue: 0.95, saturation: 0.55, brightness: 0.62)
        case .slate:
            return darkAppearance
                ? BatteryStatusColorComponents(hue: 0.58, saturation: 0.22, brightness: 0.78)
                : BatteryStatusColorComponents(hue: 0.58, saturation: 0.18, brightness: 0.45)
        }
    }

    // MARK: - Custom visibility

    private static func customResolution(
        _ components: BatteryStatusColorComponents
    ) -> BatteryStatusColorResolution {
        let base = color(from: components)
        guard let baseRGB = rgb(base) else {
            return BatteryStatusColorResolution(
                color: base,
                referenceContrast: 1,
                wasAdjusted: false
            )
        }

        let originalContrast = minimumContrast(baseRGB, references: references)
        if originalContrast >= minimumReferenceContrast {
            return BatteryStatusColorResolution(
                color: base,
                referenceContrast: originalContrast,
                wasAdjusted: false
            )
        }

        // Search a bounded sequence of mixes toward white or black.
        // This keeps the user's hue as long as possible while restoring
        // visibility on both reference backgrounds.
        var best: (rgb: RGB, contrast: Double, amount: Double)?
        for destination in [RGB(1, 1, 1), RGB(0, 0, 0)] {
            for step in 1...40 {
                let amount = Double(step) / 40.0
                let candidate = mix(baseRGB, destination, amount: amount)
                let contrast = minimumContrast(candidate, references: references)
                if contrast >= minimumReferenceContrast {
                    if best == nil || amount < best!.amount {
                        best = (candidate, contrast, amount)
                    }
                    break
                }
            }
        }

        if let best {
            return BatteryStatusColorResolution(
                color: makeColor(best.rgb),
                referenceContrast: best.contrast,
                wasAdjusted: true
            )
        }

        // A middle grey always separates from the four reference luminances;
        // use a bounded maximin search if a narrow interval escaped the mixes.
        let fallback = (0...255).map { value -> (RGB, Double) in
            let grey = Double(value) / 255
            let color = RGB(grey, grey, grey)
            return (color, minimumContrast(color, references: references))
        }.max { $0.1 < $1.1 }!
        return BatteryStatusColorResolution(
            color: makeColor(fallback.0),
            referenceContrast: fallback.1,
            wasAdjusted: true
        )
    }

    // MARK: - WCAG helpers

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    private static func minimumContrast(of color: CGColor) -> Double {
        guard let rgb = rgb(color) else { return 1 }
        return minimumContrast(rgb, references: references)
    }

    private static func minimumContrast(_ color: RGB, references: [RGB]) -> Double {
        references.map { contrastRatio(color, $0) }.min() ?? 1
    }

    private static func rgb(_ color: CGColor) -> RGB? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let values = converted.components, values.count >= 3 else {
            return nil
        }
        return RGB(
            Double(min(1, max(0, values[0]))),
            Double(min(1, max(0, values[1]))),
            Double(min(1, max(0, values[2])))
        )
    }

    private static func mix(_ start: RGB, _ end: RGB, amount: Double) -> RGB {
        RGB(
            start.red + (end.red - start.red) * amount,
            start.green + (end.green - start.green) * amount,
            start.blue + (end.blue - start.blue) * amount
        )
    }

    private static func makeColor(_ color: RGB) -> CGColor {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGColor(
            colorSpace: space,
            components: [CGFloat(color.red), CGFloat(color.green), CGFloat(color.blue), 1]
        ) ?? CGColor(gray: 1, alpha: 1)
    }

    private static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func relativeLuminance(_ color: RGB) -> Double {
        0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}
