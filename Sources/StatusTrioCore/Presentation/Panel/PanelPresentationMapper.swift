import Foundation

@MainActor
enum PanelPresentationMapper {
    static func battery(
        _ status: BatteryStatus,
        powerSample: SystemPowerSample? = nil,
        inputPower: SystemPowerSample? = nil,
        batteryPower: BatteryPowerSample? = nil,
        showsPowerInfoBar: Bool = false,
        powerInfoBarIsLoading: Bool = false,
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
        let infoBar: PowerInfoBarState?
        if showsPowerInfoBar {
            if let bar = powerInfoBar(
                status: status,
                systemPower: powerSample,
                inputPower: inputPower,
                batteryPower: batteryPower,
                now: now,
                localization: localization
            ) {
                infoBar = bar
            } else if powerInfoBarIsLoading {
                // Reserve the bar's height with grey rails until the first read
                // lands, so turning the setting on (or reopening the panel) does
                // not grow the panel when the numbers arrive.
                infoBar = PowerInfoBarState(
                    items: [],
                    placeholderKinds: status.isPresent
                        ? [.input, .batteryIdle, .system]
                        : [.input, .system]
                )
            } else {
                infoBar = nil
            }
        } else {
            infoBar = nil
        }

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
            // A laptop on battery has no adapter feeding it, yet the rail still
            // yields a fresh ~0 W sample. Printing "0.0 W" under "Charger input"
            // reads as if a charger were attached but idle, so say plainly that
            // there is no external power. A no-battery Mac has no such state and
            // keeps its real reading.
            let unplugged = status.isPresent && !status.isConnectedToPower && abs(inputPower.watts) < 0.05
            if unplugged {
                // The descriptor "No adapter" moves to the label line (via the
                // .inputDisconnected kind title); the number slot keeps the
                // truthful 0.0 W reading so every card reads "number + note".
                items.append(PowerInfoBarItem(
                    kind: .inputDisconnected,
                    value: watts(inputPower.watts)
                ))
            } else {
                items.append(PowerInfoBarItem(kind: .input, value: watts(inputPower.watts)))
            }
        }
        if status.isPresent, let batteryPower, batteryPower.watts.isFinite, batteryPower.isFresh(at: now) {
            // The magnitude is the flow into (or out of) the pack, never folded
            // into system. Its sign is the direction: positive is charging,
            // negative is discharging, and a pack within 0.05 W of zero is idle
            // rather than charging. The number stays the magnitude so the card
            // reads "3.8 W" in both directions; the kind carries the direction
            // for the title, glyph and colour.
            let signedWatts = batteryPower.watts
            let magnitude = abs(signedWatts)
            let kind: PowerInfoBarKind
            if magnitude < 0.05 {
                kind = .batteryIdle
            } else if signedWatts < 0 {
                kind = .batteryDischarging
            } else {
                kind = .batteryCharging
            }
            items.append(PowerInfoBarItem(kind: kind, value: watts(magnitude)))
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
            tint: .primary,
            accessibilityLabel: title,
            accessibilityValue: subtitle,
            showsSettings: true,
            intent: .wiredDetails
        )
    }

    /// The summary icon follows the connection state (#352): a usable link uses
    /// the primary foreground ink (white in dark mode), an associated network
    /// without internet warns in caution, and a radio that is off, unassociated
    /// or unavailable stays secondary so it reads as muted rather than "on".
    private static func wifiTint(for state: WiFiState) -> PanelTint {
        switch state {
        case .connected, .hotspot, .temporary, .shared:
            return .primary
        case .noInternet:
            return .caution
        case .notAssociated, .off, .unavailable:
            return .secondary
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func vpn(
        _ status: VPNStatus,
        powerState: VPNPowerState = VPNPowerState(),
        localization: Localization
    ) -> PanelSummaryState {
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

        let service = status.powerControlService
        let power: VPNPowerPresentation? = status.showsPowerControl
            ? VPNPowerPresentation(
                isOn: status.powerControlIsOn,
                isChanging: powerState.isChanging,
                canSetPower: !powerState.isChanging
                    && (service?.isEnabled ?? false)
                    && service?.state != .invalid
                    && service?.state != .connecting
                    && service?.state != .disconnecting,
                failureMessage: powerState.failure.map {
                    switch $0 {
                    case .timedOut: localization.string(.vpnPowerTimedOut)
                    case .requestRejected, .failed: localization.string(.vpnPowerFailed)
                    }
                },
                turnOnHelp: localization.string(.vpnPowerTurnOn),
                turnOffHelp: localization.string(.vpnPowerTurnOff),
                changingHelp: localization.string(.vpnPowerChanging)
            )
            : nil

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
            intent: .none,
            vpnPower: power
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

    static func batteryTimeToFullText(
        minutes: Int?,
        targetPercent: Int? = nil,
        localization: Localization
    ) -> String {
        guard let minutes, minutes > 0 else {
            return localization.string(.batteryStateCalculatingTimeToFull)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if let targetPercent {
            if hours == 0 {
                return localization.format(
                    .batteryTimeToChargeLimitMinutes,
                    remainingMinutes,
                    targetPercent
                )
            }
            if remainingMinutes == 0 {
                return localization.format(
                    .batteryTimeToChargeLimitHours,
                    hours,
                    targetPercent
                )
            }
            return localization.format(
                .batteryTimeToChargeLimitHoursMinutes,
                hours,
                remainingMinutes,
                targetPercent
            )
        }
        if hours == 0 {
            return localization.format(.batteryTimeToFullMinutes, remainingMinutes)
        }
        if remainingMinutes == 0 {
            return localization.format(.batteryTimeToFullHours, hours)
        }
        return localization.format(.batteryTimeToFullHoursMinutes, hours, remainingMinutes)
    }

    /// IOKit's time-to-full estimate targets 100%. When macOS holds the battery
    /// at a lower charge limit, the system's own estimate targets that limit, so
    /// scale the remaining energy to the remaining percentage up to the limit.
    /// Charge to Full Now overrides the limit, so it keeps the 100% target.
    static func chargeTimeEstimate(
        _ battery: BatteryStatus,
        chargeToFullNow: ChargeToFullNowPresentation
    ) -> (minutes: Int?, targetPercent: Int?) {
        let raw = battery.timeToFullChargeMinutes
        guard let raw, raw > 0 else { return (raw, nil) }
        if chargeToFullNow.isChargingToFull || chargeToFullNow.isApplying {
            return (raw, nil)
        }
        guard let limit = battery.chargeLimitPercent,
              (1..<100).contains(limit) else { return (raw, nil) }
        let current = battery.rawPercentage.map { min(100, max(0, $0)) }
            ?? battery.percentage
        guard current < limit else { return (raw, nil) }
        let remainingToFull = 100 - current
        guard remainingToFull > 0 else { return (raw, nil) }
        let scaled = Int(
            (Double(raw) * Double(limit - current) / Double(remainingToFull)).rounded()
        )
        return (scaled > 0 ? scaled : nil, limit)
    }

    static func batteryRuntimeText(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String? {
        guard !battery.isConnectedToPower, !battery.isCharging,
              let minutes = battery.timeToEmptyMinutes, minutes > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = localization.resolvedLanguage.locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        guard let duration = formatter.string(from: DateComponents(minute: minutes)) else {
            return nil
        }
        return localization.format(.batteryTimeRemaining, duration)
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
        // macOS already reports 100% while the battery management system is
        // still finishing the charge. `isCharged` stays false until that ends,
        // which can take about an hour, so without this branch the panel would
        // keep saying "Calculating time to full" for a battery that is full.
        // This is a display-only description: it does not assert a strict
        // hardware trickle mode, and it never recomputes the percentage.
        if battery.isConnectedToPower,
           battery.percentage >= 100,
           battery.isCharging {
            return localization.string(.batteryStateTrickleCharging)
        }
        if battery.isCharging {
            // A known estimate always wins, including while Charge to Full Now
            // is running; the click only supplies a placeholder until then.
            let estimate = chargeTimeEstimate(
                battery,
                chargeToFullNow: chargeToFullNow
            )
            return batteryTimeToFullText(
                minutes: estimate.minutes,
                targetPercent: estimate.targetPercent,
                localization: localization
            )
        }
        // The system can report "connected" for a while after the click because
        // its charging flag trails the actual charge pulse. Show the time-to-full
        // placeholder immediately instead of leaving the row on "Connected to
        // power"; once a real estimate arrives the branch above takes over.
        // The charge placeholder only makes sense while the Mac is actually on
        // power. A session can outlive the adapter (the user unplugs mid-charge),
        // so never let it keep claiming a charging state on battery.
        if battery.isConnectedToPower {
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
                 .cancelLimitChangedConfirmation:
                break
            }
        }
        let runtime = batteryRuntimeText(battery, localization: localization)
        if battery.isLowPowerMode {
            let state = localization.string(.batteryStateLowPowerMode)
            return runtime.map { "\(state) · \($0)" } ?? state
        }
        if battery.isConnectedToPower {
            return localization.string(.batteryStateConnectedToPower)
        }
        return runtime ?? localization.string(.batteryStateOnBattery)
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
        // A bare tunnel is not a controllable system VPN service. Label it TUN
        // so the row never implies a VPN switch that does not exist (#272).
        // When Mihomo's read-only API attributes the active interface, name
        // the client too instead of pretending it is a system VPN.
        if let mihomo = vpn.mihomoTunnel,
           mihomo.isEnabled,
           vpn.tunnelInterfaces.contains(mihomo.device) {
            return mihomo.provider == "Clash Verge"
                ? localization.string(.vpnTitleClashVergeTunnel)
                : localization.string(.vpnTitleTunnel)
        }
        if vpn.isTunnelConnected { return localization.string(.vpnTitleTunnel) }
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
        // The link is up but macOS is withholding its name because the app lacks
        // the location permission CoreLocation needs to read an SSID.
        let permissionHidesName = connection == .wifi
            && wifi.state.isNetworkAssociated
            && (wifi.ssid?.isEmpty ?? true)
            && wifi.nameAccess != .authorized

        // Without permission the row keeps a short connection-state title and
        // turns the second line into an invitation to grant access. Clicking it
        // raises the system prompt (or opens Privacy settings when access was
        // already denied), because the detail page cannot show a name either.
        let title: String
        let subtitle: String
        let measurements: String?
        let intent: PanelSummaryIntent
        if permissionHidesName {
            title = wifiSubtitle(wifi, localization: localization)
            subtitle = localization.string(.wifiSummaryNameAccessHint)
            measurements = nil
            intent = wifi.nameAccess == .denied || wifi.nameAccess == .restricted
                ? .locationSettings
                : .requestWiFiNameAccess
        } else {
            let baseSubtitle: String
            if summarySSID != nil {
                baseSubtitle = linkSubtitle ?? localization.string(
                    wifi.state == .hotspot ? .wifiSubtitleHotspot : .wifiSubtitleConnected
                )
            } else if let ssid = wifi.ssid, !ssid.isEmpty {
                baseSubtitle = ssid
            } else if isResolvingName {
                baseSubtitle = " "
            } else {
                // A missing network name is not a connection state. The row keeps
                // the connection state, and its link measurements when the radio
                // still reports them.
                let stateText = wifiSubtitle(wifi, localization: localization)
                baseSubtitle = NetworkRowSubtitle.prepending(stateText, to: linkSubtitle) ?? stateText
            }

            // The address leads the second line, and the measurement value keeps
            // only the link facts: the connection state is already in the label,
            // so VoiceOver must not hear it twice. The placeholder line describes
            // no link at all.
            measurements = baseSubtitle == " "
                ? nil
                : NetworkRowSubtitle.prepending(localIPAddress, to: linkSubtitle)
            // The single-space subtitle is the row holding its line height while
            // the Wi-Fi name resolves. An address fills that line on its own
            // rather than trailing the placeholder's blank.
            if baseSubtitle == " " {
                subtitle = localIPAddress ?? baseSubtitle
            } else {
                subtitle = NetworkRowSubtitle.prepending(localIPAddress, to: baseSubtitle) ?? baseSubtitle
            }
            title = summarySSID ?? localization.string(.wifiTitle)
            intent = .wifiDetails
        }

        let accessibilityLabel: String
        if permissionHidesName {
            accessibilityLabel = localization.format(.commonLabelValue, title, subtitle)
        } else if let ssid = wifi.ssid, !ssid.isEmpty {
            accessibilityLabel = localization.format(
                .wifiAccessibilityWithSSID,
                ssid,
                wifiValue(wifi, localization: localization)
            )
        } else {
            accessibilityLabel = localization.format(
                .commonLabelValue,
                title,
                wifiValue(wifi, localization: localization)
            )
        }

        return PanelSummaryState(
            title: title,
            subtitle: subtitle,
            measurements: measurements,
            symbol: wifiSymbol(wifi),
            tint: wifiTint(for: wifi.state),
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
