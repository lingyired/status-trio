import SwiftUI

struct IconSourceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var phaseFiveEnabled = false
    var bluetoothDevices: [BluetoothDevice] = []
    @EnvironmentObject private var localization: Localization

    private var sources: [IconDesignerSource] {
        IconDesignerEditingModel.selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled)
    }
    private var current: IconDesignerCurrentSource {
        IconDesignerEditingModel.currentSource(for: slot, in: store.iconConfiguration, phaseFiveEnabled: phaseFiveEnabled)
    }

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerSourcesTitle)) {
            Picker(localization.string(.iconDesignerPrimarySource), selection: primaryBinding) {
                ForEach(sources, id: \.self) { source in
                    Text(localization.string(source.localizationKey)).tag(source)
                }
            }
            .accessibilityLabel(localization.string(.iconDesignerPrimarySource) + " — " + localizedSlotTitle)

            if !current.isSelectable {
                Label(localization.format(.iconDesignerCurrentSourceUnavailableFormat,
                                          localization.string(localizationKey(for: current.id))),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if current.isLegacy {
                Text(localization.string(.iconDesignerCompatible))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(localization.string(.iconDesignerFallbackSource), selection: fallbackBinding) {
                Text(localization.string(.iconDesignerNone)).tag(IconDesignerSource?.none)
                ForEach(sources.filter { $0 != primary }, id: \.self) { source in
                    Text(localization.string(source.localizationKey)).tag(Optional(source))
                }
            }
            .accessibilityLabel(localization.string(.iconDesignerFallbackSource) + " — " + localizedSlotTitle)
            if fallbackBinding.wrappedValue != nil {
                Button(localization.string(.iconDesignerSwapPrimaryFallback)) {
                    store.updateIconConfiguration { configuration in
                        _ = IconDesignerEditingModel.swapPrimaryAndFallback(for: slot, in: &configuration)
                    }
                }
                .accessibilityLabel(localization.string(.iconDesignerSwapPrimaryFallback) + " — " + localizedSlotTitle)
            }
            if airPodsSourceIsConfigured {
                airPodsSourceSettings
            }
        }
    }

    private var airPodsSourceIsConfigured: Bool {
        guard slot == .outerRing else { return false }
        let selection = store.iconConfiguration.composition.outerRing
        return selection.primary == .airPodsBattery || selection.fallback == .airPodsBattery
    }

    private var airPodsSourceSettings: some View {
        Group {
            let devices = bluetoothDevices.filter { $0.airPodsModel != nil }
            if devices.isEmpty {
                Text(localization.string(.iconDesignerControlNoBluetoothDevices))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(localization.string(.iconDesignerControlSelectAirPodsDevice), selection: airPodsDeviceBinding) {
                    Text(localization.string(.iconDesignerControlChooseBluetoothDevice)).tag(String?.none)
                    ForEach(devices, id: \.id) { device in
                        let address = BluetoothBatteryReader.normalizedAddress(device.id)
                        Text(device.name).tag(Optional(address))
                    }
                }
                .accessibilityLabel(localization.string(.iconDesignerControlSelectAirPodsDevice))
            }
            Toggle(localization.string(.iconDesignerControlAirPodsBackgroundReads), isOn: Binding(
                get: { store.refreshesAirPodsBatteryForIcon },
                set: { store.refreshesAirPodsBatteryForIcon = $0 }
            ))
        }
    }

    private var airPodsDeviceBinding: Binding<String?> {
        Binding(
            get: { store.airPodsIconDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) } },
            set: { store.airPodsIconDeviceAddress = $0 }
        )
    }

    private var localizedSlotTitle: String {
        let key: LocalizationKey = switch slot {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
        }
        return localization.string(key)
    }

    private var primary: IconDesignerSource {
        switch slot {
        case .outerRing: .ring(store.iconConfiguration.composition.outerRing.primary)
        case .center: .center(store.iconConfiguration.composition.center.primary)
        case .footer: .footer(store.iconConfiguration.composition.footer.primary)
        }
    }

    private var primaryBinding: Binding<IconDesignerSource> {
        Binding(get: { primary }, set: { value in
            store.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setPrimary(value, for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            }
        })
    }

    private var fallbackBinding: Binding<IconDesignerSource?> {
        Binding(get: {
            switch slot {
            case .outerRing:
                if let value = store.iconConfiguration.composition.outerRing.fallback { .ring(value) } else { nil }
            case .center:
                if let value = store.iconConfiguration.composition.center.fallback { .center(value) } else { nil }
            case .footer:
                if let value = store.iconConfiguration.composition.footer.fallback { .footer(value) } else { nil }
            }
        }, set: { value in
            store.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setFallback(value, for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            }
        })
    }
}

private extension IconDesignerSource {
    var localizationKey: LocalizationKey {
        switch self {
        case .ring(.automaticLegacy), .center(.automaticLegacy): .iconDesignerSourceLegacy
        case .ring(.systemBattery): .iconDesignerSourceSystemBattery
        case .ring(.airPodsBattery): .iconDesignerSourceAirPodsBattery
        case .ring(.none), .center(.none), .footer(.none): .iconDesignerSourceNone
        case .center(.network): .iconDesignerSourceNetwork
        case .center(.bluetoothAudioOutput): .iconDesignerSourceBluetoothAudio
        case .center(.pinnedBluetoothGlyph): .iconDesignerSourcePinnedBluetooth
        case .center(.connectedBluetoothDevice): .iconDesignerSourceConnectedBluetooth
        case .center(.systemBatteryPercentage): .iconDesignerSourceBatteryPercentage
        case .footer(.systemVolume): .iconDesignerSourceSystemVolume
        }
    }
}

private func localizationKey(for sourceID: String) -> LocalizationKey {
    switch sourceID {
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
}
