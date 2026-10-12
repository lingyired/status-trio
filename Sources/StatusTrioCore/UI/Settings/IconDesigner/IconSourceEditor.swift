import SwiftUI

struct IconSourceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var phaseFiveEnabled = false
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    private var sources: [IconDesignerSource] {
        IconDesignerEditingModel.selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled)
    }

    private var current: IconDesignerCurrentSource {
        IconDesignerEditingModel.currentSource(for: slot, in: store.iconConfiguration, phaseFiveEnabled: phaseFiveEnabled)
    }

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerSourcesTitle)) {
            IconDesignerControlRow(
                localization.string(.iconDesignerPrimarySource),
                identifier: "iconDesigner.source.primary"
            ) {
                Picker("", selection: primaryBinding) {
                    ForEach(sources, id: \.self) { source in
                        Text(localization.string(source.localizationKey)).tag(source)
                    }
                    if !current.isSelectable {
                        Text(localization.string(primary.localizationKey)).tag(primary)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel(localization.string(.iconDesignerPrimarySource) + " — " + localizedSlotTitle)
                .accessibilityIdentifier("iconDesigner.source.primaryPicker")
            }

            if current.isLegacy {
                SettingsHintRow(text: localization.string(.iconDesignerLegacySourcePreserved))
            } else if !current.isSelectable {
                SettingsHintRow(
                    text: localization.format(
                        .iconDesignerCurrentSourceUnavailableFormat,
                        localization.string(localizationKey(for: current.id))
                    )
                )
            }

            IconDesignerControlRow(
                localization.string(.iconDesignerFallbackSource),
                identifier: "iconDesigner.source.fallback"
            ) {
                Picker("", selection: fallbackBinding) {
                    Text(localization.string(.iconDesignerNone)).tag(IconDesignerSource?.none)
                    ForEach(sources.filter { $0 != primary }, id: \.self) { source in
                        Text(localization.string(source.localizationKey)).tag(Optional(source))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel(localization.string(.iconDesignerFallbackSource) + " — " + localizedSlotTitle)
                .accessibilityIdentifier("iconDesigner.source.fallbackPicker")
            }

            if fallbackBinding.wrappedValue != nil {
                IconDesignerControlRow(localization.string(.iconDesignerSwapPrimaryFallback), showsDivider: false) {
                    Button(localization.string(.iconDesignerSwapPrimaryFallback)) {
                        editorModel.updateIconConfiguration { configuration in
                            _ = IconDesignerEditingModel.swapPrimaryAndFallback(for: slot, in: &configuration)
                        }
                    }
                    .accessibilityLabel(localization.string(.iconDesignerSwapPrimaryFallback) + " — " + localizedSlotTitle)
                }
            }

            if airPodsSourceIsConfigured {
                airPodsSourceSettings
            }
            if connectedBluetoothSourceIsConfigured {
                IconDesignerBluetoothEditor(store: store, bluetoothDevices: bluetoothDevices, statusStore: statusStore)
            }
        }
        .accessibilityIdentifier("iconDesigner.sourceCard")
    }

    private var airPodsSourceIsConfigured: Bool {
        guard slot == .outerRing else { return false }
        let selection = store.iconConfiguration.composition.outerRing
        return selection.primary == .airPodsBattery || selection.fallback == .airPodsBattery
    }

    private var connectedBluetoothSourceIsConfigured: Bool {
        slot == .center && IconDesignerEditingModel.requiresConnectedBluetoothDevice(in: store.iconConfiguration)
    }

    private var airPodsSourceSettings: some View {
        Group {
            let devices = bluetoothDevices.devices.filter { $0.airPodsModel != nil }
            if bluetoothDevices.authorization != .allowed {
                BluetoothPermissionNoticeRow(bluetoothDevices: bluetoothDevices, statusStore: statusStore)
            } else if devices.isEmpty {
                SettingsHintRow(text: localization.string(.iconDesignerControlNoBluetoothDevices))
            } else {
                IconDesignerControlRow(localization.string(.iconDesignerControlSelectAirPodsDevice)) {
                    Picker("", selection: airPodsDeviceBinding) {
                        Text(localization.string(.iconDesignerControlChooseBluetoothDevice)).tag(String?.none)
                        ForEach(devices, id: \.id) { device in
                            let address = BluetoothBatteryReader.normalizedAddress(device.id)
                            Text(device.name).tag(Optional(address))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(localization.string(.iconDesignerControlSelectAirPodsDevice))
                }
            }

            IconDesignerControlRow(localization.string(.iconDesignerControlAirPodsBackgroundReads), showsDivider: false) {
                Toggle("", isOn: Binding(
                    get: { store.refreshesAirPodsBatteryForIcon },
                    set: { value in editorModel.perform { store.refreshesAirPodsBatteryForIcon = value } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(localization.string(.iconDesignerControlAirPodsBackgroundReads))
            }
        }
    }

    private var airPodsDeviceBinding: Binding<String?> {
        Binding(
            get: { store.airPodsIconDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) } },
            set: { value in editorModel.perform { store.airPodsIconDeviceAddress = value } }
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
        case .center:
            .center(IconDesignerBluetoothTargetModel.displaySource(for: store.iconConfiguration.composition.center.primary))
        case .footer: .footer(store.iconConfiguration.composition.footer.primary)
        }
    }

    private var primaryBinding: Binding<IconDesignerSource> {
        Binding(
            get: { primary },
            set: { value in editorModel.updateIconConfiguration { configuration in
                _ = IconDesignerEditingModel.setPrimary(resolvedSource(value), for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            } }
        )
    }

    private var fallbackBinding: Binding<IconDesignerSource?> {
        Binding(get: {
            switch slot {
            case .outerRing:
                if let value = store.iconConfiguration.composition.outerRing.fallback { .ring(value) } else { nil }
            case .center:
                if let value = store.iconConfiguration.composition.center.fallback {
                    .center(IconDesignerBluetoothTargetModel.displaySource(for: value))
                } else { nil }
            case .footer:
                if let value = store.iconConfiguration.composition.footer.fallback { .footer(value) } else { nil }
            }
        }, set: { value in
            editorModel.updateIconConfiguration { configuration in
                let source = value.map { resolvedSource($0) }
                _ = IconDesignerEditingModel.setFallback(source, for: slot, in: &configuration, phaseFiveEnabled: phaseFiveEnabled)
            }
        })
    }


    private func resolvedSource(_ source: IconDesignerSource) -> IconDesignerSource {
        guard slot == .center, source == .center(.bluetoothAudioOutput) else { return source }
        let target: IconDesignerBluetoothTarget
        if let address = store.connectedBluetoothIconDeviceAddress {
            target = .connectedDevice(address: BluetoothBatteryReader.normalizedAddress(address))
        } else {
            target = .currentAudioOutput
        }
        return .center(IconDesignerBluetoothTargetModel.source(for: target))
    }

    private func localizationKey(for source: String) -> LocalizationKey {
        switch source {
        case "automaticLegacy": .iconDesignerSourceLegacy
        case "systemBattery": .iconDesignerSourceSystemBattery
        case "airPodsBattery": .iconDesignerSourceAirPodsBattery
        case "network": .iconDesignerSourceNetwork
        case "bluetoothAudioOutput": .iconDesignerSourceBluetoothAudio
        case "pinnedBluetoothGlyph": .iconDesignerSourcePinnedBluetooth
        case "connectedBluetoothDevice": .iconDesignerSourceConnectedBluetooth
        case "systemBatteryPercentage": .iconDesignerSourceBatteryPercentage
        case "systemVolume": .iconDesignerSourceSystemVolume
        default: .iconDesignerSourceNone
        }
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
