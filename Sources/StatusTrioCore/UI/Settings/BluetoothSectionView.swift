import AppKit
import SwiftUI

/// Settings for Bluetooth audio icon and panel behavior.
struct BluetoothSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    /// Observed so a paired-device read that lands after the pane appeared
    /// refreshes the order list. `SystemStatusStore` holds this controller as a
    /// plain `let` and forwards nothing from it, so observing the store alone
    /// would leave the pane showing whatever it read first — usually nothing.
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @ObservedObject var appleDeviceDiscovery: AppleDeviceDiscoveryController
    @Binding var previewIsDark: Bool
    var onOpenIconDesigner: () -> Void = {}
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )
        }) {
            if bluetoothDevices.authorization != .allowed {
                bluetoothPermissionBanner
                SettingsDivider()
            }

            SettingsGroup(localization.string(.settingsBluetoothTitle)) {
                IconDesignerEntryRow(onOpen: onOpenIconDesigner)

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "list.bullet.rectangle",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothShowInStatusPanel),
                    subtitle: localization.string(.settingsBluetoothShowInStatusPanelDescription),
                    isOn: showInStatusPanelBinding
                )

                SettingsDivider()

                SettingsDivider()

                SettingsDivider()

                SettingsDivider()

                SettingsToggleRow(
                    symbol: SymbolFallback.name("battery.75percent", "battery.75"),
                    tint: .green,
                    title: localization.string(.settingsBluetoothBatteryLevels),
                    subtitle: localization.string(.settingsBluetoothBatteryLevelsDescription),
                    isOn: $store.showsBluetoothBatteryLevels
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "apple.logo",
                    tint: .blue,
                    title: localization.string(.settingsAppleDevicesAndBattery),
                    subtitle: localization.string(.settingsAppleDevicesAndBatteryDescription),
                    isOn: $store.showsAppleDevicesAndBattery
                )

                if store.showsAppleDevicesAndBattery {
                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "arrow.clockwise.circle",
                        tint: .green,
                        title: localization.string(.settingsAppleBackgroundRefresh),
                        subtitle: localization.string(.settingsAppleBackgroundRefreshDescription),
                        isOn: $store.refreshesAppleBatteriesInBackground
                    )

                    if store.refreshesAppleBatteriesInBackground {
                        SettingsDivider()

                        SettingsRow(
                            "clock",
                            tint: .teal,
                            title: localization.string(.settingsAppleBackgroundRefreshInterval)
                        ) {
                            HStack(spacing: 8) {
                                Text(localization.format(
                                    .settingsAppleBackgroundRefreshIntervalValue,
                                    store.appleBatteryRefreshIntervalMinutes
                                ))
                                .monospacedDigit()
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)

                                Stepper(
                                    "",
                                    value: $store.appleBatteryRefreshIntervalMinutes,
                                    in: SettingsStore.appleBatteryRefreshIntervalMinutesRange
                                )
                                .labelsHidden()
                                .fixedSize()
                                .accessibilityLabel(localization.string(.settingsAppleBackgroundRefreshInterval))
                                .accessibilityValue(localization.format(
                                    .settingsAppleBackgroundRefreshIntervalValue,
                                    store.appleBatteryRefreshIntervalMinutes
                                ))
                            }
                        }
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "eyeglasses",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothListeningModePreview),
                    subtitle: localization.string(.settingsBluetoothListeningModePreviewDescription),
                    isOn: $store.previewsBluetoothListeningMode
                )

                if store.previewsBluetoothListeningMode {
                    SettingsDivider()

                    SettingsRow(
                        "character.cursor.ibeam",
                        tint: .purple,
                        title: localization.string(.settingsBluetoothListeningModePreviewDeviceName),
                        subtitle: localization.string(.settingsBluetoothListeningModePreviewDeviceNameDescription)
                    ) {
                        TextField(
                            localization.string(.settingsBluetoothListeningModePreviewDeviceName),
                            text: $store.bluetoothListeningModePreviewDeviceName
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                        .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(
                        "number.square",
                        tint: .purple,
                        title: localization.string(.settingsBluetoothListeningModePreviewDeviceCount),
                        subtitle: localization.string(.settingsBluetoothListeningModePreviewDeviceCountDescription)
                    ) {
                        HStack(spacing: 10) {
                            Text("\(store.bluetoothListeningModePreviewDeviceCount)")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minWidth: 22, alignment: .trailing)

                            Stepper(
                                localization.string(.settingsBluetoothListeningModePreviewDeviceCount),
                                value: $store.bluetoothListeningModePreviewDeviceCount,
                                in: SettingsStore.bluetoothListeningModePreviewDeviceCountRange
                            )
                            .labelsHidden()
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        SymbolFallback.name("translate", "character.bubble", "globe"),
                        tint: .purple,
                        title: localization.string(.settingsBluetoothListeningModePreviewLanguage),
                        subtitle: localization.string(.settingsBluetoothListeningModePreviewLanguageDescription)
                    ) {
                        Picker(
                            localization.string(.settingsBluetoothListeningModePreviewLanguage),
                            selection: $store.bluetoothListeningModePreviewLanguage
                        ) {
                            Text(localization.string(.settingsLanguageFollowSystem))
                                .tag("")

                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.nativeName)
                                    .tag(lang.rawValue)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            deviceListGroup
            deviceOrderGroup
        }
        .onAppear { claimDeviceSurface() }
        .task(id: bluetoothDevices.authorization == .allowed) {
            if bluetoothDevices.authorization == .allowed { claimDeviceSurface() }
            else { bluetoothDevices.releaseVisibleSurface(Self.orderSurfaceToken) }
        }
        .onDisappear {
            bluetoothDevices.releaseVisibleSurface(Self.orderSurfaceToken)
            bluetoothDevices.releaseActivation(BluetoothDeviceController.settingsPaneActivationToken)
        }
    }

    private static let orderSurfaceToken = "bluetooth.settings.order.surface"

    /// The pane shows paired devices, so it needs the same monitor the popover
    /// uses — otherwise a fresh launch that opens Settings shows "No paired
    /// devices available" while devices are paired, and drag-to-reorder is
    /// unreachable. Only an app that already holds the grant may activate the
    /// monitor, because starting it is what raises the system prompt; the gate
    /// keeps this pane from ever prompting on its own. The claim stops the
    /// safety-net poll when the pane goes away, but it never turns the enabled
    /// flag off: the panel toggle and the popover own that.
    private func claimDeviceSurface() {
        guard BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        ) else { return }
        guard bluetoothDevices.requestActivation(BluetoothDeviceController.settingsPaneActivationToken) else { return }
        bluetoothDevices.holdVisibleSurface(Self.orderSurfaceToken)
    }

    private var deviceListGroup: some View {
        SettingsGroup(localization.string(.settingsBluetoothDeviceListGroup)) {
            SettingsToggleRow(
                symbol: "list.bullet.rectangle",
                tint: .purple,
                title: localization.string(.settingsBluetoothShowDeviceList),
                subtitle: localization.string(.settingsBluetoothShowDeviceListDescription),
                isOn: $store.showsBluetoothDeviceList
            )

            if store.showsBluetoothDeviceList {
                SettingsDivider()

                SettingsRow(
                    title: localization.string(.settingsBluetoothMaximumVisible),
                    subtitle: localization.string(.settingsBluetoothMaximumVisibleDescription),
                    leading: { SettingsIcon(symbol: "number", tint: .teal) },
                    trailing: {
                        HStack(spacing: 10) {
                            Text("\(store.maxVisibleBluetoothDevices)")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minWidth: 22, alignment: .trailing)

                            Stepper(
                                localization.string(.settingsBluetoothMaximumVisible),
                                value: $store.maxVisibleBluetoothDevices,
                                in: SettingsStore.bluetoothDeviceLimitRange
                            )
                            .labelsHidden()
                        }
                    }
                )

            }
        }
    }

    private var deviceOrderGroup: some View {
        SettingsGroup(
            localization.string(.settingsBluetoothOrderTitle),
            footnote: localization.string(.settingsBluetoothOrderFootnote)
        ) {
            SettingsCustomRow(
                "slider.horizontal.3",
                tint: .blue,
                title: localization.string(.settingsBluetoothOrderTitle),
                subtitle: localization.string(.settingsBluetoothOrderDescription)
            ) {
                if orderedBluetoothDevices.isEmpty {
                    Label(
                        localization.string(.settingsBluetoothOrderEmpty),
                        systemImage: "questionmark.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(orderedBluetoothDisplayRows, id: \.device.id) { displayRow in
                            let device = displayRow.device
                            let isHidden = displayRow.sourceIDs.allSatisfy {
                                store.hiddenBluetoothDeviceAddresses.contains(BluetoothDeviceIdentity.preferenceKey($0))
                            }
                            HStack(spacing: 10) {
                                Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(device.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    for sourceID in displayRow.sourceIDs {
                                        store.setBluetoothDeviceHidden(sourceID, hidden: !isHidden)
                                    }
                                } label: {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .font(.system(size: 13))
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .help(isHidden
                                      ? localization.string(.settingsBluetoothShowDevice)
                                      : localization.string(.settingsBluetoothHideDevice))
                                .accessibilityLabel(isHidden
                                      ? localization.string(.settingsBluetoothShowDevice)
                                      : localization.string(.settingsBluetoothHideDevice))
                                .frame(width: 26)

                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                                    .frame(width: 18)
                            }
                            .frame(height: 30)
                            .opacity(isHidden ? 0.45 : 1)
                        }
                        .onMove { source, destination in
                            store.moveBluetoothDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedBluetoothDisplayRows.map(\.device)
                            )
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: orderListHeight)
                }
            }
        }
    }

    /// Shown at the top of the pane whenever Bluetooth access is not granted, so
    /// the user sees why the device list is empty and can resolve it from here
    /// instead of hunting for a prompt. `.notDetermined` offers to raise the
    /// system prompt; `.denied`/`.restricted` send the user to the pane that
    /// gives a refused grant back. Hidden once `.allowed`.
    @ViewBuilder
    private var bluetoothPermissionBanner: some View {
        switch bluetoothDevices.authorization {
        case .allowed:
            EmptyView()
        case .notDetermined:
            permissionNotice(
                description: .settingsBluetoothPermissionNotDeterminedDescription,
                buttonKey: .bluetoothActionRequestAuthorization,
                action: { statusStore.requestBluetoothAuthorization() }
            )
        case .denied, .restricted:
            permissionNotice(
                description: .settingsBluetoothPermissionDeniedDescription,
                buttonKey: .bluetoothActionOpenPermissionSettings,
                action: { statusStore.openBluetoothPermissionSettings() }
            )
        }
    }

    private func permissionNotice(
        description: LocalizationKey,
        buttonKey: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        SettingsGroup {
            SettingsRow(
                "exclamationmark.triangle.fill",
                tint: .orange,
                title: localization.string(.settingsBluetoothPermissionRequired),
                subtitle: localization.string(description)
            ) {
                Button(localization.string(buttonKey), action: action)
                    .controlSize(.small)
            }
        }
    }

    /// The order list shows the same sequence the panel renders, so dragging in
    /// Settings moves the row the user is looking at. Read from the observed
    /// controller, not the store, so a read that lands later repaints it.
    private var sourceBluetoothDevices: [BluetoothDevice] {
        let trustedDevices = store.showsAppleDevicesAndBattery
            ? AppleDeviceCatalog.candidates(trusted: store.trustedAppleDeviceMetadata + appleDeviceDiscovery.candidates)
                .map { candidate in
                    BluetoothDevice(
                        id: candidate.id.rowID,
                        name: candidate.name,
                        kind: BluetoothMobileDeviceModel.kind(forModel: candidate.model) ?? .unknown,
                        isConnected: false,
                        appleMobileModel: candidate.model,
                        isReadOverTheAir: true
                    )
                }
            : []
        let bleDevices = nearbySettingsCandidates.map { candidate in
            let selection = store.nearbyBLESelections.first { $0.id == candidate.id }
            return BluetoothDevice(
                id: BluetoothDeviceIdentity.bleRowID(candidate.id),
                name: candidate.name,
                kind: BluetoothMobileDeviceModel.kind(forModel: selection?.model) ?? .unknown,
                isConnected: false,
                appleMobileModel: selection?.model,
                isReadOverTheAir: true
            )
        }
        return bluetoothDevices.devices.filter { !$0.isUnpairedGhost } + trustedDevices + bleDevices
    }

    private var orderedBluetoothDevices: [BluetoothDevice] {
        orderedBluetoothDisplayRows.map(\.device)
    }

    private var orderedBluetoothDisplayRows: [BluetoothDisplayRow] {
        BluetoothDeviceListPresentation.settingsDisplayRows(
            sourceBluetoothDevices,
            order: store.bluetoothDeviceOrder,
            options: store.bluetoothDeviceListOptions
        )
    }

    private var nearbySettingsCandidates: [NearbyBLEDeviceCandidate] {
        guard store.showsAppleDevicesAndBattery, bluetoothDevices.authorization == .allowed else { return [] }
        return NearbyBLEDeviceCatalog.settingsCandidates(selections: store.nearbyBLESelections)
    }

    private var orderListHeight: CGFloat {
        min(max(CGFloat(orderedBluetoothDevices.count) * 32 + 12, 48), 180)
    }

    private var showInStatusPanelBinding: Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(.bluetooth) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(.bluetooth)
                store.setPopupSection(.bluetooth, enabled: enabled)

                guard enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate(ignoringOtherApps: true)
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }
}
