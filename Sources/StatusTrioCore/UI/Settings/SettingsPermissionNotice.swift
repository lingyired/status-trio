import SwiftUI

/// A shared warning banner that surfaces when a permissions-gated feature is not
/// granted, so the user sees why the data is missing and can resolve it from the
/// pane instead of hunting for a prompt.
///
/// The look matches the Bluetooth permission notice: an orange warning icon on a
/// titled row plus a small action button. `.notDetermined` typically offers to
/// raise the system prompt; `.denied`/`.restricted` send the user to the Privacy
/// & Security pane where a refused grant is restored.
struct SettingsPermissionNotice: View {
    let title: String
    let description: LocalizationKey
    let buttonKey: LocalizationKey
    let action: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup {
            SettingsRow(
                "exclamationmark.triangle.fill",
                tint: .orange,
                title: title,
                subtitle: localization.string(description)
            ) {
                Button(localization.string(buttonKey), action: action)
                    .controlSize(.small)
            }
        }
    }
}