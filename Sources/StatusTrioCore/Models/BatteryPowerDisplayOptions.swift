struct BatteryPowerDisplayOptions: Equatable, Sendable {
    var showsInput: Bool = false
    var showsCharging: Bool = true
    var showsSystem: Bool = true
    /// Split what the Mac draws from the adapter into display / USB / chip /
    /// other branches. An unreliable split falls back to the legacy diagram.
    var showsBreakdown: Bool = true
    /// Testing aid: prefer the AppleARMBacklight estimate over the measured
    /// backlight rail even when SMC reports a positive value. If no valid
    /// estimate exists, the measured rail is still used.
    var forceBacklightEstimate: Bool = false

    static let `default` = Self()
    var showsAnyPower: Bool { showsInput || showsCharging || showsSystem || showsBreakdown }
}
