import Foundation
import PowerHelperProtocol

// MARK: - Injected facts

/// Hardware facts the helper trusts for gating. Resolved once when the daemon
/// builds the service (runtime CPU + OS band + internal battery presence). The
/// app never supplies these over XPC, so a compromised client cannot talk the
/// daemon into writing a key the machine does not have.
struct LegacyHardwareFacts: Equatable, Sendable {
    var isIntel: Bool
    var allowsLegacyLimiter: Bool
    var hasInternalBattery: Bool
}

/// Battery facts the coordinator needs for the Silicon gate decision. Injected
/// so tests never need real power sources.
protocol LegacyBatteryProviding: AnyObject {
    func currentPercent() -> Int?
    func isOnACPower() -> Bool
}

/// Durable ownership record. Written *before* the first hardware write so a
/// crash or a failed write cannot lose the stock value; cleared only after a
/// verified restore.
struct LegacyChargeLimitJournal: Codable, Equatable, Sendable {
    enum Backend: String, Codable, Sendable {
        case intelBCLM
        case silicon
    }

    var backend: Backend
    /// The ceiling the user asked for.
    var requestedLimit: Int
    /// Raw SMC payload captured before the first write, per key.
    var originalRaw: [String: Data]
    /// Raw payload the last successful write left behind, per key.
    var lastWrittenRaw: [String: Data]
    var isTemporarilyOverridden = false
}

protocol LegacyChargeLimitJournaling: AnyObject {
    func load() -> LegacyChargeLimitJournal?
    func save(_ journal: LegacyChargeLimitJournal)
    func clear()
}

/// Root-owned on-disk journal under the helper's own directory.
final class FileLegacyChargeLimitJournal: LegacyChargeLimitJournaling {
    private let url: URL

    init(directory: URL) {
        self.url = directory.appendingPathComponent("legacy-charge-limit-journal.json")
    }

    func load() -> LegacyChargeLimitJournal? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LegacyChargeLimitJournal.self, from: data)
    }

    func save(_ journal: LegacyChargeLimitJournal) {
        guard let data = try? JSONEncoder().encode(journal) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Executor

/// Byte-level SMC surface. The helper owns the key allowlist; the service only
/// names the four charge keys it understands and enforces type/size/value
/// rules before calling this.
protocol LegacySMCExecuting: AnyObject {
    func readKey(_ key: String) -> Data?
    func writeKey(_ key: String, data: Data) -> Bool
}

// MARK: - Closed key set

/// The only SMC keys this feature may touch, with expected widths. Anything
/// not listed here can never be read or written by the service.
enum LegacyChargeSMCKeys {
    static let bclm = "BCLM"
    static let ch0b = "CH0B"
    static let ch0c = "CH0C"
    static let chte = "CHTE"

    static let widths: [String: Int] = [
        bclm: 1,
        ch0b: 1,
        ch0c: 1,
        chte: 4,
    ]

    static let writeAllowlist: Set<String> = [bclm, ch0b, ch0c, chte]

    static func isValidValue(_ data: Data, for key: String) -> Bool {
        guard widths[key] == data.count else { return false }
        switch key {
        case bclm:
            guard let value = data.first else { return false }
            return (50...100).contains(value)
        case ch0b, ch0c:
            guard let value = data.first else { return false }
            return value == 0x00 || value == 0x02
        case chte:
            return data == Data([0x00, 0x00, 0x00, 0x00])
                || data == Data([0x01, 0x00, 0x00, 0x00])
        default:
            return false
        }
    }
}

// MARK: - Gate decision (kept in step with the app engine's thresholds)

enum LegacyGatePolicy {
    static let hysteresis = 2

    /// True when charging should be allowed for a limit at `limit`.
    static func shouldAllowCharging(level: Int, limit: Int, currentlyAllowed: Bool?) -> Bool {
        if level >= limit { return false }
        if level <= limit - hysteresis { return true }
        return currentlyAllowed ?? true
    }
}

// MARK: - Service

/// Server side of the legacy charge-limit XPC surface.
///
/// Ownership rules:
/// - A write is only issued after a durable journal records the raw stock value.
/// - `expectedLimit` is compared with the *observed* hardware value before any
///   write; a mismatch is reported, never overwritten.
/// - Multi-key Silicon writes roll back already-applied keys on failure.
/// - Success is reported only after reading the hardware back; a write call that
///   claims success but leaves the old bytes is a failure.
final class LegacyChargeLimitService: NSObject, LegacyChargeLimitXPCProtocol, @unchecked Sendable {
    private let executor: any LegacySMCExecuting
    private let journalStore: any LegacyChargeLimitJournaling
    private let battery: any LegacyBatteryProviding
    private let hardware: LegacyHardwareFacts
    private let lock = NSLock()

    init(
        executor: any LegacySMCExecuting,
        journal: any LegacyChargeLimitJournaling,
        battery: any LegacyBatteryProviding,
        hardware: LegacyHardwareFacts
    ) {
        self.executor = executor
        self.journalStore = journal
        self.battery = battery
        self.hardware = hardware
    }

    // MARK: Probe (read-only)

    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    ) {
        let bclmPresent = validRead(LegacyChargeSMCKeys.bclm) != nil
        let pairPresent = validRead(LegacyChargeSMCKeys.ch0b) != nil
            && validRead(LegacyChargeSMCKeys.ch0c) != nil
        let chtePresent = validRead(LegacyChargeSMCKeys.chte) != nil
        reply(
            SMLegacyChargeLimitProbeReply(
                hasInternalBattery: hardware.hasInternalBattery,
                intelBCLMPresent: bclmPresent,
                siliconPairPresent: pairPresent,
                siliconCHTEPresent: chtePresent,
                architectureName: hardware.isIntel ? "intel" : "appleSilicon",
                osBandName: hardware.allowsLegacyLimiter ? "legacy" : "unsupported",
                errorCode: .none,
                errorDescription: nil
            ),
            nil
        )
    }

    // MARK: Set limit

    func setLegacyChargeLimit(
        _ limit: Int,
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard (80...100).contains(limit) else {
            reply(failure(.limitOutOfRange, "The charge limit is outside 80–100%."))
            return
        }
        guard hardware.hasInternalBattery, hardware.allowsLegacyLimiter else {
            reply(failure(.unsupportedHardware, "This Mac or macOS version is not supported."))
            return
        }

        if hardware.isIntel {
            guard let current = validRead(LegacyChargeSMCKeys.bclm),
                  let currentPercent = current.first.map(Int.init) else {
                reply(failure(.unsupportedHardware, "The Intel charge ceiling key is unavailable."))
                return
            }
            if let expectedLimit, expectedLimit.intValue != currentPercent {
                reply(failure(.ownershipConflict, "Another controller changed the charge limit."))
                return
            }

            var session = journalStore.load() ?? LegacyChargeLimitJournal(
                backend: .intelBCLM,
                requestedLimit: limit,
                originalRaw: [LegacyChargeSMCKeys.bclm: current],
                lastWrittenRaw: [:]
            )
            session.backend = .intelBCLM
            session.requestedLimit = limit
            if session.originalRaw[LegacyChargeSMCKeys.bclm] == nil {
                session.originalRaw[LegacyChargeSMCKeys.bclm] = current
            }
            journalStore.save(session)

            guard writeAndVerify(key: LegacyChargeSMCKeys.bclm, value: Data([UInt8(limit)])) else {
                reply(failure(.verificationFailed, "The hardware did not take the new limit."))
                return
            }
            session.lastWrittenRaw[LegacyChargeSMCKeys.bclm] = Data([UInt8(limit)])
            session.isTemporarilyOverridden = false
            journalStore.save(session)
            reply(success(observedLimit: limit))
            return
        }

        // Apple Silicon: the "limit" is a target; the gate is what the hardware
        // understands. Verify the gate actually moved.
        let keySet = siliconKeySet()
        guard let keySet else {
            reply(failure(.unsupportedHardware, "No supported charging-gate key was found."))
            return
        }
        let originals = originalGateRaw(for: keySet)
        var session = journalStore.load() ?? LegacyChargeLimitJournal(
            backend: .silicon,
            requestedLimit: limit,
            originalRaw: originals,
            lastWrittenRaw: [:]
        )
        session.backend = .silicon
        session.requestedLimit = limit
        for (key, value) in originals where session.originalRaw[key] == nil {
            session.originalRaw[key] = value
        }
        journalStore.save(session)

        let level = battery.currentPercent() ?? 0
        let currentlyAllowed = gateIsOpen(keySet)
        let allow = LegacyGatePolicy.shouldAllowCharging(
            level: level,
            limit: limit,
            currentlyAllowed: currentlyAllowed
        )
        guard applyGate(keySet, allow: allow) else {
            reply(failure(.verificationFailed, "The charging gate did not change."))
            return
        }
        session.lastWrittenRaw = gateRaw(keySet, allow: allow)
        session.isTemporarilyOverridden = false
        journalStore.save(session)
        reply(success(observedLimit: allow ? 100 : limit))
    }

    // MARK: Charge to full once / cancel

    func legacyChargeToFullOnce(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var session = journalStore.load() else {
            reply(failure(.cancelled, "There is no managed limit to override."))
            return
        }
        session.isTemporarilyOverridden = true
        journalStore.save(session)

        if session.backend == .intelBCLM {
            guard writeAndVerify(key: LegacyChargeSMCKeys.bclm, value: Data([100])) else {
                reply(failure(.verificationFailed, "The hardware did not lift the limit."))
                return
            }
            session.lastWrittenRaw[LegacyChargeSMCKeys.bclm] = Data([100])
        } else {
            guard let keySet = siliconKeySet(), applyGate(keySet, allow: true) else {
                reply(failure(.verificationFailed, "The charging gate did not open."))
                return
            }
            session.lastWrittenRaw = gateRaw(keySet, allow: true)
        }
        journalStore.save(session)
        reply(success(observedLimit: 100))
    }

    func cancelLegacyChargeToFull(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var session = journalStore.load() else {
            reply(failure(.cancelled, "There is no temporary override to cancel."))
            return
        }
        guard session.isTemporarilyOverridden else {
            reply(failure(.cancelled, "There is no temporary override to cancel."))
            return
        }
        guard reapplyRequestedLimit(session: &session) else {
            reply(failure(.restoreFailed, "The saved limit could not be reapplied."))
            return
        }
        session.isTemporarilyOverridden = false
        journalStore.save(session)
        reply(success(observedLimit: session.requestedLimit))
    }

    // MARK: Disable / restore

    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard let session = journalStore.load() else {
            reply(failure(.cancelled, "No managed limit is active."))
            return
        }

        // Refuse to blindly overwrite a foreign value the user or another app
        // set while we were holding the session.
        for (key, written) in session.lastWrittenRaw {
            if let current = validRead(key), current != written {
                reply(failure(.ownershipConflict, "Another controller changed the charge setting."))
                return
            }
        }
        if let expectedLimit, session.backend == .intelBCLM,
           let stock = session.originalRaw[LegacyChargeSMCKeys.bclm]?.first.map(Int.init),
           expectedLimit.intValue != stock {
            // expectedLimit describes the *stock* value on restore paths; a
            // mismatch means the caller is working from a stale view.
            reply(failure(.ownershipConflict, "The expected charge limit does not match."))
            return
        }

        for (key, value) in session.originalRaw {
            guard writeAndVerify(key: key, value: value) else {
                reply(failure(.restoreFailed, "The stock charge setting could not be restored."))
                return
            }
        }
        if session.originalRaw.isEmpty {
            reply(failure(.restoreFailed, "No stock charge value was recorded."))
            return
        }
        journalStore.clear()
        let observed = session.backend == .intelBCLM
            ? session.originalRaw[LegacyChargeSMCKeys.bclm]?.first.map(Int.init)
            : 100
        reply(success(observedLimit: observed ?? 100))
    }

    func verifyLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard (80...100).contains(limit) else {
            reply(failure(.limitOutOfRange, "The charge limit is outside 80–100%."))
            return
        }
        guard let session = journalStore.load() else {
            reply(failure(.cancelled, "No managed limit is active."))
            return
        }
        let matches: Bool
        if session.backend == .intelBCLM {
            matches = validRead(LegacyChargeSMCKeys.bclm)?.first.map(Int.init) == limit
        } else {
            guard let keySet = siliconKeySet() else {
                reply(failure(.unsupportedHardware, "No supported charging-gate key was found."))
                return
            }
            let level = battery.currentPercent() ?? 0
            let shouldAllow = level < limit
            matches = gateIsOpen(keySet) == shouldAllow
        }
        if matches {
            reply(success(observedLimit: limit))
        } else {
            reply(failure(.verificationFailed, "The hardware is not at the requested limit."))
        }
    }

    // MARK: - Helpers

    private func validRead(_ key: String) -> Data? {
        guard LegacyChargeSMCKeys.writeAllowlist.contains(key),
              let data = executor.readKey(key),
              LegacyChargeSMCKeys.isValidValue(data, for: key) else {
            return nil
        }
        return data
    }

    private func writeAndVerify(key: String, value: Data) -> Bool {
        guard LegacyChargeSMCKeys.writeAllowlist.contains(key),
              LegacyChargeSMCKeys.isValidValue(value, for: key) else {
            return false
        }
        guard executor.writeKey(key, data: value) else { return false }
        return validRead(key) == value
    }

    private func siliconKeySet() -> SiliconGate? {
        if validRead(LegacyChargeSMCKeys.ch0b) != nil, validRead(LegacyChargeSMCKeys.ch0c) != nil {
            return .pair
        }
        if validRead(LegacyChargeSMCKeys.chte) != nil {
            return .chte
        }
        return nil
    }

    private enum SiliconGate {
        case pair
        case chte
    }

    private func originalGateRaw(for keySet: SiliconGate) -> [String: Data] {
        switch keySet {
        case .pair:
            return [
                LegacyChargeSMCKeys.ch0b: validRead(LegacyChargeSMCKeys.ch0b) ?? Data([0x00]),
                LegacyChargeSMCKeys.ch0c: validRead(LegacyChargeSMCKeys.ch0c) ?? Data([0x00]),
            ]
        case .chte:
            return [LegacyChargeSMCKeys.chte: validRead(LegacyChargeSMCKeys.chte) ?? Data([0, 0, 0, 0])]
        }
    }

    private func gateRaw(_ keySet: SiliconGate, allow: Bool) -> [String: Data] {
        switch keySet {
        case .pair:
            let byte: UInt8 = allow ? 0x00 : 0x02
            return [LegacyChargeSMCKeys.ch0b: Data([byte]), LegacyChargeSMCKeys.ch0c: Data([byte])]
        case .chte:
            return [LegacyChargeSMCKeys.chte: allow ? Data([0, 0, 0, 0]) : Data([0x01, 0, 0, 0])]
        }
    }

    private func gateIsOpen(_ keySet: SiliconGate) -> Bool {
        switch keySet {
        case .pair:
            return validRead(LegacyChargeSMCKeys.ch0b) == Data([0x00])
        case .chte:
            return validRead(LegacyChargeSMCKeys.chte) == Data([0, 0, 0, 0])
        }
    }

    /// Writes every key of the gate, rolling back the ones already applied if a
    /// later write fails, then verifies the final readback.
    private func applyGate(_ keySet: SiliconGate, allow: Bool) -> Bool {
        let desired = gateRaw(keySet, allow: allow)
        let originals = originalGateRaw(for: keySet)
        var applied: [String] = []
        for key in [LegacyChargeSMCKeys.ch0b, LegacyChargeSMCKeys.ch0c, LegacyChargeSMCKeys.chte] {
            guard let value = desired[key] else { continue }
            if !executor.writeKey(key, data: value) {
                for rollbackKey in applied.reversed() {
                    if let original = originals[rollbackKey] {
                        _ = executor.writeKey(rollbackKey, data: original)
                    }
                }
                return false
            }
            applied.append(key)
        }
        // Verify by readback: a "successful" write that leaves the old bytes is
        // not a successful limit.
        for (key, value) in desired {
            guard validRead(key) == value else { return false }
        }
        return true
    }

    private func reapplyRequestedLimit(session: inout LegacyChargeLimitJournal) -> Bool {
        if session.backend == .intelBCLM {
            let value = Data([UInt8(session.requestedLimit)])
            guard writeAndVerify(key: LegacyChargeSMCKeys.bclm, value: value) else { return false }
            session.lastWrittenRaw[LegacyChargeSMCKeys.bclm] = value
            return true
        }
        guard let keySet = siliconKeySet() else { return false }
        let level = battery.currentPercent() ?? 0
        let allow = LegacyGatePolicy.shouldAllowCharging(
            level: level,
            limit: session.requestedLimit,
            currentlyAllowed: gateIsOpen(keySet)
        )
        guard applyGate(keySet, allow: allow) else { return false }
        session.lastWrittenRaw = gateRaw(keySet, allow: allow)
        return true
    }

    private func success(observedLimit: Int?) -> SMLegacyChargeLimitWriteReply {
        SMLegacyChargeLimitWriteReply(
            succeeded: true,
            observedLimit: observedLimit.map { NSNumber(value: $0) },
            verified: true,
            errorCode: .none,
            errorDescription: nil
        )
    }

    private func failure(
        _ code: SMLegacyChargeLimitErrorCode,
        _ description: String
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
extension LegacyChargeLimitService {
    /// Best-effort restore when the app disappears without disabling.
    ///
    /// The daemon is about to idle-exit and would otherwise leave the hardware
    /// inhibited with no owner. Only values this service last wrote are
    /// restored; a foreign change is left alone and logged (bounded, no retry).
    func restoreForClientLoss() {
        lock.lock()
        defer { lock.unlock() }
        guard let session = journalStore.load() else { return }
        for (key, written) in session.lastWrittenRaw {
            if let current = validRead(key), current != written {
                NSLog("StatusTrioPowerHelper: charge key %@ changed by another writer; not restoring", key)
                journalStore.clear()
                return
            }
        }
        for (key, value) in session.originalRaw {
            if !writeAndVerify(key: key, value: value) {
                NSLog("StatusTrioPowerHelper: could not restore charge key %@ on client loss", key)
                return
            }
        }
        journalStore.clear()
    }
}
