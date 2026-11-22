struct IconContentDependencyContext: Sendable {
    let configuration: IconConfigurationV1
    let targetIsAudio: Bool
    /// Which hardware-monitor metric the `.metric` bottom source draws, so the
    /// footer hardware presentation can demand exactly that sample.
    var bottomIndicatorMetric: HardwareMonitorMetric = .cpuUsage
}

struct IconContentDependencies: Equatable, Sendable {
    var samples: Set<IconPreviewSampleSource> = []
    var requiresBluetoothMonitor = false
    var requiresAirPodsBattery = false
    var requiresHardwareMonitor = false
    /// The exact hardware metrics the composition reads, so the shared sampler
    /// can demand only what is on screen.
    var hardwareMetricIDs: Set<HardwareMetricID> = []

    mutating func formUnion(_ other: Self) {
        samples.formUnion(other.samples)
        requiresBluetoothMonitor = requiresBluetoothMonitor || other.requiresBluetoothMonitor
        requiresAirPodsBattery = requiresAirPodsBattery || other.requiresAirPodsBattery
        requiresHardwareMonitor = requiresHardwareMonitor || other.requiresHardwareMonitor
        hardwareMetricIDs.formUnion(other.hardwareMetricIDs)
    }
}

enum IconDesignerBehaviorCapability: Hashable, Sendable {
    case legacyBatteryPercentageInCenter
    case networkRepresentation
    case bluetoothOutputAppearance
    case pinnedBluetoothGlyph
    case systemBattery
    case airPodsBattery
    case systemVolume
    case hardwareMonitor
}

enum IconContentDependencyResolver {
    static func dependencies(configuration rawConfiguration: IconConfigurationV1, targetIsAudio: Bool,
                             bottomIndicatorSource: BottomIndicatorSource = .volume,
                             bindings: IconSlotBindingsV1? = nil,
                             registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> IconContentDependencies {
        let configuration = rawConfiguration.normalized()
        let context = IconContentDependencyContext(configuration: configuration, targetIsAudio: targetIsAudio)
        let effective = (bindings ?? IconSlotBindingsV1.migrated(
            from: configuration
        )).normalized()
        let selectedBindings: [IconContentBinding] = [
            effective.outerRing.primary,
            effective.outerRing.fallback,
            effective.center.primary,
            effective.center.fallback,
            effective.footer.primary,
            effective.footer.fallback
        ].compactMap { $0 }
        var dependencies = IconContentDependencies()
        for binding in Set(selectedBindings) {
            dependencies.formUnion(registry.dependencies(for: binding, context: context))
        }
        if configuration.composition.centerOverride.networkProblemOverridesPrimary,
           let network = IconContentLegacyAdapter.binding(for: CenterSource.network) {
            dependencies.formUnion(registry.dependencies(for: network, context: context))
        }
        return dependencies
    }
}
