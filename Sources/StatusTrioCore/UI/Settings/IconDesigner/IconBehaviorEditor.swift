import SwiftUI

struct IconBehaviorEditor: View {
    @ObservedObject var store: SettingsStore
    let slot: IconSlot
    var bluetoothDevices: [BluetoothDevice] = []
    var bluetoothAvailability: BluetoothAvailability = .available
    var bluetoothDeviceOrder: [String] = []
    @State private var behaviorTarget: IconDesignerBehaviorTarget = .primary
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var editorModel: IconDesignerEditorModel

    var body: some View {
        SettingsGroup(localization.string(.iconDesignerBehaviorTitle)) {
            if IconDesignerEditingModel.behaviorTargets(for: slot, in: store.iconConfiguration).count > 1 {
                IconDesignerControlRow(localization.string(.iconDesignerBehaviorTitle), showsDivider: false) {
                    Picker("", selection: behaviorTargetBinding) {
                        Text(localization.string(.iconDesignerPrimary)).tag(IconDesignerBehaviorTarget.primary)
                        Text(localization.string(.iconDesignerFallback)).tag(IconDesignerBehaviorTarget.fallback)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel(localization.string(.iconDesignerBehaviorTitle))
                    .accessibilityIdentifier("iconDesigner.behaviorTarget")
                }
            }
            switch slot {
            case .outerRing:
                batteryBehavior
            case .center:
                centerBehavior
            case .footer:
                IconDesignerControlRow(localization.string(.iconDesignerControlVolumeDisplay), showsDivider: false) {
                    Picker("", selection: Binding(
                        get: { store.iconConfiguration.behaviors.systemVolumeFooter.displayStyle },
                        set: { value in editorModel.updateIconConfiguration { $0.behaviors.systemVolumeFooter.displayStyle = value } }
                    )) {
                        Text(localization.string(.iconDesignerControlDots)).tag(VolumeDisplayStyle.dots)
                        Text(localization.string(.iconDesignerControlArc)).tag(VolumeDisplayStyle.arc)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
        .accessibilityIdentifier("iconDesigner.behaviorCard")
        .onChange(of: store.iconConfiguration) { configuration in
            behaviorTarget = IconDesignerEditingModel.validatedBehaviorTarget(
                behaviorTarget, slot: slot, in: configuration
            )
        }
    }

    /// Resolve the stored picker state against the live composition at read time.
    /// This prevents a hidden fallback selection from editing primary behavior
    /// in the render before SwiftUI delivers the configuration onChange.
    private var effectiveBehaviorTarget: IconDesignerBehaviorTarget {
        IconDesignerEditingModel.effectiveBehaviorTarget(
            behaviorTarget, slot: slot, in: store.iconConfiguration
        )
    }

    private var behaviorTargetBinding: Binding<IconDesignerBehaviorTarget> {
        Binding(
            get: { effectiveBehaviorTarget },
            set: { behaviorTarget = IconDesignerEditingModel.validatedBehaviorTarget(
                $0, slot: slot, in: store.iconConfiguration
            ) }
        )
    }

    private var batteryBehavior: some View {
        let source = IconDesignerEditingModel.source(
            for: effectiveBehaviorTarget,
            slot: .outerRing,
            in: store.iconConfiguration
        )
        let capabilities = source.map {
            IconDesignerEditingModel.behaviors(for: .outerRing, source: $0)
        } ?? []

        return Group {
            if capabilities.contains(.airPodsBattery) {
                airPodsRingBehavior
            } else if capabilities.contains(.systemBattery) {
                systemBatteryBehavior
            } else {
                SettingsHintRow(text: localization.string(.iconDesignerControlNoEditableBehavior))
            }
        }
    }

    private var systemBatteryBehavior: some View {
        Group {
            toggle(localization.string(.iconDesignerControlShowPercentage), get: { $0.behaviors.systemBatteryRing.showsPercentage }, set: { $0.behaviors.systemBatteryRing.showsPercentage = $1 })
            toggle(localization.string(.iconDesignerControlShowChargingIndicator), get: { $0.behaviors.systemBatteryRing.showsChargingIndicator }, set: { $0.behaviors.systemBatteryRing.showsChargingIndicator = $1 })
            toggle(localization.string(.iconDesignerControlChargingAnimation), get: { $0.behaviors.systemBatteryRing.showsChargingEffect }, set: { $0.behaviors.systemBatteryRing.showsChargingEffect = $1 })
            toggle(localization.string(.iconDesignerControlChargingBoltHeartbeat), get: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat }, set: { $0.behaviors.systemBatteryRing.showsChargingBoltHeartbeat = $1 })
            toggle(localization.string(.iconDesignerControlUseBatteryStatusColors), get: { $0.behaviors.systemBatteryRing.usesStatusColors }, set: { $0.behaviors.systemBatteryRing.usesStatusColors = $1 })
            toggle(localization.string(.iconDesignerControlShowPercentageWhileConnected), get: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected }, set: { $0.behaviors.systemBatteryRing.showsPercentageWhenConnected = $1 })
            if ChargingEffectTestMode.isAvailable() {
                IconDesignerControlRow(localization.string(.iconDesignerControlPreviewChargingAnimation)) {
                    Toggle("", isOn: Binding(
                        get: { store.testsChargingEffect },
                        set: { store.setChargingEffectTestEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            integerSlider(localization.string(.iconDesignerControlCriticalThreshold), value: Binding(
                get: { store.iconConfiguration.behaviors.systemBatteryRing.criticalThreshold },
                set: { value in editorModel.updateIconConfiguration(coalescingKey: "behavior.criticalThreshold") { $0.behaviors.systemBatteryRing.criticalThreshold = value } }
            ), range: 0...100, coalescingKey: "behavior.criticalThreshold")
            batteryTextScaleSlider
        }
    }

    private var batteryTextScaleSlider: some View {
        let rawTextScale = store.iconConfiguration.behaviors.systemBatteryRing.textScale
        let coalescingKey = "behavior.batteryTextScale"
        return IconDesignerScaleControl(
            title: localization.string(.iconDesignerControlTextScale),
            value: Binding(
                get: { IconDesignerEditingModel.batteryTextScaleSliderValue(for: rawTextScale) },
                set: { value in
                    editorModel.updateIconConfiguration(coalescingKey: coalescingKey) {
                        IconDesignerEditingModel.settingBatteryTextScale(value, in: &$0)
                    }
                }
            ),
            formattedValue: IconDesignerEditingModel.batteryTextScaleLabel(for: rawTextScale),
            range: IconDesignerEditingModel.batteryTextScaleRange,
            step: 0.05,
            onEditingChanged: { editing in
                if editing { editorModel.beginCoalescingGroup(coalescingKey) }
                else { editorModel.endCoalescingGroup(coalescingKey) }
            }
        )
        .help(localization.string(.iconDesignerControlTextScaleHelp))
    }

    private var centerBehavior: some View {
        Group {
            globalNetworkOverrideControl
            switch IconDesignerEditingModel.source(for: effectiveBehaviorTarget, slot: .center, in: store.iconConfiguration) {
            case .center(.automaticLegacy):
                networkBehavior(includeLegacyPercentage: true)
                legacyBluetoothBehavior
            case .center(.network):
                networkBehavior(includeLegacyPercentage: false)
            case .center(.inputSource):
                SettingsHintRow(text: localization.string(.iconDesignerControlInputSourceBehavior))
            case .center(.bluetoothAudioOutput):
                bluetoothOutputBehavior
                bluetoothIconSourcePicker
            case .center(.pinnedBluetoothGlyph):
                bluetoothSymbolPicker
            case .center(.connectedBluetoothDevice):
                if connectedBluetoothCapabilities.contains(.bluetoothOutputAppearance) {
                    bluetoothOutputBehavior
                    bluetoothIconSourcePicker
                } else {
                    SettingsHintRow(text: localization.string(.iconDesignerControlNoEditableBehavior))
                }
            case .center(.systemBatteryPercentage):
                SettingsHintRow(text: localization.string(.iconDesignerControlNoEditableBehavior))
            case .center(.none), .none, .some(.ring), .some(.footer):
                SettingsHintRow(text: localization.string(.iconDesignerControlNoEditableBehavior))
            }
        }
    }

    /// The global network-failure rule. It is deliberately outside the
    /// per-source switch above so it stays visible and editable for every centre
    /// source (input method, battery percentage, Bluetooth, network, legacy and
    /// none), and its value does not change when the primary/fallback tab flips.
    private var globalNetworkOverrideControl: some View {
        IconDesignerControlRow(
            localization.string(.iconDesignerControlNetworkProblemsOverride),
            subtitle: localization.string(.iconDesignerControlNetworkProblemsOverrideHelp),
            identifier: "iconDesigner.centerNetworkOverride"
        ) {
            Toggle("", isOn: Binding(
                get: { store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary },
                set: { value in
                    editorModel.updateIconConfiguration {
                        $0.composition.centerOverride.networkProblemOverridesPrimary = value
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(localization.string(.iconDesignerControlNetworkProblemsOverride))
            .accessibilityIdentifier("iconDesigner.centerNetworkOverride.toggle")
        }
    }

    private var connectedBluetoothCapabilities: Set<IconDesignerBehaviorCapability> {
        return IconDesignerEditingModel.behaviors(
            for: .center,
            source: .center(.connectedBluetoothDevice),
            bluetoothTarget: selectedBluetoothTarget,
            devices: effectiveBluetoothDevices
        )
    }

    private var effectiveBluetoothDevices: [BluetoothDevice] {
        bluetoothAvailability == .available ? bluetoothDevices : []
    }

    private var selectedBluetoothTarget: IconDesignerBluetoothTarget {
        let address = store.connectedBluetoothIconDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
        return address.map(IconDesignerBluetoothTarget.connectedDevice) ?? .currentAudioOutput
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
        }
    }

    private var legacyBluetoothBehavior: some View {
        Group {
            toggle(localization.string(.iconDesignerControlReplaceNetworkWithBluetooth), get: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon }, set: { $0.behaviors.bluetoothAudioCenter.replacesNetworkIcon = $1 })
            IconDesignerControlRow(localization.string(.settingsBluetoothIconChoice), showsDivider: false) {
                Picker(localization.string(.settingsBluetoothIconChoice), selection: Binding(
                    get: { store.bluetoothAudioIconChoice },
                    set: { store.bluetoothAudioIconChoice = $0 }
                )) {
                    ForEach(IconPresentationResourceResolver.availableBluetoothAudioIconChoices) { choice in
                        Label(
                            choice.displayName(using: localization),
                            systemImage: choice.symbolName ?? "arrow.clockwise"
                        )
                        .tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel(localization.string(.settingsBluetoothIconChoice))
                .accessibilityIdentifier("iconDesigner.bluetoothAudioIconChoice")
            }
            toggle(localization.string(.iconDesignerControlUseVolumeColor), get: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor }, set: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor = $1 })
        }
    }

    private var airPodsRingBehavior: some View {
        Group {
            IconDesignerControlRow(localization.string(.iconDesignerAirPodsRingBehavior)) {
                Picker("", selection: Binding(
                get: { store.iconConfiguration.behaviors.airPodsRing },
                set: { value in editorModel.updateIconConfiguration { $0.behaviors.airPodsRing = value } }
                )) {
                    Text(localization.string(.iconDesignerAirPodsRingSingle)).tag(AirPodsRingBehavior.single)
                    Text(localization.string(.iconDesignerAirPodsRingDual)).tag(AirPodsRingBehavior.dual)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            SettingsHintRow(text: localization.string(
                store.iconConfiguration.behaviors.airPodsRing == .single
                    ? .iconDesignerAirPodsSingleExplanation
                    : .iconDesignerAirPodsDualExplanation
            ))
            if store.iconConfiguration.behaviors.airPodsRing == .dual {
                toggle(
                    localization.string(.iconDesignerShowAirPodsTopSymbol),
                    get: { $0.behaviors.showsAirPodsTopSymbol },
                    set: { $0.behaviors.showsAirPodsTopSymbol = $1 }
                )
            }
        }
    }

    /// Volume-based tinting only makes sense for a real audio target; non-audio
    /// devices never show this switch.
    private var bluetoothOutputBehavior: some View {
        toggle(
            localization.string(.iconDesignerControlUseVolumeColor),
            get: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor },
            set: { $0.behaviors.bluetoothAudioCenter.usesVolumeColor = $1 }
        )
    }

    /// One glyph control for both Bluetooth audio sources. A specific choice is
    /// stored as the shared symbol override so it wins over the legacy
    /// `bluetoothAudioIconChoice`; picking Automatic clears both, restoring true
    /// device-type auto detection. Both edits run in one undoable transaction,
    /// so the two preferences can never mask each other.
    private var bluetoothIconSourcePicker: some View {
        let savedSymbol = store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
            ?? store.bluetoothAudioIconChoice.symbolName
        let options = BluetoothNetworkIconSourceOption.glyphOptions(
            devices: effectiveBluetoothDevices, order: bluetoothDeviceOrder, savedSymbol: savedSymbol
        )
        return IconDesignerControlRow(localization.string(.iconDesignerControlBluetoothSymbol), showsDivider: false) {
            Picker("", selection: Binding(
                get: { savedSymbol },
                set: { value in editorModel.perform {
                    store.updateIconConfiguration { configuration in
                        _ = IconDesignerEditingModel.setBluetoothSymbolOverride(
                            value,
                            for: effectiveBehaviorTarget,
                            in: &configuration,
                            bluetoothTarget: selectedBluetoothTarget,
                            devices: effectiveBluetoothDevices
                        )
                    }
                    // A specific glyph owns the icon; dropping the legacy choice
                    // keeps Automatic from being masked by a stale preference.
                    store.bluetoothAudioIconChoice = .automatic
                } }
            )) {
                Text(localization.string(.iconDesignerControlAutomatic)).tag(String?.none)
                ForEach(options) { option in
                    Text(label(for: option))
                        .tag(Optional(option.symbolName))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(localization.string(.iconDesignerControlBluetoothSymbol))
            .accessibilityIdentifier("iconDesigner.bluetoothIconSource")
        }
    }

    private var bluetoothSymbolPicker: some View {
        let selected = store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
        let options = BluetoothNetworkIconSourceOption.glyphOptions(
            devices: effectiveBluetoothDevices, order: bluetoothDeviceOrder, savedSymbol: selected
        )
        return IconDesignerControlRow(localization.string(.iconDesignerControlBluetoothSymbol), showsDivider: false) {
            Picker("", selection: Binding(
            get: { store.iconConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride },
            set: { value in
                editorModel.updateIconConfiguration { configuration in
                    _ = IconDesignerEditingModel.setBluetoothSymbolOverride(
                        value,
                        for: effectiveBehaviorTarget,
                        in: &configuration,
                        bluetoothTarget: selectedBluetoothTarget,
                        devices: effectiveBluetoothDevices
                    )
                }
            }
        )) {
            Text(localization.string(.iconDesignerControlAutomatic)).tag(String?.none)
            ForEach(options) { option in
                Text(label(for: option)).tag(Optional(option.symbolName))
            }
        }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(localization.string(.iconDesignerControlBluetoothSymbol))
        }
    }

    /// Product glyphs draw their localized product name; device rows draw the
    /// device name; anything else (an unknown saved symbol) keeps the explicit
    /// saved-symbol format so it is still selectable.
    private func label(for option: BluetoothNetworkIconSourceOption.GlyphOption) -> String {
        if let choice = option.choice {
            return choice.displayName(using: localization)
        }
        if let title = option.title {
            return title
        }
        if option.isSavedUnsupportedSymbol {
            return localization.format(.iconDesignerControlSavedSymbolFormat, option.symbolName)
        }
        return localization.format(.iconDesignerControlAudioOutputFormat, option.symbolName)
    }

    private func toggle(_ title: String, get: @escaping (IconConfigurationV1) -> Bool,
                        set: @escaping (inout IconConfigurationV1, Bool) -> Void) -> some View {
        IconDesignerControlRow(title) {
            Toggle("", isOn: Binding(
                get: { get(store.iconConfiguration) },
                set: { value in editorModel.updateIconConfiguration { set(&$0, value) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(title)
        }
    }

    private func integerSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, coalescingKey: String) -> some View {
        IconDesignerControlRow(title, showsDivider: false) {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    onEditingChanged: { editing in
                        if editing { editorModel.beginCoalescingGroup(coalescingKey) }
                        else { editorModel.endCoalescingGroup(coalescingKey) }
                    }
                )
                .frame(minWidth: 90, maxWidth: 160)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue)%")

                Text("\(value.wrappedValue)%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }


}
