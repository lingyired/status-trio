import SwiftUI

/// A fixed-size container for a hardware-metric SF Symbol.
///
/// SF Symbols have different intrinsic widths (a wide battery, a tall
/// thermometer, a small fan). Rendering them in a shared square box makes every
/// metric icon occupy exactly the same footprint, so labels line up in the
/// 监控 list and the status-panel tiles.
struct HardwareMetricSymbolView: View {
    let symbol: String
    /// Outer square the icon occupies.
    var box: CGFloat
    /// Maximum glyph size inside the box (kept square so wide/tall symbols share
    /// one optical size).
    var glyph: CGFloat
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: glyph, height: glyph)
            .foregroundStyle(tint)
            .frame(width: box, height: box)
            .accessibilityHidden(true)
    }
}
