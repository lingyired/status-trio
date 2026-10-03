import SwiftUI

/// The Bluetooth summary row. It reports live device state — a permission
/// request while the grant is undecided, then the states only the row can
/// explain — and lists available device readings under it. A connected device is marked
/// the way the volume output list marks the device in use, and a device the
/// report carries a level for shows it.
///
/// The row is no longer a way into a detail page: the list below it already
/// shows every paired device, with an expansion control when they do not all
/// fit, so a second page only repeated it. What that page offered besides is
/// here instead: the refresh button beside the gear, and the one-line report of
/// a level read that failed.
struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @ObservedObject var mobileBatteryController: MobileBatteryController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    var showsNearbyBatteryDevices = false
    var showsMobileBatteryLevels = false
    var listOptions: BluetoothDeviceListOptions = .standard
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenBluetoothPermissionSettings: () -> Void

    /// The paired-device list with the iOS devices the BLE scan found folded
    /// into it, derived once per body evaluation.
    private var mergedDeviceList: MobileBatteryDeviceMerge.Result {
        let scanResults = BluetoothNearbyBatteryListPresentation.visibleDevices(
            from: controller.nearbyBatteryDevices,
            enabled: showsNearbyBatteryLevels
        )
        return MobileBatteryDeviceMerge.merged(
            devices: controller.devices,
            batteryLevels: controller.batteryLevels,
            nearbyDevices: scanResults,
            mobileSnapshots: showsMobileBatteryFeature ? mobileBatteryController.snapshots : [],
            fallbackWatchName: localization.string(.mobileBatteryWatchFallbackName)
        )
    }

    var body: some View {
        let merged = mergedDeviceList
        let nearbyDevices = merged.remainingNearby

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                titleBlock

                Button(action: {
                    controller.refreshFromUser()
                    mobileBatteryController.refresh()
                }) {
                    // Trailing-aligned inside the button's own box: the other
                    // rows end on their disclosure chevron itself, so its right
                    // edge is what sits ten points before the gear. A glyph
                    // centred in this 24-point box would land about seven points
                    // to the left of that column. The whole box stays clickable.
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The same weight as the disclosure chevron the other rows end
                // on, so the panel's trailing column reads as one thing. The gear
                // beside it stays `secondary`, exactly as it does next to that
                // chevron in the Wi-Fi and battery rows.
                .foregroundStyle(.tertiary)
                .help(localization.string(.bluetoothRefresh))
                .accessibilityLabel(localization.string(.bluetoothRefresh))

                Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(localization.string(.bluetoothActionOpenSettings))
                    .frame(width: 24, height: 24)
            }

            if showsDeviceList(for: merged) {
                let pairedIDs = Set(controller.devices.map(\.id))
                if let heading = BluetoothDeviceListHeading.title(
                    hasNearbyDevices: !nearbyDevices.isEmpty,
                    hasExternalMobileDevices: merged.mobileDeviceIDs.contains { !pairedIDs.contains($0) }
                ) {
                    Text(localization.string(heading))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }

                BluetoothDeviceList(
                    devices: visibleDeviceRows(from: merged),
                    batteryLevels: merged.batteryLevels,
                    mobileMetadataByDeviceID: merged.mobileMetadataByDeviceID,
                    actionStates: controller.deviceActionStates,
                    confirmingAddress: controller.pendingDisconnectConfirmation,
                    options: listOptions,
                    onPerformAction: { controller.performDeviceAction(for: $0) },
                    onRequestDisconnect: { controller.requestDisconnectConfirmation(for: $0) },
                    onCancelDisconnect: { controller.cancelDisconnectConfirmation() }
                )

                if controller.batteryLevelsReadFailed {
                    // The list is where the levels are, so this is where a report
                    // that could not be read is reported: one line for the whole
                    // list, never a placeholder on every row.
                    Text(localization.string(.bluetoothBatteryUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !nearbyDevices.isEmpty {
                NearbyBluetoothBatteryList(devices: nearbyDevices)
            }

            if let message = mobileFailureMessage {
                Text(localization.string(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        }
        .task(id: batteryReadTaskID) {
            // Reading levels launches system_profiler, so the claim is held only
            // while the summary actually wants them. The row stays on screen
            // while the setting changes, so the release has to happen here and
            // not only in `onDisappear`: otherwise switching the setting off
            // leaves the read running and the level it published on screen until
            // the row disappears and comes back. A claim rather than a toggle
            guard showsBatteryLevels, summaryPresentation.hasConnectedDevices else {
                controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
                return
            }
            controller.requestBatteryLevels(Self.summaryBatteryLevelsToken)
        }
        .task(id: showsNearbyBatteryLevels) {
            guard showsNearbyBatteryLevels else {
                // The setting is off, so the surface is no longer entitled to
                // what the scan read: these go now rather than at the end of
                // their lifetime.
                controller.releaseNearbyBatteryDevices(Self.nearbyBatteryDevicesToken)
                return
            }
            // This claim follows the saved opt-in across popover closes. The
            // controller's popover token is the separate gate that stops the
            // scanner immediately when the popover closes.
            controller.requestNearbyBatteryDevices(Self.nearbyBatteryDevicesToken)
        }
        .task(id: mobileBatteryClaimTaskID) {
            guard BluetoothMobileBatteryPanelVisibility.shouldClaim(
                showsBatteryLevels: showsBatteryLevels,
                showsMobileBatteryLevels: showsMobileBatteryLevels,
                options: listOptions
            ) else {
                mobileBatteryController.release(Self.mobileBatteryToken)
                return
            }
            mobileBatteryController.request(Self.mobileBatteryToken)
        }
        .onDisappear {
            controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
            // The panel closing is not the feature being switched off: it is the
            // same surface coming back in a moment, so what it read stays for the
            // cache's own lifetime. Dropping it here made every reopen pay for a
            // fresh scan, connect and GATT read before an iPhone row could be
            // drawn at all, while the paired rows — whose report survives the
            // close — appeared at once.
            controller.releaseNearbyBatteryDevices(
                Self.nearbyBatteryDevicesToken,
                keepingResults: true
            )
            mobileBatteryController.release(
                Self.mobileBatteryToken,
                keepingResults: BluetoothMobileBatteryPanelVisibility.shouldClaim(
                    showsBatteryLevels: showsBatteryLevels,
                    showsMobileBatteryLevels: showsMobileBatteryLevels,
                    options: listOptions
                )
            )
        }
    }

    /// The title and its subtitle. It is a button only while the state has
    /// somewhere to send the user — asking for the grant, or the pane that gives
    /// a refused one back — which is the same rule the Wi-Fi row follows. A state
    /// with no action stays a plain, non-focusable row.
    @ViewBuilder
    private var titleBlock: some View {
        if let action = summaryPresentation.rowAction {
            Button(action: { perform(action) }) { titleContent }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel)
        } else {
            titleContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel)
        }
    }

    private var titleContent: some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            BluetoothIcon(size: BluetoothPanelMetrics.iconColumnWidth)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string(.bluetoothTitle))
                    .font(.headline)
                subtitle
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func perform(_ action: BluetoothSummaryRowAction) {
        switch action {
        case .requestAuthorization:
            onRequestAuthorization()
        case .openPermissionSettings:
            onOpenBluetoothPermissionSettings()
        }
    }

    private static let summaryBatteryLevelsToken = "bluetooth.summary"
    private static let nearbyBatteryDevicesToken = "bluetooth.summary.nearbyBatteryDevices"
    private static let mobileBatteryToken = "bluetooth.summary.mobileBatteryDevices"

    private var showsNearbyBatteryLevels: Bool {
        showsBatteryLevels && showsNearbyBatteryDevices
    }

    private func showsDeviceList(for merged: MobileBatteryDeviceMerge.Result) -> Bool {
        BluetoothMobileBatteryPanelVisibility.showsList(
            availability: controller.availability,
            devices: merged.devices,
            pairedDevices: controller.devices,
            mobileDeviceIDs: merged.mobileDeviceIDs,
            showsMobileBatteryLevels: showsMobileBatteryFeature,
            options: listOptions
        )
    }

    private var mobileBatteryClaimTaskID: String {
        "\(showsBatteryLevels)-\(showsMobileBatteryLevels)-\(listOptions.showsList)"
    }

    private var showsMobileBatteryFeature: Bool {
        showsBatteryLevels && showsMobileBatteryLevels && listOptions.showsList
    }

    private var mobileFailureMessage: LocalizationKey? {
        guard showsMobileBatteryFeature,
              mobileBatteryController.snapshots.isEmpty,
              !mobileBatteryController.isRefreshing else { return nil }
        return mobileBatteryController.failures.contains(where: { $0.category == "trust-required" })
            ? .mobileBatteryTrustRequired
            : .mobileBatteryUnavailable
    }

    private func visibleDeviceRows(from merged: MobileBatteryDeviceMerge.Result) -> [BluetoothDevice] {
        guard !BluetoothPanelListVisibility.showsList(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        ) else {
            return merged.devices
        }

        // When Bluetooth is unavailable, only show rows identified by the
        // trusted phone. They remain read-only and still pass
        // through BluetoothDeviceList's hidden/order/limit rules.
        return merged.devices.compactMap { device in
            guard merged.mobileDeviceIDs.contains(device.id) else { return nil }
            return BluetoothDevice(
                id: device.id,
                name: device.name,
                kind: device.kind,
                isConnected: false,
                isReadOverTheAir: true
            )
        }
    }

    private var hidesSubtitle: Bool {
        BluetoothPanelListVisibility.hidesRowSubtitle(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        )
    }

    /// The task re-runs when the level setting or one of the device names
    /// changes. The name also covers an AirPods swapping to another device at
    /// the same address.
    private var batteryReadTaskID: String {
        let names = BluetoothDevicePresentation.grouped(controller.devices).connected
            .map(\.name)
            .joined(separator: "、")
        return "\(showsBatteryLevels)-\(names)"
    }

    private var summaryPresentation: BluetoothSummary {
        BluetoothSummary.presentation(
            availability: controller.availability,
            devices: controller.devices,
            batteryLevels: controller.batteryLevels
        )
    }

    /// The list carries the connected names, so the label that would repeat them
    /// is dropped for the same reason the visible subtitle is: every row below is
    /// already its own combined accessibility element, and announcing the names
    /// twice makes VoiceOver read each device twice. The decision stays inside
    /// the one tested rule.
    private var rowAccessibilityLabel: String {
        guard !hidesSubtitle else { return localization.string(.bluetoothTitle) }
        return "\(localization.string(.bluetoothTitle)), \(accessibilitySummary)"
    }

    private var accessibilitySummary: String {
        switch summaryPresentation {
        case .requestAuthorization:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        default:
            return summaryText
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if case .requestAuthorization = summaryPresentation {
            actionLabel(.bluetoothActionRequestAuthorization, action: onRequestAuthorization)
        } else if case .authorizationDenied = summaryPresentation {
            // The row itself performs this, the way the Wi-Fi row's subtitle does
            // for location; the line reads as what tapping does rather than as a
            // statement of fact, and a refused grant is the one state the user can
            // act on from here.
            actionLabel(
                .bluetoothActionOpenPermissionSettings,
                action: onOpenBluetoothPermissionSettings
            )
        } else if hidesSubtitle {
            EmptyView()
        } else if let segments = summaryPresentation.deviceSegments {
            // The same pieces the device rows draw, so the charging case is one
            // glyph on both surfaces rather than a glyph here and a word there.
            // Every other state is one sentence of localized text.
            BluetoothBatteryLevelText.drawn(segments)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func actionLabel(
        _ key: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(localization.string(key), action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var summaryText: String {
        switch summaryPresentation {
        case .requestAuthorization:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing:
            return localization.string(.bluetoothInitializing)
        case .authorizationDenied:
            return localization.string(.bluetoothActionOpenPermissionSettings)
        case .authorizationRestricted:
            return localization.string(.bluetoothAuthorizationRestricted)
        case .poweredOff:
            return localization.string(.bluetoothOff)
        case .unavailable:
            return localization.string(.bluetoothUnavailable)
        case .readFailed:
            return localization.string(.bluetoothReadFailed)
        case .noConnectedDevices:
            return localization.string(.bluetoothNoConnectedDevices)
        case .devices:
            // The device line is drawn from its pieces; this is its text form,
            // which is what the accessibility label above reads.
            return summaryPresentation.deviceNames ?? ""
        }
    }
}
