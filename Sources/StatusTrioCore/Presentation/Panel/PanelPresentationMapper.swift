import Foundation

@MainActor
enum PanelPresentationMapper {
    static func battery(_ status: BatteryStatus, localization: Localization) -> PanelSummaryState {
        let title = batteryTitle(status, localization: localization)
        let subtitle = batterySubtitle(status, localization: localization)

        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: nil,
            symbol: .symbol(name: batterySymbolName(status), variableValue: nil, fallback: nil),
            tint: batteryTint(status),
            accessibilityLabel: title,
            accessibilityValue: subtitle,
            showsSettings: status.isPresent,
            intent: status.isPresent ? .batteryDetails : .none
        )
    }

    static func network(
        wifi: WiFiStatus,
        connection: NetworkConnection,
        wired: PrimaryLinkDetails?,
        isConstrained: Bool,
        isResolvingName: Bool,
        localization: Localization
    ) -> PanelSummaryState {
        guard connection == .ethernet else {
            return wifiSummary(
                wifi,
                connection: connection,
                isResolvingName: isResolvingName,
                localization: localization
            )
        }

        let title = WiredLinkPresentation.title(wired, localization: localization)
        let subtitle = WiredLinkPresentation.subtitle(
            wired,
            isConstrained: isConstrained,
            localization: localization
        )
        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: nil,
            symbol: .symbol(name: "cable.connector", variableValue: nil, fallback: nil),
            tint: .secondary,
            accessibilityLabel: title,
            accessibilityValue: subtitle,
            showsSettings: true,
            intent: .wiredDetails
        )
    }

    static func vpn(_ status: VPNStatus, localization: Localization) -> PanelSummaryState {
        let title = vpnTitle(status, localization: localization)
        let subtitle = vpnSubtitle(status, localization: localization)
        let tint: PanelTint
        if status.isTunnelConnected {
            tint = .positive
        } else if status.proxy != nil {
            tint = .caution
        } else {
            tint = .secondary
        }

        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: nil,
            symbol: .symbol(
                name: status.isTunnelConnected ? "lock.shield.fill" : "lock.shield",
                variableValue: nil,
                fallback: nil
            ),
            tint: tint,
            accessibilityLabel: localization.string(.vpnTitle),
            accessibilityValue: "\(title), \(subtitle)",
            showsSettings: false,
            intent: .none
        )
    }

    static func batteryTitle(_ battery: BatteryStatus, localization: Localization) -> String {
        localization.format(.batteryTitle, battery.percentage)
    }

    static func batteryTimeToFullText(minutes: Int?, localization: Localization) -> String {
        guard let minutes, minutes > 0 else {
            return localization.string(.batteryStateCalculatingTimeToFull)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 {
            return localization.format(.batteryTimeToFullMinutes, remainingMinutes)
        }
        if remainingMinutes == 0 {
            return localization.format(.batteryTimeToFullHours, hours)
        }
        return localization.format(.batteryTimeToFullHoursMinutes, hours, remainingMinutes)
    }

    static func batterySubtitle(_ battery: BatteryStatus, localization: Localization) -> String {
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

    static func wifiValue(_ wifi: WiFiStatus, localization: Localization) -> String {
        switch wifi.state {
        case .connected:
            return localization.format(.wifiValueBars, StatusMappings.wifiBars(rssi: wifi.rssi))
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

    static func wifiSubtitle(_ wifi: WiFiStatus, localization: Localization) -> String {
        if let ssid = wifi.ssid, !ssid.isEmpty { return ssid }
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

    static func vpnTitle(_ vpn: VPNStatus, localization: Localization) -> String {
        if let serviceName = vpn.serviceName, !serviceName.isEmpty { return serviceName }
        if vpn.isTunnelConnected { return localization.string(.vpnTitle) }
        if vpn.proxy != nil { return localization.string(.vpnSubtitleSystemProxy) }
        return localization.string(.vpnTitle)
    }

    static func vpnSubtitle(_ vpn: VPNStatus, localization: Localization) -> String {
        if vpn.isTunnelConnected {
            guard let endpoint = vpn.proxy?.endpoint else {
                return localization.string(.vpnValueConnected)
            }
            return localization.format(.vpnSubtitleConnectedWithProxy, endpoint)
        }
        guard let proxy = vpn.proxy else {
            return localization.string(.vpnValueDisconnected)
        }
        return proxy.endpoint ?? localization.string(.vpnSubtitleProxyAutomatic)
    }

    private static func wifiSummary(
        _ wifi: WiFiStatus,
        connection: NetworkConnection,
        isResolvingName: Bool,
        localization: Localization
    ) -> PanelSummaryState {
        let summarySSID = WiFiSummaryPresentation.summarySSID(wifi, connection: connection)
        let measurements = WiFiSummaryPresentation.measurements(
            wifi,
            connection: connection,
            localization: localization
        )
        let subtitle: String
        if summarySSID != nil {
            subtitle = measurements ?? localization.string(
                wifi.state == .hotspot ? .wifiSubtitleHotspot : .wifiSubtitleConnected
            )
        } else if let ssid = wifi.ssid, !ssid.isEmpty {
            subtitle = ssid
        } else if isResolvingName {
            subtitle = " "
        } else if wifi.state.isNetworkAssociated && wifi.nameAccess == .notDetermined {
            subtitle = localization.string(.wifiActionRequestNameAccess)
        } else if wifi.state.isNetworkAssociated
                    && (wifi.nameAccess == .denied || wifi.nameAccess == .restricted) {
            subtitle = localization.string(.wifiActionOpenLocationSettings)
        } else {
            subtitle = wifiSubtitle(wifi, localization: localization)
        }

        let action = StatusMappings.wifiSummaryAction(for: wifi)
        let intent: PanelSummaryIntent
        switch action {
        case .openDetails:
            intent = .wifiDetails
        case .requestNameAccess:
            intent = .requestWiFiNameAccess
        case .openLocationSettings:
            intent = .locationSettings
        }

        let title = summarySSID ?? localization.string(.wifiTitle)
        let accessibilityLabel: String
        if let ssid = wifi.ssid, !ssid.isEmpty {
            accessibilityLabel = localization.format(
                .wifiAccessibilityWithSSID,
                ssid,
                wifiValue(wifi, localization: localization)
            )
        } else {
            accessibilityLabel = localization.format(
                .commonLabelValue,
                localization.string(.wifiTitle),
                wifiValue(wifi, localization: localization)
            )
        }

        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: measurements,
            symbol: wifiSymbol(wifi),
            tint: .secondary,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: measurements ?? "",
            showsSettings: true,
            intent: intent
        )
    }

    private static func batterySymbolName(_ battery: BatteryStatus) -> String {
        guard battery.isPresent else { return "battery.slash" }
        if battery.isCharging || battery.isConnectedToPower { return "battery.100.bolt" }
        return switch battery.percentage {
        case 88...100: "battery.100"
        case 63..<88: "battery.75"
        case 38..<63: "battery.50"
        case 13..<38: "battery.25"
        default: "battery.0"
        }
    }

    private static func batteryTint(_ battery: BatteryStatus) -> PanelTint {
        guard battery.isPresent else { return .secondary }
        if battery.isCharging || battery.isConnectedToPower { return .positive }
        if battery.isLowPowerMode { return .caution }
        if battery.percentage <= 20 { return .critical }
        return .primary
    }

    private static func wifiSymbol(_ wifi: WiFiStatus) -> IconSymbolSource {
        switch wifi.state {
        case .connected:
            let bars = StatusMappings.wifiBars(rssi: wifi.rssi)
            return .symbol(name: "wifi", variableValue: max(0.25, Double(bars) / 3.0), fallback: nil)
        case .off, .unavailable:
            return .symbol(name: "wifi.slash", variableValue: nil, fallback: nil)
        case .noInternet, .notAssociated:
            return .symbol(name: "wifi.exclamationmark", variableValue: nil, fallback: nil)
        case .hotspot:
            return .symbol(name: "personalhotspot", variableValue: nil, fallback: nil)
        case .temporary, .shared:
            return .symbol(name: "wifi", variableValue: nil, fallback: nil)
        }
    }
}
