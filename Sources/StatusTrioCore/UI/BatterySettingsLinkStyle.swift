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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The padded native button supplies the same area for hover and clicks. The
/// outer negative padding restores the original row height and text position,
/// allowing adjacent targets to overlap without widening their layout spacing.
/// The container supplies one shared hover selection for the pair of rows.
struct BatterySettingsLinkRow: View {
    let title: String
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    init(
        _ title: String,
        isHovered: Bool,
        onHover: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isHovered = isHovered
        self.onHover = onHover
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
        .onHover(perform: onHover)
        .padding(.horizontal, -8)
        .padding(.vertical, -5)
    }
}
