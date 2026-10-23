struct NetworkIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.network", presentations: [
        .init(id: "center", slot: .center, title: .iconDesignerSourceNetwork, isSelectable: true, summary: .iconDesignerNetworkSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "center" else { return .unavailable(.unavailable) }
        if !context.isAlertOverride,
           case let .unavailable(reason) = context.inputs.sources.result(for: CenterSource.network.rawValue, default: .available(true)) {
            return .unavailable(reason)
        }
        return .available(.center(Self.networkState(inputs: context.inputs, configuration: context.configuration, legacy: context.legacy)))
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


    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.network])
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return [.networkRepresentation]
    }

}
