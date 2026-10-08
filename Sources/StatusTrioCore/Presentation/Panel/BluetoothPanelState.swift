import Foundation

struct PanelBluetoothDeviceRow: Equatable, Sendable {
    let address: String
    let title: String
    let subtitle: String?
    let icon: IconSymbolSource
    let batteryText: String?
    let batteryLayout: BluetoothBatteryLayout
    let batterySegments: [BluetoothBatterySegment]?
    let isConnected: Bool
    let isActionable: Bool
    let status: BluetoothDeviceRowStatus
    let statusText: String?
    let statusTint: PanelTint
    let requiresConfirmation: Bool
    let actionTitle: String
    let actionEnabled: Bool
    let isBusy: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
}

struct BluetoothPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let summaryBatterySegments: [BluetoothBatterySegment]?
    let hasConnectedDevices: Bool
    let batteryReadTaskID: String
    let pairedRows: [PanelBluetoothDeviceRow]
    let nearbyRows: [PanelBluetoothDeviceRow]
    let errorText: String?
    let showsPairedHeading: Bool
    let canExpand: Bool
    let confirmationAddress: String?
    let showsBatteryLevels: Bool
    let showsNearbyBatteryDevices: Bool
}
