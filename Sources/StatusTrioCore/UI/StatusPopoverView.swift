import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var panel: StatusPanelViewModel
    @StateObject private var submenus = CascadingSubmenuCoordinator()
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
        // The summary stays mounted while details open alongside it. Each
        // window owns one capped scroll surface; the main footer stays pinned.
        StatusPanelScrollArea(maximumHeight: layoutMetrics.maximumPanelHeight) {
            summary
                .padding(.top, 14)
                .padding(.horizontal, 14)
                .padding(.bottom, displayedSections.isEmpty ? 0 : 12)
                // Inside the panel there must be exactly one scroller. The
                // detail pages and Bluetooth lists keep their own scroll views
                // for other hosts, but disable them here.
                .environment(\.statusPanelManagesScrolling, true)
        } footer: {
            pinnedFooter
        }
        .frame(width: 330)
        .environment(\.cascadingSubmenuCoordinator, submenus)
    }

    /// Existing detail content, hosted by the active entry's child window.
    private var routeContent: some View {
        Group {
            switch panel.route {
            case .summary:
                EmptyView()
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailBinding(_ route: StatusPanelRoute) -> Binding<Bool> {
        Binding(get: { panel.route == route }, set: { presented in
            if presented {
                switch route {
                case .battery: panel.showBatteryPage()
                case .wifi: panel.showWiFiPage(showsDetailsInitially: NSEvent.modifierFlags.contains(.option))
                case .ethernet: panel.showWiredPage()
                case .inputSource: panel.showInputSourcePage()
                case .summary: break
                }
            } else if !submenus.isClosingParent, panel.route == route {
                panel.showSummaryPage()
            }
        })
    }

    private var networkDetailBinding: Binding<Bool> {
        let route: StatusPanelRoute = panel.network.intent == .wiredDetails ? .ethernet : .wifi
        let binding = detailBinding(route)
        return Binding(get: { binding.wrappedValue }, set: { presented in
            guard !presented || panel.network.intent == .wiredDetails || panel.network.intent == .wifiDetails else { return }
            binding.wrappedValue = presented
        })
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
        // Main controls remain visible while a child is open, so their demand
        // stays tied to the main panel rather than the selected detail route.
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
            .cascadingSubmenu(isPresented: detailBinding(.battery), backgroundStyle: panel.settings.panelBackgroundStyle) {
                routeContent
            }
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
            .cascadingSubmenu(isPresented: networkDetailBinding, backgroundStyle: panel.settings.panelBackgroundStyle) {
                routeContent
            }
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
            .cascadingSubmenu(isPresented: detailBinding(.inputSource), backgroundStyle: panel.settings.panelBackgroundStyle) {
                routeContent
            }
        }
    }

    private func copyValue(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
