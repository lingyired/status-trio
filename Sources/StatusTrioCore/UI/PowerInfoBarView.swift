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
            ForEach(state.items) { item in
                card(item)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ item: PowerInfoBarItem) -> some View {
        let tint = Self.tint(for: item.kind)
        return VStack(alignment: .center, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: Self.symbolName(for: item.kind))
                    .font(.system(size: Self.iconSize(for: item.kind), weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(item.value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(localization.string(item.title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private static func symbolName(for kind: PowerInfoBarKind) -> String {
        switch kind {
        case .input: return "powerplug.fill"
        case .battery: return "battery.100.bolt"
        case .system: return "laptopcomputer"
        }
    }

    /// SF Symbols do not share one optical weight; keep the battery glyph a
    /// touch smaller so the three cards read evenly.
    private static func iconSize(for kind: PowerInfoBarKind) -> CGFloat {
        switch kind {
        case .input: return 15
        case .battery: return 12
        case .system: return 13
        }
    }

    private static func tint(for kind: PowerInfoBarKind) -> Color {
        switch kind {
        case .input: return .primary
        case .battery: return .green
        case .system: return .blue
        }
    }
}
