import SwiftUI

struct IconPresetPicker: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    @State private var confirmation: Confirmation?
    @EnvironmentObject private var localization: Localization

    var body: some View {
        HStack {
            Button(localization.string(.iconDesignerControlRestoreSlot)) { confirmation = .slot }
            Spacer()
            Button(localization.string(.iconDesignerControlClassicPreset)) { confirmation = .classic }
        }
        .alert(item: $confirmation) { choice in
            switch choice {
            case .slot:
                Alert(title: Text(localization.format(.iconDesignerControlRestoreSlotQuestionFormat, localization.string(slot.localizationKey))),
                      message: Text(localization.string(.iconDesignerControlSlotRestoreMessage)),
                      primaryButton: .destructive(Text(localization.string(.iconDesignerControlRestoreAction))) {
                          store.updateIconConfiguration { $0 = $0.resetting(slot) }
                      }, secondaryButton: .cancel())
            case .classic:
                Alert(title: Text(localization.string(.iconDesignerControlRestoreClassicConfirmation)),
                      message: Text(localization.string(.iconDesignerControlClassicRestoreMessage)),
                      primaryButton: .destructive(Text(localization.string(.iconDesignerControlRestoreAction))) { store.resetIconConfiguration() },
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
    var localizationKey: LocalizationKey {
        switch self {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
        }
    }
}
