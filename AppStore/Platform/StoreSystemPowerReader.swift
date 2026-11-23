import Foundation

/// Store-side stand-in for the Direct-only SMC `SystemPowerReader`. The App Store
/// build cannot read AppleSMC, so every read reports "no data".
struct SystemPowerReader: Sendable {
    func read() -> SystemPowerSample? { nil }

    func readSensors(
        system: Bool,
        input: Bool,
        battery: Bool,
        breakdown: Bool = false,
        temperature: Bool = false
    ) -> PowerSensorReadings {
        .empty
    }
}
