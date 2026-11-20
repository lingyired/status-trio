import Foundation

enum CenterResolver {
    static func resolve(inputs: IconResolutionInputs, configuration: IconConfigurationV1,
                        legacy: IconPresentationConfiguration, now: Date = .now,
                        bindingSelection: IconSlotBindingSelection? = nil,
                        registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> (state: CenterState?, trace: SlotResolutionTrace, source: CenterSource?) {
        let context = IconContentContext(inputs: inputs, configuration: configuration, legacy: legacy, now: now)
        let snapshot = inputs.system.snapshot
        if configuration.composition.centerOverride.networkProblemOverridesPrimary,
           StatusMappings.isNetworkOffline(wifi: snapshot.wifi, connection: snapshot.connection),
           let binding = IconContentLegacyAdapter.binding(for: CenterSource.network) {
            var overrideContext = context
            overrideContext.isAlertOverride = true
            switch registry.resolve(binding, for: .center, context: overrideContext) {
            case let .available(.center(state)):
                return (state, .init(selectedSourceID: CenterSource.network.rawValue, role: .primary,
                    primaryFailure: nil, reason: .overridden(.networkProblem)), .network)
            case let .unavailable(reason):
                return (nil, .init(selectedSourceID: nil, role: .none, primaryFailure: reason, reason: .none), nil)
            default: return (nil, .empty, nil)
            }
        }
        let selection = bindingSelection ?? .init(
            primary: IconContentLegacyAdapter.binding(for: configuration.composition.center.primary),
            fallback: configuration.composition.center.fallback.flatMap(IconContentLegacyAdapter.binding(for:)))
        let output = IconPluginSlotResolver.resolve(primary: selection.primary,
            fallback: selection.fallback, slot: .center, context: context, registry: registry)
        let source = output.binding.flatMap { IconContentLegacyAdapter.centerSource(for: $0) }
        guard case let .center(state) = output.payload else { return (nil, output.trace, source) }
        return (state, output.trace, source)
    }
}
