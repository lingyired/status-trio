import SwiftUI

struct IconSourceEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var phaseFiveEnabled = false
    var target: IconDesignerBehaviorTarget = .primary
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    private var sources: [IconDesignerSource] {
        IconDesignerEditingModel.selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled)
    }

    private var selectedSource: IconDesignerSource? {
        IconDesignerEditingModel.source(for: target, slot: slot, in: store.iconConfiguration)
    }

    var body: some View {
        SettingsGroup(localization.string(target == .primary ? .iconDesignerContentTitle : .iconDesignerFallbackSource)) {
            IconDesignerControlRow(localization.string(target == .primary ? .iconDesignerContentTitle : .iconDesignerFallbackSource),
                identifier: target == .primary ? "iconDesigner.source.primary" : "iconDesigner.source.fallback") {
                IconDesignerSourcePicker(selection: sourceBinding, sources: offeredSources, allowsEmpty: target == .fallback,
                    title: localization.string(target == .primary ? .iconDesignerPrimarySource : .iconDesignerFallbackSource) + " — " + localizedSlotTitle,
                    identifier: target == .primary ? "iconDesigner.source.primaryPicker" : "iconDesigner.source.fallbackPicker")
            }

            if let selectedSource, let binding = selectedSource.pluginBinding,
               let presentation = BuiltinIconPlugins.makeRegistry().presentation(for: binding) {
                if !presentation.isSelectable {
                    SettingsHintRow(text: localization.string(.iconDesignerLegacySourcePreserved))
                } else if let summary = presentation.summary {
                    SettingsHintRow(text: localization.string(summary))
                }
            } else if selectedSource?.pluginBinding == nil {
                SettingsHintRow(text: localization.string(target == .primary ? .iconDesignerHiddenExplanation : .iconDesignerHideElement))
            }

            if target == .fallback, selectedSource != nil {
                IconDesignerControlRow(localization.string(.iconDesignerSwapPrimaryFallback), showsDivider: false) {
                    Button(localization.string(.iconDesignerSwapPrimaryFallback)) {
                        editorModel.updateIconConfiguration { configuration in
                            _ = IconDesignerEditingModel.swapPrimaryAndFallback(for: slot, in: &configuration)
                        }
                    }
                    .accessibilityLabel(localization.string(.iconDesignerSwapPrimaryFallback) + " — " + localizedSlotTitle)
                }
            }
            if airPodsSourceIsConfigured { airPodsSourceSettings }
            if connectedBluetoothSourceIsConfigured {
                IconDesignerBluetoothEditor(store: store, bluetoothDevices: bluetoothDevices, statusStore: statusStore,
                    behaviorTarget: target)
            }
        }
        .accessibilityIdentifier(target == .primary ? "iconDesigner.sourceCard" : "iconDesigner.fallbackSourceCard")
    }

    private var offeredSources: [IconDesignerSource] {
        guard target == .fallback else { return sources }
        return sources.filter { $0 != primary && $0.pluginBinding != nil }
    }

    private var sourceBinding: Binding<IconDesignerSource?> {
        Binding(get: { target == .primary ? primary : fallbackBinding.wrappedValue }, set: { value in
            if target == .primary {
                if let value { primaryBinding.wrappedValue = value }
            } else { fallbackBinding.wrappedValue = value }
        })
    }

    private var airPodsSourceIsConfigured: Bool {
        selectedSource == .ring(.airPodsBattery)
    }

    private var connectedBluetoothSourceIsConfigured: Bool {
        switch selectedSource {
        case .center(.bluetoothAudioOutput), .center(.connectedBluetoothDevice), .center(.pinnedBluetoothGlyph): true
        default: false
        }
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
        IconDesignerSourceSelection.localizationKey(forRawSourceID: source) ?? .iconDesignerSourceNone
    }
}
