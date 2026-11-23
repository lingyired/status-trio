import Foundation

/// How the status-panel window draws its background (issue #233).
///
/// All three choices are offered on every macOS version. `.liquidGlass` is only
/// renderable on macOS 26+, so a persisted or default value resolves to
/// `.classicMaterial` on older systems. Reduce Transparency always forces
/// `.solid` at render time, regardless of this setting.
enum PanelBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    /// Native `NSGlassEffectView` material introduced in macOS 26 (Tahoe).
    case liquidGlass
    /// The pre-Tahoe `NSVisualEffectView(.popover)` frosted material.
    case classicMaterial
    /// Opaque fill that follows the system light / dark appearance.
    case solid

    var id: String { rawValue }

    /// Whether `NSGlassEffectView` can be used on the running OS.
    static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The style a fresh install uses: Liquid Glass on macOS 26+, the classic
    /// material on older systems.
    static var systemDefault: PanelBackgroundStyle {
        isLiquidGlassAvailable ? .liquidGlass : .classicMaterial
    }

    /// Resolves a persisted value, dropping `.liquidGlass` on systems that
    /// cannot render it, so a defaults value carried over from another macOS
    /// version never selects an unavailable background.
    static func resolved(_ stored: PanelBackgroundStyle?) -> PanelBackgroundStyle {
        guard let stored else { return systemDefault }
        if stored == .liquidGlass, !isLiquidGlassAvailable { return .classicMaterial }
        return stored
    }

    /// The style actually rendered. Reduce Transparency always forces `.solid`
    /// for accessibility; otherwise the resolved user choice is used.
    static func renderStyle(
        for style: PanelBackgroundStyle,
        reduceTransparency: Bool
    ) -> PanelBackgroundStyle {
        if reduceTransparency { return .solid }
        return resolved(style)
    }

    /// The styles offered on the running OS. Liquid Glass is omitted where it
    /// cannot be rendered; the rest keep the canonical order.
    static var availableStyles: [PanelBackgroundStyle] {
        allCases.filter { $0 != .liquidGlass || isLiquidGlassAvailable }
    }
}
