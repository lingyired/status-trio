import Foundation

/// Typed facts returned by the helper's read-only probe.
struct LegacyChargeLimitProbeFacts: Equatable, Sendable {
    var hasInternalBattery: Bool
    var intelBCLMPresent: Bool
    var siliconPairPresent: Bool
    var siliconCHTEPresent: Bool
    /// macOS 15.7+/26 firmware charge limit (bfD0/bfE0/bfF0) is present.
    var firmwareLimitPresent: Bool = false

    var hasAnySupportedKey: Bool {
        intelBCLMPresent || siliconPairPresent || siliconCHTEPresent || firmwareLimitPresent
    }
}

enum LegacyChargeLimitUnavailability: Equatable, Sendable {
    case unsupportedOS
    case rosetta
    case noInternalBattery
    case noSupportedKeys
    case helperUnavailable
}

enum LegacyChargeLimitAvailability: Equatable, Sendable {
    case available(LegacyChargeBackend)
    case unavailable(LegacyChargeLimitUnavailability)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Decides whether the Settings/panel control may appear at all.
    ///
    /// Order matters: an unsupported OS or a Rosetta process is reported even
    /// when the helper is missing, so the UI can explain the real reason.
    static func resolve(
        probe: LegacyChargeLimitProbeFacts,
        architecture: LegacyRuntimeArchitecture,
        osBand: LegacyOSBand,
        helperAvailable: Bool
    ) -> LegacyChargeLimitAvailability {
        guard osBand.allowsLegacyLimiter else {
            return .unavailable(.unsupportedOS)
        }
        if architecture == .rosetta {
            return .unavailable(.rosetta)
        }
        guard probe.hasInternalBattery else {
            return .unavailable(.noInternalBattery)
        }
        guard probe.hasAnySupportedKey else {
            return .unavailable(.noSupportedKeys)
        }
        guard helperAvailable else {
            return .unavailable(.helperUnavailable)
        }
        if architecture == .intel {
            return probe.intelBCLMPresent ? .available(.intelBCLM) : .unavailable(.noSupportedKeys)
        }
        if probe.firmwareLimitPresent { return .available(.firmwareLimit) }
        if probe.siliconPairPresent || probe.siliconCHTEPresent {
            return .available(.siliconLegacyInhibit)
        }
        return .unavailable(.noSupportedKeys)
    }
}
/// Whether the Settings group may appear at all.
///
/// The plan says the opt-in group is shown only on eligible macOS 13–15 with an
/// internal battery and a helper-capable distribution. Helper approval is a
/// *status inside* the group, not a reason to hide it, so the user has a place
/// to start the approval flow.
enum LegacyChargeLimitPlatformEligibility {
    static func isEligible(
        architecture: LegacyRuntimeArchitecture,
        osBand: LegacyOSBand,
        hasInternalBattery: Bool
    ) -> Bool {
        osBand.allowsLegacyLimiter
            && architecture != .rosetta
            && hasInternalBattery
    }

    static func isEligibleCurrent(hasInternalBattery: Bool) -> Bool {
        if LegacyChargeLimitController.isDemoPreviewForced { return true }
        return isEligible(
            architecture: LegacyRuntimeArchitecture.current,
            osBand: LegacyOSBand.current,
            hasInternalBattery: hasInternalBattery
        )
    }
}
