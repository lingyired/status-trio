import Foundation
import IOKit.ps
import SMCPrivateAPI

/// Concrete byte-level executor backed by the AppleSMC IOKit bridge.
///
/// This is the only place the daemon performs real SMC I/O. It defers key
/// validation to `LegacyChargeLimitService`, which enforces the closed allowlist
/// and value shapes before calling here; the bridge repeats the allowlist check
/// as defence in depth.
///
/// NOT RUN: no real SMC read or write has been exercised on Intel or Apple
/// Silicon macOS 13–15 hardware. See `docs/legacy-charge-limit.md`.
final class IOKitLegacySMCExecutor: LegacySMCExecuting {
    private var opened = false
    private let lock = NSLock()

    init() {}

    private func ensureOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if opened { return true }
        guard STSMCOpen() == 0 else { return false }
        opened = true
        return true
    }

    deinit {
        STSMClose()
    }

    func readKey(_ key: String) -> Data? {
        guard ensureOpen() else { return nil }
        var buffer = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        let ok = buffer.withUnsafeMutableBufferPointer { raw in
            STSMReadKeyCopy(key, raw.baseAddress, UInt32(raw.count), &size)
        }
        guard ok, size > 0, size <= UInt32(buffer.count) else { return nil }
        return Data(buffer.prefix(Int(size)))
    }

    func writeKey(_ key: String, data: Data) -> Bool {
        guard ensureOpen(), !data.isEmpty, data.count <= 32 else { return false }
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            return STSMWriteKeyAllowlisted(key, base, UInt32(data.count))
        }
    }
}

// MARK: - Facts resolved once at helper startup

/// Runtime hardware facts for the daemon. Kept separate from the app's domain
/// model because the helper must not link AppKit/SwiftUI.
enum LegacyHelperEnvironment {
    /// True only for a native Intel process. A Rosetta process reports
    /// `x86_64` but runs on Apple Silicon, so the CPU brand check wins.
    static func isIntel() -> Bool {
        #if arch(x86_64)
        return !isRosetta()
        #else
        return false
        #endif
    }

    static func isRosetta() -> Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return result == 0 && translated == 1
    }

    /// macOS 13–15 only; 16–26.3 is out of this milestone and 26.4+ is native.
    static func allowsLegacyLimiter() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        switch version.majorVersion {
        case 13, 14, 15: return true
        default: return false
        }
    }

    static func hasInternalBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }

    static func facts() -> LegacyHardwareFacts {
        LegacyHardwareFacts(
            isIntel: isIntel(),
            allowsLegacyLimiter: allowsLegacyLimiter(),
            hasInternalBattery: hasInternalBattery()
        )
    }
}

/// Battery/power facts for the Silicon gate decision.
final class SystemLegacyBatteryProvider: LegacyBatteryProviding {
    func currentPercent() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return description[kIOPSCurrentCapacityKey] as? Int
        }
        return nil
    }

    func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return false
        }
        return type == kIOPSACPowerValue
    }
}