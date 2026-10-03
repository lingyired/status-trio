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
    @Binding var previewIsDark: Bool
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
                SettingsToggleRow(
                    symbol: "list.bullet.rectangle",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothShowInStatusPanel),
                    subtitle: localization.string(.settingsBluetoothShowInStatusPanelDescription),
                    isOn: showInStatusPanelBinding
                )

                SettingsDivider()

                SettingsRow(
                    "wave.3.right.circle.fill",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothSymbolScale),
                    subtitle: localization.string(.settingsBluetoothSymbolScaleDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.bluetoothSymbolScale },
                                set: { store.bluetoothSymbolScale = (round($0 * 20) / 20) }
                            ),
                            in: SettingsStore.bluetoothSymbolScaleRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(localization.string(.settingsBluetoothSymbolScale))
                        .accessibilityValue(
                            "\(Int(round(store.bluetoothSymbolScale * 100)))%"
                        )

                        Text("\(Int(round(store.bluetoothSymbolScale * 100)))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wave.3.right.circle.fill",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothReplaceNetworkIcon),
                    subtitle: localization.string(.settingsBluetoothReplaceNetworkIconDescription),
                    isOn: $store.replacesNetworkIconWithBluetoothAudio
                )

                if store.replacesNetworkIconWithBluetoothAudio {
                    SettingsDivider()

                    networkIconSourceRow

                    if !sourceOptionsOffersDevices {
                        SettingsDivider()

                        SettingsHintRow(
                            text: localization.string(.settingsBluetoothNetworkIconSourceDevicesEmpty)
                        )
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "speaker.wave.2.fill",
                    tint: .cyan,
                    title: localization.string(.settingsBluetoothVolumeColor),
                    subtitle: localization.string(.settingsBluetoothVolumeColorDescription),
                    isOn: $store.usesBluetoothAudioVolumeColor
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wifi.exclamationmark",
                    tint: .orange,
                    title: localization.string(.settingsBluetoothNetworkErrorPriority),
                    subtitle: localization.string(.settingsBluetoothNetworkErrorPriorityDescription),
                    isOn: $store.prioritizesNetworkErrorsOverBluetoothAudio
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "battery.75percent",
                    tint: .green,
                    title: localization.string(.settingsBluetoothBatteryLevels),
                    subtitle: localization.string(.settingsBluetoothBatteryLevelsDescription),
                    isOn: $store.showsBluetoothBatteryLevels
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "dot.radiowaves.left.and.right",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothNearbyBatteryDevices),
                    subtitle: localization.string(.settingsBluetoothNearbyBatteryDevicesDescription),
                    isOn: $store.showsNearbyBluetoothBatteryDevices
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "iphone.gen3.radiowaves.left.and.right",
                    tint: .teal,
                    title: localization.string(.settingsBluetoothMobileBatteryDevices),
                    subtitle: localization.string(.settingsBluetoothMobileBatteryDevicesDescription),
                    isOn: $store.showsMobileDeviceBatteryLevels
                )

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
                        "translate",
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
        .onDisappear { bluetoothDevices.releaseVisibleSurface(Self.orderSurfaceToken) }
    }

    private static let orderSurfaceToken = "bluetooth.settings.order.surface"

    /// Which glyph replaces the network icon, as one flat pop-up menu: the audio
    /// device leads, and every classified paired device follows.
    ///
    /// The menu is deliberately flat. A `Section` inside the picker's content
    /// was dropped when the menu opened on macOS, which left the user with the
    /// audio entry alone and no way to pick a device; the contents are built and
    /// tested in `BluetoothNetworkIconSourceOption` instead.
    ///
    /// The row draws the choice's own glyph, so it reads like the menu bar will.
    private var networkIconSourceRow: some View {
        SettingsRow(
            title: localization.string(.settingsBluetoothNetworkIconSourceGroup),
            subtitle: localization.string(.settingsBluetoothNetworkIconSourceAudioDescription),
            leading: { SettingsIcon(symbol: selectedOption.symbolName, tint: .blue) }
        ) {
            Picker(
                localization.string(.settingsBluetoothNetworkIconSourceGroup),
                selection: networkIconSourceBinding
            ) {
                ForEach(sourceOptions) { option in
                    Label(
                        option.title
                            ?? localization.string(.settingsBluetoothNetworkIconSourceAudio),
                        systemImage: option.symbolName
                    )
                    .tag(option.source)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("bluetooth.networkIconSource")
        }
    }

    private var networkIconSourceBinding: Binding<BluetoothNetworkIconSource> {
        Binding(
            get: { selectedOption.source },
            set: { source in
                switch source {
                case .audioDevices:
                    store.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
                case let .device(address):
                    guard let option = sourceOptions.first(where: { $0.source == source }) else {
                        return
                    }
                    store.setBluetoothNetworkIconDevice(
                        address: address,
                        symbolName: option.symbolName
                    )
                }
            }
        )
    }

    /// The menu's contents, and the row's own glyph with them.
    private var sourceOptions: [BluetoothNetworkIconSourceOption] {
        BluetoothNetworkIconSourceOption.options(
            devices: bluetoothDevices.devices,
            order: store.bluetoothDeviceOrder
        )
    }

    /// Whether the menu has anything to offer besides the audio entry. When it
    /// does not, the pane says why — a grant that has not been given yet and a
    /// Mac with nothing paired both leave the menu with one row, and without
    /// the hint that reads as a broken menu.
    private var sourceOptionsOffersDevices: Bool {
        BluetoothNetworkIconSourceOption.listsDevices(devices: bluetoothDevices.devices)
    }

    /// The choice the menu shows as selected. A saved address whose device is
    /// gone from the paired list falls back to the audio entry, which is the
    /// only entry the menu still offers.
    private var selectedOption: BluetoothNetworkIconSourceOption {
        let options = sourceOptions
        guard let address = store.bluetoothNetworkIconDeviceAddress,
              let picked = options.first(where: { $0.source == .device(address: address) })
        else {
            return options[0]
        }
        return picked
    }

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
        bluetoothDevices.activate()
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

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "eye.slash",
                    tint: .indigo,
                    title: localization.string(.settingsBluetoothHideUnpairedDevices),
                    subtitle: localization.string(.settingsBluetoothHideUnpairedDevicesDescription),
                    isOn: $store.hidesGhostBluetoothDevices
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
                        ForEach(orderedBluetoothDevices) { device in
                            let key = BluetoothBatteryReader.normalizedAddress(device.id)
                            let ghostHiddenByFilter = device.isUnpairedGhost
                                && store.hidesGhostBluetoothDevices
                                && !store.revealedGhostBluetoothDeviceAddresses.contains(key)
                            let isHidden = ghostHiddenByFilter
                                || store.hiddenBluetoothDeviceAddresses.contains(key)
                            // Ghost devices: a per-row eye only makes sense while the
                            // global filter is on — it reveals one ghost without showing
                            // all. With the filter off every ghost already shows, so there
                            // is nothing to toggle individually.
                            let showsEyeButton = !device.isUnpairedGhost || store.hidesGhostBluetoothDevices
                            HStack(spacing: 10) {
                                Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(device.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if device.isUnpairedGhost {
                                    Text(localization.string(.settingsBluetoothNotInSystemSettings))
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }

                                if showsEyeButton {
                                    Button {
                                        if device.isUnpairedGhost {
                                            store.setBluetoothGhostRevealed(
                                                device.id,
                                                revealed: !store.revealedGhostBluetoothDeviceAddresses.contains(key)
                                            )
                                        } else {
                                            store.setBluetoothDeviceHidden(device.id, hidden: !isHidden)
                                        }
                                    } label: {
                                        Image(systemName: isHidden ? "eye.slash" : "eye")
                                            .font(.system(size: 13))
                                    }
                                    .buttonStyle(.plain)
                                    .help(isHidden
                                          ? localization.string(.settingsBluetoothShowDevice)
                                          : localization.string(.settingsBluetoothHideDevice))
                                    .accessibilityLabel(isHidden
                                          ? localization.string(.settingsBluetoothShowDevice)
                                          : localization.string(.settingsBluetoothHideDevice))
                                }

                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 3)
                            .opacity(isHidden ? 0.45 : 1)
                        }
                        .onMove { source, destination in
                            store.moveBluetoothDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedBluetoothDevices
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
    private var orderedBluetoothDevices: [BluetoothDevice] {
        BluetoothDeviceListPresentation.orderedDevices(
            bluetoothDevices.devices,
            using: store.bluetoothDeviceOrder
        )
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
                    NSApp.activate()
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }
}
