import Foundation
import SMCPrivateAPI

/// Concrete `LegacySMCExecuting` backed by the AppleSMC IOKit bridge.
///
/// This is the only place the daemon performs real SMC I/O. It is deliberately
/// thin: it maps the typed intents (`BCLM` ceiling, silicon inhibit on/off) to
/// the bridge's allowlisted key writes and always reads back so a caller can
/// distinguish "write returned OK" from "hardware actually changed".
///
/// NOT RUN: this executor has not been exercised against real hardware in this
/// session. The read-only probe and behaviour validation are manual procedures
/// on authorized Intel/macOS 13–15 and Apple Silicon/macOS 13–15 hosts.
final class IOKitLegacySMCExecutor: LegacySMCExecuting {
    private var opened = false

    init() {}

    /// Opens the SMC user client lazily. Returns false when unavailable (e.g.
    /// non-entitled VM), which the service surfaces as unsupported.
    private func ensureOpen() -> Bool {
        if opened { return true }
        guard STSMCOpen() == 0 else { return false }
        opened = true
        return true
    }

    deinit {
        STSMClose()
    }

    // MARK: - Intel BCLM

    func readIntelBCLM() -> Int? {
        guard ensureOpen() else { return nil }
        var result = STSMReadResult()
        guard STSMReadKey("BCLM", &result), result.ok, result.bytesRead == 1 else {
            return nil
        }
        return Int(result.bytes.0)
    }

    func writeIntelBCLM(_ limit: Int) -> Int? {
        guard ensureOpen(), (0...100).contains(limit) else { return nil }
        var byte = UInt8(limit)
        let ok = withUnsafePointer(to: &byte) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 1) { raw in
                STSMWriteKeyAllowlisted("BCLM", raw, 1)
            }
        }
        guard ok else { return nil }
        // Readback so the caller never trusts the write return alone.
        return readIntelBCLM()
    }

    // MARK: - Apple Silicon inhibit

    func siliconKeySetName() -> LegacySMCInhibitKeySetName? {
        guard ensureOpen() else { return nil }
        var b = STSMReadResult()
        var c = STSMReadResult()
        if STSMReadKey("CH0B", &b), b.ok, STSMReadKey("CH0C", &c), c.ok {
            return .pairCH0BCH0C
        }
        var t = STSMReadResult()
        if STSMReadKey("CHTE", &t), t.ok, t.bytesRead == 4 {
            return .chte
        }
        return nil
    }

    func writeSiliconInhibit(allow: Bool, keySet: LegacySMCInhibitKeySetName) -> Bool {
        guard ensureOpen() else { return false }
        switch keySet {
        case .pairCH0BCH0C:
            let value: UInt8 = allow ? 0x00 : 0x02
            var byte = value
            let wroteB = withUnsafePointer(to: &byte) { ptr in
                ptr.withMemoryRebound(to: UInt8.self, capacity: 1) { raw in
                    STSMWriteKeyAllowlisted("CH0B", raw, 1)
                }
            }
            guard wroteB else { return false }
            var byte2 = value
            let wroteC = withUnsafePointer(to: &byte2) { ptr in
                ptr.withMemoryRebound(to: UInt8.self, capacity: 1) { raw in
                    STSMWriteKeyAllowlisted("CH0C", raw, 1)
                }
            }
            return wroteC
        case .chte:
            // 1 = inhibit, 0 = allow, 4-byte little-endian value.
            var bytes = allow ? [UInt8](repeating: 0, count: 4) : [1, 0, 0, 0]
            return bytes.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return false }
                return STSMWriteKeyAllowlisted("CHTE", base, 4)
            }
        }
    }

    func siliconChargingAllowed() -> Bool? {
        guard ensureOpen() else { return nil }
        if let keySet = siliconKeySetName() {
            switch keySet {
            case .pairCH0BCH0C:
                var b = STSMReadResult()
                guard STSMReadKey("CH0B", &b), b.ok, b.bytesRead == 1 else {
                    return nil
                }
                return b.bytes.0 == 0x00
            case .chte:
                var t = STSMReadResult()
                guard STSMReadKey("CHTE", &t), t.ok, t.bytesRead == 4 else {
                    return nil
                }
                return (t.bytes.0 == 0 && t.bytes.1 == 0 && t.bytes.2 == 0 && t.bytes.3 == 0)
            }
        }
        return nil
    }
}