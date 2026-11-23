import SwiftUI

/// The neutral surface painted behind a hardware-monitor card in the opaque
/// (PanelCardSurfaceStyle.solid) rendering branch.
///
/// Hardware cards are deliberately neutral, not tinted by a metric colour: the
/// ring arc and the value text carry the semantic colour, the card itself does
/// not. The shared power-card PowerCardSilver values lean cool on purpose (they
/// belong to the charger-input cards), which over the opaque panel fill read as a
/// bright blue-grey rectangle. This family is a plain neutral grey in both
/// appearances so those cards stop shimmering, without touching PowerCardSilver
/// or any other surface.
///
/// Glass (Liquid Glass) keeps the existing panelCardSurface path. The classic
/// material and solid branches use the neutral wash/card below, matching the
/// keep-awake capsule's quiet neutral surface instead of the cool silver.
struct HardwareMonitorCardSurface: Equatable, Sendable {
    /// The card fill.
    let background: PowerCardRGB
    /// The 1 pt hairline rim.
    let border: PowerCardRGB
    /// The fill used while the pointer is over an interactive card.
    let hover: PowerCardRGB
    /// The unfilled groove behind a progress bar.
    let progressTrack: PowerCardRGB

    var backgroundColor: Color { background.color }
    var borderColor: Color { border.color }
    var hoverColor: Color { hover.color }
    var progressTrackColor: Color { progressTrack.color }

    /// #292B2F / #F2F3F5 background, #393C42 / #DFE2E6 rim, #32353A / #E9EBEF
    /// hover, #41444A / #DDE0E4 progress groove.
    static func values(scheme: ColorScheme) -> HardwareMonitorCardSurface {
        let dark = scheme == .dark
        return HardwareMonitorCardSurface(
            background: dark
                ? PowerCardRGB(red: 0x29 / 255, green: 0x2B / 255, blue: 0x2F / 255)
                : PowerCardRGB(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255),
            border: dark
                ? PowerCardRGB(red: 0x39 / 255, green: 0x3C / 255, blue: 0x42 / 255)
                : PowerCardRGB(red: 0xDF / 255, green: 0xE2 / 255, blue: 0xE6 / 255),
            hover: dark
                ? PowerCardRGB(red: 0x32 / 255, green: 0x35 / 255, blue: 0x3A / 255)
                : PowerCardRGB(red: 0xE9 / 255, green: 0xEB / 255, blue: 0xEF / 255),
            progressTrack: dark
                ? PowerCardRGB(red: 0x41 / 255, green: 0x44 / 255, blue: 0x4A / 255)
                : PowerCardRGB(red: 0xDD / 255, green: 0xE0 / 255, blue: 0xE4 / 255)
        )
    }

    /// The unfilled groove colour for a progress bar under the current card
    /// strategy. Glass and material keep the pre-existing primary at 10 % wash;
    /// solid uses the neutral groove above.
    static func progressTrackColor(cardStyle: PanelCardSurfaceStyle, scheme: ColorScheme) -> Color {
        cardStyle == .solid
            ? values(scheme: scheme).progressTrackColor
            : Color.primary.opacity(0.10)
    }

    /// Top/bottom opacities for the trend chart under-curve gradient. The solid
    /// branch thins the area fill so it no longer floods the neutral card while
    /// the line stroke keeps the metric full data colour.
    static func trendAreaFillOpacities(cardStyle: PanelCardSurfaceStyle) -> (top: Double, bottom: Double) {
        cardStyle == .solid ? (top: 0.42, bottom: 0.16) : (top: 0.78, bottom: 0.38)
    }
}

/// Paints a hardware-monitor card: neutral opaque fill + hairline rim in the
/// solid branch, otherwise the shared panelCardSurface wash so Liquid Glass and
/// the classic material keep their exact current look.
private struct HardwareMonitorCardSurfaceModifier: ViewModifier {
    let surface: PowerCardSurface
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle
    let hovered: Bool

    @Environment(\.panelCardSurfaceStyle) private var cardStyle
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch cardStyle {
        case .solid:
            let palette = HardwareMonitorCardSurface.values(scheme: scheme)
            content
                .background(shape.fill(hovered ? palette.hoverColor : palette.backgroundColor))
                .overlay { shape.strokeBorder(palette.borderColor, lineWidth: 1) }
        case .glass:
            content.panelCardSurface(
                surface,
                tint: .clear,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
        case .material:
            // Match the keep-awake capsule's classic-material surface: a faint
            // neutral primary wash so the frosted panel still shows through,
            // with no blue-grey silver cast.
            content
                .background(shape.fill(Color.primary.opacity(0.08)))
                .overlay { shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) }
        }
    }
}

extension View {
    /// Wrap a hardware-monitor card. The glass branch keeps the shared panel
    /// card surface; material and solid use the neutral hardware recipe.
    func hardwareMonitorCardSurface(
        _ surface: PowerCardSurface = .silver(.connected),
        cornerRadius: CGFloat = 13,
        cornerStyle: RoundedCornerStyle = .continuous,
        hovered: Bool = false
    ) -> some View {
        modifier(HardwareMonitorCardSurfaceModifier(
            surface: surface,
            cornerRadius: cornerRadius,
            cornerStyle: cornerStyle,
            hovered: hovered
        ))
    }
}
