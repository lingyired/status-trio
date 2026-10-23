import SwiftUI

/// The row under the known networks that reveals the connected network's
/// details.
///
/// The whole row is the button. Making only the caption and its symbol
/// clickable left the rest of the row inert, which reads as "clicking does
/// nothing" to anyone aiming at the row rather than at its few points of text.
/// The caption and the accessibility label both state the action the row
/// performs, so VoiceOver hears "Hide details" while the details are open
/// instead of announcing the collapsed wording in both states.
struct WiFiDetailsToggleRow: View {
    @Binding var isExpanded: Bool

    @EnvironmentObject private var localization: Localization

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                PanelActionGlyph(
                    systemName: WiFiNetworkPresentation.detailsToggleSymbol(isExpanded: isExpanded),
                    size: 16
                )
                Text(
                    localization.string(
                        WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: isExpanded)
                    )
                )
            }
            // The row is the hit target across the whole list width, not just
            // the glyphs it draws.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            localization.string(
                WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: isExpanded)
            )
        )
    }
}
