import Foundation

enum OuterRingResolver {
    static func resolve(
        inputs: IconResolutionInputs,
        configuration: IconConfigurationV1,
        legacy: IconPresentationConfiguration,
        behavior: AirPodsRingBehavior = .single,
        now: Date = .now
    ) -> (state: OuterRingState?, trace: SlotResolutionTrace) {
        let selection = configuration.composition.outerRing
        let selected: SourceSelectionResult<RingSource> = chooseSource(selection, none: .none) { source -> SourceResult<Bool> in
            switch source {
            case .none: .unavailable(.unavailable)
            case .automaticLegacy: .available(true)
            case .systemBattery: inputs.sources.result(for: source.rawValue, default: .available(true))
            case .airPodsBattery:
                switch inputs.sources.availability[source.rawValue] {
                case .available:
                    if let snapshot = inputs.sources.airPodsBattery,
                       AirPodsRingMapper.resolve(snapshot: snapshot, behavior: behavior, now: now) != nil {
                        .available(true)
                    } else {
                        .unavailable(.temporarilyStale)
                    }
                case let .unavailable(reason): .unavailable(reason)
                case nil: .unavailable(.disconnected)
                }
            }
        }
        guard let source = selected.source else { return (nil, trace(selected, source: nil)) }
        if source == .airPodsBattery {
            let ring = inputs.sources.airPodsBattery.flatMap {
                AirPodsRingMapper.resolve(snapshot: $0, behavior: behavior, now: now)
            }
            return (ring, trace(selected, source: source))
        }
        guard source == .systemBattery || source == .automaticLegacy else {
            return (nil, trace(selected, source: source))
        }
        return (IconPresentationMapper.scene(inputs: inputs.system, configuration: legacy).outerRing,
                trace(selected, source: source))
    }

    private static func trace(_ result: SourceSelectionResult<RingSource>, source: RingSource?) -> SlotResolutionTrace {
        SlotResolutionTrace(selectedSourceID: source?.rawValue, role: result.role,
                            primaryFailure: result.primaryFailure, reason: result.reason)
    }
}
