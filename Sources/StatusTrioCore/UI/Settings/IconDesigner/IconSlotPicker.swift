import SwiftUI

struct IconSlotPicker: View {
    @Binding var selection: IconSlot
    var configuration: IconConfigurationV1 = .classic
    @EnvironmentObject private var localization: Localization

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            picker.buttonSizing(.flexible)
        } else {
            picker
        }
    }

    private var picker: some View {
        Picker(localization.string(.iconDesignerControlIconSlot), selection: $selection) {
            ForEach(IconSlot.allCases, id: \.self) { slot in
                Text(localization.string(slotNameKey(for: slot)))
                    .help(localization.string(slotNameKey(for: slot)))
                    .accessibilityLabel(localization.string(slotNameKey(for: slot)))
                    .tag(slot)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityLabel(localization.string(.iconDesignerControlIconSlot))
        .accessibilityValue(localizedSelectionValue)
        .accessibilityIdentifier("iconDesigner.slotSelector")
    }

    private var localizedSelectionValue: String {
        let slot = selection
        let sourceID = IconDesignerEditingModel.currentSource(for: slot, in: configuration).id
        let sourceKey: LocalizationKey = switch sourceID {
        case "automaticLegacy": .iconDesignerSourceLegacy
        case "systemBattery": .iconDesignerSourceSystemBattery
        case "airPodsBattery": .iconDesignerSourceAirPodsBattery
        case "network": .iconDesignerSourceNetwork
        case "bluetoothAudioOutput": .iconDesignerSourceBluetoothAudio
        case "pinnedBluetoothGlyph": .iconDesignerSourcePinnedBluetooth
        case "connectedBluetoothDevice": .iconDesignerSourceConnectedBluetooth
        case "systemBatteryPercentage": .iconDesignerSourceBatteryPercentage
        case "systemVolume": .iconDesignerSourceSystemVolume
        case "none": .iconDesignerSourceNone
        default: .iconDesignerSourceNone
        }
        return localization.format(
            .iconDesignerAccessibilityValueFormat,
            localization.string(sourceKey),
            localization.string(.iconDesignerAccessibilitySelected)
        )
    }

    private func slotNameKey(for slot: IconSlot) -> LocalizationKey {
        switch slot {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
        }
    }
}
