import SwiftUI

/// Compatibility wrapper around surface-level icon settings.
struct AppIconSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(store: store, statusStore: statusStore, isDarkBackground: $previewIsDark)
        }) {
            SettingsGroup {
                SettingsRow("questionmark.circle", tint: .indigo, title: localization.string(.guideTitle)) {
                    Button(action: onShowIconGuide) {
                        Label(localization.string(.guideOpen), systemImage: "macwindow")
                    }
                }
            }
            IconSurfaceSettings(store: store, statusStore: statusStore, previewIsDark: $previewIsDark)
        }
    }
}
