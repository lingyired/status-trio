import Foundation

/// Converts a resolver trace into privacy-safe localization keys. Source IDs are
/// deliberately never surfaced: they may contain Bluetooth addresses.
struct IconResolutionExplanationEntry: Equatable, Sendable {
    let slotName: LocalizationKey
    let reasonKeys: [LocalizationKey]
}

enum IconResolutionExplanation {
    static func entries(for trace: IconResolutionTrace) -> [IconResolutionExplanationEntry] {
        [
            IconResolutionExplanationEntry(slotName: .iconDesignerSlotOuterRing,
                                           reasonKeys: localizationKeys(for: trace.outerRing)),
            IconResolutionExplanationEntry(slotName: .iconDesignerSlotCenter,
                                           reasonKeys: localizationKeys(for: trace.center)),
            IconResolutionExplanationEntry(slotName: .iconDesignerSlotFooter,
                                           reasonKeys: localizationKeys(for: trace.footer))
        ]
    }

    static func localizationKeys(for trace: SlotResolutionTrace) -> [LocalizationKey] {
        switch trace.reason {
        case .overridden(.networkProblem):
            return [.iconResolutionOverriddenNetworkProblem]
        case .fallback(let reason):
            return [.iconResolutionFallback, unavailableKey(reason)]
        case .primary:
            return [.iconResolutionPrimary]
        case .none:
            if let failure = trace.primaryFailure {
                return [.iconResolutionNone, unavailableKey(failure)]
            }
            return [.iconResolutionNone]
        }
    }

    private static func unavailableKey(_ reason: IconSourceUnavailableReason) -> LocalizationKey {
        switch reason {
        case .disconnected: .iconResolutionUnavailableDisconnected
        case .permissionDenied: .iconResolutionUnavailablePermissionDenied
        case .unavailable: .iconResolutionUnavailableUnavailable
        case .unknown: .iconResolutionUnavailableUnknown
        case .temporarilyStale: .iconResolutionUnavailableTemporarilyStale
        }
    }
}

struct IconDesignerSlotAccessibilityValue: Equatable, Sendable {
    let slotName: LocalizationKey
    let sourceName: String
    let isSelected: Bool
}

enum IconDesignerAccessibility {
    static func slotValue(slot: IconSlot, currentSource: String, isSelected: Bool) -> IconDesignerSlotAccessibilityValue {
        let key: LocalizationKey
        switch slot {
        case .outerRing: key = .iconDesignerSlotOuterRing
        case .center: key = .iconDesignerSlotCenter
        case .footer: key = .iconDesignerSlotFooter
        }
        return IconDesignerSlotAccessibilityValue(slotName: key, sourceName: currentSource, isSelected: isSelected)
    }
}
