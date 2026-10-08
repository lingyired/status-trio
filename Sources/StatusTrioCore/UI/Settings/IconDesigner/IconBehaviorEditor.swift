import SwiftUI

struct IconBehaviorEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var bluetoothDevices: [BluetoothDevice] = []
    var bluetoothDeviceOrder: [String] = []
    @State private var behaviorTarget: IconDesignerBehaviorTarget = .primary
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerBehaviorTitle)) {
            if IconDesignerEditingModel.behaviorTargets(for: slot, in: store.iconConfiguration).count > 1 {
                Picker(localization.string(.iconDesignerBehaviorTitle), selection: $behaviorTarget) {
                    Text(localization.string(.iconDesignerPrimary)).tag(IconDesignerBehaviorTarget.primary)
                    Text(localization.string(.iconDesignerFallback)).tag(IconDesignerBehaviorTarget.fallback)
                }
                .pickerStyle(.segmented)
            }
            switch slot {
            case .outerRing:
                batteryBehavior
            case .center:
                centerBehavior
            case .footer:
                Picker(localization.string(.iconDesignerControlVolumeDisplay), selection: Binding(
                    get: { store.iconConfiguration.behaviors.systemVolumeFooter.displayStyle },
                    set: { value in store.updateIconConfiguration { $0.behaviors.systemVolumeFooter.displayStyle = value } }
                )) {
                    Text(localization.string(.iconDesignerControlDots)).tag(VolumeDisplayStyle.dots)
                    Text(localization.string(.iconDesignerControlArc)).tag(VolumeDisplayStyle.arc)
                }
            }
        }
    }

    private var batteryBehavior: some View {
        Group {
            toggle(localization.string(.iconDesignerControlShowPercentage), get: { $0.behaviors.systemBatteryRing.showsPercentage }, set: { $0.behaviors.systemBatteryRing.showsPercentage = $1 })
            toggle(localization.string(.iconDesignerControlShowChargingIndicator), get: { $0.behaviors.systemBatteryRing.showsChargingIndicator }, set: { $0.behaviors.systemBatteryRing.showsChargingIndicator = $1 })
            toggle(localization.string(.iconDesignerControlChargingAnimation), get: { $0.behaviors.systemBatteryRing.showsChargingEffect }, set: { $0.behaviors.systemBatteryRing.showsChargingEffect = $1 })
            toggle(localization.string(.iconDesignerControlChargingBoltHeartbeat), get: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat }, set: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat = $1 })
            toggle(localization.string(.iconDesignerControlUseBatteryStatusColors), get: { $0.behaviors.systemBatteryRing.usesStatusColors }, set: { $0.behaviors.systemBatteryRing.usesStatusColors = $1 })
            toggle(localization.string(.iconDesignerControlShowPercentageWhileConnected), get: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected }, set: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected = $1 })
            if ChargingEffectTestMode.isAvailable() {
                Toggle(localization.string(.iconDesignerControlPreviewChargingAnimation), isOn: Binding(
                    get: { store.testsChargingEffect },
                    set: { store.setChargingEffectTestEnabled($0) }
                ))
            }
            integerSlider(localization.string(.iconDesignerControlCriticalThreshold), value: Binding(
                get: { store.iconConfiguration.behaviors.systemBatteryRing.criticalThreshold },
                set: { value in store.updateIconConfiguration { $0.behaviors.systemBatteryRing.criticalThreshold = value } }
            ), range: 0...100)
            doubleSlider(localization.string(.iconDesignerControlTextScale), value: Binding(
                get: { store.iconConfiguration.behaviors.systemBatteryRing.textScale },
                set: { value in store.updateIconConfiguration { $0.behaviors.systemBatteryRing.textScale = value } }
            ), range: 1...3)
        }
    }

    private var centerBehavior: some View {
        Group {
            switch IconDesignerEditingModel.source(for: behaviorTarget, slot: .center, in: store.iconConfiguration) {
            case .center(.automaticLegacy):
                networkBehavior(includeLegacyPercentage: true)
                legacyBluetoothBehavior
            case .center(.network):
                networkBehavior(includeLegacyPercentage: false)
            case .center(.bluetoothAudioOutput):
                bluetoothOutputBehavior
            case .center(.pinnedBluetoothGlyph):
                doubleSlider("Pinned Bluetooth symbol scale", value: Binding(
                    get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.symbolScale },
                    set: { value in store.updateIconConfiguration { $0.behaviors.bluetoothAudioCenter.symbolScale = value } }
                ), range: 1...3)
                bluetoothSymbolPicker
            case .center(.connectedBluetoothDevice), .center(.systemBatteryPercentage), .center(.none), .none, .some(.ring), .some(.footer):
                Text(localization.string(.iconDesignerControlNoEditableBehavior))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func networkBehavior(includeLegacyPercentage: Bool) -> some View {
        Group {
            toggle(localization.string(.iconDesignerControlWifiForEthernet), get: { $0.behaviors.networkCenter.showsWiFiIconForEthernet }, set: { $0.behaviors.networkCenter.showsWiFiIconForEthernet = $1 })
            toggle(localization.string(.iconDesignerControlWifiForHotspot), get: { $0.behaviors.networkCenter.showsWiFiIconForHotspot }, set: { $0.behaviors.networkCenter.showsWiFiIconForHotspot = $1 })
            toggle(localization.string(.iconDesignerControlWifiForTemporaryConnection), get: { $0.behaviors.networkCenter.showsWiFiIconForTemporaryConnection }, set: { $0.behaviors.networkCenter.showsWiFiIconForTemporaryConnection = $1 })
            toggle(localization.string(.iconDesignerControlWifiForInternetSharing), get: { $0.behaviors.networkCenter.showsWiFiIconForInternetSharing }, set: { $0.behaviors.networkCenter.showsWiFiIconForInternetSharing = $1 })
            if includeLegacyPercentage {
                toggle(localization.string(.iconDesignerControlLegacyBatteryPercentage), get: { $0.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot }, set: { $0.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = $1 })
            }
            doubleSlider(localization.string(.iconDesignerControlWifiSymbolScale), value: Binding(
                get: { store.iconConfiguration.behaviors.networkCenter.wifiScale },
                set: { value in store.updateIconConfiguration { $0.behaviors.networkCenter.wifiScale = value } }
            ), range: 0.5...3)
        }
    }

    private var legacyBluetoothBehavior: some View {
        Group {
            toggle(localization.string(.iconDesignerControlReplaceNetworkWithBluetooth), get: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon }, set: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon = $1 })
            toggle(localization.string(.iconDesignerControlPrioritizeNetworkErrors), get: { $0.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors }, set: { $0.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = $1 })
            toggle(localization.string(.iconDesignerControlUseVolumeColor), get: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor }, set: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor = $1 })
            doubleSlider(localization.string(.iconDesignerControlBluetoothSymbolScale), value: Binding(
                get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.symbolScale },
                set: { value in store.updateIconConfiguration { $0.behaviors.bluetoothAudioCenter.symbolScale = value } }
            ), range: 1...3)
        }
    }

    private var bluetoothOutputBehavior: some View {
        Group {
            doubleSlider(localization.string(.iconDesignerControlBluetoothSymbolScale), value: Binding(
                get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.symbolScale },
                set: { value in store.updateIconConfiguration { $0.behaviors.bluetoothAudioCenter.symbolScale = value } }
            ), range: 1...3)
            if behaviorTarget == .primary,
               store.iconConfiguration.composition.center.primary == .bluetoothAudioOutput {
                toggle(localization.string(.iconDesignerControlNetworkProblemsOverrideBluetooth), get: { $0.composition.centerOverride.networkProblemOverridesPrimary }, set: { $0.composition.centerOverride.networkProblemOverridesPrimary = $1 })
            }
        }
    }

    private var bluetoothSymbolPicker: some View {
        let options = BluetoothNetworkIconSourceOption.options(devices: bluetoothDevices, order: bluetoothDeviceOrder)
        let selected = store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
        return Picker(localization.string(.iconDesignerControlBluetoothSymbol), selection: Binding(
            get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride },
            set: { value in
                store.updateIconConfiguration { configuration in
                    _ = IconDesignerEditingModel.setBluetoothSymbolOverride(
                        value, for: behaviorTarget, in: &configuration
                    )
                }
            }
        )) {
            Text(localization.string(.iconDesignerControlAutomatic)).tag(String?.none)
            ForEach(options) { option in
                Text(option.title ?? localization.format(.iconDesignerControlAudioOutputFormat, option.symbolName)).tag(Optional(option.symbolName))
            }
            if let selected, !options.contains(where: { $0.symbolName == selected }) {
                Text(localization.format(.iconDesignerControlSavedSymbolFormat, selected)).tag(Optional(selected))
            }
        }
        .accessibilityLabel(localization.string(.iconDesignerControlBluetoothSymbol))
    }

    private func toggle(_ title: String, get: @escaping (IconConfigurationV1) -> Bool,
                        set: @escaping (inout IconConfigurationV1, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(
            get: { get(store.iconConfiguration) },
            set: { value in store.updateIconConfiguration { set(&$0, value) } }
        ))
    }

    private func integerSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue)%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }), in: Double(range.lowerBound)...Double(range.upperBound))
        }
    }

    private func doubleSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue, specifier: "%.2f")×").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 0.05)
        }
    }
}
