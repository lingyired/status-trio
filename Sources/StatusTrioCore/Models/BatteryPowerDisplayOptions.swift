struct BatteryPowerDisplayOptions: Equatable, Sendable {
    var showsInput: Bool = false
    var showsCharging: Bool = true
    var showsSystem: Bool = true

    static let `default` = Self()
    var showsAnyPower: Bool { showsInput || showsCharging || showsSystem }
}
