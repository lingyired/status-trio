import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var panel: StatusPanelViewModel
    /// Observed so the Low Power Mode control appears the moment the helper is
    /// approved — reading `.isReady` off the shared manager without observing
    /// it left the control invisible until the popover was recreated.
    @ObservedObject private var helper: PrivilegedHelperManager = .shared
    let scrollTargets: PopoverScrollTargets
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let requestBluetoothAuthorization: () -> Void
    let openBatterySettings: () -> Void
    let openAppBatterySettings: () -> Void
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
    /// The footer's Actions menu closes the panel before opening another window.
    var dismissPanel: () -> Void = {}

    var body: some View {
        Group {
            switch panel.route {
            case .summary:
                summary
            case .battery:
                BatteryDetailsView(
                    state: panel.batteryDetails,
                    onBack: { panel.showSummaryPage() },
                    onOpenBatterySettings: openBatterySettings,
                    onOpenAppBatterySettings: openAppBatterySettings,
                    onCopyValue: { copyValue($0) },
                    onAppear: { panel.actions.batteryDetailsAppeared() },
                    lowPowerMode: panel.store.lowPowerMode,
                    showsLowPowerControl: panel.settings.controlsLowPowerMode
                        && helper.isReady,
                    chargeToFullNow: panel.chargeToFullNowPresentation,
                    onChargeToFullNow: { panel.actions.requestChargeToFullNow() }
                )
            case .wifi:
                WiFiNetworkListView(
                    state: panel.wifiDetails,
                    onBack: { panel.showSummaryPage() },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    onSetPower: { panel.actions.setWiFiPower($0) },
                    onRefresh: { panel.actions.refreshWiFi() },
                    onOpenSharingSettings: openSharingSettings,
                    onCopyValue: { copyValue($0) },
                    showsDetails: panel.wifiDisclosure.showsDetails,
                    showsMore: panel.wifiDisclosure.showsMore,
                    onSetShowsDetails: { panel.setWiFiShowsDetails($0) },
                    onSetShowsMore: { panel.setWiFiShowsMore($0) }
                )
            case .ethernet:
                EthernetLinkView(
                    state: panel.wiredDetails,
                    onBack: { panel.showSummaryPage() },
                    onOpenNetworkSettings: openNetworkSettings,
                    onOpenSharingSettings: openSharingSettings,
                    onCopyValue: { copyValue($0) }
                )
            case .inputSource:
                InputSourceListView(
                    state: panel.inputSource,
                    onBack: { panel.showSummaryPage() },
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

            PopoverFooterView(openSettings: openSettings, quit: quit, dismissPanel: dismissPanel)
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
                onOpenBatteryDetails: { panel.showBatteryPage() },
                onOpenBatterySettings: openBatterySettings,
                lowPowerMode: panel.store.lowPowerMode,
                showsLowPowerToggle: panel.settings.controlsLowPowerMode
                    && helper.isReady,
                chargeToFullNow: panel.summaryChargeToFullNowPresentation,
                onChargeToFullNow: {
                    panel.actions.requestChargeToFullNow()
                }
            )
        case .network:
            NetworkStatusView(
                state: panel.network,
                onOpenWiFiDetails: { panel.showWiFiPage(showsDetailsInitially: $0) },
                onOpenWiredDetails: { panel.showWiredPage() },
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
                onSelectListeningMode: { panel.actions.setListeningMode(address: $0, mode: $1) },
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings,
                onOpenBluetoothPermissionSettings: openBluetoothPermissionSettings,
                onSetRadioPower: { enabled in
                    panel.actions.setBluetoothPower(enabled)
                },
                layoutSnapshots: panel.layoutSnapshots
            )
        case .volume:
            VolumeControlsView(
                state: panel.volume,
                actions: panel.actions,
                scrollTargets: scrollTargets,
                onOpenSoundSettings: openSoundSettings
            )
        case .brightness:
            BrightnessControlsView(
                state: panel.brightness,
                actions: panel.actions
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
                onOpen: { panel.showInputSourcePage() },
                onOpenKeyboardSettings: openKeyboardSettings
            )
        }
    }

    private func copyValue(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
