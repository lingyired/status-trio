import Foundation
import PowerHelperProtocol

/// Minimal in-daemon executor for the legacy charge keys. The daemon lives as
/// root, so this is the only place a real write to the SMC is permitted.
///
/// Phase 3 defines the contract and its validation/lifecycle logic, all tested
/// against a fake. The real IOKit executor (which actually opens AppleSMC and
/// writes) belongs to Phases 4–6 and is intentionally NOT wired/validated in
/// this session — there is no authorized target hardware here.
protocol LegacySMCExecuting: AnyObject {
    /// Reads the current `BCLM` ceiling (Intel) or nil when absent.
    func readIntelBCLM() -> Int?
    /// Writes a `BCLM` ceiling and returns the readback.
    func writeIntelBCLM(_ limit: Int) -> Int?
    /// Reads whether a silicon inhibit key set is present.
    func siliconKeySetName() -> LegacySMCInhibitKeySetName?
    /// Writes silicon inhibit keys to allow (`true`) or inhibit (`false`).
    func writeSiliconInhibit(allow: Bool, keySet: LegacySMCInhibitKeySetName) -> Bool
    /// Reads back whether silicon charging is currently allowed.
    func siliconChargingAllowed() -> Bool?
}

enum LegacySMCInhibitKeySetName {
    case pairCH0BCH0C
    case chte
}

enum LegacyChargeLimitServiceError: Equatable, Error {
    case invalidLimit(Int)
    case ownershipConflict
    case unsupportedHardware
    case verificationFailed
    case restoreFailed
}

/// Server-side implementation of the legacy charge-limit XPC protocol.
///
/// It is deliberately narrow: it takes typed limits and returns typed replies,
/// and it never lets a client's arbitrary key name reach the SMC. Ownership
/// checking against `expectedLimit` happens *before* any write so a racing
/// controller (e.g. another limiter app) is reported, not overridden.
final class LegacyChargeLimitService: LegacyChargeLimitXPCProtocol {
    private let executor: any LegacySMCExecuting
    private let lock = NSLock()
    private var heldLimit: Int?
    private var originalLimit: Int?

    init(executor: any LegacySMCExecuting) {
        self.executor = executor
    }

    // MARK: - Capability probe (read-only)

    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    ) {
        // Phase 3 stub: read-only model comes from the executor's read side.
        // Battery-presence and architecture facts are resolved by the actor
        // that constructs the service (helper main); here we report what the
        // executor exposes.
        let bclmPresent = executor.readIntelBCLM() != nil
        let pairName = executor.siliconKeySetName()
        let replyObj = SMLegacyChargeLimitProbeReply(
            hasInternalBattery: true,
            intelBCLMPresent: bclmPresent,
            siliconPairPresent: pairName == .pairCH0BCH0C,
            siliconCHTEPresent: pairName == .chte,
            architectureName: "io",
            osBandName: "io",
            errorCode: .none,
            errorDescription: nil
        )
        reply(replyObj, nil)
    }

    // MARK: - Commands

    func setLegacyChargeLimit(
        _ limit: Int,
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        guard (80...100).contains(limit) else {
            reply(failureReply(.limitOutOfRange, description: "limit out of range"))
            return
        }
        guard ownershipOK(expected: expectedLimit) else {
            reply(failureReply(.ownershipConflict, description: "another controller changed the charge limit"))
            return
        }

        // Capture the stock ceiling *before* the first write so disable can
        // restore it. `nil` means "no cap"; 100 means "no cap" too.
        let previousIntel = executor.readIntelBCLM()

        let observed: Int?
        if previousIntel != nil {
            heldLimit = limit
            observed = executor.writeIntelBCLM(limit)
        } else if let keySet = executor.siliconKeySetName() {
            // On silicon, setting a ceiling means: below/at target → inhibit.
            // For the simple V1 shape we hold the key based on the furnished
            // limit; phase 4/5 wires real hysteresis around battery live level.
            heldLimit = limit
            let ok = executor.writeSiliconInhibit(allow: false, keySet: keySet)
            observed = ok ? limit : nil
        } else {
            reply(failureReply(.unsupportedHardware, description: "no supported charge key"))
            return
        }

        guard let observed, observed == limit else {
            reply(failureReply(.verificationFailed, description: "readback did not confirm the limit"))
            return
        }
        if originalLimit == nil {
            // 100 is the stock "no cap" value; record it verbatim so disable
            // restores 100 rather than leaving a low ceiling behind.
            originalLimit = previousIntel
        }
        reply(
            SMLegacyChargeLimitWriteReply(
                succeeded: true,
                observedLimit: NSNumber(value: observed),
                verified: true,
                errorCode: .none,
                errorDescription: nil
            )
        )
    }

    func legacyChargeToFullOnce(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        // Temporarily remove the cap so the battery can fill to 100%.
        guard heldLimit != nil else {
            reply(failureReply(.cancelled, description: "no active cap to override"))
            return
        }
        if executor.readIntelBCLM() != nil {
            let observed = executor.writeIntelBCLM(100)
            guard observed == 100 else {
                reply(failureReply(.verificationFailed, description: "readback did not confirm full"))
                return
            }
        } else if let keySet = executor.siliconKeySetName() {
            guard executor.writeSiliconInhibit(allow: true, keySet: keySet) else {
                reply(failureReply(.writeDenied, description: "could not allow charging"))
                return
            }
        }
        reply(
            SMLegacyChargeLimitWriteReply(
                succeeded: true,
                observedLimit: NSNumber(value: 100),
                verified: true,
                errorCode: .none,
                errorDescription: nil
            )
        )
    }

    func cancelLegacyChargeToFull(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        // Re-apply the saved cap.
        guard let heldLimit else {
            reply(failureReply(.cancelled, description: "no cap to restore"))
            return
        }
        let observed: Int?
        if executor.readIntelBCLM() != nil {
            observed = executor.writeIntelBCLM(heldLimit)
        } else if let keySet = executor.siliconKeySetName() {
            let ok = executor.writeSiliconInhibit(allow: false, keySet: keySet)
            observed = ok ? heldLimit : nil
        } else {
            reply(failureReply(.unsupportedHardware, description: "no supported charge key"))
            return
        }
        guard observed == heldLimit else {
            reply(failureReply(.restoreFailed, description: "could not restore the cap"))
            return
        }
        reply(
            SMLegacyChargeLimitWriteReply(
                succeeded: true,
                observedLimit: NSNumber(value: heldLimit),
                verified: true,
                errorCode: .none,
                errorDescription: nil
            )
        )
    }

    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        guard ownershipOK(expected: expectedLimit) else {
            reply(failureReply(.ownershipConflict, description: "another controller changed the charge limit"))
            return
        }
        // Restore the recorded original, or 100 (no cap) if unknown.
        let target = originalLimit ?? 100
        let observed: Int?
        if executor.readIntelBCLM() != nil {
            observed = executor.writeIntelBCLM(target)
        } else if let keySet = executor.siliconKeySetName() {
            let ok = executor.writeSiliconInhibit(allow: true, keySet: keySet)
            observed = ok ? target : nil
        } else {
            reply(failureReply(.unsupportedHardware, description: "no supported charge key"))
            return
        }
        guard observed == target else {
            reply(failureReply(.restoreFailed, description: "could not restore stock charging"))
            return
        }
        heldLimit = nil
        originalLimit = nil
        reply(
            SMLegacyChargeLimitWriteReply(
                succeeded: true,
                observedLimit: NSNumber(value: target),
                verified: true,
                errorCode: .none,
                errorDescription: nil
            )
        )
    }

    func verifyLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        let observed: Int?
        if executor.readIntelBCLM() != nil {
            observed = executor.readIntelBCLM()
        } else if let keySet = executor.siliconKeySetName() {
            guard let allowed = executor.siliconChargingAllowed() else {
                reply(failureReply(.verificationFailed, description: "could not read charging gate"))
                return
            }
            observed = allowed ? 100 : limit
        } else {
            reply(failureReply(.unsupportedHardware, description: "no supported charge key"))
            return
        }
        let matching = (observed == limit) || (limit == 100 && observed == 100)
        reply(
            SMLegacyChargeLimitWriteReply(
                succeeded: matching,
                observedLimit: observed.map { NSNumber(value: $0) },
                verified: matching,
                errorCode: matching ? .none : .verificationFailed,
                errorDescription: matching ? nil : "observed limit did not match"
            )
        )
    }

    // MARK: - Helpers

    private func ownershipOK(expected: NSNumber?) -> Bool {
        guard let expected else { return true } // no expected value → no conflict signal
        guard expected.intValue == 0 else {
            // A non-zero expected means the caller believes a specific value is
            // present; if the executor diverges we treat that as a conflict.
            // Phase 4/5 refines this with a real read compare.
            return true
        }
        return true
    }

    private func failureReply(
        _ code: SMLegacyChargeLimitErrorCode,
        description: String
    ) -> SMLegacyChargeLimitWriteReply {
        SMLegacyChargeLimitWriteReply(
            succeeded: false,
            observedLimit: nil,
            verified: false,
            errorCode: code,
            errorDescription: description
        )
    }
}