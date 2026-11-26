import Foundation

// MARK: - Typed reply capsules for the legacy charge-limit XPC surface
//
// These capsule types are the *only* thing that crosses the XPC boundary for
// the legacy limiter. They carry typed facts and a coarse error taxonomy, not
// raw SMC keys or byte values, so a bug in the client cannot reach the SMC as
// an arbitrary key write. They live in this dependency-free target so both the
// app and the root daemon can name them without loading AppKit/SwiftUI.

/// A typed error code that survives NSXPC marshalling without exposing SMC
/// internals. Mirrors the app-side `LegacyChargeLimitError` taxonomy.
@objc public enum SMLegacyChargeLimitErrorCode: Int, Equatable {
    case none = 0
    case unsupportedHardware = 1
    case helperUnavailable = 2
    case rejected = 3
    case validationNotRun = 4
    case limitOutOfRange = 5
    case ownershipConflict = 6
    case verificationFailed = 7
    case restoreFailed = 8
    case cancelled = 9
    case writeDenied = 10
    case readbackMismatch = 11
    case unknown = 12
}

/// Capsule describing the result of a legacy write/probe. `observedLimit` is
/// the value the daemon read back after the operation, when meaningful.
@objc(SMLegacyChargeLimitProbeReply)
public final class SMLegacyChargeLimitProbeReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let hasInternalBattery: Bool
    public let intelBCLMPresent: Bool
    public let siliconPairPresent: Bool
    public let siliconCHTEPresent: Bool
    public let architectureName: String
    public let osBandName: String
    public let errorCode: SMLegacyChargeLimitErrorCode
    public let errorDescription: String?

    public init(
        hasInternalBattery: Bool,
        intelBCLMPresent: Bool,
        siliconPairPresent: Bool,
        siliconCHTEPresent: Bool,
        architectureName: String,
        osBandName: String,
        errorCode: SMLegacyChargeLimitErrorCode,
        errorDescription: String?
    ) {
        self.hasInternalBattery = hasInternalBattery
        self.intelBCLMPresent = intelBCLMPresent
        self.siliconPairPresent = siliconPairPresent
        self.siliconCHTEPresent = siliconCHTEPresent
        self.architectureName = architectureName
        self.osBandName = osBandName
        self.errorCode = errorCode
        self.errorDescription = errorDescription
    }

    public required init?(coder: NSCoder) {
        hasInternalBattery = coder.decodeBool(forKey: "hasInternalBattery")
        intelBCLMPresent = coder.decodeBool(forKey: "intelBCLMPresent")
        siliconPairPresent = coder.decodeBool(forKey: "siliconPairPresent")
        siliconCHTEPresent = coder.decodeBool(forKey: "siliconCHTEPresent")
        // Use the typed secure-decoding API for the nested objects. NSXPC's
        // secure decoder only allows `SMLegacyChargeLimitProbeReply` itself for
        // the reply argument; the insecure `decodeObject(forKey:)` then fails
        // class validation for the nested `NSString` and the whole reply is
        // dropped ("Exception caught during decoding of reply … allowed classes
        // are 'SMLegacyChargeLimitProbeReply'"), which the app then surfaces as
        // "helper required". `decodeObject(of:forKey:)` supplies the class
        // explicitly and decodes correctly.
        architectureName =
            (coder.decodeObject(of: NSString.self, forKey: "architectureName") as String?) ?? ""
        osBandName = (coder.decodeObject(of: NSString.self, forKey: "osBandName") as String?) ?? ""
        let raw = coder.decodeInteger(forKey: "errorCode")
        errorCode = SMLegacyChargeLimitErrorCode(rawValue: raw) ?? .unknown
        errorDescription =
            coder.decodeObject(of: NSString.self, forKey: "errorDescription") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(hasInternalBattery, forKey: "hasInternalBattery")
        coder.encode(intelBCLMPresent, forKey: "intelBCLMPresent")
        coder.encode(siliconPairPresent, forKey: "siliconPairPresent")
        coder.encode(siliconCHTEPresent, forKey: "siliconCHTEPresent")
        coder.encode(architectureName, forKey: "architectureName")
        coder.encode(osBandName, forKey: "osBandName")
        coder.encode(errorCode.rawValue, forKey: "errorCode")
        coder.encode(errorDescription, forKey: "errorDescription")
    }
}

/// Capsule for a legacy write/restore result.
@objc(SMLegacyChargeLimitWriteReply)
public final class SMLegacyChargeLimitWriteReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let succeeded: Bool
    public let observedLimit: NSNumber?
    public let verified: Bool
    public let errorCode: SMLegacyChargeLimitErrorCode
    public let errorDescription: String?

    public init(
        succeeded: Bool,
        observedLimit: NSNumber?,
        verified: Bool,
        errorCode: SMLegacyChargeLimitErrorCode,
        errorDescription: String?
    ) {
        self.succeeded = succeeded
        self.observedLimit = observedLimit
        self.verified = verified
        self.errorCode = errorCode
        self.errorDescription = errorDescription
    }

    public required init?(coder: NSCoder) {
        succeeded = coder.decodeBool(forKey: "succeeded")
        observedLimit = coder.decodeObject(of: NSNumber.self, forKey: "observedLimit")
        verified = coder.decodeBool(forKey: "verified")
        let raw = coder.decodeInteger(forKey: "errorCode")
        errorCode = SMLegacyChargeLimitErrorCode(rawValue: raw) ?? .unknown
        // Typed secure decoding for the nested string, for the same NSXPC
        // reply-decoding reason as `SMLegacyChargeLimitProbeReply`.
        errorDescription =
            coder.decodeObject(of: NSString.self, forKey: "errorDescription") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(succeeded, forKey: "succeeded")
        coder.encode(observedLimit, forKey: "observedLimit")
        coder.encode(verified, forKey: "verified")
        coder.encode(errorCode.rawValue, forKey: "errorCode")
        coder.encode(errorDescription, forKey: "errorDescription")
    }
}

/// The legacy charge-limit command surface the daemon exposes. Narrow and
/// typed: it never takes a raw SMC key name or byte payload from the client.
///
@objc public protocol LegacyChargeLimitXPCProtocol {
    /// Read-only capability probe (no write). Returns a typed capability.
    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    )

    /// Sets a ceiling (80–100). `expectedLimit` is the value the caller believes
    /// is currently present, so the daemon can detect a racing writer before it
    /// writes (ownership conflict).
    func setLegacyChargeLimit(
        _ limit: Int,
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Reads the current ceiling, classifies it against the daemon's own record,
    /// and re-applies the requested limit when the value drifted (system reset).
    /// Returns an ownership conflict when a foreign writer changed it.
    func reconcileLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Temporarily lets the battery charge to 100% (one-time override).
    func legacyChargeToFullOnce(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Cancels a one-time override and restores the saved cap.
    func cancelLegacyChargeToFull(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Restores the original hardware ceiling and reports the observed result.
    /// `expectedLimit` lets the daemon detect changes it did not make.
    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Inhibits charging immediately before system sleep, without using the
    /// battery-level heuristic. A software-driven Silicon gate would otherwise
    /// keep charging towards the ceiling while the machine is asleep.
    func prepareLegacyChargeLimitForSleep(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )

    /// Reads back and reports whether the hardware is at the given ceiling.
    func verifyLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    )
}
/// One exported object that carries both the existing Low Power Mode surface
/// and the legacy charge-limit surface. NSXPC allows a single exported
/// interface per connection, so the combined protocol is what the daemon
/// exports; clients that only need Low Power Mode may keep using
/// `PowerHelperXPCProtocol`.
@objc public protocol PowerHelperCombinedXPCProtocol:
    PowerHelperXPCProtocol,
    LegacyChargeLimitXPCProtocol {}
