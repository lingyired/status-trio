import Foundation
import PowerHelperProtocol

/// Facts are resolved inside the helper, never supplied by the XPC caller.
struct LegacyHardwareFacts: Equatable, Sendable {
    var isIntel: Bool
    var allowsLegacyLimiter: Bool
    var hasInternalBattery: Bool
}

protocol LegacyBatteryProviding: AnyObject {
    func currentPercent() -> Int?
    func isOnACPower() -> Bool
}

protocol LegacySMCExecuting: AnyObject {
    func readKey(_ key: String) -> Data?
    func writeKey(_ key: String, data: Data) -> Bool
}

enum LegacyChargeSMCKeys {
    static let bclm = "BCLM"
    static let ch0b = "CH0B"
    static let ch0c = "CH0C"
    static let chte = "CHTE"
    static let widths = [bclm: 1, ch0b: 1, ch0c: 1, chte: 4]
    static let writeAllowlist: Set<String> = [bclm, ch0b, ch0c, chte]

    static func isValidValue(_ data: Data, for key: String) -> Bool {
        guard widths[key] == data.count else { return false }
        switch key {
        case bclm: return (50...100).contains(Int(data[0]))
        case ch0b, ch0c: return data[0] == 0 || data[0] == 2
        case chte: return data == Data([0, 0, 0, 0]) || data == Data([1, 0, 0, 0])
        default: return false
        }
    }
}

enum LegacyGatePolicy {
    static let hysteresis = 2
    static func shouldAllowCharging(level: Int, limit: Int, currentlyAllowed: Bool?) -> Bool {
        if limit == 100 { return true }
        if level >= limit { return false }
        if level <= limit - hysteresis { return true }
        return currentlyAllowed ?? true
    }
}

/// Serialized coordinator. A record of the original and the intended write is
/// durable before I/O. A successful readback confirms bytes only, not that the
/// battery actually stopped charging (physical validation remains NOT RUN).
/// The coordinator itself is not the XPC-exported object: each connection gets
/// its own `LegacyChargeConnection` proxy that supplies that connection's owner
/// id. Keeping the exported surface off this type makes the ownership rule
/// structural rather than a convention.
final class LegacyChargeLimitService: NSObject, @unchecked Sendable {
    private let executor: any LegacySMCExecuting
    private let journalStore: any LegacyChargeLimitJournaling
    private let battery: any LegacyBatteryProviding
    private let hardware: LegacyHardwareFacts
    private let hardwareModel: String
    private let osBuild: String
    private let lock = NSLock()
    /// Connection currently owning the hardware. Any other live connection is
    /// refused a mutating command, so an unrelated XPC session (Low Power Mode)
    /// cannot disable or overwrite the cap.
    private var ownerID: UUID?
    /// Called with `true`/`false` when client-loss recovery becomes pending or
    /// is resolved, so the daemon can hold itself alive while a cap is stranded.
    private let recoveryDemandChanged: (Bool) -> Void
    private typealias Session = LegacyChargeLimitJournal
    // Protocol requirements spell this type in their signatures, so the
    // alias must be at least internal.
    typealias Reply = SMLegacyChargeLimitWriteReply

    private struct Failure: Error {
        let code: SMLegacyChargeLimitErrorCode
        let message: String
        init(_ code: SMLegacyChargeLimitErrorCode, _ message: String) {
            self.code = code
            self.message = message
        }
    }

    init(
        executor: any LegacySMCExecuting,
        journal: any LegacyChargeLimitJournaling,
        battery: any LegacyBatteryProviding,
        hardware: LegacyHardwareFacts,
        hardwareModel: String = LegacyHelperEnvironment.modelIdentifier(),
        osBuild: String = LegacyHelperEnvironment.osBuild(),
        recoveryDemandChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.executor = executor
        self.journalStore = journal
        self.battery = battery
        self.hardware = hardware
        self.hardwareModel = hardwareModel
        self.osBuild = osBuild
        self.recoveryDemandChanged = recoveryDemandChanged
    }

    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    ) {
        // Probe and writes share the same lock; the underlying user client is
        // never touched concurrently by this coordinator.
        let result = lock.withLock {
            let eligible = hardware.hasInternalBattery && hardware.allowsLegacyLimiter
            return SMLegacyChargeLimitProbeReply(
                hasInternalBattery: hardware.hasInternalBattery,
                intelBCLMPresent: eligible && hardware.isIntel && validRead("BCLM") != nil,
                siliconPairPresent: eligible && !hardware.isIntel
                    && validRead("CH0B") != nil && validRead("CH0C") != nil,
                siliconCHTEPresent: eligible && !hardware.isIntel && validRead("CHTE") != nil,
                architectureName: hardware.isIntel ? "intel" : "appleSilicon",
                osBandName: hardware.allowsLegacyLimiter ? "legacy" : "unsupported",
                errorCode: eligible ? .none : .unsupportedHardware,
                errorDescription: nil
            )
        }
        reply(result, nil)
    }

    func setLegacyChargeLimit(
        _ limit: Int, expectedLimit: NSNumber?, ownerID: UUID,
        withReply reply: @escaping (Reply?) -> Void
    ) {
        perform(reply) {
            try requireEligible()
            try claimHardware(ownerID)
            guard (80...100).contains(limit) else {
                throw Failure(.limitOutOfRange, "The charge limit is outside 80–100%.")
            }
            let previous = try loadOwnedJournal()
            let raw: [String: Data]
            if let previous {
                raw = try readOwned(previous)
            } else {
                raw = try discoverOriginal()
            }
            if let expectedLimit {
                let expected = try validatedPercent(expectedLimit)
                let actual = hardware.isIntel ? raw["BCLM"].map { Int($0[0]) } : previous?.requestedLimit
                // Silicon has no firmware percentage. Its raw gate ownership
                // is checked by readOwned, and expectedLimit names the held intent.
                guard actual == expected else {
                    throw Failure(.ownershipConflict, "The expected current limit changed.")
                }
            }
            var session = previous ?? Session(
                backend: hardware.isIntel ? .intelBCLM : .silicon,
                hardwareModel: hardwareModel,
                osBuild: osBuild,
                requestedLimit: limit,
                originalRaw: raw,
                lastWrittenRaw: raw
            )
            let desired = try desiredRaw(session: session, limit: limit, full: false, current: raw)
            try apply(&session, desired: desired, current: raw)
            session.requestedLimit = limit
            session.isTemporarilyOverridden = false
            try persist(session)
            return success(observedLimit: hardware.isIntel ? limit : nil)
        }
    }

    func legacyChargeToFullOnce(ownerID: UUID, withReply reply: @escaping (Reply?) -> Void) {
        perform(reply) {
            try requireEligible()
            try adoptOrRequire(ownerID)
            var session = try requireSession()
            let current = try readOwned(session)
            let desired = try desiredRaw(session: session, limit: 100, full: true, current: current)
            try apply(&session, desired: desired, current: current)
            // Accepted override is recorded only after successful readback.
            session.isTemporarilyOverridden = true
            try persist(session)
            return success(observedLimit: session.backend == .intelBCLM ? 100 : nil)
        }
    }

    func cancelLegacyChargeToFull(ownerID: UUID, withReply reply: @escaping (Reply?) -> Void) {
        perform(reply) {
            try requireEligible()
            try adoptOrRequire(ownerID)
            var session = try requireSession()
            guard session.isTemporarilyOverridden else {
                throw Failure(.cancelled, "There is no temporary override to cancel.")
            }
            let current = try readOwned(session)
            let desired = try desiredRaw(
                session: session, limit: session.requestedLimit, full: false, current: current
            )
            try apply(&session, desired: desired, current: current)
            session.isTemporarilyOverridden = false
            try persist(session)
            return success(observedLimit: session.backend == .intelBCLM ? session.requestedLimit : nil)
        }
    }

    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?, ownerID: UUID, withReply reply: @escaping (Reply?) -> Void
    ) {
        perform(reply) {
            try requireEligible()
            try adoptOrRequire(ownerID)
            var session = try requireSession()
            let current = try readOwned(session, allowInterrupted: true)
            if let expectedLimit {
                let expected = try validatedPercent(expectedLimit)
                let actual = session.backend == .intelBCLM
                    ? current["BCLM"].map { Int($0[0]) } : session.requestedLimit
                guard actual == expected else {
                    throw Failure(.ownershipConflict, "The expected current limit changed.")
                }
            }
            try apply(&session, desired: session.originalRaw, current: current)
            // A failed clear is a failed disable; retain the verified restore
            // state in the journal so a retry remains safe.
            try journalStore.clear()
            clearOwnership()
            return success(observedLimit: session.backend == .intelBCLM
                ? session.originalRaw["BCLM"].map { Int($0[0]) } : nil)
        }
    }

    /// Forces the Silicon gate closed before sleep. Intel firmware owns its own
    /// cutoff, so that path is a documented no-op here.
    func prepareForSleep(ownerID: UUID, withReply reply: @escaping (Reply?) -> Void) {
        perform(reply) {
            try requireEligible()
            try adoptOrRequire(ownerID)
            var session = try requireSession()
            guard session.backend == .silicon else {
                return success(observedLimit: nil)
            }
            guard !session.isTemporarilyOverridden else {
                // A one-time full charge is an explicit user decision and must
                // survive ordinary sleep.
                return success(observedLimit: nil)
            }
            let current = try readOwned(session)
            // Follow the family recorded in the journal, never the keys that
            // happen to exist now.
            let desired: [String: Data]
            if session.originalRaw["CHTE"] != nil {
                desired = ["CHTE": Data([1, 0, 0, 0])]
            } else {
                desired = ["CH0B": Data([2]), "CH0C": Data([2])]
            }
            try apply(&session, desired: desired, current: current)
            try persist(session)
            return success(observedLimit: nil)
        }
    }

    func verifyLegacyChargeLimit(
        _ limit: Int, ownerID: UUID? = nil, withReply reply: @escaping (Reply?) -> Void
    ) {
        perform(reply) {
            try requireEligible()
            let session = try requireSession()
            // Reconnection after a helper crash must own quit restoration even
            // if it only verifies the saved session and never changes the cap.
            if let ownerID { try adoptOrRequire(ownerID) }
            guard session.requestedLimit == limit else {
                throw Failure(.ownershipConflict, "The saved target changed.")
            }
            _ = try readOwned(session)
            guard session.pendingRaw == nil else {
                throw Failure(.verificationFailed, "A previous write needs explicit recovery.")
            }
            // No writes and no guessed percentage for Silicon. This confirms
            // the recorded raw gate only, not a firmware-enforced ceiling.
            return success(observedLimit: session.backend == .intelBCLM
                ? session.lastWrittenRaw["BCLM"].map { Int($0[0]) } : nil)
        }
    }

    /// A new session claims the hardware; a session with no live owner (app
    /// relaunch, first launch after a crash) may be adopted by one connection.
    /// Two live connections can never own the same cap.
    private func claimHardware(_ newOwner: UUID) throws {
        if let ownerID, ownerID != newOwner {
            throw Failure(.ownershipConflict, "Another connection owns the charge limit.")
        }
        ownerID = newOwner
    }

    /// Mutating an existing session requires being its live owner, or adopting
    /// it when no other live connection holds it.
    private func adoptOrRequire(_ requested: UUID) throws {
        if let ownerID, ownerID != requested {
            throw Failure(.ownershipConflict, "Another connection owns the charge limit.")
        }
        ownerID = requested
    }

    private func clearOwnership() {
        ownerID = nil
        recoveryDemandChanged(false)
    }

    /// Reconciles a journal left by a crashed or killed helper before the
    /// daemon serves any new request.
    ///
    /// A durable journal means some earlier process owned this hardware and is
    /// gone. Restoring the recorded stock values is the safe default. A current
    /// value that belongs to neither our last write nor our pending write is a
    /// foreign change: keep the record, do not write, and stay alive so the
    /// stranded state is not silently abandoned.
    @discardableResult
    func reconcileAtStartup() -> Bool {
        lock.withLock {
            do {
                guard var session = try loadOwnedJournal() else { return true }
                try requireEligible()
                let current = try readOwned(session, allowInterrupted: true)
                try apply(&session, desired: session.originalRaw, current: current)
                try journalStore.clear()
                recoveryDemandChanged(false)
                return true
            } catch {
                NSLog(
                    "StatusTrioPowerHelper: startup charge reconciliation pending: %@",
                    String(describing: error)
                )
                recoveryDemandChanged(true)
                return false
            }
        }
    }

    /// Connection owner loss must call this before releasing its idle lease.
    /// False means recovery remains pending; the caller must keep the helper
    /// alive and make the error visible instead of silently abandoning a cap.
    @discardableResult
    func restoreForClientLoss(owner: UUID) -> Bool {
        lock.withLock {
            // Only the connection that owns the session may trigger recovery;
            // an unrelated connection ending must not touch the active cap.
            guard ownerID == owner else { return true }
            do {
                guard var session = try loadOwnedJournal() else {
                    clearOwnership()
                    return true
                }
                try requireEligible()
                let current = try readOwned(session, allowInterrupted: true)
                try apply(&session, desired: session.originalRaw, current: current)
                try journalStore.clear()
                clearOwnership()
                return true
            } catch {
                NSLog("StatusTrioPowerHelper: charge recovery pending: %@", String(describing: error))
                ownerID = nil
                recoveryDemandChanged(true)
                return false
            }
        }
    }

    // MARK: Transaction boundary

    private func apply(_ session: inout Session, desired: [String: Data], current: [String: Data]) throws {
        guard Set(desired.keys) == Set(session.originalRaw.keys),
              desired.allSatisfy({ LegacyChargeSMCKeys.isValidValue($0.value, for: $0.key) }) else {
            throw Failure(.unsupportedHardware, "The charge key payload is invalid.")
        }
        session.pendingRaw = desired
        // Failing persistence prevents all hardware I/O.
        try persist(session)
        var touched: [String] = []
        do {
            for key in desired.keys.sorted() {
                guard validRead(key) == current[key] else {
                    throw Failure(.ownershipConflict, "A charge key changed at the write boundary.")
                }
                guard desired[key] != current[key] else { continue }
                touched.append(key) // a failed call may still have applied
                guard executor.writeKey(key, data: desired[key]!), validRead(key) == desired[key] else {
                    throw Failure(.verificationFailed, "The hardware did not confirm the write.")
                }
            }
            guard desired.allSatisfy({ validRead($0.key) == $0.value }) else {
                throw Failure(.verificationFailed, "The charge key readback changed.")
            }
        } catch {
            // Roll back only values attributable to this transaction. A foreign
            // change is never overwritten. Confirm every rollback readback.
            var restored = true
            for key in touched.reversed() {
                guard let original = current[key], let observed = validRead(key) else {
                    restored = false
                    continue
                }
                if observed == original { continue }
                guard observed == desired[key], executor.writeKey(key, data: original),
                      validRead(key) == original else {
                    restored = false
                    continue
                }
            }
            if restored {
                session.lastWrittenRaw = current
                session.pendingRaw = nil
                try persist(session)
                throw error
            }
            // pendingRaw remains durable for an explicit restore/reconcile.
            throw Failure(.restoreFailed, "A partial charge write could not be rolled back.")
        }
        session.lastWrittenRaw = desired
        session.pendingRaw = nil
        try persist(session)
    }

    private func perform(_ reply: (Reply?) -> Void, operation: () throws -> Reply) {
        let result: Reply = lock.withLock {
            do { return try operation() }
            catch let error as Failure { return failure(error.code, error.message) }
            catch { return failure(.rejected, "The recovery journal could not be saved or read.") }
        }
        // Do not invoke client code while holding the coordinator lock.
        reply(result)
    }

    private func requireEligible() throws {
        guard hardware.hasInternalBattery, hardware.allowsLegacyLimiter,
              !hardwareModel.isEmpty, hardwareModel != "unknown" else {
            throw Failure(.unsupportedHardware, "This hardware or macOS version is not eligible.")
        }
    }

    private func loadOwnedJournal() throws -> Session? {
        guard let session = try journalStore.load() else { return nil }
        if let recordedBuild = session.osBuild, recordedBuild != osBuild {
            throw Failure(.ownershipConflict, "The recovery record belongs to a different system build.")
        }
        guard session.hardwareModel == hardwareModel,
              (session.backend == .intelBCLM) == hardware.isIntel,
              (80...100).contains(session.requestedLimit) else {
            throw Failure(.ownershipConflict, "The recovery record belongs to different hardware.")
        }
        let keys = Set(session.originalRaw.keys)
        let validKeys = session.backend == .intelBCLM ? keys == ["BCLM"]
            : keys == ["CH0B", "CH0C"] || keys == ["CHTE"]
        guard validKeys, keys == Set(session.lastWrittenRaw.keys),
              session.originalRaw.allSatisfy({ LegacyChargeSMCKeys.isValidValue($0.value, for: $0.key) }),
              session.lastWrittenRaw.allSatisfy({ LegacyChargeSMCKeys.isValidValue($0.value, for: $0.key) }) else {
            throw Failure(.ownershipConflict, "The recovery record has an invalid key set.")
        }
        if let pending = session.pendingRaw {
            guard keys == Set(pending.keys),
                  pending.allSatisfy({ LegacyChargeSMCKeys.isValidValue($0.value, for: $0.key) }) else {
                throw Failure(.ownershipConflict, "The pending recovery payload is invalid.")
            }
        }
        return session
    }

    private func requireSession() throws -> Session {
        guard let session = try loadOwnedJournal() else {
            throw Failure(.cancelled, "No managed charge session exists.")
        }
        return session
    }

    private func readOwned(_ session: Session, allowInterrupted: Bool = false) throws -> [String: Data] {
        if session.pendingRaw != nil && !allowInterrupted {
            throw Failure(.verificationFailed, "An interrupted write needs explicit restoration.")
        }
        var raw: [String: Data] = [:]
        for (key, expected) in session.lastWrittenRaw {
            guard let current = validRead(key) else {
                throw Failure(.verificationFailed, "A charge setting could not be read.")
            }
            guard current == expected || (allowInterrupted && current == session.pendingRaw?[key]) else {
                throw Failure(.ownershipConflict, "Another controller changed a charge setting.")
            }
            raw[key] = current
        }
        return raw
    }

    private func discoverOriginal() throws -> [String: Data] {
        if hardware.isIntel, let ceiling = validRead("BCLM") { return ["BCLM": ceiling] }
        if !hardware.isIntel {
            if let b = validRead("CH0B"), let c = validRead("CH0C") { return ["CH0B": b, "CH0C": c] }
            if let t = validRead("CHTE") { return ["CHTE": t] }
        }
        throw Failure(.unsupportedHardware, "No validated charge key set was found.")
    }

    private func desiredRaw(
        session: Session, limit: Int, full: Bool, current: [String: Data]
    ) throws -> [String: Data] {
        if session.backend == .intelBCLM { return ["BCLM": Data([UInt8(limit)])] }
        let allow: Bool
        if full || limit == 100 { allow = true }
        else {
            guard let level = battery.currentPercent(), (0...100).contains(level) else {
                throw Failure(.verificationFailed, "The internal battery level is unknown.")
            }
            let open = current["CH0B"] == Data([0]) && current["CH0C"] == Data([0])
                || current["CHTE"] == Data([0, 0, 0, 0])
            allow = !battery.isOnACPower() || LegacyGatePolicy.shouldAllowCharging(
                level: level, limit: limit, currentlyAllowed: open
            )
        }
        // Choose the family from the journaled key set, never from whichever
        // keys happen to exist now; mixing families would fail the closed-set
        // check and could leave a partially owned gate.
        if session.originalRaw["CHTE"] != nil {
            return ["CHTE": allow ? Data([0, 0, 0, 0]) : Data([1, 0, 0, 0])]
        }
        return ["CH0B": Data([allow ? 0 : 2]), "CH0C": Data([allow ? 0 : 2])]
    }

    private func persist(_ session: Session) throws {
        try journalStore.save(session)
    }

    private func validRead(_ key: String) -> Data? {
        guard LegacyChargeSMCKeys.writeAllowlist.contains(key), let raw = executor.readKey(key),
              LegacyChargeSMCKeys.isValidValue(raw, for: key) else { return nil }
        return raw
    }

    private func validatedPercent(_ number: NSNumber) throws -> Int {
        let percent = number.intValue
        guard number.doubleValue.isFinite, number.doubleValue == Double(percent),
              (50...100).contains(percent) else {
            throw Failure(.ownershipConflict, "The expected current limit is invalid.")
        }
        return percent
    }

    private func success(observedLimit: Int?) -> Reply {
        Reply(succeeded: true, observedLimit: observedLimit.map { NSNumber(value: $0) },
              verified: true, errorCode: .none, errorDescription: nil)
    }

    private func failure(_ code: SMLegacyChargeLimitErrorCode, _ message: String) -> Reply {
        Reply(succeeded: false, observedLimit: nil, verified: false, errorCode: code, errorDescription: message)
    }
}
