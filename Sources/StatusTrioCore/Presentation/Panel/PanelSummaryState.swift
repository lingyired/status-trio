import Foundation

enum PanelTint: Equatable, Sendable {
    case primary
    case secondary
    case positive
    case caution
    case critical
}

enum PanelSummaryIntent: Equatable, Sendable {
    case none
    case batteryDetails
    case wifiDetails
    case requestWiFiNameAccess
    case locationSettings
    case wiredDetails
    case requestBluetoothAuthorization
    case openBluetoothPermissionSettings
}

struct PanelSummaryState: Equatable, Sendable {
    let title: String
    let subtitle: String
    let measurements: String?
    let symbol: IconSymbolSource
    let tint: PanelTint
    let accessibilityLabel: String
    let accessibilityValue: String
    let showsSettings: Bool
    let intent: PanelSummaryIntent
}
