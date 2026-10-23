struct IconPluginSlotOutput: Equatable, Sendable {
    let payload: IconContentPayload?
    let binding: IconContentBinding?
    let trace: SlotResolutionTrace
}

enum IconPluginSlotResolver {
    static func resolve(primary: IconContentBinding?, fallback: IconContentBinding?, slot: IconSlot,
                        context: IconContentContext, registry: IconContentPluginRegistry) -> IconPluginSlotOutput {
        guard let primary else { return .init(payload: nil, binding: nil, trace: .empty) }
        switch registry.resolve(primary, for: slot, context: context) {
        case let .available(payload):
            return output(payload, binding: primary, role: .primary, failure: nil, reason: .primary)
        case let .unavailable(reason):
            if let fallback, fallback != primary,
               case let .available(payload) = registry.resolve(fallback, for: slot, context: context) {
                return output(payload, binding: fallback, role: .fallback, failure: reason, reason: .fallback(reason))
            }
            return .init(payload: nil, binding: nil, trace: .init(selectedSourceID: nil, role: .none, primaryFailure: reason, reason: .none))
        }
    }

    private static func output(_ payload: IconContentPayload, binding: IconContentBinding,
                               role: SlotResolutionRole, failure: IconSourceUnavailableReason?, reason: SlotResolutionReason) -> IconPluginSlotOutput {
        .init(payload: payload, binding: binding, trace: .init(
            selectedSourceID: IconContentLegacyAdapter.sourceID(for: binding), role: role, primaryFailure: failure, reason: reason))
    }
}
