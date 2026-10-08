import SwiftUI

/// The Designer shell uses the existing pinned preview + scrolling settings page.
/// Slot-specific editing is added by the next implementation task.
struct IconDesignerView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void

    var body: some View {
        AppIconSectionView(
            store: store,
            statusStore: statusStore,
            previewIsDark: $previewIsDark,
            onShowIconGuide: onShowIconGuide
        )
    }
}
