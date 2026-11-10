struct BluetoothDeviceIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.bluetooth-device", presentations: [
        .init(id: "output", slot: .center, title: .iconDesignerSourceBluetoothAudio, isSelectable: true, summary: .iconDesignerBluetoothSummary),
        .init(id: "connected", slot: .center, title: .iconDesignerSourceConnectedBluetooth, isSelectable: true, summary: .iconDesignerBluetoothSummary),
        .init(id: "pinned-glyph", slot: .center, title: .iconDesignerSourcePinnedBluetooth, isSelectable: false)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        let inputs = context.inputs
        let renderConfiguration = context.configuration
        let source: CenterSource
        switch presentationID {
        case "output": source = .bluetoothAudioOutput
        case "connected": source = .connectedBluetoothDevice
        case "pinned-glyph": source = .pinnedBluetoothGlyph
        default: return .unavailable(.unavailable)
        }
        let fallback: SourceResult<Bool>
        switch source {
        case .bluetoothAudioOutput:
            fallback = inputs.system.snapshot.volume.currentDevice?.isBluetoothAudio == true ? .available(true) : .unavailable(.disconnected)
        case .connectedBluetoothDevice:
            // Mirror main's `.bluetoothDevice` rule: the current Bluetooth audio
            // device (or an explicit glyph override) is enough; no separate
            // "selected device address" is required.
            let selectedAvailable = inputs.sources.availability[source.rawValue] == .available
                && inputs.sources.connectedBluetoothDeviceSymbol != nil
            let canShow = StatusMappings.canShowBluetoothIcon(
                currentDevice: inputs.system.snapshot.volume.currentDevice,
                options: context.legacy.bluetooth
            )
            fallback = (selectedAvailable || canShow) ? .available(true) : .unavailable(.disconnected)
        default: fallback = .available(true)
        }
        if source == .connectedBluetoothDevice {
            if case let .unavailable(reason) = fallback { return .unavailable(reason) }
        } else if case let .unavailable(reason) = inputs.sources.result(for: source.rawValue, default: fallback) {
            return .unavailable(reason)
        }
        let state: CenterState?
        switch source {
        case .bluetoothAudioOutput:
            let configuredSymbol = renderConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
                ?? inputs.system.runtimeOptions?.bluetoothAudioIconChoice.symbolName
            let icon = configuredSymbol.map {
                IconSymbolSource.symbol(name: $0, variableValue: nil, fallback: "headphones")
            } ?? inputs.system.audioIcon ?? .symbol(name: "headphones", variableValue: nil, fallback: nil)
            state = .symbol(IconSymbolState(source: icon, color: bluetoothColor(
                inputs: inputs, configuration: renderConfiguration, isAudioTarget: true
            ),
                scale: renderConfiguration.behaviors.bluetoothAudioCenter.symbolScale))
        case .connectedBluetoothDevice:
            let bluetoothOptions = context.legacy.bluetooth
            let currentDevice = inputs.system.snapshot.volume.currentDevice
            if inputs.sources.availability[source.rawValue] == .available,
               let selectedSymbol = inputs.sources.connectedBluetoothDeviceSymbol {
                // An explicitly selected, connected device keeps its own glyph and
                // volume-aware colour (designer / selected-device behaviour).
                let isAudioTarget = inputs.sources.connectedBluetoothDeviceIsAudio == true
                let symbol = isAudioTarget
                    ? (bluetoothOptions.networkIconSymbolOverride ?? selectedSymbol)
                    : selectedSymbol
                state = .symbol(IconSymbolState(
                    source: .symbol(name: symbol, variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
                    color: bluetoothColor(inputs: inputs, configuration: renderConfiguration, isAudioTarget: isAudioTarget),
                    scale: bluetoothOptions.symbolScale
                ))
            } else {
                // Otherwise mirror `IconPresentationMapper.centerState`'s
                // `.bluetoothDevice` branch exactly (main's product behaviour for
                // the settings "Bluetooth device" centre).
                let symbolSource: IconSymbolSource
                if let override = bluetoothOptions.networkIconSymbolOverride {
                    symbolSource = .symbol(name: override, variableValue: nil, fallback: "dot.radiowaves.left.and.right")
                } else if currentDevice?.isBluetoothAudio == true,
                          let selectedSymbol = bluetoothOptions.iconChoice.symbolName {
                    symbolSource = .symbol(name: selectedSymbol, variableValue: nil, fallback: "headphones")
                } else if let audioIcon = inputs.system.audioIcon {
                    symbolSource = audioIcon
                } else {
                    symbolSource = .symbol(name: "headphones", variableValue: nil, fallback: nil)
                }
                let color: IconColorRole = bluetoothOptions.iconColor == .primary ? .primary : .bluetoothIcon
                state = .symbol(IconSymbolState(source: symbolSource, color: color, scale: bluetoothOptions.symbolScale))
            }
        case .pinnedBluetoothGlyph:
            let savedSymbol = renderConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
            let icon = savedSymbol.map {
                IconSymbolSource.symbol(name: $0, variableValue: nil, fallback: "dot.radiowaves.left.and.right")
            } ?? .symbol(name: "headphones", variableValue: nil, fallback: nil)
            state = .symbol(IconSymbolState(source: icon, color: .bluetooth,
                scale: renderConfiguration.behaviors.bluetoothAudioCenter.symbolScale))
        default: return .unavailable(.unavailable)
        }
        return .available(.center(state))
    }

    private func bluetoothColor(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        isAudioTarget: Bool
    ) -> IconColorRole {
        guard isAudioTarget,
              configuration.behaviors.bluetoothAudioCenter.usesVolumeColor else {
            return .bluetooth
        }
        let volume = inputs.system.snapshot.volume
        return StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted).map { $0 > 0 } == true
            ? .bluetooth
            : .primary
    }


    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        var samples: Set<IconPreviewSampleSource> = [.bluetoothTarget]
        if context.configuration.behaviors.bluetoothAudioCenter.usesVolumeColor, context.targetIsAudio {
            samples.insert(.systemVolume)
        }
        return .init(samples: samples, requiresBluetoothMonitor: presentationID == "connected")
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        switch presentationID {
        case "output": return [.bluetoothOutputAppearance]
        case "pinned-glyph": return [.pinnedBluetoothGlyph]
        case "connected": return context.targetIsAudio ? [.bluetoothOutputAppearance] : []
        default: return []
        }
    }

}
