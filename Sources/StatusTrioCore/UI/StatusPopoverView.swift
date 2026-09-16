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
    case wifi(showDetails: Bool)
    case bluetooth
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let requestBluetoothAuthorization: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openLocationSettings: () -> Void
    let openBluetoothSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void
    @State private var panel: PopoverPanel = .summary

    var body: some View {
        Group {
            switch panel {
            case .summary:
                summary
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    controller: store.wifiNetworks,
                    wifi: store.popupSnapshot.wifi,
                    onBack: { panel = .summary },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    showsDetailsInitially: showDetails
                )
            case .bluetooth:
                BluetoothDeviceListView(
                    controller: store.bluetoothDevices,
                    onBack: {
                        store.closeBluetoothDetails()
                        panel = .summary
                    },
                    onRequestAuthorization: requestBluetoothAuthorization,
                    onOpenBluetoothSettings: openBluetoothSettings
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

            VStack(spacing: 2) {
                PopoverMenuButton(
                    title: localization.string(.menuSettings),
                    icon: "gearshape",
                    shortcut: "⌘,",
                    action: openSettings
                )
                .keyboardShortcut(",", modifiers: .command)

                PopoverMenuButton(
                    title: localization.string(.menuQuit),
                    icon: "power",
                    shortcut: "⌘Q",
                    action: quit
                )
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private func popupSection(_ section: PopupSection) -> some View {
        switch section {
        case .battery:
            BatteryStatusView(
                battery: store.popupSnapshot.battery,
                onOpenBatterySettings: openBatterySettings
            )
        case .network:
            WiFiStatusView(
                wifi: store.popupSnapshot.wifi,
                onOpenDetails: { showDetails in
                    store.activateWiFiPanel()
                    panel = .wifi(showDetails: showDetails)
                },
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenLocationSettings: openLocationSettings
            )
        case .bluetooth:
            BluetoothStatusView(
                controller: store.bluetoothDevices,
                onOpenDetails: {
                    store.openBluetoothDetails()
                    panel = .bluetooth
                },
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings
            )
        case .volume:
            VolumeControlsView(
                settings: settings,
                volume: store.liveVolume,
                isEnabled: store.isVolumeControlAvailable,
                onVolumeChange: store.setVolume,
                onToggleMute: store.toggleMute,
                onSelectOutputDevice: store.selectOutputDevice,
                onOpenSoundSettings: openSoundSettings
            )
        }
    }
}

private struct PopoverMenuButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.85))

                Spacer(minLength: 0)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
