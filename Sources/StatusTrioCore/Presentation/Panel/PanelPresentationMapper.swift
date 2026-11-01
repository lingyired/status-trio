import Foundation

@MainActor
enum PanelPresentationMapper {
    static func battery(
        _ status: BatteryStatus,
        powerSample: SystemPowerSample? = nil,
        inputPower: SystemPowerSample? = nil,
        batteryPower: BatteryPowerSample? = nil,
        showsPowerInfoBar: Bool = false,
        now: Date = Date(),
        localization: Localization,
        chargeToFullNow: ChargeToFullNowPresentation = .hidden
    ) -> PanelSummaryState {
        let title = batteryTitle(
            status,
            powerSample: powerSample,
            now: now,
            localization: localization
        )
        let subtitle = batterySubtitle(
            status,
            localization: localization,
            chargeToFullNow: chargeToFullNow
        )
        // A Mac with no battery can still open the page when the runtime shows
        // that it has a usable whole-machine power reading.
        let canOpenDetails = status.isPresent
            || (powerSample?.isFresh(at: now) ?? false)
        let infoBar = showsPowerInfoBar
            ? powerInfoBar(
                status: status,
                systemPower: powerSample,
                inputPower: inputPower,
                batteryPower: batteryPower,
                now: now,
                localization: localization
            )
            : nil

        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: nil,
            symbol: .symbol(name: batterySymbolName(status), variableValue: nil, fallback: nil),
            tint: batteryTint(status),
            accessibilityLabel: title,
            accessibilityValue: subtitle,
            showsSettings: canOpenDetails,
            intent: canOpenDetails ? .batteryDetails : .none,
            powerInfoBar: infoBar
        )
    }

    /// Provisional power info bar. Each rail is shown on its own and missing or
    /// stale rails are simply absent; rails are never added into a "total".
    private static func powerInfoBar(
        status: BatteryStatus,
        systemPower: SystemPowerSample?,
        inputPower: SystemPowerSample?,
        batteryPower: BatteryPowerSample?,
        now: Date,
        localization: Localization
    ) -> PowerInfoBarState? {
        let locale = localization.resolvedLanguage.locale
        func watts(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " W"
        }
        var items: [PowerInfoBarItem] = []
        if let inputPower, inputPower.watts.isFinite, inputPower.isFresh(at: now) {
            items.append(PowerInfoBarItem(kind: .input, value: watts(inputPower.watts)))
        }
        if status.isPresent, let batteryPower, batteryPower.watts.isFinite, batteryPower.isFresh(at: now) {
            // Battery power keeps its own sign out of the label; the magnitude
            // is the flow into (or out of) the pack, never folded into system.
            // A pack sitting at 0 W is idle, not charging, so say that instead
            // of printing a misleading 0.0 W.
            let magnitude = abs(batteryPower.watts)
            items.append(PowerInfoBarItem(
                kind: .battery,
                value: magnitude < 0.05
                    ? localization.string(.powerInfoBarNotCharging)
                    : watts(magnitude)
            ))
        }
        if let systemPower, systemPower.watts.isFinite, systemPower.isFresh(at: now) {
            items.append(PowerInfoBarItem(kind: .system, value: watts(systemPower.watts)))
        }
        return items.isEmpty ? nil : PowerInfoBarState(items: items)
    }

    static func network(
        wifi: WiFiStatus,
        connection: NetworkConnection,
        wired: PrimaryLinkDetails?,
        isConstrained: Bool,
        isResolvingName: Bool,
        localIPAddress: String? = nil,
        localization: Localization
    ) -> PanelSummaryState {
        let address = nonEmpty(localIPAddress)
        guard connection == .ethernet else {
            return wifiSummary(
                wifi,
                connection: connection,
                isResolvingName: isResolvingName,
                localIPAddress: address,
                localization: localization
            )
        }

        let title = WiredLinkPresentation.title(wired, localization: localization)
        let linkSubtitle = WiredLinkPresentation.subtitle(
            wired,
            isConstrained: isConstrained,
            localization: localization
        )
        let subtitle = NetworkRowSubtitle.prepending(address, to: linkSubtitle) ?? linkSubtitle
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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
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

    static func batteryTitle(
        _ battery: BatteryStatus,
        powerSample: SystemPowerSample? = nil,
        now: Date = Date(),
        localization: Localization
    ) -> String {
        guard battery.isPresent else {
            // A Mac with no battery has no percentage to show. Use the runtime
            // whole-machine reading when it is fresh; otherwise say so instead
            // of inventing 0 W or 100%.
            guard let powerSample, powerSample.isFresh(at: now), powerSample.watts.isFinite else {
                return localization.string(.batteryTitlePowerUnavailable)
            }
            let watts = Int(min(999, max(0, powerSample.watts)).rounded())
            return localization.format(.batteryTitlePower, watts)
        }
        return localization.format(.batteryTitle, battery.percentage)
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

    static func batterySubtitle(
        _ battery: BatteryStatus,
        localization: Localization,
        chargeToFullNow: ChargeToFullNowPresentation = .hidden
    ) -> String {
        if !battery.isPresent {
            return localization.string(.batteryStateNotPresent)
        }
        if battery.isCharged {
            return localization.string(.batteryStateCharged)
        }
        if battery.isCharging {
            // A known estimate always wins, including while Charge to Full Now
            // is running; the click only supplies a placeholder until then.
            return batteryTimeToFullText(
                minutes: battery.timeToFullChargeMinutes,
                localization: localization
            )
        }
        // The system can report "connected" for a while after the click because
        // its charging flag trails the actual charge pulse. Show the time-to-full
        // placeholder immediately instead of leaving the row on "Connected to
        // power"; once a real estimate arrives the branch above takes over.
        switch chargeToFullNow {
        case .applying, .chargingToFull, .cancelling:
            return localization.string(.batteryStateCalculatingTimeToFull)
        case .hidden,
             .available,
             .failed,
             .unavailable,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelFailed,
             .limitRestored:
            break
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
        localIPAddress: String?,
        localization: Localization
    ) -> PanelSummaryState {
        let summarySSID = WiFiSummaryPresentation.summarySSID(wifi, connection: connection)
        let linkSubtitle = WiFiSummaryPresentation.measurements(
            wifi,
            connection: connection,
            localization: localization
        )
        let subtitle: String
        if summarySSID != nil {
            subtitle = linkSubtitle ?? localization.string(
                wifi.state == .hotspot ? .wifiSubtitleHotspot : .wifiSubtitleConnected
            )
        } else if let ssid = wifi.ssid, !ssid.isEmpty {
            subtitle = ssid
        } else if isResolvingName {
            subtitle = " "
        } else {
            // A missing network name is not a connection state. The row keeps
            // the connection state, and its link measurements when the radio
            // still reports them; the detail page owns the permission action.
            let stateText = wifiSubtitle(wifi, localization: localization)
            subtitle = NetworkRowSubtitle.prepending(stateText, to: linkSubtitle) ?? stateText
        }

        // The address leads the second line, and the measurement value keeps
        // only the link facts: the connection state is already in the label, so
        // VoiceOver must not hear it twice. The placeholder line describes no
        // link at all.
        let measurements = subtitle == " "
            ? nil
            : NetworkRowSubtitle.prepending(localIPAddress, to: linkSubtitle)
        // The single-space subtitle is the row holding its line height while the
        // Wi-Fi name resolves. An address fills that line on its own rather than
        // trailing the placeholder's blank.
        let displayedSubtitle: String
        if subtitle == " " {
            displayedSubtitle = localIPAddress ?? subtitle
        } else {
            displayedSubtitle = NetworkRowSubtitle.prepending(localIPAddress, to: subtitle) ?? subtitle
        }

        // The row itself is always the way into the Wi-Fi details, where the
        // network-name permission action lives.
        let intent: PanelSummaryIntent = .wifiDetails

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
            subtitle: displayedSubtitle,
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
        if battery.isCharging { return .positive }
        if battery.isLowPowerMode { return .caution }
        if battery.isConnectedToPower { return .positive }
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
