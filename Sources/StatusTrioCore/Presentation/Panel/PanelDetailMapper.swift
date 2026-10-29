import Foundation

@MainActor
enum PanelDetailMapper {
    static func battery(
        status battery: BatteryStatus,
        details: BatteryDetails?,
        localization: Localization,
        powerOptions: BatteryPowerDisplayOptions = .default,
        energyApps: ApplicationEnergyRanking? = nil
    ) -> PanelDetailState {
        var rows: [PanelDetailRow] = []
        if let details {
            let reading = BatteryPowerPresentation(details: details, isConnectedToPower: battery.isConnectedToPower)
            let watts = reading.watts.map {
                $0.formatted(.number.precision(.fractionLength(1)).locale(localization.resolvedLanguage.locale)) + " W"
            } ?? localization.string(reading.unavailableTitle)
            let showsPowerReading = !battery.isConnectedToPower || powerOptions.showsSystem
            if showsPowerReading { rows.append(row(reading.title, value: watts, localization: localization)) }
            if showsPowerReading, let timestamp = reading.timestamp {
                rows.append(row(
                    reading.timestampTitle,
                    value: timestamp.formatted(.dateTime.hour().minute().second().locale(localization.resolvedLanguage.locale)),
                    localization: localization
                ))
            }
            if powerOptions.showsCharging, let charging = reading.chargingWatts {
                rows.append(row(
                    .batteryDetailsCharging,
                    value: charging.formatted(.number.precision(.fractionLength(1)).locale(localization.resolvedLanguage.locale)) + " W",
                    tint: .positive,
                    localization: localization
                ))
            }
            if let power = details.power {
                rows.append(row(.batteryDetailsVoltage, value: power.volts.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " V", localization: localization))
                rows.append(row(.batteryDetailsCurrent, value: power.amps.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " A", localization: localization))
            }
            if let watts = details.adapterWatts {
                rows.append(row(.batteryDetailsAdapter, value: watts.formatted(.number.locale(localization.resolvedLanguage.locale)) + " W", localization: localization))
            }
            if !battery.isConnectedToPower {
                let remaining = details.remainingMinutes.map {
                    Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(localization.resolvedLanguage.locale))
                } ?? localization.string(.batteryDetailsUnavailable)
                rows.append(row(.batteryDetailsRemaining, value: remaining, localization: localization))
            }
            if let count = details.cycleCount {
                rows.append(row(.batteryDetailsCycles, value: count.formatted(.number.locale(localization.resolvedLanguage.locale)), localization: localization))
            }
        }
        rows.append(row(
            .batteryDetailsLowPower,
            value: localization.string(battery.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff),
            localization: localization
        ))
        return PanelDetailState(
            title: PanelPresentationMapper.batteryTitle(battery, localization: localization),
            rows: rows,
            isLoading: details == nil,
            errorText: nil,
            explanation: localization.string(.batteryDetailsExplanation),
            lifecycleIdentity: "\(battery.isPresent)-\(battery.isConnectedToPower)-\(battery.isCharging)",
            powerFlow: details.flatMap {
                battery.isConnectedToPower && powerOptions.showsAnyPower
                    ? powerFlow(status: battery, details: $0, options: powerOptions, localization: localization) : nil
            },
            energyApps: energyApps
        )
    }

    private static func powerFlow(status: BatteryStatus, details: BatteryDetails,
                                  options: BatteryPowerDisplayOptions, localization: Localization) -> BatteryPowerFlowState {
        func metric(_ label: LocalizationKey, _ watts: Double?) -> BatteryPowerFlowState.Metric {
            let value = watts.map { watts -> String in
                // The flow cards are only 62 pt wide. Three-digit values with
                // two decimals wrap onto a second line, so drop the fraction
                // from 100 W upward. Round to the displayed precision first so
                // 99.996 does not become the equally wide "100.00 W".
                let roundedMagnitude = (abs(watts) * 100).rounded() / 100
                let fractionDigits = roundedMagnitude >= 100 ? 0 : 2
                let number = watts.formatted(
                    .number
                        .precision(.fractionLength(fractionDigits))
                        .locale(localization.resolvedLanguage.locale)
                )
                return number + " W"
            } ?? localization.string(.batteryDetailsUnavailable)
            return BatteryPowerFlowState.Metric(label: localization.string(label), value: value, watts: watts)
        }
        // A live positive sample wins over the snapshot's charging flag: during
        // a charge-limit pulse macOS can keep `isCharging` false for tens of
        // seconds while the pack is already taking current. Without the flag,
        // keep showing "—" (unknown) instead of claiming a real 0 W.
        let sampledCharging = details.power.flatMap { $0.watts > 0 ? $0.watts : nil }
        let charging: Double? = sampledCharging ?? (status.isCharging ? nil : 0)
        return BatteryPowerFlowState(
            input: options.showsInput ? metric(.batteryPowerInput, details.inputPower?.watts) : nil,
            battery: options.showsCharging ? metric(.batteryPowerCharging, charging) : nil,
            system: options.showsSystem ? metric(.batteryPowerSystem, details.systemPower?.watts) : nil
        )
    }

    static func wired(details: PrimaryLinkDetails?, localization: Localization) -> PanelDetailState {
        let rows = LinkDetailPresentation.wiredRows(details ?? .unavailable).map {
            linkRow($0, localization: localization)
        }
        return PanelDetailState(
            title: WiredLinkPresentation.title(details, localization: localization),
            rows: rows,
            isLoading: false,
            errorText: nil,
            explanation: nil
        )
    }

    static func wifi(
        status: WiFiStatus,
        networks: [WiFiNetwork],
        details: WiFiConnectionDetails,
        listState: WiFiListState,
        localization: Localization
    ) -> WiFiPanelState {
        let groups = WiFiNetworkPresentation.grouped(networks, wifiState: status.state)
        let personalHotspotRows = groups.personalHotspot.map {
            wifiRow($0, wifiState: status.state, localization: localization)
        }
        let knownRows = groups.known.map {
            wifiRow($0, wifiState: status.state, localization: localization)
        }
        let otherRows = groups.other.map {
            wifiRow($0, wifiState: status.state, localization: localization)
        }
        let hasVisibleNetworks = !personalHotspotRows.isEmpty || !knownRows.isEmpty || !otherRows.isEmpty
        let message: String?
        let intent: PanelSummaryIntent
        switch listState {
        case .scanning:
            message = localization.string(.wifiScanning)
            intent = .none
        case .ready where !hasVisibleNetworks:
            message = localization.string(.wifiNoNetworks)
            intent = .none
        case .poweredOff:
            message = localization.string(.wifiPanelOff)
            intent = .none
        case .noInterface:
            message = localization.string(.wifiNoInterface)
            intent = .none
        case .permissionDenied:
            message = localization.string(.wifiPermissionDenied)
            intent = .locationSettings
        case .failed:
            message = localization.string(.wifiScanFailed)
            intent = .none
        case .idle where status.nameAccess == .notDetermined,
             .ready where status.nameAccess == .notDetermined:
            message = localization.string(.wifiActionRequestNameAccess)
            intent = .requestWiFiNameAccess
        case .idle, .ready:
            message = nil
            intent = .none
        }
        let collapsedDetailRowCount = LinkDetailPresentation.wirelessRows(
            details,
            expanded: false,
            localization: localization
        ).count
        let rows = LinkDetailPresentation.wirelessRows(
            details,
            expanded: true,
            localization: localization
        ).map { linkRow($0, localization: localization) }
        return WiFiPanelState(
            detail: PanelDetailState(
                title: localization.string(.wifiTitle),
                rows: rows,
                isLoading: false,
                errorText: nil,
                explanation: nil
            ),
            collapsedDetailRowCount: collapsedDetailRowCount,
            showMoreTitle: localization.string(.wifiDetailsMore),
            showLessTitle: localization.string(.wifiDetailsLess),
            personalHotspotRows: personalHotspotRows,
            knownRows: knownRows,
            otherRows: otherRows,
            powerIsOn: listState != .poweredOff && status.state != .off,
            canSetPower: listState != .noInterface,
            canRefresh: listState.allowsRefresh,
            isScanning: listState.isScanning,
            message: message,
            messageIntent: intent,
            showsConnectionDetails: details.ssid != nil
                || knownRows.contains(where: \.selected)
                || personalHotspotRows.contains(where: \.selected)
        )
    }

    private static func wifiRow(
        _ network: WiFiNetwork,
        wifiState: WiFiState,
        localization: Localization
    ) -> PanelWiFiNetworkRow {
        let name = network.ssid.isEmpty ? localization.string(.wifiHiddenNetwork) : network.ssid
        let action = WiFiNetworkPresentation.action(for: network)
        let connected = network.isConnected
        let description = connected
            ? localization.string(.wifiConnected)
            : localization.string(.wifiNotConnected)
        let actionText = action == .openSettings ? ", \(localization.string(.wifiActionOpenSettings))" : ""
        let bars = network.rssi.map { StatusMappings.wifiBars(rssi: $0) }
        let signal: IconSymbolSource
        if let bars, bars > 0 {
            signal = .symbol(name: "wifi", variableValue: max(0.25, Double(bars) / 3.0), fallback: "wifi.exclamationmark")
        } else {
            signal = .symbol(name: "wifi.exclamationmark", variableValue: nil, fallback: "wifi")
        }
        return PanelWiFiNetworkRow(
            key: network.identity,
            name: name,
            signalSymbol: signal,
            signalSystemImage: WiFiNetworkPresentation.trailingSymbol(for: network, wifiState: wifiState),
            securityMarker: network.security.requiresPassword ? "lock.fill" : nil,
            selected: connected,
            accessibilityLabel: "\(name), \(description)\(actionText)",
            opensSettings: action == .openSettings
        )
    }

    private static func linkRow(_ row: LinkDetailRow, localization: Localization) -> PanelDetailRow {
        let value = row.value.flatMap { $0.isEmpty ? nil : $0 } ?? localization.string(.networkDetailUnavailable)
        return PanelDetailRow(
            id: row.label.rawValue,
            label: localization.string(row.label),
            value: value,
            accessibilityValue: value,
            tint: .primary,
            isCopyable: row.isCopyable
        )
    }

    private static func row(
        _ key: LocalizationKey,
        value: String,
        tint: PanelTint = .primary,
        localization: Localization
    ) -> PanelDetailRow {
        PanelDetailRow(
            id: key.rawValue,
            label: localization.string(key),
            value: value,
            accessibilityValue: value,
            tint: tint
        )
    }
}
