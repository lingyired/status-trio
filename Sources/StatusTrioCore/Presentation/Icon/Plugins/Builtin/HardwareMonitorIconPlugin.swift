struct HardwareMonitorIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.hardware-monitor", presentations: [
        .init(id: "ring", slot: .outerRing, title: .hardwareMonitorTitle,
              isSelectable: true, summary: .hardwareMonitorSettingsMetricsDescription)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "ring" else { return .unavailable(.unavailable) }
        // The source is always selectable: even when every metric is currently
        // unreadable the ring keeps its (greyed) track rather than blanking the
        // whole menu-bar icon. Per-metric availability is handled in the mapper.
        let state = HardwareRingMapper.resolve(
            snapshot: context.inputs.sources.hardwareMetrics,
            configuration: context.configuration.behaviors.hardwareRing,
            levels: context.inputs.sources.hardwareRingLevels,
            metricColors: context.inputs.sources.hardwareMetricColors,
            speedCapsMbps: context.inputs.sources.hardwareSpeedCapsMbps,
            now: context.now
        )
        return .available(.outerRing(state))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        guard presentationID == "ring" else { return .init() }
        let configuration = context.configuration.behaviors.hardwareRing.normalized()
        let metricIDs = Set(configuration.referencedMetrics.map(\.metricID))
        return .init(samples: [.hardwareMonitor], requiresHardwareMonitor: true, hardwareMetricIDs: metricIDs)
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        presentationID == "ring" ? [.hardwareMonitor] : []
    }
}
