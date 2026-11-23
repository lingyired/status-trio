import Foundation

/// Converts a resolver trace into privacy-safe localization keys. Source IDs are
/// deliberately never surfaced: they may contain Bluetooth addresses.
struct IconResolutionExplanationEntry: Equatable, Sendable {
    let slotName: LocalizationKey
    let reasonKeys: [LocalizationKey]
}

enum IconResolutionExplanation {
    static func entries(
        for resolutionTrace: IconResolutionTrace,
        permissionBlockedSlots: Set<IconSlot> = [],
        bluetoothAuthorization: BluetoothAuthorizationStatus = .denied
    ) -> [IconResolutionExplanationEntry] {
        let permissionReasonKey: LocalizationKey = bluetoothAuthorization == .notDetermined
            ? .settingsBluetoothPermissionRequired
            : .iconResolutionUnavailablePermissionDenied
        return IconSlot.allCases.map { slot in
            let slotTrace = trace(for: slot, in: resolutionTrace)
            let reasons = permissionBlockedSlots.contains(slot) && slotTrace.role == .fallback
                ? [.iconResolutionFallback, permissionReasonKey]
                : localizationKeys(for: slotTrace)
            return IconResolutionExplanationEntry(slotName: slot.localizationKey, reasonKeys: reasons)
        }
    }

    static func permissionBlockedBluetoothFallbackSlots(
        configuration: IconConfigurationV1,
        trace: IconResolutionTrace,
        authorization: BluetoothAuthorizationStatus,
        scenario: IconPreviewScenario
    ) -> Set<IconSlot> {
        guard scenario == .live, authorization != .allowed else { return [] }
        let composition = configuration.composition
        var slots: Set<IconSlot> = []
        if composition.outerRing.primary == .airPodsBattery, trace.outerRing.role == .fallback {
            slots.insert(.outerRing)
        }
        let bluetoothCenterSources: Set<CenterSource> = [.bluetoothAudioOutput, .pinnedBluetoothGlyph, .connectedBluetoothDevice]
        if bluetoothCenterSources.contains(composition.center.primary), trace.center.role == .fallback {
            slots.insert(.center)
        }
        return slots
    }

    private static func trace(for slot: IconSlot, in trace: IconResolutionTrace) -> SlotResolutionTrace {
        switch slot {
        case .outerRing: trace.outerRing
        case .center: trace.center
        case .footer: trace.footer
        }
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

private extension IconSlot {
    var localizationKey: LocalizationKey {
        switch self {
        case .outerRing: .iconDesignerSlotOuterRing
        case .center: .iconDesignerSlotCenter
        case .footer: .iconDesignerSlotFooter
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
