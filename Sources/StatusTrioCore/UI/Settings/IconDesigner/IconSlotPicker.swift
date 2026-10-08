import SwiftUI

struct IconSlotPicker: View {
    @Binding var selection: IconSlot
    var configuration: IconConfigurationV1 = .classic
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(IconSlot.allCases, id: \.self) { slot in
                    let accessibility = accessibilityValue(for: slot)
                    Button {
                        selection = slot
                    } label: {
                        Label(localization.string(accessibility.slotName), systemImage: slot.symbol)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selection == slot ? Color.accentColor.opacity(0.16) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(localization.string(accessibility.slotName))
                    .accessibilityValue(localization.format(
                        .iconDesignerAccessibilityValueFormat,
                        localizedSourceName(for: slot),
                        localization.string(selection == slot ? .iconDesignerAccessibilitySelected : .iconDesignerAccessibilityNotSelected)
                    ))
                    .accessibilityAddTraits(selection == slot ? .isSelected : [])
                }
            }
            Picker(localization.string(.iconDesignerControlIconSlot), selection: $selection) {
                ForEach(IconSlot.allCases, id: \.self) { slot in
                    Text(localization.string(accessibilityValue(for: slot).slotName)).tag(slot)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func accessibilityValue(for slot: IconSlot) -> IconDesignerSlotAccessibilityValue {
        IconDesignerAccessibility.slotValue(
            slot: slot,
            currentSource: localizedSourceName(for: slot),
            isSelected: selection == slot
        )
    }

    private func localizedSourceName(for slot: IconSlot) -> String {
        let source = IconDesignerEditingModel.currentSource(for: slot, in: configuration).id
        let key: LocalizationKey = switch source {
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
        return localization.string(key)
    }
}

private extension IconSlot {
    var symbol: String {
        switch self { case .outerRing: "circle.dashed"; case .center: "circle.inset.filled"; case .footer: "circle.bottomhalf.filled" }
    }
}
