import Foundation

enum OuterRingResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        legacy: IconPresentationConfiguration, behavior: AirPodsRingBehavior = .single,
                        showsAirPodsTopSymbol: Bool = false, now: Date = .now,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> (state: OuterRingState?, trace: SlotResolutionTrace) {
        var renderConfiguration = configuration
        renderConfiguration.behaviors.airPodsRing = behavior
        renderConfiguration.behaviors.showsAirPodsTopSymbol = showsAirPodsTopSymbol
        let selection = configuration.composition.outerRing
        let output = IconPluginSlotResolver.resolve(primary: IconContentLegacyAdapter.binding(for: selection.primary),
            fallback: selection.fallback.flatMap { IconContentLegacyAdapter.binding(for: $0) }, slot: .outerRing,
            context: .init(inputs: inputs, configuration: renderConfiguration, legacy: legacy, now: now), registry: registry)
        guard case let .outerRing(state) = output.payload else { return (nil, output.trace) }
        return (state, output.trace)
    }
}
