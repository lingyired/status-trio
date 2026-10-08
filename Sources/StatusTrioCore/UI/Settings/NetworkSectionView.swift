import SwiftUI

struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    var onOpenIconDesigner: () -> Void = {}

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(store: store, statusStore: statusStore, isDarkBackground: $previewIsDark)
        }) {
            IconDesignerEntryRow(onOpen: onOpenIconDesigner)
        }
    }
}
