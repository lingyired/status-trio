import Foundation

enum BatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    case charging
}

/// What fills the battery arc's top gap.
enum BatteryGapContent: Equatable, Sendable {
    /// Charging: the lightning bolt.
    case bolt
    /// Connected to power without charging: the plug.
    case plug
    /// The percentage numerals.
    case percentage
    /// Nothing: the arc closes into a full circle.
    case empty
}

enum WiFiSummaryAction: Equatable, Sendable {
    case openDetails
    case requestNameAccess
    case openLocationSettings
}

enum StatusMappings {
    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        // Parentheses are required for this negative partial range in Swift 6.
        case (-60)...:
            return 3
        case -78 ... -61:
            return 2
        case -88 ... -79:
            return 1
        default:
            return 0
        }
    }

    static func wifiSummaryAction(for wifi: WiFiStatus) -> WiFiSummaryAction {
        guard wifi.state.isNetworkAssociated else { return .openDetails }

        switch wifi.nameAccess {
        case .authorized:
            return .openDetails
        case .notDetermined:
            return .requestNameAccess
        case .denied, .restricted:
            return .openLocationSettings
        }
    }

    static func volumeSteps(scalar: Double?, isMuted: Bool) -> Int? {
        guard let scalar else { return nil }
        let clamped = min(1, max(0, scalar))
        if isMuted || clamped == 0 { return 0 }
        if clamped <= 0.25 { return 1 }
        if clamped <= 0.50 { return 2 }
        if clamped <= 0.75 { return 3 }
        return 4
    }

    static func batteryColorRole(
        _ battery: BatteryStatus,
        criticalThreshold: Int = 20
    ) -> BatteryColorRole {
        let threshold = min(100, max(0, criticalThreshold))
        if battery.percentage < threshold { return .critical }
        if battery.isLowPowerMode { return .lowPower }
        if battery.isCharging || battery.isConnectedToPower { return .charging }
        return .foreground
    }

    /// A charging battery keeps the bolt. A connected power source that is not
    /// charging — including a battery that is already full — shows the plug,
    /// or the percentage when the user asked for the number in that state and
    /// the percentage is available at all.
    static func batteryGapContent(
        _ battery: BatteryStatus,
        options: BatteryIconOptions
    ) -> BatteryGapContent {
        if battery.isPresent, options.showsChargingIndicator {
            if battery.isCharging { return .bolt }
            let showsPercentageForPower = options.showsPercentageWhenConnected
                && options.showsPercentage
            if battery.isConnectedToPower, !showsPercentageForPower {
                return .plug
            }
        }

        return options.showsPercentage ? .percentage : .empty
    }

    /// How far around the ring the battery arc is drawn.
    ///
    /// The arc is measured against `fullThreshold`, not against a fixed 100%,
    /// so a level-limited battery can close the ring at the level the user
    /// picked (#105). `fullThreshold` defaults to 100 and therefore keeps the
    /// raw-percentage behaviour for every caller with no opinion of its own.
    static func batteryProgress(
        _ battery: BatteryStatus,
        fullThreshold: Int = BatteryIconOptions.defaultFullThreshold
    ) -> Double {
        let threshold = min(100, max(1, fullThreshold))
        return min(1, max(0, Double(battery.percentage) / Double(threshold)))
    }

    static func shouldReplaceNetworkIcon(
        currentDevice: AudioOutputDevice?,
        wifi: WiFiStatus,
        connection: NetworkConnection,
        options: BluetoothAudioIconOptions
    ) -> Bool {
        guard options.replacesNetworkIcon else { return false }

        // A picked device pins the glyph, so the current output is irrelevant
        // to the decision. Without one, the replacement still requires the
        // current output to be Bluetooth audio.
        if options.networkIconSymbolOverride == nil {
            guard currentDevice?.transport == .bluetooth
                    || currentDevice?.transport == .bluetoothLowEnergy else {
                return false
            }
        }

        guard options.prioritizesNetworkErrors else { return true }

        // A wired connection is not a Wi-Fi error and can still coexist with
        // Bluetooth audio.
        if connection == .offline { return false }
        return !wifi.state.isBluetoothReplacementNetworkError
    }

    /// Whether the machine is genuinely offline right now.
    ///
    /// Shares the Wi-Fi error vocabulary with the Bluetooth replacement rule,
    /// with one deliberate difference: a live wired (or otherwise connected)
    /// link is never an outage. A wired user with Wi-Fi switched off is online,
    /// so their input-source icon must not be displaced by a Wi-Fi error.
    static func isNetworkOffline(
        wifi: WiFiStatus,
        connection: NetworkConnection
    ) -> Bool {
        switch connection {
        case .ethernet, .other:
            return false
        case .offline:
            return true
        case .wifi, .unknown:
            return wifi.state.isBluetoothReplacementNetworkError
        }
    }
}

private extension WiFiState {
    var isBluetoothReplacementNetworkError: Bool {
        switch self {
        case .notAssociated, .noInternet, .off, .unavailable:
            true
        case .connected, .hotspot, .temporary, .shared:
            false
        }
    }
}
