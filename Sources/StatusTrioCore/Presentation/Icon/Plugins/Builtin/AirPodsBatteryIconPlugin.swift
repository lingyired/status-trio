struct AirPodsBatteryIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.airpods-battery", presentations: [
        .init(id: "ring", slot: .outerRing, title: .iconDesignerSourceAirPodsBattery, isSelectable: true, summary: .iconDesignerAirPodsSummary)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "ring" else { return .unavailable(.unavailable) }
        let id = RingSource.airPodsBattery.rawValue
        switch context.inputs.sources.availability[id] {
        case let .unavailable(reason): return .unavailable(reason)
        case nil: return .unavailable(.disconnected)
        case .available: break
        }
        let held = context.inputs.sources.holdingSourceIDs.contains(id)
        guard let snapshot = context.inputs.sources.airPodsBattery,
              held || AirPodsRingMapper.isFresh(snapshot, at: context.now),
              AirPodsRingMapper.hasRenderableBattery(snapshot) else { return .unavailable(.temporarilyStale) }
        let appearance = context.configuration.appearance
        return .available(.outerRing(AirPodsRingMapper.resolve(snapshot: snapshot,
            behavior: context.configuration.behaviors.airPodsRing, now: context.now, isHeld: held,
            showsTopSymbol: context.configuration.behaviors.showsAirPodsTopSymbol,
            topSymbolScale: context.configuration.behaviors.systemBatteryRing.textScale,
            leftColor: Self.colorRole(appearance.airPodsLeftArcColor.selection),
            rightColor: Self.colorRole(appearance.airPodsRightArcColor.selection),
            singleColor: Self.colorRole(appearance.airPodsSingleArcColor.selection))))
    }

    private static func colorRole(_ selection: BluetoothIconColorSelection) -> IconColorRole {
        switch selection {
        case .systemBlue: .bluetooth
        case .primary: .primary
        case let .custom(components):
            .custom(IconRGBA.hsb(
                hue: components.hue,
                saturation: components.saturation,
                brightness: components.brightness
            ))
        }
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.airPods], requiresBluetoothMonitor: true, requiresAirPodsBattery: true)
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return [.airPodsBattery]
    }

}
