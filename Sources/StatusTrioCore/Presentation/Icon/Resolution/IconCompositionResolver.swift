import Foundation

struct IconResolutionInputs: Equatable, Sendable {
    var system: IconPresentationInputs
    var sources: IconSourceSnapshot
}

struct SourceSelectionResult<Source: Codable & Hashable & Sendable>: Equatable, Sendable {
    var source: Source?
    var role: SlotResolutionRole
    var primaryFailure: IconSourceUnavailableReason?
    var reason: SlotResolutionReason
}

func chooseSource<Source: Codable & Hashable & Sendable>(
    _ selection: SlotSelection<Source>,
    none: Source,
    availability: (Source) -> SourceResult<Bool>
) -> SourceSelectionResult<Source> {
    guard selection.primary != none else {
        return SourceSelectionResult(source: nil, role: .none, primaryFailure: nil, reason: .none)
    }
    switch availability(selection.primary) {
    case .available:
        return SourceSelectionResult(source: selection.primary, role: .primary, primaryFailure: nil, reason: .primary)
    case let .unavailable(primaryFailure):
        guard let fallback = selection.fallback, fallback != none else {
            return SourceSelectionResult(source: nil, role: .none, primaryFailure: primaryFailure, reason: .none)
        }
        switch availability(fallback) {
        case .available:
            return SourceSelectionResult(source: fallback, role: .fallback, primaryFailure: primaryFailure,
                                         reason: .fallback(primaryFailure))
        case .unavailable:
            return SourceSelectionResult(source: nil, role: .none, primaryFailure: primaryFailure, reason: .none)
        }
    }
}

enum IconCompositionResolver {
    static func resolve(inputs: IconResolutionInputs, configuration rawConfiguration: IconConfigurationV1) -> IconResolutionOutput {
        let configuration = rawConfiguration.normalized()
        let legacy = configuration.legacyPresentationConfiguration

        let ring = OuterRingResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy)
        let center = CenterResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy)
        let footer = FooterResolver.resolve(inputs: inputs, configuration: configuration, legacy: legacy)
        return IconResolutionOutput(
            scene: IconPaletteResolver.apply(
                IconSceneState(outerRing: ring.state, center: center.state, footer: footer.state),
                appearance: configuration.appearance
            ),
            trace: IconResolutionTrace(outerRing: ring.trace, center: center.trace, footer: footer.trace)
        )
    }
}
