import SwiftUI

struct IconBehaviorEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var bluetoothDevices: [BluetoothDevice] = []
    var bluetoothDeviceOrder: [String] = []

    var body: some View {
        SettingsGroup("Behavior") {
            switch slot {
            case .outerRing:
                batteryBehavior
            case .center:
                centerBehavior
            case .footer:
                Picker("Volume display", selection: Binding(
                    get: { store.iconConfiguration.behaviors.systemVolumeFooter.displayStyle },
                    set: { value in store.updateIconConfiguration { $0.behaviors.systemVolumeFooter.displayStyle = value } }
                )) {
                    Text("Dots").tag(VolumeDisplayStyle.dots)
                    Text("Arc").tag(VolumeDisplayStyle.arc)
                }
            }
        }
    }

    private var batteryBehavior: some View {
        Group {
            toggle("Show percentage", get: { $0.behaviors.systemBatteryRing.showsPercentage }, set: { $0.behaviors.systemBatteryRing.showsPercentage = $1 })
            toggle("Show charging indicator", get: { $0.behaviors.systemBatteryRing.showsChargingIndicator }, set: { $0.behaviors.systemBatteryRing.showsChargingIndicator = $1 })
            toggle("Charging animation", get: { $0.behaviors.systemBatteryRing.showsChargingEffect }, set: { $0.behaviors.systemBatteryRing.showsChargingEffect = $1 })
            toggle("Charging bolt heartbeat", get: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat }, set: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat = $1 })
            toggle("Use battery status colors", get: { $0.behaviors.systemBatteryRing.usesStatusColors }, set: { $0.behaviors.systemBatteryRing.usesStatusColors = $1 })
            toggle("Show percentage while connected", get: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected }, set: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected = $1 })
            if ChargingEffectTestMode.isAvailable() {
                Toggle("Preview charging animation", isOn: Binding(
                    get: { store.testsChargingEffect },
                    set: { store.setChargingEffectTestEnabled($0) }
                ))
            }
            integerSlider("Critical threshold", value: Binding(
                get: { store.iconConfiguration.behaviors.systemBatteryRing.criticalThreshold },
                set: { value in store.updateIconConfiguration { $0.behaviors.systemBatteryRing.criticalThreshold = value } }
            ), range: 0...100)
            doubleSlider("Text scale", value: Binding(
                get: { store.iconConfiguration.behaviors.systemBatteryRing.textScale },
                set: { value in store.updateIconConfiguration { $0.behaviors.systemBatteryRing.textScale = value } }
            ), range: 1...3)
        }
    }

    private var centerBehavior: some View {
        Group {
            switch store.iconConfiguration.composition.center.primary {
            case .network:
                toggle("Wi-Fi symbol for Ethernet", get: { $0.behaviors.networkCenter.showsWiFiIconForEthernet }, set: { $0.behaviors.networkCenter.showsWiFiIconForEthernet = $1 })
                toggle("Wi-Fi symbol for hotspot", get: { $0.behaviors.networkCenter.showsWiFiIconForHotspot }, set: { $0.behaviors.networkCenter.showsWiFiIconForHotspot = $1 })
                toggle("Wi-Fi symbol for temporary connection", get: { $0.behaviors.networkCenter.showsWiFiIconForTemporaryConnection }, set: { $0.behaviors.networkCenter.showsWiFiIconForTemporaryConnection = $1 })
                toggle("Wi-Fi symbol for Internet Sharing", get: { $0.behaviors.networkCenter.showsWiFiIconForInternetSharing }, set: { $0.behaviors.networkCenter.showsWiFiIconForInternetSharing = $1 })
                toggle("Show battery percentage in connection slot", get: { $0.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot }, set: { $0.behaviors.networkCenter.showsBatteryPercentageInConnectionSlot = $1 })
                doubleSlider("Wi-Fi symbol scale", value: Binding(
                    get: { store.iconConfiguration.behaviors.networkCenter.wifiScale },
                    set: { value in store.updateIconConfiguration { $0.behaviors.networkCenter.wifiScale = value } }
                ), range: 0.5...3)
            case .bluetoothAudioOutput:
                toggle("Replace network symbol with Bluetooth audio", get: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon }, set: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon = $1 })
                toggle("Use volume color", get: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor }, set: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor = $1 })
                toggle("Prioritize network errors", get: { $0.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors }, set: { $0.behaviors.bluetoothAudioCenter.prioritizesNetworkErrors = $1 })
                doubleSlider("Bluetooth symbol scale", value: Binding(
                    get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.symbolScale },
                    set: { value in store.updateIconConfiguration { $0.behaviors.bluetoothAudioCenter.symbolScale = value } }
                ), range: 1...3)
                bluetoothSymbolPicker
                if IconDesignerEditingModel.allowsNetworkProblemOverride(in: store.iconConfiguration) {
                    toggle("Network problems override Bluetooth", get: { $0.composition.centerOverride.networkProblemOverridesPrimary }, set: { $0.composition.centerOverride.networkProblemOverridesPrimary = $1 })
                }
            case .automaticLegacy, .pinnedBluetoothGlyph, .connectedBluetoothDevice, .systemBatteryPercentage, .none:
                Text("Select a Network or Bluetooth audio source to edit its behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bluetoothSymbolPicker: some View {
        let options = BluetoothNetworkIconSourceOption.options(devices: bluetoothDevices, order: bluetoothDeviceOrder)
        let selected = store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
        return Picker("Bluetooth fallback symbol", selection: Binding(
            get: { selected },
            set: { value in
                store.updateIconConfiguration { configuration in
                    _ = IconDesignerEditingModel.setBluetoothSymbolOverride(value, in: &configuration)
                }
            }
        )) {
            Text("Automatic").tag(String?.none)
            ForEach(options) { option in
                Text(option.title ?? "Audio output — \(option.symbolName)").tag(Optional(option.symbolName))
            }
            if let selected, !options.contains(where: { $0.symbolName == selected }) {
                Text("Saved symbol — \(selected)").tag(Optional(selected))
            }
        }
        .accessibilityLabel("Bluetooth fallback symbol")
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
