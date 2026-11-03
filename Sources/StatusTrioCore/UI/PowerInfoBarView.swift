import SwiftUI

/// Provisional power info bar under the panel's battery module. It mirrors the
/// details-page metric cards: icon and wattage on the first row, the rail name
/// underneath. Each number is its own reading and the cards are never summed
/// into a whole-machine total.
struct PowerInfoBarView: View {
    @EnvironmentObject private var localization: Localization
    let state: PowerInfoBarState

    var body: some View {
        HStack(spacing: 8) {
            if state.items.isEmpty {
                ForEach(state.placeholderKinds, id: \.self) { kind in
                    card(kind: kind, value: nil)
                }
            } else {
                ForEach(state.items) { item in
                    card(kind: item.kind, value: item.value)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(kind: PowerInfoBarKind, value: String?) -> some View {
        let tint = Self.tint(for: kind)
        return VStack(alignment: .center, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: Self.symbolName(for: kind))
                    .font(.system(size: Self.iconSize(for: kind), weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                if let value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 46, height: 12)
                        .accessibilityHidden(true)
                }
            }

            Text(localization.string(kind.title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The panel chrome is transparent Liquid Glass, so a very light tint
        // disappears over a bright or colourful desktop. Keep the fill and a
        // thin rim opaque enough that each card still reads as a surface. The
        // battery details flow diagram reuses this exact styling for its input
        // card, so both "charger input" chips match.
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private static func symbolName(for kind: PowerInfoBarKind) -> String {
        switch kind {
        case .input: return "powerplug.fill"
        // Only charging carries the bolt. A discharging or idle pack is a plain
        // battery so the direction reads at a glance.
        case .batteryCharging: return "battery.100.bolt"
        case .batteryDischarging, .batteryIdle: return "battery.100"
        case .system: return "laptopcomputer"
        }
    }

    /// SF Symbols do not share one optical weight; keep the battery glyph a
    /// touch smaller so the three cards read evenly.
    private static func iconSize(for kind: PowerInfoBarKind) -> CGFloat {
        switch kind {
        case .input: return 15
        case .batteryCharging, .batteryDischarging, .batteryIdle: return 12
        case .system: return 13
        }
    }

    private static func tint(for kind: PowerInfoBarKind) -> Color {
        switch kind {
        case .input: return .primary
        case .batteryCharging: return .green
        // Charging is green; discharging is deliberately not, so the two are
        // never mistaken for each other. Idle stays neutral.
        case .batteryDischarging: return .orange
        case .batteryIdle: return .secondary
        case .system: return .blue
        }
    }
}
