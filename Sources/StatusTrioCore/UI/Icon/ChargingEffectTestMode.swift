import Foundation

/// Keeps the temporary CPU test local to icon rendering. Monitoring and the
/// status shown in the popover continue to use the actual battery reading.
enum ChargingEffectTestMode {
    static func isAvailable(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> Bool {
        bundleIdentifier?.contains(".dev.") == true
    }

    static func battery(_ battery: BatteryStatus, enabled: Bool) -> BatteryStatus {
        guard enabled else { return battery }
        return BatteryStatus(
            rawPercentage: battery.isPresent ? battery.rawPercentage : 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: battery.isLowPowerMode,
            isConnectedToPower: true
        )
    }

    static func status(_ status: MenuBarStatus, enabled: Bool) -> MenuBarStatus {
        guard enabled else { return status }
        return MenuBarStatus(
            battery: battery(status.battery, enabled: true),
            wifi: status.wifi,
            connection: status.connection,
            volume: status.volume
        )
    }

    static func snapshot(_ snapshot: StatusSnapshot, enabled: Bool) -> StatusSnapshot {
        guard enabled else { return snapshot }
        return snapshot.replacingBattery(battery(snapshot.battery, enabled: true))
    }
}
