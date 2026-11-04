import Foundation

/// Typed facts returned by the helper's read-only probe.
struct LegacyChargeLimitProbeFacts: Equatable, Sendable {
    var hasInternalBattery: Bool
    var intelBCLMPresent: Bool
    var siliconPairPresent: Bool
    var siliconCHTEPresent: Bool

    var hasAnySupportedKey: Bool {
        intelBCLMPresent || siliconPairPresent || siliconCHTEPresent
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
        let backend = architecture == .intel ? LegacyChargeBackend.intelBCLM
                                             : LegacyChargeBackend.siliconLegacyInhibit
        switch backend {
        case .intelBCLM where probe.intelBCLMPresent:
            return .available(.intelBCLM)
        case .siliconLegacyInhibit where probe.siliconPairPresent || probe.siliconCHTEPresent:
            return .available(.siliconLegacyInhibit)
        default:
            return .unavailable(.noSupportedKeys)
        }
    }
}