import Foundation

/// Independent gate for the "prefer the system battery optimization" hint.
///
/// The hint belongs to macOS 26.4+, where the OS ships its own charge limit.
/// It must not be derived from a private-API capability probe: once the legacy
/// SMC backend exists on macOS 13–15, a capability-based gate would start
/// recommending the system optimization on systems that do not have it.
enum ChargeLimitSystemVersionGate {
    static func prefersSystemBatteryOptimization(version: OperatingSystemVersion) -> Bool {
        if version.majorVersion > 26 { return true }
        return version.majorVersion == 26 && version.minorVersion >= 4
    }

    static func prefersSystemBatteryOptimization() -> Bool {
        prefersSystemBatteryOptimization(version: ProcessInfo.processInfo.operatingSystemVersion)
    }
}