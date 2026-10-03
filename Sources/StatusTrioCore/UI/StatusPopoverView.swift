import SwiftUI

@MainActor
enum StatusPresentation {
    static let statusItemAccessibilityLabel = "Status Trio"

    static func statusItemAccessibilityValue(
        _ snapshot: StatusSnapshot,
        localization: Localization
    ) -> String {
        statusItemAccessibilityValue(
            MenuBarStatus(snapshot: snapshot),
            localization: localization
        )
    }

    static func statusItemAccessibilityValue(
        _ status: MenuBarStatus,
        localization: Localization
    ) -> String {
        let battery = status.battery
        let batterySummary: String
        if battery.isPresent {
            let percentage = localization.format(
                .batteryAccessibilityValue,
                battery.percentage
            )
            let subtitle = batterySubtitle(battery, localization: localization)
            if isOrdinaryBatteryState(battery) {
                batterySummary = percentage
            } else {
                batterySummary = localization.format(
                    .commonParenthetical,
                    percentage,
                    subtitle
                )
            }
        } else {
            batterySummary = localization.string(.batteryStateNotPresent)
        }

        let networkSummary = status.connection == .ethernet
            ? localization.string(.ethernetAccessibilityConnected)
            : wifiAccessibilitySummary(status.wifi, localization: localization)
        let volumeSummary = localization.format(
            .accessibilityVolume,
            volumeValue(status.volume, localization: localization)
        )

        return localization.format(
            .accessibilityStatus,
            batterySummary,
            networkSummary,
            volumeSummary
        )
    }

    static func batteryTitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        localization.format(.batteryTitle, battery.percentage)
    }

    static func batteryTimeToFullText(
        minutes: Int?,
        localization: Localization
    ) -> String {
        guard let minutes, minutes > 0 else {
            return localization.string(.batteryStateCalculatingTimeToFull)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return localization.format(
                .batteryTimeToFullMinutes,
                remainingMinutes
            )
        }
        if remainingMinutes == 0 {
            return localization.format(.batteryTimeToFullHours, hours)
        }
        return localization.format(
            .batteryTimeToFullHoursMinutes,
            hours,
            remainingMinutes
        )
    }

    static func batterySubtitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        if !battery.isPresent {
            return localization.string(.batteryStateNotPresent)
        }
        if battery.isCharged {
            return localization.string(.batteryStateCharged)
        }
        if battery.isCharging {
            return batteryTimeToFullText(
                minutes: battery.timeToFullChargeMinutes,
                localization: localization
            )
        }
        if battery.isLowPowerMode {
            return localization.string(.batteryStateLowPowerMode)
        }
        if battery.isConnectedToPower {
            return localization.string(.batteryStateConnectedToPower)
        }
        return localization.string(.batteryStateOnBattery)
    }

    static func wifiValue(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        switch wifi.state {
        case .connected:
            return localization.format(
                .wifiValueBars,
                StatusMappings.wifiBars(rssi: wifi.rssi)
            )
        case .notAssociated:
            return localization.string(.wifiValueNotAssociated)
        case .off:
            return localization.string(.wifiValueOff)
        case .noInternet:
            return localization.string(.wifiValueNoInternet)
        case .hotspot:
            return localization.string(.wifiValueHotspot)
        case .temporary:
            return localization.string(.wifiValueTemporary)
        case .shared:
            return localization.string(.wifiValueShared)
        case .unavailable:
            return localization.string(.wifiValueUnavailable)
        }
    }

    static func wifiSubtitle(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid
        }

        switch wifi.state {
        case .connected:
            return localization.string(.wifiSubtitleConnected)
        case .notAssociated:
            return localization.string(.wifiSubtitleNotAssociated)
        case .off:
            return localization.string(.wifiSubtitleOff)
        case .noInternet:
            return localization.string(.wifiSubtitleNoInternet)
        case .hotspot:
            return localization.string(.wifiSubtitleHotspot)
        case .temporary:
            return localization.string(.wifiSubtitleTemporary)
        case .shared:
            return localization.string(.wifiSubtitleShared)
        case .unavailable:
            return localization.string(.wifiSubtitleUnavailable)
        }
    }

    static func volumeTitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volumeTitle(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    /// The row's leading text: the VPN service name when the system has one
    /// connected, `VPN` when only an interface was found, and the proxy label
    /// when a proxy is the only thing up.
    static func vpnTitle(
        _ vpn: VPNStatus,
        localization: Localization
    ) -> String {
        if let serviceName = vpn.serviceName, !serviceName.isEmpty {
            return serviceName
        }
        if vpn.isTunnelConnected {
            return localization.string(.vpnTitle)
        }
        if vpn.proxy != nil {
            return localization.string(.vpnSubtitleSystemProxy)
        }
        return localization.string(.vpnTitle)
    }

    /// The row's detail: the tunnel verdict, the proxy endpoint, or both when a
    /// tunnel and a proxy are up together.
    static func vpnSubtitle(
        _ vpn: VPNStatus,
        localization: Localization
    ) -> String {
        if vpn.isTunnelConnected {
            guard let endpoint = vpn.proxy?.endpoint else {
                return localization.string(.vpnValueConnected)
            }
            return localization.format(.vpnSubtitleConnectedWithProxy, endpoint)
        }
        guard let proxy = vpn.proxy else {
            return localization.string(.vpnValueDisconnected)
        }
        // A PAC-driven proxy has no endpoint to print, so it names its kind.
        return proxy.endpoint ?? localization.string(.vpnSubtitleProxyAutomatic)
    }

    static func volumeTitle(
        _ volume: MenuBarVolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else {
            return localization.string(.volumeTitleUnavailable)
        }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        return localization.format(.volumeTitle, percentage)
    }

    static func volumeValue(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volumeValue(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    static func volumeValue(
        _ volume: MenuBarVolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else { return "—" }
        let clampedScalar = min(1, max(0, scalar))
        let percentage = Int((clampedScalar * 100).rounded())
        if volume.isMuted {
            return localization.string(.volumeMuted)
        }
        let steps = StatusMappings.volumeSteps(
            scalar: clampedScalar,
            isMuted: volume.isMuted
        ) ?? 0
        return localization.format(.volumeValue, percentage, steps)
    }

    static func volumeSubtitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volume.deviceName ?? localization.string(.volumeNoDefaultDevice)
    }

    private static func wifiAccessibilitySummary(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        let value = wifiValue(wifi, localization: localization)
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return localization.format(.wifiAccessibilityWithSSID, ssid, value)
        }
        return localization.format(
            .commonLabelValue,
            localization.string(.wifiTitle),
            value
        )
    }

    private static func isOrdinaryBatteryState(_ battery: BatteryStatus) -> Bool {
        battery.isPresent
            && !battery.isCharged
            && !battery.isCharging
            && !battery.isLowPowerMode
            && !battery.isConnectedToPower
    }
}


private enum PopoverPanel {
    case summary
    case battery
    case wifi(showDetails: Bool)
    case ethernet
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
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
    @State private var panel: PopoverPanel = .summary

    var body: some View {
        Group {
            switch panel {
            case .summary:
                summary
            case .battery:
                BatteryDetailsView(
                    controller: store.batteryDetails,
                    battery: store.popupSnapshot.battery,
                    onBack: {
                        store.closeBatteryDetails()
                        panel = .summary
                    },
                    onOpenBatterySettings: openBatterySettings
                )
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    controller: store.wifiNetworks,
                    wifi: store.popupSnapshot.wifi,
                    onBack: {
                        store.closeWiFiDetails()
                        panel = .summary
                    },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    showsDetailsInitially: showDetails
                )
            case .ethernet:
                EthernetLinkView(
                    primaryLink: store.primaryLink,
                    onBack: {
                        store.closePrimaryLinkPanel()
                        panel = .summary
                    },
                    onOpenNetworkSettings: openNetworkSettings
                )
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(settings.visiblePopupSections) { section in
                popupSection(section)

                if section != settings.visiblePopupSections.last {
                    Divider()
                }
            }

            if !settings.visiblePopupSections.isEmpty {
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
                battery: store.popupSnapshot.battery,
                onOpenBatteryDetails: { panel = .battery },
                onOpenBatterySettings: openBatterySettings
            )
        case .network:
            NetworkStatusView(
                primaryLink: store.primaryLink,
                connection: store.popupSnapshot.connection,
                isConstrained: store.isNetworkConstrained,
                wifi: store.popupSnapshot.wifi,
                isResolvingName: store.isResolvingWiFiName,
                onOpenWiFiDetails: { showDetails in
                    store.activateWiFiPanel()
                    panel = .wifi(showDetails: showDetails)
                },
                onOpenWiredDetails: {
                    store.activatePrimaryLinkPanel()
                    panel = .ethernet
                },
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenNetworkSettings: openNetworkSettings,
                onOpenLocationSettings: openLocationSettings
            )
        case .vpn:
            VPNStatusView(vpn: store.vpnStatus)
        case .bluetooth:
            BluetoothStatusView(
                controller: store.bluetoothDevices,
                mobileBatteryController: store.mobileBattery,
                showsBatteryLevels: settings.showsBluetoothBatteryLevels,
                showsNearbyBatteryDevices: settings.showsNearbyBluetoothBatteryDevices,
                showsMobileBatteryLevels: settings.showsMobileDeviceBatteryLevels,
                listOptions: settings.bluetoothDeviceListOptions,
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings,
                onOpenBluetoothPermissionSettings: openBluetoothPermissionSettings
            )
        case .volume:
            VolumeControlsView(
                settings: settings,
                bluetoothController: store.bluetoothDevices,
                listeningModes: store.bluetoothListeningModes,
                scrollTargets: scrollTargets,
                volume: store.liveVolume,
                isControllerAvailable: store.isVolumeControllerAvailable,
                onVolumeChange: { store.setVolume($0) },
                onVolumeEditingEnded: { store.finishVolumeAdjustment() },
                onToggleMute: { store.toggleMute() },
                onSelectOutputDevice: { store.selectOutputDevice($0) },
                onOpenSoundSettings: openSoundSettings
            )
        case .audioInput:
            AudioInputControlsView(
                status: store.liveInput,
                onSelect: { store.selectInputDevice($0) },
                onScalarChange: { store.setInputScalar($0) },
                onToggleMute: { store.toggleInputMute() },
                onOpenSoundSettings: openSoundSettings
            )
        }
    }
}
