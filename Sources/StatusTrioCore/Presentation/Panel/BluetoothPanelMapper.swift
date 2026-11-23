import Foundation

@MainActor
enum BluetoothPanelMapper {
    static func map(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        actionStates: [String: BluetoothDeviceActionState],
        nearbyDevices: [NearbyBluetoothBatteryDevice],
        batteryLevelsReadFailed: Bool,
        isExpanded: Bool,
        options: BluetoothDeviceListOptions,
        showsBatteryLevels: Bool,
        showsNearbyBatteryDevices: Bool,
        confirmingAddress: String?,
        localization: Localization
    ) -> BluetoothPanelState {
        let visibleNearby = BluetoothNearbyBatteryListPresentation.visibleDevices(
            from: nearbyDevices,
            enabled: showsBatteryLevels && showsNearbyBatteryDevices
        )
        let merged = BluetoothNearbyDeviceMerge.merged(
            devices: devices,
            batteryLevels: batteryLevels,
            nearbyDevices: visibleNearby
        )
        let listIsVisible = BluetoothPanelListVisibility.showsList(
            availability: availability,
            devices: merged.devices,
            options: options
        )
        let list = BluetoothDeviceListModel.make(
            devices: merged.devices,
            batteryLevels: merged.batteryLevels,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded,
            options: options
        )
        let pairedRows = listIsVisible
            ? list.visibleDevices.map {
                pairedRow(
                    $0,
                    batteryLevels: showsBatteryLevels ? merged.batteryLevels : [:],
                    actionStates: actionStates,
                    localization: localization
                )
            }
            : []
        let nearbyRows = merged.remainingNearby.map { device in
            nearbyRow(device, localization: localization)
        }
        let summary = BluetoothSummary.presentation(
            availability: availability,
            devices: devices,
            batteryLevels: showsBatteryLevels ? batteryLevels : [:]
        )
        let hideSubtitle = BluetoothPanelListVisibility.hidesRowSubtitle(
            availability: availability,
            devices: devices,
            options: options
        )
        let summaryText = summaryText(summary, localization: localization)
        let accessibilitySummary = summary == .requestAuthorization
            ? localization.string(.bluetoothAuthorizationNotDetermined)
            : summaryText
        let summaryIntent: PanelSummaryIntent
        let subtitle: String
        switch summary.rowAction {
        case .requestAuthorization:
            summaryIntent = .requestBluetoothAuthorization
            subtitle = localization.string(.bluetoothActionRequestAuthorization)
        case .openPermissionSettings:
            summaryIntent = .openBluetoothPermissionSettings
            subtitle = localization.string(.bluetoothActionOpenPermissionSettings)
        case nil:
            summaryIntent = .none
            subtitle = summaryText
        }
        let title = localization.string(.bluetoothTitle)
        let summaryState = PanelSummaryState(
            title: title,
            subtitle: hideSubtitle ? "" : subtitle,
            measurements: nil,
            symbol: .symbol(name: "bluetooth", variableValue: nil, fallback: "antenna.radiowaves.left.and.right"),
            tint: .secondary,
            accessibilityLabel: hideSubtitle ? title : "\(title), \(accessibilitySummary)",
            accessibilityValue: accessibilitySummary,
            showsSettings: true,
            intent: summaryIntent
        )
        let normalizedConfirmation = confirmingAddress.map { BluetoothBatteryReader.normalizedAddress($0) }

        return BluetoothPanelState(
            summary: summaryState,
            summaryBatterySegments: hideSubtitle ? nil : summary.deviceSegments,
            hasConnectedDevices: summary.hasConnectedDevices,
            batteryReadTaskID: "\(showsBatteryLevels)-" + BluetoothDevicePresentation.grouped(devices).connected.map(\.name).joined(separator: "、"),
            pairedRows: pairedRows,
            nearbyRows: nearbyRows,
            errorText: listIsVisible && batteryLevelsReadFailed
                ? localization.string(.bluetoothBatteryUnavailable)
                : nil,
            showsPairedHeading: !pairedRows.isEmpty && !nearbyRows.isEmpty,
            canExpand: listIsVisible && list.canToggleExpansion,
            confirmationAddress: normalizedConfirmation,
            showsBatteryLevels: showsBatteryLevels,
            showsNearbyBatteryDevices: showsNearbyBatteryDevices
        )
    }

    private static func pairedRow(
        _ device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel],
        actionStates: [String: BluetoothDeviceActionState],
        localization: Localization
    ) -> PanelBluetoothDeviceRow {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        let actionState = actionStates[address]
        let status = BluetoothDeviceActionPolicy.status(for: device, actionState: actionState)
        let batterySegments = BluetoothDevicePresentation.batteryLevelSegments(
            for: device,
            batteryLevels: batteryLevels
        )
        let stateText: String
        switch status {
        case .connected: stateText = localization.string(.bluetoothConnected)
        case .notConnected: stateText = localization.string(.bluetoothNotConnected)
        case .connecting: stateText = localization.string(.bluetoothStateConnecting)
        case .disconnecting: stateText = localization.string(.bluetoothStateDisconnecting)
        case .connectFailed: stateText = localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed: stateText = localization.string(.bluetoothStateDisconnectFailed)
        }
        let action = BluetoothDeviceActionPolicy.action(for: device)
        let isBusy: Bool
        switch actionState {
        case .connecting, .disconnecting: isBusy = true
        case .failed, .none: isBusy = false
        }
        let statusText: String?
        switch status {
        case .connecting: statusText = localization.string(.bluetoothStateConnecting)
        case .disconnecting: statusText = localization.string(.bluetoothStateDisconnecting)
        case .connectFailed: statusText = localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed: statusText = localization.string(.bluetoothStateDisconnectFailed)
        case .connected, .notConnected: statusText = nil
        }
        let statusTint: PanelTint
        switch status {
        case .connectFailed, .disconnectFailed: statusTint = .critical
        case .connected, .notConnected, .connecting, .disconnecting: statusTint = .secondary
        }
        return PanelBluetoothDeviceRow(
            address: address,
            title: device.name,
            subtitle: statusText,
            icon: .symbol(name: BluetoothDeviceRowIcon.symbolName(for: device), variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            batteryText: batterySegments?.plainText,
            batteryLayout: BluetoothDevicePresentation.batteryLayout(for: device, batteryLevels: batteryLevels),
            batterySegments: batterySegments,
            isConnected: device.isConnected,
            isActionable: BluetoothDeviceActionPolicy.isActionable(device),
            status: status,
            statusText: statusText,
            statusTint: statusTint,
            requiresConfirmation: BluetoothDeviceActionPolicy.requiresConfirmation(for: device),
            actionTitle: localization.string(action == .connect ? .bluetoothActionConnect : .bluetoothActionDisconnect),
            actionEnabled: BluetoothDeviceActionPolicy.isActionable(device) && !isBusy,
            isBusy: isBusy,
            accessibilityLabel: device.name,
            accessibilityValue: [stateText, batterySegments?.plainText].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private static func nearbyRow(
        _ device: NearbyBluetoothBatteryDevice,
        localization: Localization
    ) -> PanelBluetoothDeviceRow {
        let title = device.displayName(fallback: localization.string(.bluetoothNearbyDeviceFallback))
        let value = localization.format(.batteryAccessibilityValue, device.batteryLevel)
        return PanelBluetoothDeviceRow(
            address: device.id.uuidString,
            title: title,
            subtitle: nil,
            icon: .symbol(name: "dot.radiowaves.left.and.right", variableValue: nil, fallback: nil),
            batteryText: "\(device.batteryLevel)%",
            batteryLayout: .inline,
            batterySegments: [.text("\(device.batteryLevel)%")],
            isConnected: false,
            isActionable: false,
            status: .notConnected,
            statusText: nil,
            statusTint: .secondary,
            requiresConfirmation: false,
            actionTitle: "",
            actionEnabled: false,
            isBusy: false,
            accessibilityLabel: title,
            accessibilityValue: value
        )
    }

    private static func summaryText(_ summary: BluetoothSummary, localization: Localization) -> String {
        switch summary {
        case .requestAuthorization: localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing: localization.string(.bluetoothInitializing)
        case .authorizationDenied: localization.string(.bluetoothActionOpenPermissionSettings)
        case .authorizationRestricted: localization.string(.bluetoothAuthorizationRestricted)
        case .poweredOff: localization.string(.bluetoothOff)
        case .unavailable: localization.string(.bluetoothUnavailable)
        case .readFailed: localization.string(.bluetoothReadFailed)
        case .noConnectedDevices: localization.string(.bluetoothNoConnectedDevices)
        case .devices: summary.deviceNames ?? ""
        }
    }
}
