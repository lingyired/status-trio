import SwiftUI

/// Keeps app-icon display settings in the ordinary settings window while launching
/// composition editing in its dedicated, larger window.
struct IconDesignerLaunchSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    let onOpenIconDesigner: (IconSlot) -> Void

    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(store: store, statusStore: statusStore, isDarkBackground: $previewIsDark)
        }) {
            IconDesignerEntryRow(title: localization.string(.iconDesignerTitle)) {
                onOpenIconDesigner(.outerRing)
            }

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
