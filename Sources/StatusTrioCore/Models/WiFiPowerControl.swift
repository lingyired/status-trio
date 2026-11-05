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
    /// Bluetooth radio uses the same rule for connected peripherals.
    static func requiresConfirmation(for state: WiFiState) -> Bool {
        state == .connected || state == .hotspot
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

    /// The radio is on for every state except an explicit `.off`; `.unavailable`
    /// never reaches the toggle because `canConfigure` hides it first.
    static func isRadioOn(state: WiFiState) -> Bool {
        state != .off
    }
}
