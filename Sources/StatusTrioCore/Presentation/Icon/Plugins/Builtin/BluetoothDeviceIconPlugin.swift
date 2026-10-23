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
            fallback = inputs.sources.availability[source.rawValue] == .available ? .available(true) : .unavailable(.disconnected)
        default: fallback = .available(true)
        }
        if case let .unavailable(reason) = inputs.sources.result(for: source.rawValue, default: fallback) { return .unavailable(reason) }
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
            let isAudioTarget = inputs.sources.connectedBluetoothDeviceIsAudio == true
            let symbol = isAudioTarget
                ? (renderConfiguration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
                    ?? inputs.sources.connectedBluetoothDeviceSymbol)
                : inputs.sources.connectedBluetoothDeviceSymbol
            state = symbol.map {
                .symbol(IconSymbolState(
                    source: .symbol(name: $0, variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
                    color: bluetoothColor(inputs: inputs, configuration: renderConfiguration, isAudioTarget: isAudioTarget),
                    scale: renderConfiguration.behaviors.bluetoothAudioCenter.symbolScale
                ))
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
