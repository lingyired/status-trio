import Foundation

@MainActor
enum PanelDetailMapper {
    static func battery(
        status battery: BatteryStatus,
        details: BatteryDetails?,
        localization: Localization,
        powerOptions: BatteryPowerDisplayOptions = .default,
        showsPowerFlow: Bool = true,
        energyApps: ApplicationEnergyRanking? = nil
    ) -> PanelDetailState {
        var rows: [PanelDetailRow] = []
        if let details {
            let reading = BatteryPowerPresentation(
                details: details,
                isConnectedToPower: battery.isConnectedToPower,
                isBatteryPresent: battery.isPresent
            )
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
            if battery.isPresent, let power = details.power {
                rows.append(row(.batteryDetailsVoltage, value: power.volts.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " V", localization: localization))
                rows.append(row(.batteryDetailsCurrent, value: power.amps.formatted(.number.precision(.fractionLength(2)).locale(localization.resolvedLanguage.locale)) + " A", localization: localization))
            }
            if battery.isPresent, let watts = details.adapterWatts {
                rows.append(row(.batteryDetailsAdapter, value: watts.formatted(.number.locale(localization.resolvedLanguage.locale)) + " W", localization: localization))
            }
            if battery.isPresent, !battery.isConnectedToPower {
                let remaining = details.remainingMinutes.map {
                    Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(localization.resolvedLanguage.locale))
                } ?? localization.string(.batteryDetailsUnavailable)
                rows.append(row(.batteryDetailsRemaining, value: remaining, localization: localization))
            }
            if battery.isPresent, let count = details.cycleCount {
                rows.append(row(.batteryDetailsCycles, value: count.formatted(.number.locale(localization.resolvedLanguage.locale)), localization: localization))
            }
        }
        rows.append(row(
            .batteryDetailsLowPower,
            value: localization.string(battery.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff),
            localization: localization
        ))
        return PanelDetailState(
            title: PanelPresentationMapper.batteryTitle(
                battery,
                powerSample: details?.systemPower,
                localization: localization
            ),
            rows: rows,
            isLoading: details == nil,
            errorText: nil,
            explanation: localization.string(.batteryDetailsExplanation),
            lifecycleIdentity: "\(battery.isPresent)-\(battery.isConnectedToPower)-\(battery.isCharging)",
            powerFlow: details.flatMap { details -> BatteryPowerFlowState? in
                // On battery the diagram still has a source (the pack), but only
                // when a verified split exists; otherwise the legacy flow stays
                // adapter-only.
                guard showsPowerFlow, powerOptions.showsAnyPower,
                      battery.isConnectedToPower || details.breakdown != nil else { return nil }
                let flow = powerFlow(status: battery, details: details,
                                     options: powerOptions, localization: localization)
                // Every switch can be off while the split still requests
                // sampling; an empty diagram is not a diagram.
                return flow.input == nil && flow.destinations.isEmpty ? nil : flow
            },
            energyApps: energyApps
        )
    }

    private static func powerFlow(status: BatteryStatus, details: BatteryDetails,
                                  options: BatteryPowerDisplayOptions, localization: Localization) -> BatteryPowerFlowState {
        func metric(_ label: LocalizationKey, _ watts: Double?,
                    kind: BatteryPowerFlowState.Kind = .system,
                    help: LocalizationKey? = nil) -> BatteryPowerFlowState.Metric {
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
            return BatteryPowerFlowState.Metric(
                label: localization.string(label), value: value, watts: watts, kind: kind,
                help: help.map { localization.string($0) })
        }
        // A live positive sample wins over the snapshot's charging flag: during
        // a charge-limit pulse macOS can keep `isCharging` false for tens of
        // seconds while the pack is already taking current. Without the flag,
        // keep showing "—" (unknown) instead of claiming a real 0 W.
        let sampledCharging = details.power.flatMap { $0.watts > 0 ? $0.watts : nil }
        let charging: Double? = sampledCharging ?? (status.isCharging ? nil : 0)
        // The left node names whichever rail feeds the diagram: the adapter
        // input, or the pack when it is discharging into the machine.
        let sourceLabel: LocalizationKey = details.breakdown?.source == .battery
            ? .batteryPowerBatterySource : .batteryPowerInput
        let sourceWatts = details.breakdown?.sourceWatts ?? details.inputPower?.watts
        let input = options.showsInput ? metric(sourceLabel, sourceWatts) : nil
        // A verified split replaces the single system node. Without one the
        // legacy two-branch diagram stays exactly as it was.
        if options.showsBreakdown, let split = details.breakdown {
            var destinations: [BatteryPowerFlowState.Metric] = []
            // A battery that is not taking current has no flow to draw: showing
            // a 0.00 W node would claim a branch that does not exist. The pack is
            // the source, not a destination, when it is discharging.
            if options.showsCharging, split.source == .adapter, let charging, charging > 0.05 {
                destinations.append(metric(.batteryPowerCharging, charging, kind: .charging))
            }
            if let display = split.display {
                destinations.append(metric(.batteryPowerDisplay, display.watts, kind: .display))
            }
            if let usb = split.usb {
                destinations.append(metric(.batteryPowerUSB, usb.watts, kind: .usb))
            }
            // The residual covers the SoC and every DC load not measured above,
            // so it takes the system node's place and its switch.
            if options.showsSystem {
                destinations.append(metric(.batteryPowerSystem, split.system.watts, kind: .system,
                                           help: .batteryPowerSystemHelp))
            }
            return BatteryPowerFlowState(input: input, destinations: destinations)
        }
        return BatteryPowerFlowState(
            input: input,
            battery: options.showsCharging ? metric(.batteryPowerCharging, charging, kind: .charging) : nil,
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
        case .poweredOff:
            message = localization.string(.wifiPanelOff)
            intent = .none
        case .noInterface:
            message = localization.string(.wifiNoInterface)
            intent = .none
        case .permissionDenied:
            message = localization.string(.wifiPermissionDenied)
            intent = .locationSettings
        case .failed where status.nameAccess == .notDetermined:
            // The scan needs location access the app was never granted, so the
            // failure is the permission prompt's job, not "scan failed".
            message = localization.string(.wifiActionRequestNameAccess)
            intent = .requestWiFiNameAccess
        case .failed:
            message = localization.string(.wifiScanFailed)
            intent = .none
        case .idle where status.nameAccess == .notDetermined,
             .ready where status.nameAccess == .notDetermined
                && !hasVisibleNetworks:
            // CoreWLAN can answer an unauthorized scan with an empty list and no
            // error, so this must precede the empty-list message: the missing
            // permission is the cause, not the range.
            message = localization.string(.wifiActionRequestNameAccess)
            intent = .requestWiFiNameAccess
        case .ready where !hasVisibleNetworks && status.nameAccess != .authorized:
            // Without authorization an empty scan says nothing about the range,
            // so only an authorized scan may claim there are no networks.
            message = status.nameAccess == .denied || status.nameAccess == .restricted
                ? localization.string(.wifiPermissionDenied)
                : localization.string(.wifiActionRequestNameAccess)
            intent = status.nameAccess == .denied || status.nameAccess == .restricted
                ? .locationSettings
                : .requestWiFiNameAccess
        case .ready where !hasVisibleNetworks:
            message = localization.string(.wifiNoNetworks)
            intent = .none
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
