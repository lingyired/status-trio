struct BatteryPowerDisplayOptions: Equatable, Sendable {
    var showsInput: Bool = false
    var showsCharging: Bool = true
    var showsSystem: Bool = true
    /// Split what the Mac draws from the adapter into display / USB / chip /
    /// other branches. An unreliable split falls back to the legacy diagram.
    var showsBreakdown: Bool = true

    static let `default` = Self()
    var showsAnyPower: Bool { showsInput || showsCharging || showsSystem || showsBreakdown }
}
