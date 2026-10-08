import Foundation

enum OuterRingResolver {
    static func resolve(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration
    ) -> (state: OuterRingState?, trace: SlotResolutionTrace) {
        let selection = configuration.composition.outerRing
        let selected: SourceSelectionResult<RingSource> = chooseSource(selection, none: .none) { source -> SourceResult<Bool> in
            switch source {
            case .none: .unavailable(.unavailable)
            case .systemBattery: inputs.sources.result(for: source.rawValue, default: .available(true))
            case .airPodsBattery: inputs.sources.result(for: source.rawValue, default: .available(false))
            }
        }
        guard let source = selected.source else { return (nil, trace(selected, source: nil)) }
        guard source == .systemBattery else { return (nil, trace(selected, source: source)) }
        return (IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).outerRing,
                trace(selected, source: source))
    }

    private static func trace(_ result: SourceSelectionResult<RingSource>, source: RingSource?) -> SlotResolutionTrace {
        SlotResolutionTrace(selectedSourceID: source?.rawValue, role: result.role,
                            primaryFailure: result.primaryFailure, reason: result.reason)
    }
}
