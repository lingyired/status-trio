import SwiftUI

struct IconPresetPicker: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    @State private var confirmation: Confirmation?

    var body: some View {
        HStack {
            Button("Restore this slot…") { confirmation = .slot }
            Spacer()
            Button("Classic…") { confirmation = .classic }
        }
        .alert(item: $confirmation) { choice in
            switch choice {
            case .slot:
                Alert(title: Text("Restore \(slot.title) to Classic?"),
                      message: Text("Other icon slots, Dock background, and permissions will be unchanged."),
                      primaryButton: .destructive(Text("Restore")) {
                          store.updateIconConfiguration { $0 = $0.resetting(slot) }
                      }, secondaryButton: .cancel())
            case .classic:
                Alert(title: Text("Restore Classic icon configuration?"),
                      message: Text("Only icon configuration will be restored. Dock background and permissions will be unchanged."),
                      primaryButton: .destructive(Text("Restore")) { store.resetIconConfiguration() },
                      secondaryButton: .cancel())
            }
        }
    }
}

private enum Confirmation: Identifiable {
    case slot, classic
    var id: Self { self }
}

private extension IconSlot {
    var title: String {
        switch self { case .outerRing: "outer ring"; case .center: "center"; case .footer: "footer" }
    }
}
