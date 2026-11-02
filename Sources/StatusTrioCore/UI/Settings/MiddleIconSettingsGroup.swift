import AppKit
import SwiftUI

struct MiddleIconSettingsGroup: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(localization.string(.settingsMiddleIconTitle)) {
            SettingsMenuRow(
                symbol: "circle.inset.filled",
                tint: .indigo,
                title: localization.string(.settingsMiddleIconSource),
                subtitle: localization.string(.settingsMiddleIconDescription),
                selection: $store.connectionCenterSource,
                options: ConnectionCenterSource.allCases,
                label: sourceLabel
            )
            .accessibilityIdentifier("appIcon.middleSource")

            if store.connectionCenterSource == .bluetoothDevice {
                SettingsDivider()
                MiddleBluetoothIconOptions(store: store, statusStore: statusStore,
                                           bluetoothDevices: statusStore.bluetoothDevices)
            }

            if store.connectionCenterSource != .network {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "wifi.exclamationmark", tint: .orange,
                    title: localization.string(.settingsMiddleIconNetworkWarnings),
                    subtitle: localization.string(.settingsMiddleIconNetworkWarningsDescription),
                    isOn: $store.prioritizesNetworkErrors
                )
                .accessibilityIdentifier("appIcon.networkWarnings")
            }
        }
    }

    private func sourceLabel(_ source: ConnectionCenterSource) -> String {
        let key: LocalizationKey = switch source {
        case .network: .settingsMiddleIconNetwork
        case .bluetoothDevice: .settingsMiddleIconBluetooth
        case .inputSource: .settingsMiddleIconInputSource
        case .batteryPercentage: .settingsMiddleIconBatteryPercentage
        case .power: .settingsMiddleIconPower
        }
        return localization.string(key)
    }
}

/// A demand owner exists only while the Bluetooth source's controls are visible.
private struct MiddleBluetoothIconOptions: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var bluetoothDevices: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    @State private var settingsDemandToken: BluetoothSettingsDemandToken?

    var body: some View {
        VStack(spacing: 0) {
            if bluetoothDevices.authorization != .allowed {
                permissionRow
                SettingsDivider()
            }
            networkIconSourceRow
            if selectedOption.source == .audioDevices {
                SettingsDivider()
                bluetoothAudioIconChoiceRow
            }
            if !sourceOptionsOffersDevices {
                SettingsDivider()
                SettingsHintRow(text: localization.string(.settingsBluetoothNetworkIconSourceDevicesEmpty))
            }
        }
        .onAppear {
            settingsDemandToken = statusStore.beginBluetoothSettingsDemand()
        }
        .onDisappear {
            if let token = settingsDemandToken { statusStore.endBluetoothSettingsDemand(token) }
            settingsDemandToken = nil
        }
    }

    private var permissionRow: some View {
        let undetermined = bluetoothDevices.authorization == .notDetermined
        return SettingsRow("exclamationmark.triangle.fill", tint: .orange,
            title: localization.string(.settingsBluetoothPermissionRequired),
            subtitle: localization.string(undetermined
                ? .settingsBluetoothPermissionNotDeterminedDescription
                : .settingsBluetoothPermissionDeniedDescription)) {
            Button(localization.string(undetermined
                ? .bluetoothActionRequestAuthorization
                : .bluetoothActionOpenPermissionSettings)) {
                if undetermined { statusStore.requestBluetoothAuthorization() }
                else { statusStore.openBluetoothPermissionSettings() }
            }
            .controlSize(.small)
        }
    }

    private var bluetoothAudioIconChoiceRow: some View {
        SettingsRow(
            "headphones",
            tint: .blue,
            title: localization.string(.settingsBluetoothIconChoice),
            subtitle: localization.string(.settingsBluetoothIconChoiceDescription)
        ) {
            Picker(
                localization.string(.settingsBluetoothIconChoice),
                selection: Binding(
                    get: { store.bluetoothAudioIconChoice },
                    set: { store.bluetoothAudioIconChoice = $0 }
                )
            ) {
                ForEach(IconPresentationResourceResolver.availableBluetoothAudioIconChoices) { choice in
                    Label(
                        choice.displayName(using: localization),
                        systemImage: choice.symbolName ?? "arrow.clockwise"
                    )
                    .tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(localization.string(.settingsBluetoothIconChoice))
            .accessibilityIdentifier("bluetooth.audioIconChoice")
        }
    }

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

}
