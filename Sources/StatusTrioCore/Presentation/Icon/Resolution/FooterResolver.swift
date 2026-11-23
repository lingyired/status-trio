import Foundation

enum FooterResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        legacy: IconPresentationConfiguration, now: Date = .now,
                        bindingSelection: IconSlotBindingSelection? = nil,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> (state: FooterState?, trace: SlotResolutionTrace) {
        let selection = bindingSelection ?? .init(
            primary: IconContentLegacyAdapter.binding(for: configuration.composition.footer.primary),
            fallback: configuration.composition.footer.fallback.flatMap(IconContentLegacyAdapter.binding(for:)))
        let output = IconPluginSlotResolver.resolve(primary: selection.primary,
            fallback: selection.fallback, slot: .footer,
            context: .init(inputs: inputs, configuration: configuration, legacy: legacy, now: now,
                           bottomIndicatorMetric: inputs.system.bottomIndicatorMetric), registry: registry)
        guard case let .footer(state) = output.payload else { return (nil, output.trace) }
        return (state, output.trace)
    }
}
