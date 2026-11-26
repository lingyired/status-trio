import Foundation

/// Pure domain model for the *legacy* charge limiter (macOS 13–15, Intel and
/// Apple Silicon) that coexists with the native PowerUI path on macOS 26.4+.
///
/// This file intentionally contains no IOKit, no UI and no writes. Every
/// decision is a pure function over facts that the privileged helper discovers
/// and returns over the typed XPC probe; the read-only SMC implementation lives
/// in the helper, not here.

// MARK: - Runtime & OS classification

/// How the legacy limiter behaves around system sleep on Apple Silicon, where
/// the software gate only holds while something can act on it.
enum LegacySleepPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Stop charging before sleep; resume toward the ceiling on wake. (Default)
    case pauseCharging
    /// Keep the Mac awake (the display may still turn off) until the ceiling is
    /// reached, then allow normal sleep. Mirrors AlDente's "disable sleep until
    /// limit" option.
    case keepAwakeUntilLimit

    var id: String { rawValue }

    /// Pure decision: hold a sleep-prevention assertion right now?
    static func shouldStayAwake(
        level: Int, target: Int, isOnAC: Bool, hasSession: Bool, policy: LegacySleepPolicy
    ) -> Bool {
        guard policy == .keepAwakeUntilLimit, hasSession, isOnAC else { return false }
        return level < target
    }
}

enum LegacyRuntimeArchitecture: Equatable, Sendable {
    /// Native Intel (`x86_64` on non-Rosetta).
    case intel
    /// Native Apple Silicon (`arm64`).
    case appleSilicon
    /// Process running under Rosetta on Apple Silicon.
    case rosetta
    /// Anything else we do not support for legacy limiting.
    case unsupported

    var isPotentiallySupported: Bool {
        self == .intel || self == .appleSilicon
    }

    /// Runtime classification. Rosetta on Apple Silicon reports `x86_64`, so
    /// the translation flag has to win over the compile-time architecture.
    static var current: LegacyRuntimeArchitecture {
        #if arch(x86_64)
        return isRosettaProcess() ? .rosetta : .intel
        #elseif arch(arm64)
        return .appleSilicon
        #else
        return .unsupported
        #endif
    }

    private static func isRosettaProcess() -> Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return result == 0 && translated == 1
    }
}

enum LegacyOSBand: Equatable, Sendable {
    /// macOS 13–14 (first-generation legacy support band).
    case thirteenToFourteen
    /// macOS 15 (distinct SMC-capability band, possibly entitlement-gated).
    case fifteen
    /// macOS 16–26.3 (not released in this milestone).
    case sixteenToTahoeLegacy
    /// macOS 26.4+ (native PowerUI path owns the feature).
    case tahoe
    /// Unknown / too new or too old.
    case unknown

    /// Product scope (user, 2026-11-05): "legacy" means macOS 13–15. macOS 16
    /// through 26.3 is out of this milestone; 26.4+ uses the native limit.
    var allowsLegacyLimiter: Bool {
        self == .thirteenToFourteen || self == .fifteen
    }

    static var current: LegacyOSBand {
        LegacyOSBandFactor.band(ProcessInfo.processInfo.operatingSystemVersion)
    }
}

enum LegacyOSBandError: Equatable, Error, Sendable {
    case malformedVersion
}

enum LegacyOSBandFactor {
    /// Classifies a major/minor version string.
    ///
    /// Version bands are interpreted in the same zone as the plan's matrix
    /// (§1): 13–14 legacy band, 15 a distinct band, 16–26.3 not released,
    /// 26.4+ native. Anything else is `.unknown`.
    static func band(_ version: OperatingSystemVersion) -> LegacyOSBand {
        switch version.majorVersion {
        case 13, 14: return .thirteenToFourteen
        case 15: return .fifteen
        case 16...26:
            return version.majorVersion == 26 && version.minorVersion >= 4
                ? .tahoe
                : .sixteenToTahoeLegacy
        case 27: return .tahoe
        default: return .unknown
        }
    }
}

// MARK: - Hardware capability (injected; filled by the read-only probe later)

/// What the read-only SMC probe exposes about the hardware. Kept as a value so
/// the probe result can be passed in and re-read without hitting IOKit during
/// pure tests. Presence vs writability are kept distinct: a key can exist but
/// be entitlement-gated (macOS 15+ / macOS 27 firmware), which must be
/// discovered by validated behaviour, i.e. only on authorized hardware.
struct LegacyHardwareCapabilities: Equatable, Sendable {
    var architecture: LegacyRuntimeArchitecture
    var osBand: LegacyOSBand
    var hasInternalBattery: Bool

    /// Keys that exist and have the expected type/width.
    var presentKeys: Set<String> = []
    /// Keys whose write produced a verified readback during an authorized
    /// behavioural probe. Empty until that validation has happened.
    var verifiedWritableKeys: Set<String> = []

    /// Type/size facts for the keys we understand (ui8 vs ui32 etc.).
    var keyInfo: [String: LegacySMCKeyInfo] = [:]

    /// Confirms there is a real, internal, non-tribble battery.
    var hasUsableBattery: Bool { hasInternalBattery }
}

struct LegacySMCKeyInfo: Equatable, Sendable {
    var dataType: String
    var dataSize: Int
}

// MARK: - Backend selection

enum LegacyChargeBackend: Equatable, Sendable {
    case intelBCLM
    case siliconLegacyInhibit
    /// macOS 15.7+/26 firmware charge limit (bfD0/bfE0/bfF0). Firmware enforces
    /// the band; the app only sets/clears it.
    case firmwareLimit
    case unsupported

    /// Chooses the backend strictly from injected capability facts. Does not
    /// depend on the costs of actually reaching the hardware.
    static func select(using caps: LegacyHardwareCapabilities) -> LegacyChargeBackend {
        guard caps.hasUsableBattery,
              caps.osBand.allowsLegacyLimiter else {
            return .unsupported
        }
        switch caps.architecture {
        case .intel:
            return caps.presentKeys.contains(LegacySMCKeys.intelBCLM)
                ? .intelBCLM
                : .unsupported
        case .appleSilicon:
            if caps.presentKeys.contains(LegacySMCKeys.firmwareUpper),
               caps.presentKeys.contains(LegacySMCKeys.firmwareLower),
               caps.presentKeys.contains(LegacySMCKeys.firmwareEnable) {
                return .firmwareLimit
            }
            return LegacySMCBytePolicy.siliconKeySet(presentKeys: caps.presentKeys) != nil
                ? .siliconLegacyInhibit
                : .unsupported
        case .rosetta, .unsupported:
            return .unsupported
        }
    }
}

/// Namespace for the SMC keys used by the legacy limiter.
enum LegacySMCKeys {
    static let intelBCLM = "BCLM"
    static let intelBFCL = "BFCL"
    static let siliconCH0B = "CH0B"
    static let siliconCH0C = "CH0C"
    static let siliconCHTE = "CHTE"
    static let siliconCHWA = "CHWA"
    static let firmwareUpper = "bfD0"
    static let firmwareLower = "bfE0"
    static let firmwareEnable = "bfF0"
}

// MARK: - Status

enum LegacyChargeLimitStatus: Equatable, Sendable {
    case notEnabled
    case helperApprovalRequired
    case checkingHardware
    case holding(at: Int)
    case temporarilyChargingToFull
    case unsupported
    case restoreFailed
    /// A write or verification did not take; the user may retry explicitly.
    case failed
    /// Another controller changed the hardware value; automatic management is
    /// paused until the user re-applies or chooses a limit.
    case externalChange
    /// Hardware control is not verified on this host (missing/writable-key
    /// validation did not pass). Distinct from "unsupported" because the host
    /// may eventually support it after a validated probe.
    case unverified

    var isActive: Bool {
        switch self {
        case .holding, .temporarilyChargingToFull: return true
        default: return false
        }
    }
}

// MARK: - Errors, commands and results

enum LegacyChargeLimitError: Equatable, Sendable, Error {
    case unsupportedHardware
    case helperUnavailable
    case rejected(String)
    case validationNotRun
    case limitOutOfRange(Int)
    case ownershipConflict
    case verificationFailed
    case restoreFailed
    case cancelled
    case writeDenied
    case readbackMismatch
    case unknown

    var isTerminal: Bool {
        switch self {
        case .restoreFailed, .verificationFailed, .ownershipConflict,
             .writeDenied, .unsupportedHardware, .readbackMismatch:
            return true
        default: return false
        }
    }
}

struct LegacyChargeLimitCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case setLimit(Int)
        case chargeToFullOnce
        case cancelChargeToFull
        case disable
        case reapply
    }

    var kind: Kind
    /// Expected current hardware value, if known, so a racing writer can be
    /// detected before we write.
    var expectedLimit: Int?
    var requiresVerification: Bool
}

struct LegacyChargeLimitResult: Equatable, Sendable {
    var succeeded: Bool
    var error: LegacyChargeLimitError?
    var observedLimit: Int?
    var verified: Bool

    static func success(observedLimit: Int?, verified: Bool) -> LegacyChargeLimitResult {
        LegacyChargeLimitResult(
            succeeded: true,
            error: nil,
            observedLimit: observedLimit,
            verified: verified
        )
    }

    static func failure(_ error: LegacyChargeLimitError) -> LegacyChargeLimitResult {
        LegacyChargeLimitResult(succeeded: false, error: error, observedLimit: nil, verified: false)
    }
}

// MARK: - Session (separate from the native ManagedChargeLimitSession)

struct LegacyChargeLimitSession: Codable, Equatable, Sendable {
    /// The user's intended ceiling.
    var requestedLimit: Int
    /// The original hardware value captured before we took over, if any.
    var originalLimit: Int?
    /// True while a temporary "charge to full" override is in progress.
    var isTemporarilyOverridden = false
    /// When the temporary override ends (24h after it started). `nil` means the
    /// older "until the battery is full" behaviour.
    var temporaryFullUntil: Date?
    /// True when a newer command superseded us (last-writer-wins).
    var isPaused = false
    /// Persisted before issuing a write; restart requires revalidation.
    var isPending = false

    var isValid: Bool {
        (80...100).contains(requestedLimit)
    }
}

@MainActor
protocol LegacyChargeLimitSessionStoring: AnyObject {
    func load() -> LegacyChargeLimitSession?
    func save(_ session: LegacyChargeLimitSession)
    func clear()
}

@MainActor
final class UserDefaultsLegacyChargeLimitSessionStore: LegacyChargeLimitSessionStoring {
    static let defaultsKey = "legacyChargeLimit.session.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load() -> LegacyChargeLimitSession? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let session = try? JSONDecoder().decode(LegacyChargeLimitSession.self, from: data),
              session.isValid else { return nil }
        return session
    }

    func save(_ session: LegacyChargeLimitSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() { defaults.removeObject(forKey: Self.defaultsKey) }
}

@MainActor
final class VolatileLegacyChargeLimitSessionStore: LegacyChargeLimitSessionStoring {
    private var session: LegacyChargeLimitSession?
    func load() -> LegacyChargeLimitSession? { session }
    func save(_ session: LegacyChargeLimitSession) { self.session = session }
    func clear() { session = nil }
}