import AppKit
import SwiftUI

private enum PopoverPanel {
    case summary
    case battery
    case wifi(showDetails: Bool)
    case ethernet
    case inputSource
}

struct StatusPopoverView: View {
    @ObservedObject var panel: StatusPanelViewModel
    /// Observed so the Low Power Mode control appears the moment the helper is
    /// approved — reading `.isReady` off the shared manager without observing
    /// it left the control invisible until the popover was recreated.
    @ObservedObject var helper: PrivilegedHelperFacade
    let capabilityPolicy: DistributionCapabilityPolicy
    let scrollTargets: PopoverScrollTargets
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let requestBluetoothAuthorization: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openNetworkSettings: () -> Void
    let openSharingSettings: () -> Void
    let openLocationSettings: () -> Void
    let openBluetoothSettings: () -> Void
    let openBluetoothPermissionSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let openSoundInputSettings: () -> Void
    let openKeyboardSettings: () -> Void
    let quit: () -> Void
    @State private var currentPanel: PopoverPanel = .summary

    init(
        panel: StatusPanelViewModel,
        helper: PrivilegedHelperFacade = PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault,
        scrollTargets: PopoverScrollTargets,
        requestWiFiNameAccess: @escaping () -> Void,
        requestBluetoothAuthorization: @escaping () -> Void,
        openBatterySettings: @escaping () -> Void,
        openWiFiSettings: @escaping () -> Void,
        openNetworkSettings: @escaping () -> Void,
        openSharingSettings: @escaping () -> Void,
        openLocationSettings: @escaping () -> Void,
        openBluetoothSettings: @escaping () -> Void,
        openBluetoothPermissionSettings: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openSoundSettings: @escaping () -> Void,
        openSoundInputSettings: @escaping () -> Void,
        openKeyboardSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.panel = panel
        self.helper = helper
        self.capabilityPolicy = capabilityPolicy
        self.scrollTargets = scrollTargets
        self.requestWiFiNameAccess = requestWiFiNameAccess
        self.requestBluetoothAuthorization = requestBluetoothAuthorization
        self.openBatterySettings = openBatterySettings
        self.openWiFiSettings = openWiFiSettings
        self.openNetworkSettings = openNetworkSettings
        self.openSharingSettings = openSharingSettings
        self.openLocationSettings = openLocationSettings
        self.openBluetoothSettings = openBluetoothSettings
        self.openBluetoothPermissionSettings = openBluetoothPermissionSettings
        self.openSettings = openSettings
        self.openSoundSettings = openSoundSettings
        self.openSoundInputSettings = openSoundInputSettings
        self.openKeyboardSettings = openKeyboardSettings
        self.quit = quit
    }

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
                    onAppear: { panel.actions.batteryDetailsAppeared() },
                    lowPowerMode: panel.store.lowPowerMode,
                    showsLowPowerControl: panel.settings.controlsLowPowerMode
                        && !capabilityPolicy.blocksControl(.privilegedHelper)
                        && helper.isReady
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
                    onOpenSharingSettings: openSharingSettings,
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
                    onOpenSharingSettings: openSharingSettings,
                    onCopyValue: { copyValue($0) }
                )
            case .inputSource:
                InputSourceListView(
                    state: panel.inputSource,
                    onBack: { currentPanel = .summary },
                    onSelect: { panel.actions.selectInputSource($0) },
                    onOpenKeyboardSettings: openKeyboardSettings
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
        .task(id: [
            panel.listeningModeTaskID,
            String(panel.visiblePopupSections.contains(.bluetooth)),
            String(panel.visiblePopupSections.contains(.volume))
        ]) {
            if panel.store.isPopoverVisible,
               panel.visiblePopupSections.contains(.bluetooth) || panel.visiblePopupSections.contains(.volume) {
                panel.actions.volumeListChanged()
            } else {
                panel.actions.volumeListDisappeared()
            }
        }
        .onDisappear { panel.actions.volumeListDisappeared() }
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
                onOpenBatterySettings: openBatterySettings,
                lowPowerMode: panel.store.lowPowerMode,
                showsLowPowerToggle: panel.settings.controlsLowPowerMode
                    && !capabilityPolicy.blocksControl(.privilegedHelper)
                    && helper.isReady
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
                radioPower: panel.store.bluetoothPower,
                mobileBatteryController: panel.store.mobileBattery,
                showsBatteryLevels: panel.settings.showsBluetoothBatteryLevels,
                showsAppleDevicesAndBattery: panel.settings.showsAppleDevicesAndBattery,
                nearbyBLESelections: panel.settings.nearbyBLESelections,
                trustedAppleDeviceMetadata: panel.settings.trustedAppleDeviceMetadata,
                currentTrustedAppleCandidates: panel.store.trustedAppleDeviceCandidates,
                trustedDiscoveryGeneration: panel.store.trustedAppleDeviceDiscoveryGeneration,
                listOptions: panel.settings.bluetoothDeviceListOptions,
                showsRadioPowerControl: panel.settings.showsBluetoothPowerControl,
                showsBluetoothInStatusPanel: panel.settings.enabledPopupSections.contains(.bluetooth),
                listeningModePresentations: panel.store.bluetoothListeningModes.huaweiBluetoothRowPresentations,
                capabilityPolicy: capabilityPolicy,
                onSelectListeningMode: { panel.actions.setListeningMode(address: $0, mode: $1) },
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings,
                onOpenBluetoothPermissionSettings: openBluetoothPermissionSettings,
                onSetRadioPower: { enabled in
                    panel.actions.setBluetoothPower(enabled)
                }
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
                onOpenSoundSettings: openSoundInputSettings
            )
        case .inputSource:
            InputSourceStatusView(
                state: panel.inputSource,
                onOpen: { currentPanel = .inputSource },
                onOpenKeyboardSettings: openKeyboardSettings
            )
        }
    }

    private func copyValue(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
