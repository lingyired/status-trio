import Foundation

struct SystemPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

protocol SystemPowerReading: Sendable {
    func read() -> SystemPowerSample?

    /// Single read of the requested AppleSMC sensors. The distribution-specific
    /// implementation performs one short-lived connection; the unavailable
    /// reader (and any conformer that only supports the system total) falls back
    /// to `read()` for the system value and reports no input/battery sample.
    func readSensors(
        system: Bool,
        input: Bool,
        battery: Bool
    ) -> (system: SystemPowerSample?, input: SystemPowerSample?, battery: BatteryPowerSample?)
}

extension SystemPowerReading {
    func readSensors(
        system: Bool,
        input: Bool,
        battery: Bool
    ) -> (system: SystemPowerSample?, input: SystemPowerSample?, battery: BatteryPowerSample?) {
        (system ? read() : nil, nil, nil)
    }
}

struct UnavailableSystemPowerReader: SystemPowerReading {
    func read() -> SystemPowerSample? { nil }
}
