import Foundation

/// One refresh's worth of SMC power sensors. Every field is a best-effort
/// reading from the same short-lived connection.
struct PowerSensorReadings: Equatable, Sendable {
    var system: SystemPowerSample?
    var input: SystemPowerSample?
    var battery: BatteryPowerSample?
    /// Built-in display backlight power (`PDBR`, else `PBLR`). Machines with
    /// neither report nil.
    var display: SystemPowerSample?
    /// Accessory output on SMC channels D1–D4 (`DnJV` volts × `DnJI` amps).
    var portRails: PortOutputRails = .unavailable
    /// Battery temperature from `TB0T`, decoded by `BatteryHealthParser`.
    var batteryTemperatureCelsius: Double?

    static let empty = Self()
}
