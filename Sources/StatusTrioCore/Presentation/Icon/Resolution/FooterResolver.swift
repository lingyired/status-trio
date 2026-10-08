import Foundation

enum FooterResolver {
    static func resolve(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration
    ) -> (state: FooterState?, trace: SlotResolutionTrace) {
        let selected: SourceSelectionResult<FooterSource> = chooseSource(configuration.composition.footer, none: .none) { source -> SourceResult<Bool> in
            switch source {
            case .none: .unavailable(.unavailable)
            case .systemVolume: inputs.sources.result(for: source.rawValue, default: .available(true))
            }
        }
        guard let source = selected.source else { return (nil, trace(selected, source: nil)) }
        return (IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).footer,
                trace(selected, source: source))
    }

    private static func trace(_ result: SourceSelectionResult<FooterSource>, source: FooterSource?) -> SlotResolutionTrace {
        SlotResolutionTrace(selectedSourceID: source?.rawValue, role: result.role,
                            primaryFailure: result.primaryFailure, reason: result.reason)
    }
}
