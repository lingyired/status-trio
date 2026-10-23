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
        return .available(.outerRing(AirPodsRingMapper.resolve(snapshot: snapshot,
            behavior: context.configuration.behaviors.airPodsRing, now: context.now, isHeld: held,
            showsTopSymbol: context.configuration.behaviors.showsAirPodsTopSymbol)))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        return .init(samples: [.airPods], requiresBluetoothMonitor: true, requiresAirPodsBattery: true)
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        return [.airPodsBattery]
    }

}
