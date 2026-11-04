import Foundation

/// The I/O surface a real SMC probe (Phase 2) and a test fake both implement.
///
/// This is deliberately protocol-based and value-shaped so the pure domain
/// model (Phase 1) and its unit tests never touch IOKit. Reads are the same
/// calls used for both capability discovery and read-back verification;
/// a successful read does **not** imply a successful write (see
/// ```verifiedWritableKeys```).
protocol SMCAccessing: AnyObject {
    /// Returns key info plus the current raw bytes for a key, or nil if the
    /// key is absent / wrong width.
    func readKey(_ key: String) -> (info: LegacySMCKeyInfo, data: Data)?
    /// Attempts a raw write. Fillers return the bytes the backing store holds
    /// afterwards; a real backend returns the verified readback.
    func writeKey(_ key: String, data: Data) -> (ok: Bool, observed: Data?)
}

/// Why a battery read failed, kept minimal.
enum LegacyBatteryReadError: Equatable, Sendable {
    case noBattery
    case readFailed
}

/// Injectable battery facts (level, and whether we believe we are on AC).
struct LegacyBatterySnapshot: Equatable, Sendable {
    var levelPercent: Int
    var isOnAC: Bool
}

/// The accepted battery-source surface for the legacy limiter.
protocol LegacyBatteryReading: AnyObject {
    func snapshot() throws -> LegacyBatterySnapshot
}

/// Deterministic in-memory SMC fake. Holds a dict of key -> (info, data) and
/// honours an explicit write-allowlist plus a "verified-writable" set so tests
/// can model entitlement-gated or read-only keys.
final class FakeSMC: SMCAccessing, @unchecked Sendable {
    private(set) var store: [String: (info: LegacySMCKeyInfo, data: Data)]
    let writeAllowlist: Set<String>
    var verifiedWritableKeys: Set<String>
    var writeLog: [String] = []

    init(
        store: [String: (info: LegacySMCKeyInfo, data: Data)] = [:],
        writeAllowlist: Set<String> = [],
        verifiedWritableKeys: Set<String> = []
    ) {
        self.store = store
        self.writeAllowlist = writeAllowlist
        self.verifiedWritableKeys = verifiedWritableKeys
    }

    func readKey(_ key: String) -> (info: LegacySMCKeyInfo, data: Data)? {
        store[key]
    }

    func writeKey(_ key: String, data: Data) -> (ok: Bool, observed: Data?) {
        guard writeAllowlist.contains(key) else {
            writeLog.append("deny:\(key)")
            return (false, store[key]?.data)
        }
        guard store[key] != nil else {
            writeLog.append("missing:\(key)")
            return (false, nil)
        }
        store[key]?.data = data
        writeLog.append("write:\(key)=\(bytes(data))")
        return (true, data)
    }

    private func bytes(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }
}

/// Deterministic battery fake.
final class FakeBattery: LegacyBatteryReading, @unchecked Sendable {
    var levelPercent: Int
    var isOnAC: Bool

    init(levelPercent: Int, isOnAC: Bool = true) {
        self.levelPercent = levelPercent
        self.isOnAC = isOnAC
    }

    func snapshot() throws -> LegacyBatterySnapshot {
        LegacyBatterySnapshot(levelPercent: levelPercent, isOnAC: isOnAC)
    }
}