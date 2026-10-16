import Foundation

enum CenterResolver {
    static func resolve(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration
    ) -> (state: CenterState?, trace: SlotResolutionTrace, source: CenterSource?) {
        let renderConfiguration = configuration
        let selection = renderConfiguration.composition.center
        let primary = selection.primary
        if primary == .automaticLegacy {
            return (IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).center,
                    SlotResolutionTrace(selectedSourceID: primary.rawValue, role: .primary,
                                        primaryFailure: nil, reason: .primary), source: primary)
        }
        let selected: SourceSelectionResult<CenterSource> = chooseSource(selection, none: .none) { source -> SourceResult<Bool> in
            switch source {
            case .none:
                return .unavailable(.unavailable)
            case .automaticLegacy:
                return .available(true)
            case .network:
                return inputs.sources.result(for: source.rawValue, default: .available(true))
            case .bluetoothAudioOutput:
                let connected = inputs.system.snapshot.volume.currentDevice?.isBluetoothAudio == true
                return inputs.sources.result(for: source.rawValue,
                    default: connected ? .available(true) : .unavailable(.disconnected))
            case .pinnedBluetoothGlyph:
                return inputs.sources.result(for: source.rawValue, default: .available(true))
            case .connectedBluetoothDevice:
                switch inputs.sources.availability[source.rawValue] {
                case .available: return .available(true)
                case let .unavailable(reason): return .unavailable(reason)
                case nil: return .unavailable(.disconnected)
                }
            case .systemBatteryPercentage:
                let present = inputs.system.snapshot.battery.isPresent
                return inputs.sources.result(for: source.rawValue,
                    default: present ? .available(true) : .unavailable(.unavailable))
            }
        }
        guard let source = selected.source else { return (nil, trace(selected, source: nil), source: nil) }

        let snapshot = inputs.system.snapshot
        let selectedBluetoothIsAudio: Bool = switch source {
        case .bluetoothAudioOutput:
            true
        case .connectedBluetoothDevice:
            inputs.sources.connectedBluetoothDeviceIsAudio == true
        default:
            false
        }
        if configuration.composition.centerOverride.networkProblemOverridesPrimary,
           primary == source,
           selectedBluetoothIsAudio,
           hasNetworkProblem(snapshot) {
            let network = networkState(inputs: inputs, configuration: configuration, legacy: legacy)
            return (network, SlotResolutionTrace(selectedSourceID: CenterSource.network.rawValue, role: .primary,
                primaryFailure: selected.primaryFailure, reason: .overridden(.networkProblem)), source: .network)
        }

        let state: CenterState?
        switch source {
        case .automaticLegacy:
            state = IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).center
        case .network:
            if inputs.system.runtimeOptions?.connectionCenterSource == .inputSource {
                // The main input-source setting augments legacy/Network V1
                // centers only. The old mapper owns its priority and automatic
                // fallback rules, including network warnings and Bluetooth.
                state = IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).center
            } else {
                state = networkState(inputs: inputs, configuration: configuration, legacy: legacy)
            }
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
        case .systemBatteryPercentage:
            let battery = snapshot.battery
            state = battery.isPresent
                ? .text(IconTextState(text: "\(battery.percentage)", color: .primary,
                                     scale: configuration.behaviors.systemBatteryRing.textScale))
                : nil
        case .none: state = nil
        }
        return (state, trace(selected, source: source), source)
    }

    private static func hasNetworkProblem(_ snapshot: StatusSnapshot) -> Bool {
        guard snapshot.connection != .offline else { return false }
        return switch snapshot.wifi.state {
        case .notAssociated, .noInternet, .off, .unavailable: true
        case .connected, .hotspot, .temporary, .shared: false
        }
    }

    private static func bluetoothColor(
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

    private static func networkState(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration
    ) -> CenterState? {
        // The explicit network source never lets Bluetooth behavior preempt network state.
        let legacyConnection = legacy.connection
        let options = IconPresentationConfiguration(
            battery: legacy.battery,
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: legacyConnection.showsWiFiIconForEthernet,
                showsWiFiIconForHotspot: legacyConnection.showsWiFiIconForHotspot,
                showsWiFiIconForTemporaryConnection: legacyConnection.showsWiFiIconForTemporaryConnection,
                showsWiFiIconForInternetSharing: legacyConnection.showsWiFiIconForInternetSharing,
                showsBatteryPercentageInConnectionSlot: false,
                wifiScale: legacyConnection.wifiScale
            ),
            volume: legacy.volume,
            bluetooth: .standard
        )
        return IconPresentationMapper.scene(inputs: inputs.system, configuration: options).center
    }

    private static func trace(_ result: SourceSelectionResult<CenterSource>, source: CenterSource?) -> SlotResolutionTrace {
        SlotResolutionTrace(selectedSourceID: source?.rawValue, role: result.role,
                            primaryFailure: result.primaryFailure, reason: result.reason)
    }
}
