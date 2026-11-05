import AppKit
import SwiftUI

struct MiddleIconSettingsGroup: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    /// Omitted on the dedicated "Middle Icon" page, where the page title already
    /// names the section; kept when the group sits among the other icon groups.
    var showsGroupTitle: Bool = true
    @EnvironmentObject private var localization: Localization
    @State private var showsNetworkIconOptions = false

    var body: some View {
        SettingsGroup(showsGroupTitle ? localization.string(.settingsMiddleIconTitle) : nil) {
            sourcePicker

            // This divider follows the full-width picker (no leading icon
            // column), so align it with the picker's content edge instead of the
            // icon-row inset that would leave a gap on the left.
            SettingsDivider(inset: SettingsMetrics.rowPaddingH)
            middleIconSizeRow

            if store.connectionCenterSource == .network {
                SettingsDivider()
                connectionStyleDisclosure
            }

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

    /// One shared size for every middle content: Wi-Fi, Bluetooth, input source
    /// and the numeric modes all follow this value.
    private var middleIconSizeRow: some View {
        SettingsRow(
            "circle.inset.filled",
            tint: .indigo,
            title: localization.string(.settingsMiddleIconSize),
            subtitle: localization.string(.settingsMiddleIconSizeDescription)
        ) {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { store.wifiSymbolScale },
                        set: { store.wifiSymbolScale = (round($0 * 20) / 20) }
                    ),
                    in: SettingsStore.wifiSymbolScaleRange
                )
                .frame(width: 130)
                .controlSize(.small)
                .accessibilityLabel(localization.string(.settingsMiddleIconSize))
                .accessibilityValue("\(Int(round(store.wifiSymbolScale * 100)))%")

                Text("\(Int(round(store.wifiSymbolScale * 100)))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    /// The network-only glyph variants; hidden for the other sources because
    /// they cannot draw a Wi-Fi state.
    private var connectionStyleDisclosure: some View {
        VStack(spacing: 0) {
            SettingsDisclosureRow(
                "cable.connector",
                tint: .teal,
                title: localization.string(.settingsNetworkConnectionIcons),
                subtitle: localization.string(.settingsNetworkConnectionIconsDescription),
                isExpanded: $showsNetworkIconOptions
            )

            if showsNetworkIconOptions {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "cable.connector",
                    tint: .teal,
                    title: localization.string(.settingsNetworkWiFiIconForEthernet),
                    isOn: $store.showsWiFiIconForEthernet
                )
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "personalhotspot",
                    tint: .blue,
                    title: localization.string(.settingsNetworkWiFiIconForHotspot),
                    isOn: $store.showsWiFiIconForHotspot
                )
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "network",
                    tint: .purple,
                    title: localization.string(.settingsNetworkWiFiIconForTemporaryConnection),
                    isOn: $store.showsWiFiIconForTemporaryConnection
                )
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "antenna.radiowaves.left.and.right",
                    tint: .indigo,
                    title: localization.string(.settingsNetworkWiFiIconForInternetSharing),
                    isOn: $store.showsWiFiIconForInternetSharing
                )
            }
        }
    }

    /// Five options are too many for a pop-up menu to read well, so the middle
    /// content is a full-width row of picture tiles: each tile shows what the
    /// slot would draw, and the selected one carries the standard ring.
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.string(.settingsMiddleIconDescription))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                ForEach(ConnectionCenterSource.allCases) { source in
                    let selected = store.connectionCenterSource == source
                    Button {
                        store.connectionCenterSource = source
                    } label: {
                        VStack(spacing: 5) {
                            MiddleIconSourcePreview(source: source)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                                .selectionRing(selected, cornerRadius: 6)
                            Text(sourceLabel(source))
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(sourceLabel(source))
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(localization.string(.settingsMiddleIconSource))

            if store.connectionCenterSource == .chargingStatus {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(localization.string(.settingsMiddleIconChargingStatusDescription))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
        .accessibilityIdentifier("appIcon.middleSource")
    }

    private func sourceLabel(_ source: ConnectionCenterSource) -> String {
        let key: LocalizationKey = switch source {
        case .network: .settingsMiddleIconNetwork
        case .bluetoothDevice: .settingsMiddleIconBluetooth
        case .inputSource: .settingsMiddleIconInputSource
        case .batteryPercentage: .settingsMiddleIconBatteryPercentage
        case .power: .settingsMiddleIconPower
        case .chargingStatus: .settingsMiddleIconChargingStatus
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
        let choice = store.bluetoothAudioIconChoice
        let choiceTitle = choice.displayName(using: localization)
        return SettingsRow(
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
            .settingsMenuPickerWidth()
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
        let option = selectedOption
        let optionTitle = option.title
            ?? localization.string(.settingsBluetoothNetworkIconSourceAudio)
        return SettingsRow(
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
            .pickerStyle(.menu)
            .settingsMenuPickerWidth()
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

/// A real miniature of the status icon with only the middle content changed,
/// so each tile shows exactly what the slot will draw.
private struct MiddleIconSourcePreview: View {
    let source: ConnectionCenterSource
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            MenuBarPreviewBackdrop(isDarkBackground: dark, cornerRadius: 6)
            if let image = MiddleIconPreviewScene.image(for: source, isDarkBackground: dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Builds the still preview for one middle-content option from the real mapper
/// and renderer, with a fixed sample status so the tiles never disagree with
/// the menu bar artwork.
@MainActor
private enum MiddleIconPreviewScene {
    private static let now = Date(timeIntervalSince1970: 1_789_555_974)

    private static let device = AudioOutputDevice(
        id: 0,
        name: "AirPods",
        uid: "middle-icon.preview",
        isCurrent: true,
        volume: 0.5,
        transport: .bluetooth
    )

    private static let inputSource = InputSourceDescriptor(
        id: "com.apple.keylayout.ABC",
        localizedName: "ABC",
        primaryLanguage: "en",
        iconURL: nil,
        shortLabel: "中"
    )

    private static let snapshot = StatusSnapshot(
        battery: BatteryStatus(
            rawPercentage: 68,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        ),
        wifi: WiFiStatus(state: .connected, rssi: -52),
        connection: .wifi,
        volume: VolumeStatus(
            scalar: 0.5,
            isMuted: false,
            deviceName: device.name,
            currentDevice: device
        )
    )

    static func image(for source: ConnectionCenterSource, isDarkBackground: Bool) -> NSImage? {
        let connection = ConnectionIconOptions(
            centerSource: source,
            prioritizesNetworkErrors: true,
            wifiScale: 1.0
        )
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: connection,
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(symbolScale: 1.0)
        )
        let inputs = IconPresentationInputs(
            snapshot: snapshot,
            audioIcon: nil,
            inputSource: source == .inputSource ? inputSource : nil,
            systemPower: source == .power
                ? SystemPowerSample(watts: 24, readAt: now)
                : nil
        )
        let scene = IconPresentationMapper.scene(
            inputs: inputs,
            configuration: configuration,
            now: now
        )
        return StatusIconPreviewCache.shared.image(
            scene: scene,
            size: 28,
            scale: 2,
            appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: isDarkBackground)
        )
    }
}
