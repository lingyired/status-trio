import Foundation

/// The outcome of pressing the Wi-Fi summary row's power control.
enum WiFiPowerToggleDecision: Equatable, Sendable {
    /// Write the requested radio state directly.
    case set(Bool)
    /// Ask before turning the radio off.
    case confirmOff
}

enum WiFiPowerTogglePolicy {
    /// Turning the radio off while a network is associated asks first; the
    /// Bluetooth radio uses the same rule for connected peripherals. Every
    /// associated state counts, not just a healthy link: a no-internet,
    /// temporary or shared (Internet Sharing) association still drops when the
    /// radio goes off.
    ///
    /// `confirmsPowerOff` mirrors the user's "Confirm Before Turning Off Wi-Fi"
    /// setting (#305): when they turn it off, every associated state switches
    /// off directly too. The unassociated states never asked in the first
    /// place, so they are unaffected either way.
    static func requiresConfirmation(for state: WiFiState, confirmsPowerOff: Bool = true) -> Bool {
        guard confirmsPowerOff else { return false }
        return state.isNetworkAssociated
    }

    static func decision(isOn: Bool, requiresConfirmation: Bool) -> WiFiPowerToggleDecision {
        if isOn && requiresConfirmation { return .confirmOff }
        return .set(!isOn)
    }

    /// VoiceOver must hear what the button will do, not the state it is in.
    @MainActor
    static func accessibilityLabel(isOn: Bool, localization: Localization) -> String {
        localization.string(isOn ? .wifiPowerTurnOff : .wifiPowerTurnOn)
    }

    @MainActor
    static func accessibilityValue(isOn: Bool, localization: Localization) -> String {
        localization.string(isOn ? .batteryDetailsOn : .batteryDetailsOff)
    }
}

enum WiFiPowerControlVisibility {
    /// No Wi-Fi hardware means there is no radio to switch, so neither the
    /// Settings toggle nor the summary control is offered.
    static func canConfigure(state: WiFiState) -> Bool {
        state != .unavailable
    }

    static func showsSettingsControl(state: WiFiState) -> Bool {
        canConfigure(state: state)
    }

    static func showsSummaryToggle(state: WiFiState, isEnabled: Bool) -> Bool {
        isEnabled && canConfigure(state: state)
    }

    /// The summary row carries the radio control for every Wi-Fi intent,
    /// including the permission rows. Granting location access is only about
    /// reading the network name; switching the radio never needs it, so hiding
    /// the control there would take away the in-panel power switch.
    static func showsSummaryToggle(intent: PanelSummaryIntent, isEnabled: Bool) -> Bool {
        isEnabled && isWiFiSummaryIntent(intent)
    }

    /// A failed write is only reported on a row that offered the control, so the
    /// message never appears without the button that caused it.
    static func showsFailureMessage(
        intent: PanelSummaryIntent,
        isEnabled: Bool,
        failed: Bool
    ) -> Bool {
        failed && showsSummaryToggle(intent: intent, isEnabled: isEnabled)
    }

    private static func isWiFiSummaryIntent(_ intent: PanelSummaryIntent) -> Bool {
        switch intent {
        case .wifiDetails, .requestWiFiNameAccess, .locationSettings:
            return true
        case .none, .batteryDetails, .wiredDetails,
             .requestBluetoothAuthorization, .openBluetoothPermissionSettings:
            return false
        }
    }

    /// The radio is on for every state except an explicit `.off`; `.unavailable`
    /// never reaches the toggle because `canConfigure` hides it first.
    static func isRadioOn(state: WiFiState) -> Bool {
        state != .off
    }
}
