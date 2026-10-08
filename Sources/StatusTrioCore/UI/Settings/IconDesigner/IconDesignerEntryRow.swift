import SwiftUI

struct IconDesignerEntryRow: View {
    let onOpen: () -> Void
    var body: some View {
        SettingsGroup("Icon settings") {
            Button(action: onOpen) {
                Label("Configure in Icon Designer", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
