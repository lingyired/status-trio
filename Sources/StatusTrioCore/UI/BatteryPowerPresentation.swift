import Foundation

/// One power row: its label, value and timestamp must all refer to the same source.
struct BatteryPowerPresentation {
    let title: LocalizationKey
    let watts: Double?
    let timestamp: Date?
    let timestampTitle: LocalizationKey
    let unavailableTitle: LocalizationKey
    /// Charge power, shown as its own row so the primary row can stay
    /// source-accurate. A battery only charges on external power.
    let chargingWatts: Double?

    init(details: BatteryDetails, isConnectedToPower: Bool, isBatteryPresent: Bool = true) {
        if !isBatteryPresent {
            // A Mac with no battery has only the whole-machine total. It is
            // never relabelled as discharge and never replaced with a fake 0 W.
            chargingWatts = nil
            title = .batteryDetailsWatt
            watts = details.systemPower?.watts
            timestamp = details.systemPower?.readAt
            timestampTitle = .batteryDetailsSystemReadAt
            unavailableTitle = details.powerAvailability == .collecting
                ? .batteryDetailsCollecting : .batteryDetailsUnavailable
            return
        }
        chargingWatts = isConnectedToPower
            ? details.power.flatMap { $0.watts > 0 ? $0.watts : nil }
            : nil
        if isConnectedToPower {
            title = .batteryDetailsSystemPower
            watts = details.systemPower?.watts
            timestamp = details.systemPower?.readAt
            timestampTitle = .batteryDetailsSystemReadAt
            unavailableTitle = .batteryDetailsUnavailable
        } else {
            // The view can see a power-source change before its appearance
            // task clears the preceding sample. Never relabel charging as discharge.
            let discharge = details.power.flatMap { $0.watts < 0 ? $0 : nil }
            title = .batteryDetailsDischarging
            watts = discharge.map { -$0.watts }
            timestamp = discharge?.updatedAt
            timestampTitle = .batteryDetailsSampled
            unavailableTitle = details.powerAvailability == .collecting || details.power != nil
                ? .batteryDetailsCollecting : .batteryDetailsUnavailable
        }
    }
}
