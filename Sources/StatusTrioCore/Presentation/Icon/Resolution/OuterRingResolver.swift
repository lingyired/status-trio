import Foundation

enum OuterRingResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        legacy: IconPresentationConfiguration, behavior: AirPodsRingBehavior = .single,
                        showsAirPodsTopSymbol: Bool = false, now: Date = .now,
                        bindingSelection: IconSlotBindingSelection? = nil,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> (state: OuterRingState?, trace: SlotResolutionTrace) {
        var renderConfiguration = configuration
        renderConfiguration.behaviors.airPodsRing = behavior
        renderConfiguration.behaviors.showsAirPodsTopSymbol = showsAirPodsTopSymbol
        let selection = bindingSelection ?? .init(
            primary: IconContentLegacyAdapter.binding(for: configuration.composition.outerRing.primary),
            fallback: configuration.composition.outerRing.fallback.flatMap(IconContentLegacyAdapter.binding(for:)))
        let output = IconPluginSlotResolver.resolve(primary: selection.primary,
            fallback: selection.fallback, slot: .outerRing,
            context: .init(inputs: inputs, configuration: renderConfiguration, legacy: legacy, now: now), registry: registry)
        guard case let .outerRing(state) = output.payload else { return (nil, output.trace) }
        return (state, output.trace)
    }
}
