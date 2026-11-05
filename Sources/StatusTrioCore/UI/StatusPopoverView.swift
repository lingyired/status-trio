import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var panel: StatusPanelViewModel
    /// Observed so the Low Power Mode control appears the moment the helper is
    /// approved — reading `.isReady` off the shared manager without observing
    /// it left the control invisible until the popover was recreated.
    @ObservedObject private var helper: PrivilegedHelperManager = .shared
    let scrollTargets: PopoverScrollTargets
    /// The panel window's current height budget (#237). The content caps and
    /// scrolls itself at the same number the window uses, so the two never
    /// disagree about how tall the panel may get.
    @ObservedObject var layoutMetrics: StatusPanelLayoutMetrics
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
    var openDisplaySettings: () -> Void = {}
    let openKeyboardSettings: () -> Void
    let quit: () -> Void
    /// The footer's Actions menu closes the panel before opening another window.
    var dismissPanel: () -> Void = {}

    var body: some View {
        // One scroll surface for every route (#237). The area measures the page
        // at its natural height and only scrolls once the screen budget cannot
        // hold it, so a short page still hugs its content. The summary footer
        // stays outside the scroll view so it is always reachable.
        StatusPanelScrollArea(maximumHeight: layoutMetrics.maximumPanelHeight) {
            routeContent
                // Inside the panel there must be exactly one scroller. The
                // detail pages and Bluetooth lists keep their own scroll views
                // for other hosts, but disable them here.
                .environment(\.statusPanelManagesScrolling, true)
                .environment(\.airPodsConversationCache, panel.store.airPodsConversationCache)
        } footer: {
            if panel.route == .summary {
                pinnedFooter
            }
        }
        .frame(width: 330)
    }

    /// The current route, inset for the panel's fixed width.
    ///
    /// The bottom inset is 12pt when the summary's pinned footer follows, which
    /// reproduces the old in-page `VStack` spacing before the footer's rule.
    private var routeContent: some View {
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
                    highPowerMode: panel.store.highPowerMode,
                    showsHighPowerControl: panel.settings.controlsLowPowerMode
                        && helper.isReady,
                    isConnectedToPower:
                        panel.store.popupSnapshot.battery.isConnectedToPower,
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
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, routeBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The gap between the route content and the pinned footer. The summary
    /// keeps 12pt so the footer's rule sits where the old in-page spacing put
    /// it; an empty summary lets the footer own the whole inset.
    private var routeBottomPadding: CGFloat {
        guard panel.route == .summary else { return 14 }
        return displayedSections.isEmpty ? 0 : 12
    }

    private var summary: some View {
        let sections = displayedSections
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                popupSection(section)

                if section != sections.last {
                    Divider()
                }
            }
        }
        // The volume device list is summary-only: keep its lifecycle tied to
        // this page so leaving for a detail route stops it, while scrolling a
        // long summary does not.
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

    /// The summary sections actually rendered: the brightness section is
    /// dropped when every display is hidden, so no empty section or dangling
    /// separator is left behind (#241).
    private var displayedSections: [PopupSection] {
        panel.displayedSummarySections
    }

    /// The footer only renders on the summary route, so its rule follows the
    /// sections that are actually drawn. When every section is hidden the rule
    /// would otherwise sit over an empty page.
    private var showsFooterRule: Bool {
        !displayedSections.isEmpty
    }

    /// The summary footer, pinned to the panel's bottom edge (#237).
    private var pinnedFooter: some View {
        VStack(spacing: 12) {
            if showsFooterRule {
                Divider()
                    .opacity(0.6)
                    .padding(.vertical, 2)
            }

            PopoverFooterView(openSettings: openSettings, quit: quit, dismissPanel: dismissPanel)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
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
                highPowerMode: panel.store.highPowerMode,
                isConnectedToPower:
                    panel.store.popupSnapshot.battery.isConnectedToPower,
                chargeToFullNow: panel.summaryChargeToFullNowPresentation,
                onChargeToFullNow: {
                    panel.actions.requestChargeToFullNow()
                }
            )
        case .network:
            WiFiPowerSummaryView(panel: panel,
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
                listeningModePresentations: panel.settings.showsBluetoothListeningMode
                    ? panel.store.bluetoothListeningModes.huaweiBluetoothRowPresentations
                    : [:],
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
            VolumeControlsSection(
                model: panel.volumeControl,
                actions: panel.actions,
                scrollTargets: scrollTargets,
                onOpenSoundSettings: openSoundSettings
            )
        case .brightness:
            BrightnessControlsView(
                state: panel.brightness,
                actions: panel.actions,
                scrollTargets: scrollTargets,
                onOpenDisplaySettings: openDisplaySettings
            )
        case .audioInput:
            AudioInputControlsView(
                state: panel.audioInput,
                actions: panel.actions,
                scrollTargets: scrollTargets,
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

private struct WiFiPowerSummaryView: View {
    @ObservedObject var panel: StatusPanelViewModel
    @ObservedObject private var store: SystemStatusStore
    let state: PanelSummaryState
    let onOpenWiFiDetails: (Bool) -> Void
    let onOpenWiredDetails: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    init(panel: StatusPanelViewModel, state: PanelSummaryState, onOpenWiFiDetails: @escaping (Bool) -> Void, onOpenWiredDetails: @escaping () -> Void, onRequestNameAccess: @escaping () -> Void, onOpenWiFiSettings: @escaping () -> Void, onOpenNetworkSettings: @escaping () -> Void, onOpenLocationSettings: @escaping () -> Void) {
        self.panel = panel
        self.store = panel.store
        self.state = state
        self.onOpenWiFiDetails = onOpenWiFiDetails
        self.onOpenWiredDetails = onOpenWiredDetails
        self.onRequestNameAccess = onRequestNameAccess
        self.onOpenWiFiSettings = onOpenWiFiSettings
        self.onOpenNetworkSettings = onOpenNetworkSettings
        self.onOpenLocationSettings = onOpenLocationSettings
    }

    var body: some View {
        NetworkStatusView(
            showsWiFiPowerControl: WiFiPowerControlVisibility.showsSummaryToggle(
                state: store.popupSnapshot.wifi.state,
                isEnabled: panel.settings.showsWiFiPowerControl
            ),
            wifiPowerIsOn: WiFiPowerControlVisibility.isRadioOn(state: store.popupSnapshot.wifi.state),
            wifiPowerCanSet: !store.wifiPowerIsChanging,
            wifiPowerRequiresConfirmation: WiFiPowerTogglePolicy.requiresConfirmation(
                for: store.popupSnapshot.wifi.state
            ),
            wifiPowerFailed: store.wifiPowerFailed,
            onSetWiFiPower: { store.setWiFiPower($0) },
            state: state, onOpenWiFiDetails: onOpenWiFiDetails, onOpenWiredDetails: onOpenWiredDetails,
            onRequestNameAccess: onRequestNameAccess, onOpenWiFiSettings: onOpenWiFiSettings,
            onOpenNetworkSettings: onOpenNetworkSettings, onOpenLocationSettings: onOpenLocationSettings
        )
    }
}
