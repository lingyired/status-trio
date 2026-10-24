import SwiftUI

enum BluetoothSummaryAction: CaseIterable, Equatable {
    case refresh
    case radioPower
    case settings
}

enum BluetoothSummaryActionLayout {
    static func trailingActions(
        showsPowerControl: Bool,
        showsPowerButton: Bool
    ) -> [BluetoothSummaryAction] {
        if showsPowerControl && showsPowerButton {
            return [.radioPower, .refresh, .settings]
        }
        return [.refresh, .settings]
    }
}

enum BluetoothSummaryActionAvailability {
    static func isRefreshEnabled(
        availability: BluetoothAvailability,
        radioPowerIsChanging: Bool
    ) -> Bool {
        availability == .available && !radioPowerIsChanging
    }

    static func refreshAction(
        refreshDevices: @escaping () -> Void,
        refreshMobileBatteries: @escaping () -> Void
    ) -> () -> Void {
        {
            refreshDevices()
            refreshMobileBatteries()
        }
    }
}

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
    @ObservedObject var radioPower: BluetoothRadioPowerController
    @ObservedObject var mobileBatteryController: MobileBatteryController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    var showsAppleDevicesAndBattery = false
    var nearbyBLESelections: [NearbyBLEDeviceSelection] = []
    var trustedAppleDeviceMetadata: [AppleDeviceCandidate] = []
    var currentTrustedAppleCandidates: [AppleDeviceCandidate] = []
    var trustedDiscoveryGeneration: UInt64 = 0
    var listOptions: BluetoothDeviceListOptions = .standard
    var showsRadioPowerControl = true
    var showsBluetoothInStatusPanel = true
    var listeningModePresentations: [String: BluetoothListeningModePresentation] = [:]
    var capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    var onSelectListeningMode: (String, BluetoothListeningMode) -> Void = { _, _ in }
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenBluetoothPermissionSettings: () -> Void
    let onSetRadioPower: (Bool) -> Void

    @State private var visibleTrustedAppleIDs = Set<AppleDeviceID>()
    @State private var visibleNearbyBLEIDs = Set<UUID>()
    @State private var confirmingPowerOff = false

    private var unhiddenListOptions: BluetoothDeviceListOptions {
        BluetoothDeviceListOptions(
            showsList: listOptions.showsList,
            maxVisibleDevices: listOptions.maxVisibleDevices,
            order: listOptions.order,
            hidesGhostDevices: listOptions.hidesGhostDevices,
            revealedGhostDeviceAddresses: listOptions.revealedGhostDeviceAddresses
        )
    }

    /// The nearby rows are persisted readings, kept across scans so a missed
    /// scan does not flicker a row away. That retention only applies while the
    /// app can still read Bluetooth: under an authorization prompt or with
    /// Bluetooth off, a cached level would claim a live status the app cannot
    /// corroborate.
    private var visibleNearbyBLESelections: [NearbyBLEDeviceSelection] {
        NearbyBLEDeviceCatalog.revealedSelections(
            nearbyBLESelections,
            enabled: showsAppleDevicesAndBattery,
            availability: controller.availability
        )
    }

    private var sourceRowsForAliasHiding: [BluetoothDevice] {
        let options = unhiddenListOptions
        let trustedCandidates = showsAppleDevicesAndBattery
            ? AppleDeviceCatalog.candidates(trusted: trustedAppleDeviceMetadata)
            : []
        let trustedRows = AppleDeviceCatalog.projection(
            candidates: trustedCandidates,
            trustedSnapshots: showsAppleDevicesAndBattery && showsMobileBatteryFeature
                ? mobileBatteryController.snapshots
                : [],
            options: options
        ).rows.map(\.device)
        let nearbyRows = NearbyBLEDeviceCatalog.panelRows(
            selections: visibleNearbyBLESelections,
            readings: controller.nearbyBatteryDevices,
            failures: controller.nearbyBLEReadFailures,
            options: options,
            now: Date(),
            batteryLevelsEnabled: showsBatteryLevels
        ).map(\.device)
        return trustedRows + nearbyRows
    }

    private var effectiveListOptions: BluetoothDeviceListOptions {
        BluetoothDeviceListPresentation.expandingHiddenAliases(
            in: listOptions,
            among: sourceRowsForAliasHiding
        )
    }

    private var resolvesRadioPowerControl: Bool {
        !capabilityPolicy.blocksControl(.bluetoothRadioPower)
            && BluetoothPowerControlVisibility.showsPanelControl(
                authorization: controller.authorization,
                showsInStatusPanel: showsBluetoothInStatusPanel,
                isEnabled: showsRadioPowerControl
            )
    }

    private var appleProjection: AppleDeviceCatalog.Projection {
        let candidates = showsAppleDevicesAndBattery
            ? AppleDeviceCatalog.candidates(trusted: trustedAppleDeviceMetadata)
            : []
        let knownIDs = Set(candidates.map(\.id))
        let failures = Set(mobileBatteryController.failures.compactMap { failure -> AppleDeviceID? in
            guard let deviceID = failure.deviceID else { return nil }
            let match = candidates.first { candidate in
                switch candidate.id {
                case let .trustedDevice(id): id == deviceID
                case let .trustedWatch(_, id): id == deviceID
                case .ble: false
                }
            }?.id
            return match.flatMap { knownIDs.contains($0) ? $0 : nil }
        })
        return AppleDeviceCatalog.projection(
            candidates: candidates,
            trustedSnapshots: showsAppleDevicesAndBattery && showsMobileBatteryFeature ? mobileBatteryController.snapshots : [],
            failures: showsMobileBatteryFeature ? failures : [],
            options: effectiveListOptions
        )
    }

    var body: some View {
        let appleProjection = appleProjection
        let appleRows = appleProjection.rows
        let nearbyRows = NearbyBLEDeviceCatalog.panelRows(
            selections: visibleNearbyBLESelections,
            readings: controller.nearbyBatteryDevices,
            failures: controller.nearbyBLEReadFailures, options: effectiveListOptions, now: Date(),
            batteryLevelsEnabled: showsBatteryLevels
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                titleBlock

                let powerPresentation = BluetoothRadioPowerPresentation.make(
                    power: radioPower.power,
                    isChanging: radioPower.isChanging,
                    failure: radioPower.failure,
                    localization: localization
                )
                ForEach(
                    BluetoothSummaryActionLayout.trailingActions(
                        showsPowerControl: resolvesRadioPowerControl,
                        showsPowerButton: powerPresentation.showsToggle
                    ),
                    id: \.self
                ) { action in
                    switch action {
                    case .refresh:
                        refreshButton
                    case .radioPower:
                        radioPowerToggle(presentation: powerPresentation)
                    case .settings:
                        settingsButton
                    }
                }
            }

            if listOptions.showsList && (BluetoothPanelListVisibility.showsList(availability: controller.availability, devices: controller.devices, options: listOptions) || !appleRows.isEmpty || !nearbyRows.isEmpty) {
                BluetoothDeviceList(
                    devices: controller.devices,
                    batteryLevels: controller.batteryLevels.merging(appleProjection.batteryLevels, uniquingKeysWith: { _, apple in apple }),
                    nearbyReadingsByID: Dictionary(controller.nearbyBatteryDevices.map { ($0.id, $0) }, uniquingKeysWith: { old, new in
                        new.lastUpdated >= old.lastUpdated ? new : old
                    }),
                    mobileMetadataByDeviceID: appleProjection.mobileMetadataByDeviceID,
                    nearbyRows: nearbyRows,
                    onVisibleNearbyIDsChanged: { ids in
                        visibleNearbyBLEIDs = ids
                        updateReadAuthorization(readAuthorizationSnapshot)
                    },
                    appleRows: appleRows,
                    onVisibleAppleIDsChanged: { ids in
                        visibleTrustedAppleIDs = ids
                        updateReadAuthorization(readAuthorizationSnapshot)
                    },
                    actionStates: controller.deviceActionStates,
                    confirmingAddress: controller.pendingDisconnectConfirmation,
                    options: effectiveListOptions,
                    listeningModePresentations: listeningModePresentations,
                    onSelectListeningMode: onSelectListeningMode,
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
        .task(id: resolvesRadioPowerControl) {
            guard resolvesRadioPowerControl else { return }
            radioPower.refresh()
        }
        .task(id: mobileBatteryClaimTaskID) {
            guard showsMobileBatteryFeature else {
                mobileBatteryController.release(Self.mobileBatteryToken)
                return
            }
            mobileBatteryController.request(Self.mobileBatteryToken)
        }
        .task(id: currentTrustedAppleGeneration) {
            mobileBatteryController.setAuthorizedDeviceIDs([])
        }
        .onChange(of: readAuthorizationSnapshot) { snapshot in
            updateReadAuthorization(snapshot)
        }
        .onDisappear {
            controller.setVisibleNearbyBLEDevices([], for: "bluetooth.summary.ble")
            controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
            mobileBatteryController.release(
                Self.mobileBatteryToken,
                keepingResults: showsMobileBatteryFeature
            )
            mobileBatteryController.setAuthorizedDeviceIDs([])
        }
        .alert(
            localization.string(.bluetoothPowerOffConfirmTitle),
            isPresented: $confirmingPowerOff
        ) {
            Button(localization.string(.commonCancel), role: .cancel) {}
            Button(localization.string(.bluetoothPowerOffConfirmAction), role: .destructive) {
                onSetRadioPower(false)
            }
        } message: {
            Text(localization.string(.bluetoothPowerOffConfirmMessage))
        }
    }

    private var refreshButton: some View {
        Button(action: BluetoothSummaryActionAvailability.refreshAction(
            refreshDevices: { controller.refreshFromUser() },
            refreshMobileBatteries: refreshMobileBatteries
        )) {
            PanelActionGlyph(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!BluetoothSummaryActionAvailability.isRefreshEnabled(
            availability: controller.availability,
            radioPowerIsChanging: radioPower.isChanging
        ))
        .help(localization.string(.bluetoothRefresh))
        .accessibilityLabel(localization.string(.bluetoothRefresh))
    }

    private var settingsButton: some View {
        Button(action: onOpenBluetoothSettings) {
            PanelActionGlyph(systemName: "gearshape")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(localization.string(.bluetoothActionOpenSettings))
        .accessibilityLabel(localization.string(.bluetoothActionOpenSettings))
    }

    private func radioPowerToggle(
        presentation: BluetoothRadioPowerPresentation
    ) -> some View {
        Button {
            let enabled = !presentation.isOn
            if !enabled && BluetoothRadioPowerPolicy.requiresConfirmation(
                beforeTurningOff: controller.devices
            ) {
                confirmingPowerOff = true
            } else {
                onSetRadioPower(enabled)
            }
        } label: {
            PanelActionGlyph(systemName: presentation.symbolName)
        }
        .buttonStyle(.plain)
        .foregroundStyle(powerIconColor(for: presentation.iconState))
        .disabled(!presentation.toggleEnabled)
        .help(
            localization.string(
                presentation.isOn ? .bluetoothPowerTurnOff : .bluetoothPowerTurnOn
            )
        )
        .accessibilityLabel(
            localization.string(
                presentation.isOn ? .bluetoothPowerTurnOff : .bluetoothPowerTurnOn
            )
        )
        .accessibilityValue(presentation.accessibilityValue)
    }

    private func powerIconColor(for state: BluetoothRadioPowerIconState) -> Color {
        switch state {
        case .on:
            .accentColor
        case .off:
            .secondary
        case .unknown, .unavailable:
            .secondary.opacity(0.65)
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
    private static let mobileBatteryToken = "bluetooth.summary.mobileBatteryDevices"

    private var mobileBatteryClaimTaskID: String {
        "\(showsBatteryLevels)-\(showsAppleDevicesAndBattery)-\(listOptions.showsList)"
    }

    private var currentTrustedAppleGeneration: UInt64 {
        showsAppleDevicesAndBattery ? trustedDiscoveryGeneration : 0
    }

    private var readAuthorizationSnapshot: BluetoothSummaryReadAuthorizationSnapshot {
        BluetoothSummaryReadAuthorizationSnapshot(
            showsBatteryLevels: showsBatteryLevels,
            showsAppleDevicesAndBattery: showsAppleDevicesAndBattery,
            showsList: listOptions.showsList,
            currentTrustedAppleCandidates: currentTrustedAppleCandidates
        )
    }

    private func updateReadAuthorization(_ snapshot: BluetoothSummaryReadAuthorizationSnapshot) {
        mobileBatteryController.setAuthorizedDeviceIDs(
            snapshot.showsMobileBatteryFeature
                ? BluetoothVisibilityAuthorization.trustedIDs(
                    visibleIDs: visibleTrustedAppleIDs,
                    currentCandidates: snapshot.currentTrustedAppleCandidates
                )
                : []
        )
        controller.setVisibleNearbyBLEDevices(
            BluetoothVisibilityAuthorization.nearbyIDs(
                visibleIDs: visibleNearbyBLEIDs,
                showsBatteryLevels: snapshot.showsBatteryLevels,
                showsAppleDevicesAndBattery: snapshot.showsAppleDevicesAndBattery,
                showsList: snapshot.showsList
            ),
            for: "bluetooth.summary.ble"
        )
    }

    private var showsMobileBatteryFeature: Bool {
        showsBatteryLevels
            && showsAppleDevicesAndBattery
            && listOptions.showsList
            && !capabilityPolicy.blocksControl(.mobileBatteryHelper)
    }

    private var refreshMobileBatteries: () -> Void {
        guard !capabilityPolicy.blocksControl(.mobileBatteryHelper) else {
            return {}
        }
        return { mobileBatteryController.refresh() }
    }

    private var mobileFailureMessage: LocalizationKey? {
        MobileBatteryFailurePresentation.message(
            isEnabled: showsMobileBatteryFeature,
            snapshots: mobileBatteryController.snapshots,
            failures: mobileBatteryController.failures,
            isRefreshing: mobileBatteryController.isRefreshing
        )
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
        let radioPresentation = BluetoothRadioPowerPresentation.make(
            power: radioPower.power,
            isChanging: radioPower.isChanging,
            failure: radioPower.failure,
            localization: localization
        )
        if let failureText = radioPresentation.subtitle {
            return failureText
        }
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
