struct NetworkIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.network", presentations: [
        .init(id: "center", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true, summary: .iconDesignerNetworkSummary),
        .init(id: "footer", slot: .footer, title: .iconDesignerSourceNetwork, isSelectable: true, summary: .iconDesignerNetworkSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        switch presentationID {
        case "center":
            if !context.isAlertOverride,
               case let .unavailable(reason) = context.inputs.sources.result(
                   for: CenterSource.network.rawValue, default: .available(true)) {
                return .unavailable(reason)
            }
            return .available(.center(Self.networkState(
                inputs: context.inputs, configuration: context.configuration, legacy: context.legacy)))
        case "footer":
            return .available(.footer(Self.footerState(inputs: context.inputs, legacy: context.legacy)))
        default:
            return .unavailable(.unavailable)
        }
    }

    /// Reuses the host's existing bottom-indicator artwork for Wi-Fi bars. The
    /// plugin forces its own source so the binding, not a stale individual
    /// setting, decides what the footer draws.
    static func footerState(inputs: IconResolutionInputs,
                            legacy: IconPresentationConfiguration) -> FooterState? {
        var systemInputs = inputs.system
        systemInputs.bottomIndicatorSource = .wifi
        return IconPresentationMapper.scene(inputs: systemInputs, configuration: legacy).footer
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
                centerSource: .network,
                prioritizesNetworkErrors: false,
                wifiScale: legacyConnection.wifiScale
            ),
            volume: legacy.volume,
            bluetooth: .standard
        )
        return IconPresentationMapper.scene(inputs: inputs.system, configuration: options).center
    }


    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.network])
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return [.networkRepresentation]
    }

}
