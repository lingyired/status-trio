import SwiftUI

/// An obvious, whole-row action for the Wi-Fi location permission states on the
/// details page. The old presentation was a plain caption that read as help
/// text; this renders a neutral, bordered button with a leading icon and a
/// trailing chevron so the user can see it is the way to resolve the prompt.
/// Deliberately not accent-tinted: a permission hint should read as a quiet,
/// tappable row rather than a primary blue action.
struct WiFiPermissionActionButton: View {
    @Environment(\.statusPanelMediumTextEnabled) private var panelMediumText
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 12, weight: panelMediumText ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}