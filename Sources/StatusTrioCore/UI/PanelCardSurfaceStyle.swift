import AppKit
import SwiftUI

/// The compositing strategy for a card surface inside the status panel,
/// resolved from the panel's effective background style (#296).
///
/// A card cannot decide its look from `ColorScheme` alone: it is composited
/// over one of three panel backgrounds (`PanelBackgroundStyle`). A translucent
/// wash tuned for Liquid Glass turns into a flat, dirty-looking rectangle over
/// the opaque solid fill, and feels too heavy over the classic material. This
/// type names the three strategies and carries one resolved decision to the
/// SwiftUI content through the environment, so every card shares it instead of
/// each view re-deriving its own opacity.
enum PanelCardSurfaceStyle: Equatable, Sendable {
    /// The panel already draws native glass (`NSGlassEffectView`). The card is a
    /// low-opacity tinted wash that lets that glass through; it never nests a
    /// second glass view (which double-rims and greys the surface over the
    /// panel's own glass).
    case glass
    /// The pre-Tahoe frosted material: a system material plus a semantic wash
    /// and a hairline rim.
    case material
    /// An opaque, appearance-adaptive surface with its own palette — not the
    /// glass wash at 100 % opacity.
    case solid

    /// Maps the panel's rendered background to the matching card strategy.
    /// Reduce Transparency has already collapsed the background to `.solid` by
    /// the time this is called, so it always forces the opaque surface.
    static func resolve(_ style: PanelBackgroundStyle) -> PanelCardSurfaceStyle {
        switch style {
        case .liquidGlass: return .glass
        case .classicMaterial: return .material
        case .solid: return .solid
        }
    }

    /// The opaque base behind a solid card. It is deliberately a different
    /// dynamic colour from the panel's own `windowBackgroundColor`, so the card
    /// reads as a raised surface rather than melting into the fill in either
    /// appearance.
    static func solidBase(scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

/// The effective card style for a view subtree. Defaults to `.glass` so the
/// existing rendering tests and any preview that does not inject a value keep
/// the tuned Liquid Glass wash they were written against.
private struct PanelCardSurfaceStyleKey: EnvironmentKey {
    static let defaultValue: PanelCardSurfaceStyle = .glass
}

extension EnvironmentValues {
    var panelCardSurfaceStyle: PanelCardSurfaceStyle {
        get { self[PanelCardSurfaceStyleKey.self] }
        set { self[PanelCardSurfaceStyleKey.self] = newValue }
    }
}

/// Draws one power card's fill and rim using the resolved panel card style.
///
/// The glass branch is byte-for-byte the pre-existing `PowerCardSurface` wash so
/// its recorded rendering stays valid; the material branch adds a system
/// material behind a thinner wash; the solid branch paints an opaque dynamic
/// base under a faint semantic tint.
private struct PanelCardSurfaceModifier: ViewModifier {
    let surface: PowerCardSurface
    let tint: Color
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle

    @Environment(\.panelCardSurfaceStyle) private var cardStyle
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
    }

    func body(content: Content) -> some View {
        switch cardStyle {
        case .glass:
            if #available(macOS 26.0, *), PanelCardSurfaceExperiment.useNative, cardStyle == .glass {
                content
                    .glassEffect(
                        .regular.tint(surface.fill(tint: tint, scheme: scheme, cardStyle: .glass)),
                        in: shape
                    )
            } else {
                content
                    .background(shape.fill(surface.fill(tint: tint, scheme: scheme, cardStyle: .glass)))
                    .overlay { shape.strokeBorder(surface.stroke(tint: tint, scheme: scheme, cardStyle: .glass), lineWidth: 1) }
            }
        case .material:
            content
                .background(shape.fill(surface.fill(tint: tint, scheme: scheme, cardStyle: .material)))
                .background(shape.fill(.ultraThinMaterial))
                .overlay { shape.strokeBorder(surface.stroke(tint: tint, scheme: scheme, cardStyle: .material), lineWidth: 1) }
        case .solid:
            content
                .background(shape.fill(surface.fill(tint: tint, scheme: scheme, cardStyle: .solid)))
                .background(shape.fill(PanelCardSurfaceStyle.solidBase(scheme: scheme)))
                .overlay { shape.strokeBorder(surface.stroke(tint: tint, scheme: scheme, cardStyle: .solid), lineWidth: 1) }
        }
    }
}

extension View {
    /// Paint this card's surface with the shared power-card strategy.
    func panelCardSurface(
        _ surface: PowerCardSurface,
        tint: Color,
        cornerRadius: CGFloat = 12,
        cornerStyle: RoundedCornerStyle = .continuous
    ) -> some View {
        modifier(PanelCardSurfaceModifier(
            surface: surface,
            tint: tint,
            cornerRadius: cornerRadius,
            cornerStyle: cornerStyle
        ))
    }
}
