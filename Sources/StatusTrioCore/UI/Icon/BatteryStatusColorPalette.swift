import AppKit

/// Concrete colours resolved once per render, before drawing any primitives.
///
/// The system semantic colours are starting points, not a promise that they
/// match the system battery icon pixel for pixel. Resolving once here keeps the
/// renderer's non-main-actor raster path off `NSAppearance.performAsCurrentDrawingAppearance`
/// per primitive, and lets a real appearance (including high contrast) decide
/// the variant instead of a hard-coded aqua/darkAqua guess.
struct BatteryStatusColorPalette {
    let charging: CGColor
    let lowPower: CGColor
    let critical: CGColor

    static func resolved(appearance: NSAppearance) -> Self {
        var result = Self(
            charging: CGColor(gray: 1, alpha: 1),
            lowPower: CGColor(gray: 1, alpha: 1),
            critical: CGColor.redFallback
        )
        appearance.performAsCurrentDrawingAppearance {
            result = Self(
                charging: rgb(.systemGreen),
                lowPower: rgb(.systemYellow),
                critical: rgb(.systemRed)
            )
        }
        return result
    }

    static func resolved(dark: Bool) -> Self {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        return resolved(appearance: NSAppearance(named: name) ?? NSAppearance.currentDrawing())
    }

    /// Explicit-ink renderers (including headless fixtures) infer appearance
    /// from their supplied ink; live menu-bar rendering supplies its real one.
    static func inferred(foreground: CGColor, critical: CGColor) -> Self {
        let brightness = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
        let resolved = resolved(dark: brightness >= 0.5)
        return Self(
            charging: resolved.charging,
            lowPower: resolved.lowPower,
            critical: critical
        )
    }

    func color(for role: BatteryStatusColorRole) -> CGColor {
        switch role {
        case .charging: charging
        case .lowPower: lowPower
        case .critical: critical
        }
    }

    /// Replaces the semantic baselines with the user's per-role selections. The
    /// `.system` roles keep `self`'s resolved baseline, so a real high-contrast
    /// appearance is preserved instead of being re-derived from a light/dark flag.
    func applying(_ statusColors: BatteryStatusColors, darkAppearance: Bool) -> Self {
        guard statusColors.hasOverrides else { return self }
        func resolve(_ role: BatteryStatusColorRole, _ baseline: CGColor) -> CGColor {
            BatteryStatusColorResolver.resolve(
                selection: statusColors.selection(for: role),
                systemBaseline: baseline,
                darkAppearance: darkAppearance
            ).color
        }
        return Self(
            charging: resolve(.charging, charging),
            lowPower: resolve(.lowPower, lowPower),
            critical: resolve(.critical, critical)
        )
    }

    private static func rgb(_ color: NSColor) -> CGColor {
        color.usingColorSpace(.deviceRGB)?.cgColor ?? color.cgColor
    }
}

private extension CGColor {
    static var redFallback: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }
}
