struct IconContentDependencyContext: Sendable {
    let configuration: IconConfigurationV1
    let targetIsAudio: Bool
}

struct IconContentDependencies: Equatable, Sendable {
    var samples: Set<IconPreviewSampleSource> = []
    var requiresBluetoothMonitor = false
    var requiresAirPodsBattery = false

    mutating func formUnion(_ other: Self) {
        samples.formUnion(other.samples)
        requiresBluetoothMonitor = requiresBluetoothMonitor || other.requiresBluetoothMonitor
        requiresAirPodsBattery = requiresAirPodsBattery || other.requiresAirPodsBattery
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
}

enum IconContentDependencyResolver {
    static func dependencies(configuration rawConfiguration: IconConfigurationV1, targetIsAudio: Bool,
                             registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> IconContentDependencies {
        let configuration = rawConfiguration.normalized()
        let context = IconContentDependencyContext(configuration: configuration, targetIsAudio: targetIsAudio)
        let composition = configuration.composition
        let bindings: [IconContentBinding] = [
            IconContentLegacyAdapter.binding(for: composition.outerRing.primary),
            composition.outerRing.fallback.flatMap { IconContentLegacyAdapter.binding(for: $0) },
            IconContentLegacyAdapter.binding(for: composition.center.primary),
            composition.center.fallback.flatMap { IconContentLegacyAdapter.binding(for: $0) },
            IconContentLegacyAdapter.binding(for: composition.footer.primary),
            composition.footer.fallback.flatMap { IconContentLegacyAdapter.binding(for: $0) }
        ].compactMap { $0 }
        var dependencies = IconContentDependencies()
        for binding in Set(bindings) {
            dependencies.formUnion(registry.dependencies(for: binding, context: context))
        }
        if composition.centerOverride.networkProblemOverridesPrimary,
           let network = IconContentLegacyAdapter.binding(for: CenterSource.network) {
            dependencies.formUnion(registry.dependencies(for: network, context: context))
        }
        return dependencies
    }
}
