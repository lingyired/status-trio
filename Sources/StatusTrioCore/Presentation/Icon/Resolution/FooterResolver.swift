import Foundation

enum FooterResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        legacy: IconPresentationConfiguration, now: Date = .now,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> (state: FooterState?, trace: SlotResolutionTrace) {
        let selection = configuration.composition.footer
        let output = IconPluginSlotResolver.resolve(primary: IconContentLegacyAdapter.binding(for: selection.primary),
            fallback: selection.fallback.flatMap { IconContentLegacyAdapter.binding(for: $0) }, slot: .footer,
            context: .init(inputs: inputs, configuration: configuration, legacy: legacy, now: now), registry: registry)
        guard case let .footer(state) = output.payload else { return (nil, output.trace) }
        return (state, output.trace)
    }
}
