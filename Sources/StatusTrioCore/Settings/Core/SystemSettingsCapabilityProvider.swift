import Foundation

/// Capability availability read from cheap, already-available signals.
///
/// It never starts device sampling to answer a schema query: unknown capabilities
/// stay `unknown` (which callers must not treat as "unsupported"). Callers may
/// pass explicit overrides for a session.
struct SystemSettingsCapabilityProvider: SettingsCapabilityProvider {
    var overrides: [String: SettingsCapabilityDescriptor.Availability] = [:]

    func availability(for capabilityID: String) -> SettingsCapabilityDescriptor.Availability {
        if let override = overrides[capabilityID] { return override }
        switch capabilityID {
        case "ui.liquidGlass":
            return PanelBackgroundStyle.isLiquidGlassAvailable ? .available : .unavailable
        default:
            return .unknown
        }
    }
}
