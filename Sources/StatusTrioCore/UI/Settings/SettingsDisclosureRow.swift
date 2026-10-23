import SwiftUI

/// The state-dependent parts of a disclosure row, kept as plain data so the
/// triangle rotation, the accessibility wording, and the accessibility label
/// can be asserted without rendering a view.
enum SettingsDisclosurePresentation {
    /// The triangle points down while collapsed and up while expanded.
    static func rotationDegrees(isExpanded: Bool) -> Double {
        isExpanded ? 180 : 0
    }

    /// Whether VoiceOver reports the row as expanded.
    static func accessibilityValueKey(isExpanded: Bool) -> LocalizationKey {
        isExpanded ? .commonExpanded : .commonCollapsed
    }

    /// What VoiceOver says the row does, which is the opposite of its state.
    static func accessibilityHintKey(isExpanded: Bool) -> LocalizationKey {
        isExpanded ? .commonCollapse : .commonExpand
    }

    /// The row title leads, exactly as the visible row does; the explanation
    /// follows only when the row has one.
    static func accessibilityLabel(title: String, subtitle: String?) -> String {
        guard let subtitle, !subtitle.isEmpty else { return title }
        return "\(title), \(subtitle)"
    }
}

/// A settings row that reveals the rows below it when it is clicked.
///
/// The whole row is the button. A disclosure triangle on its own is roughly an
/// 11-point glyph, so a row that makes only the triangle clickable reads as
/// "clicking does nothing" to anyone aiming at the row's title, which is where
/// people actually click. The triangle itself stays purely decorative and is
/// hidden from VoiceOver, whose state and action come from the row instead.
struct SettingsDisclosureRow: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool

    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        _isExpanded = isExpanded
    }

    var body: some View {
        Button(action: { toggle() }) {
            SettingsRow(symbol, tint: tint, title: title, subtitle: subtitle) {
                PanelActionGlyph(
                    systemName: "chevron.down",
                    font: .system(size: 11, weight: .medium),
                    size: 16
                )
                    .foregroundStyle(.secondary)
                    .rotationEffect(
                        .degrees(
                            SettingsDisclosurePresentation.rotationDegrees(isExpanded: isExpanded)
                        )
                    )
                    .accessibilityHidden(true)
            }
            // The row is the hit target: without this the button only reacts to
            // the glyphs it draws, not to the whole width it occupies.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            SettingsDisclosurePresentation.accessibilityLabel(title: title, subtitle: subtitle)
        )
        .accessibilityValue(
            localization.string(
                SettingsDisclosurePresentation.accessibilityValueKey(isExpanded: isExpanded)
            )
        )
        .accessibilityHint(
            localization.string(
                SettingsDisclosurePresentation.accessibilityHintKey(isExpanded: isExpanded)
            )
        )
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
