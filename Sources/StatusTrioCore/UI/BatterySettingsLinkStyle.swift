import SwiftUI

/// Button style used only by the two "open … settings" actions at the bottom of
/// the battery details page. The label expands to the full row width so the
/// blank space to the right of the text is part of the button, and the row
/// paints its own hover highlight. Other buttons in the app keep their existing
/// styles.
struct BatterySettingsLinkButtonStyle: ButtonStyle {
    /// Owned by the row, so hovering one action never highlights the other.
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// One full-width settings action row. The whole row — including the blank space
/// to the right of the text — is the button's target. Hover state is injected so
/// the container can give each row its own, and tests can render a row hovered
/// or idle without a live pointer.
struct BatterySettingsLinkRow: View {
    let title: String
    let isHovered: Bool
    let action: () -> Void

    init(_ title: String, isHovered: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isHovered = isHovered
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(BatterySettingsLinkButtonStyle(isHovered: isHovered))
    }
}
