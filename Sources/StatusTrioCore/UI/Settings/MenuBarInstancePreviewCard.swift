import AppKit
import SwiftUI

/// Pinned preview for the menu-bar instance page.
///
/// It renders the selected instance through the same renderer as the real
/// status item, in the menu-bar context the rest of Settings uses, so the
/// shorthand stays visible while the editor scrolls underneath it.
struct MenuBarInstancePreviewCard: View {
    let model: MenuBarInstanceEditorModel?
    /// A hidden instance still renders, but dimmed, so the preview never
    /// suggests an item that is not actually in the menu bar.
    var isEnabled = true
    @Binding var isDarkBackground: Bool
    let localization: Localization

    var body: some View {
        VStack(spacing: 8) {
            bar

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var bar: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .medium))
                .accessibilityHidden(true)

            Spacer(minLength: 4)

            if let model {
                MenuBarInstancePreviewImage(
                    model: model,
                    isDarkBackground: isDarkBackground,
                    localization: localization
                )
                .opacity(isEnabled ? 1 : 0.4)
            } else {
                Text(localization.string(.menuBarEditorAddOrSelect))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "wifi")
                .font(.system(size: 11.5))
                .fixedSize()
                .accessibilityHidden(true)
            Image(systemName: "battery.75")
                .font(.system(size: 13))
                .fixedSize()
                .accessibilityHidden(true)
            Text("9:41")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .fixedSize()
                .accessibilityHidden(true)

            PreviewAppearanceToggle(
                isDarkBackground: $isDarkBackground,
                localization: localization,
                compact: true
            )
        }
        .foregroundStyle(isDarkBackground ? Color.white : Color.black)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct MenuBarInstancePreviewImage: View {
    @ObservedObject var model: MenuBarInstanceEditorModel
    let isDarkBackground: Bool
    let localization: Localization

    var body: some View {
        if let image = model.previewImage(dark: isDarkBackground) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 110, maxHeight: 18, alignment: .trailing)
                .layoutPriority(1)
                .accessibilityLabel(localization.string(.menuBarEditorPreview))
        } else {
            Text(localization.string(.menuBarEditorNoContent))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityLabel(localization.string(.menuBarEditorPreview))
        }
    }
}
