import AppKit
import SwiftUI

private enum PopoverPanel {
    case summary
    case battery
    case wifi(showDetails: Bool)
    case ethernet
}

struct StatusPopoverView: View {
    @ObservedObject var panel: StatusPanelViewModel
    let scrollTargets: PopoverScrollTargets
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let requestBluetoothAuthorization: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openNetworkSettings: () -> Void
    let openLocationSettings: () -> Void
    let openBluetoothSettings: () -> Void
    let openBluetoothPermissionSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void
    @State private var currentPanel: PopoverPanel = .summary

    var body: some View {
        Group {
            switch currentPanel {
            case .summary:
                summary
            case .battery:
                BatteryDetailsView(
                    state: panel.batteryDetails,
                    onBack: {
                        panel.actions.batteryDetailsClosed()
                        currentPanel = .summary
                    },
                    onOpenBatterySettings: openBatterySettings,
                    onCopyValue: { copyValue($0) },
                    onAppear: { panel.actions.batteryDetailsAppeared() }
                )
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    state: panel.wifiDetails,
                    onBack: {
                        panel.actions.wifiDetailsClosed()
                        currentPanel = .summary
                    },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    onSetPower: { panel.actions.setWiFiPower($0) },
                    onRefresh: { panel.actions.refreshWiFi() },
                    onCopyValue: { copyValue($0) },
                    showsDetailsInitially: showDetails
                )
            case .ethernet:
                EthernetLinkView(
                    state: panel.wiredDetails,
                    onBack: {
                        panel.actions.wiredDetailsClosed()
                        currentPanel = .summary
                    },
                    onOpenNetworkSettings: openNetworkSettings,
                    onCopyValue: { copyValue($0) }
                )
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(panel.visiblePopupSections) { section in
                popupSection(section)

                if section != panel.visiblePopupSections.last {
                    Divider()
                }
            }

            if !panel.visiblePopupSections.isEmpty {
                Divider()
                    .opacity(0.6)
                    .padding(.vertical, 2)
            }

            PopoverFooterView(openSettings: openSettings, quit: quit)
        }
    }

    @ViewBuilder
    private func popupSection(_ section: PopupSection) -> some View {
        switch section {
        case .battery:
            BatteryStatusView(
                state: panel.battery,
                cautionColor: .yellow,
                onOpenBatteryDetails: {
                    currentPanel = .battery
                },
                onOpenBatterySettings: openBatterySettings
            )
        case .network:
            NetworkStatusView(
                state: panel.network,
                onOpenWiFiDetails: { showDetails in
                    panel.actions.wifiDetailsOpened()
                    currentPanel = .wifi(showDetails: showDetails)
                },
                onOpenWiredDetails: {
                    panel.actions.wiredDetailsOpened()
                    currentPanel = .ethernet
                },
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenNetworkSettings: openNetworkSettings,
                onOpenLocationSettings: openLocationSettings
            )
        case .vpn:
            VPNStatusView(state: panel.vpn)
        case .bluetooth:
            BluetoothStatusView(
                controller: panel.store.bluetoothDevices,
                mobileBatteryController: panel.store.mobileBattery,
                showsBatteryLevels: panel.settings.showsBluetoothBatteryLevels,
                showsAppleDevicesAndBattery: panel.settings.showsAppleDevicesAndBattery,
                nearbyBLESelections: panel.settings.nearbyBLESelections,
                trustedAppleDeviceMetadata: panel.settings.trustedAppleDeviceMetadata,
                currentTrustedAppleCandidates: panel.store.trustedAppleDeviceCandidates,
                trustedDiscoveryGeneration: panel.store.trustedAppleDeviceDiscoveryGeneration,
                listOptions: panel.settings.bluetoothDeviceListOptions,
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings,
                onOpenBluetoothPermissionSettings: openBluetoothPermissionSettings
            )
        case .volume:
            VolumeControlsView(
                state: panel.volume,
                actions: panel.actions,
                scrollTargets: scrollTargets,
                onOpenSoundSettings: openSoundSettings
            )
        case .audioInput:
            AudioInputControlsView(
                state: panel.audioInput,
                actions: panel.actions,
                onOpenSoundSettings: openSoundSettings
            )
        }
    }

    private func copyValue(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
