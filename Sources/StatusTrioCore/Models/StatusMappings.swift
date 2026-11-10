import Foundation

enum BatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    /// The system is in High Power Mode (#235). Mutually exclusive with
    /// `lowPower`; it wins over `charging` because High Power Mode is itself a
    /// connected-power state.
    case highPower
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

enum StatusMappings {
    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        // Parentheses are required for this negative partial range in Swift 6.
        case (-70)...:
            return 3
        case -78 ... -71:
            return 2
        case -88 ... -79:
            return 1
        default:
            return 0
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
        criticalThreshold: Int = 20,
        isHighPowerMode: Bool = false,
        /// A battery-less Mac is always on AC power, so its decorative ring still
        /// reflects the "connected to power" colour (#309). Charging and
        /// Low/High Power Mode keep their usual precedence.
        treatAsConnected: Bool = false,
        /// When on, the charging / connected-to-power state draws in the plain
        /// foreground colour instead of the charging colour (#309). Low, High
        /// Power Mode and critical keep their own colours.
        monochromeCharging: Bool = false
    ) -> BatteryColorRole {
        let threshold = min(100, max(0, criticalThreshold))
        if battery.percentage < threshold { return .critical }
        if battery.isLowPowerMode { return .lowPower }
        if isHighPowerMode { return .highPower }
        if battery.isCharging || battery.isConnectedToPower || treatAsConnected {
            return monochromeCharging ? .foreground : .charging
        }
        return .foreground
    }

    /// Each power state carries its own top-gap marker (#315): a charging
    /// battery, a connected-but-not-charging one, and plain battery use can each
    /// show the percentage, the bolt, the plug, or nothing. A battery-less Mac
    /// has no real level, so its decorative plug/bolt is drawn from
    /// `noBatteryMarker` and a percentage choice falls back to the plug.
    static func batteryGapContent(
        _ battery: BatteryStatus,
        options: BatteryIconOptions
    ) -> BatteryGapContent {
        let marker: BatteryTopMarker
        if !battery.isPresent {
            marker = options.noBatteryMarker
        } else if battery.isCharging {
            marker = options.chargingMarker
        } else if battery.isConnectedToPower {
            marker = options.connectedMarker
        } else {
            marker = options.onBatteryMarker
        }

        switch marker {
        case .percentage:
            // A battery-less Mac never claims the placeholder 100% as a number.
            return battery.isPresent ? .percentage : .plug
        case .bolt:
            return .bolt
        case .plug:
            return .plug
        case .hidden:
            return .empty
        }
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

    /// Availability only; source selection and outage priority belong to the scene.
    static func canShowBluetoothIcon(
        currentDevice: AudioOutputDevice?,
        options: BluetoothAudioIconOptions
    ) -> Bool {
        options.networkIconSymbolOverride != nil
            || currentDevice?.transport == .bluetooth
            || currentDevice?.transport == .bluetoothLowEnergy
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
