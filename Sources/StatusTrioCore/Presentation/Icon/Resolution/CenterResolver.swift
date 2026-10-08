import Foundation

enum CenterResolver {
    static func resolve(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration
    ) -> (state: CenterState?, trace: SlotResolutionTrace) {
        let selection = configuration.composition.center
        let primary = selection.primary
        if primary == .automaticLegacy {
            return (IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).center,
                    SlotResolutionTrace(selectedSourceID: primary.rawValue, role: .primary,
                                        primaryFailure: nil, reason: .primary))
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
                return inputs.sources.result(for: source.rawValue, default: .unavailable(.disconnected))
            case .systemBatteryPercentage:
                let present = inputs.system.snapshot.battery.isPresent
                return inputs.sources.result(for: source.rawValue,
                    default: present ? .available(true) : .unavailable(.unavailable))
            }
        }
        guard let source = selected.source else { return (nil, trace(selected, source: nil)) }

        let snapshot = inputs.system.snapshot
        if configuration.composition.centerOverride.networkProblemOverridesPrimary,
           primary == .bluetoothAudioOutput,
           source == .bluetoothAudioOutput,
           hasNetworkProblem(snapshot) {
            let network = networkState(inputs: inputs, configuration: configuration, legacy: legacy)
            return (network, SlotResolutionTrace(selectedSourceID: CenterSource.network.rawValue, role: .primary,
                primaryFailure: selected.primaryFailure, reason: .overridden(.networkProblem)))
        }

        let state: CenterState?
        switch source {
        case .automaticLegacy:
            state = IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).center
        case .network:
            state = networkState(inputs: inputs, configuration: configuration, legacy: legacy)
        case .bluetoothAudioOutput:
            let icon = inputs.system.audioIcon ?? .symbol(name: "headphones", variableValue: nil, fallback: nil)
            state = .symbol(IconSymbolState(source: icon, color: .bluetooth,
                scale: configuration.behaviors.bluetoothAudioCenter.symbolScale))
        case .connectedBluetoothDevice:
            state = inputs.sources.connectedBluetoothDeviceSymbol.map {
                .symbol(IconSymbolState(
                    source: .symbol(name: $0, variableValue: nil, fallback: BluetoothDeviceRowIcon.genericSymbol),
                    color: .bluetooth,
                    scale: configuration.behaviors.bluetoothAudioCenter.symbolScale
                ))
            }
        case .pinnedBluetoothGlyph:
            let savedSymbol = configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride
            let icon = savedSymbol.map {
                IconSymbolSource.symbol(name: $0, variableValue: nil, fallback: "dot.radiowaves.left.and.right")
            } ?? .symbol(name: "headphones", variableValue: nil, fallback: nil)
            state = .symbol(IconSymbolState(source: icon, color: .bluetooth,
                scale: configuration.behaviors.bluetoothAudioCenter.symbolScale))
        case .systemBatteryPercentage:
            let battery = snapshot.battery
            state = battery.isPresent
                ? .text(IconTextState(text: "\(battery.percentage)", color: .primary,
                                     scale: configuration.behaviors.systemBatteryRing.textScale))
                : nil
        case .none: state = nil
        }
        return (state, trace(selected, source: source))
    }

    private static func hasNetworkProblem(_ snapshot: StatusSnapshot) -> Bool {
        guard snapshot.connection != .offline else { return false }
        return switch snapshot.wifi.state {
        case .notAssociated, .noInternet, .off, .unavailable: true
        case .connected, .hotspot, .temporary, .shared: false
        }
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
