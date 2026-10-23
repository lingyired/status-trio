import AppKit
import SwiftUI

enum IconGuidePart: CaseIterable, Identifiable {
    case battery, network, volume
    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .battery: .settingsPopupOrderBattery
        // The same name the popup section carries, and the one its own
        // explanation already uses: this part of the icon shows network status,
        // and its symbol changes with the connection type.
        case .network: .settingsPopupOrderNetwork
        case .volume: .settingsPopupOrderVolume
        }
    }

    func explanationKey(volumeStyle: VolumeDisplayStyle) -> LocalizationKey {
        switch self {
        case .battery: .guideBattery
        case .network: .guideNetwork
        case .volume: volumeStyle == .dots ? .guideVolumeDots : .guideVolumeArc
        }
    }
}

enum IconGuidePage: Equatable {
    case anatomy
    case states

    var next: Self {
        switch self {
        case .anatomy: .states
        case .states: .states
        }
    }

    var previous: Self {
        switch self {
        case .anatomy: .anatomy
        case .states: .anatomy
        }
    }
}

enum IconGuidePreviewAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var isDarkBackground: Bool {
        self == .dark
    }

    var dockBackgroundStyle: DockIconBackgroundStyle {
        self == .dark ? .dark : .light
    }

    var titleKey: LocalizationKey {
        self == .dark ? .settingsPreviewDark : .settingsPreviewLight
    }
}

enum IconGuideState: String, CaseIterable, Identifiable, Sendable {
    case charging
    case lowBattery
    case ethernet
    case noInternetMuted
    case hotspotLowPower
    case weakWiFi
    case wifiOff
    case bluetoothHeadphones
    case bluetoothAirPods
    case wifiVolumeTint

    static var all: [Self] { allCases }

    var id: String { rawValue }

    var volumeDisplayStyleOverride: VolumeDisplayStyle? {
        switch self {
        case .charging: .dots
        case .weakWiFi: .arc
        case .bluetoothHeadphones: .dots
        case .bluetoothAirPods: .dots
        case .wifiVolumeTint: .dots
        default: nil
        }
    }

    var titleKey: LocalizationKey {
        switch self {
        case .charging: .guideStateCharging
        case .lowBattery: .guideStateLowBattery
        case .ethernet: .guideStateEthernet
        case .noInternetMuted: .guideStateNoInternetMuted
        case .hotspotLowPower: .guideStateHotspotLowPower
        case .weakWiFi: .guideStateWeakWiFi
        case .wifiOff: .guideStateWiFiOff
        case .bluetoothHeadphones: .guideStateBluetoothHeadphones
        case .bluetoothAirPods: .guideStateBluetoothAirPods
        case .wifiVolumeTint: .guideStateWiFiVolumeTint
        }
    }

    /// The examples' own Bluetooth settings, layered over the configured ones.
    /// The guide opens on a fresh install where both options are still off, and a
    /// card that followed the defaults would show the same Wi-Fi artwork twice.
    ///
    /// The two device cards show one icon: the device symbol replaces the network
    /// symbol in the middle and the volume row underneath turns blue. The third
    /// keeps the Wi-Fi symbol in the middle and only tints the volume row, which
    /// is what the volume colour option does on its own; its label names Wi-Fi
    /// because that is the symbol the card draws.
    func bluetoothAudioOptions(
        configuring configured: BluetoothAudioIconOptions
    ) -> BluetoothAudioIconOptions {
        switch self {
        case .bluetoothHeadphones, .bluetoothAirPods:
            BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                usesVolumeColor: true,
                prioritizesNetworkErrors: configured.prioritizesNetworkErrors,
                symbolScale: configured.symbolScale
            )
        case .wifiVolumeTint:
            BluetoothAudioIconOptions(
                replacesNetworkIcon: false,
                usesVolumeColor: true,
                prioritizesNetworkErrors: configured.prioritizesNetworkErrors,
                symbolScale: configured.symbolScale
            )
        default:
            configured
        }
    }

    /// The Bluetooth examples stand in for the audio device, one per device
    /// family so each card shows the symbol the system uses for it. They only
    /// feed the artwork: nothing is read from the system.
    static let bluetoothHeadphonesExampleDevice = AudioOutputDevice(
        id: 0,
        name: "Bluetooth Headphones",
        uid: "guide.bluetooth.headphones",
        isCurrent: true,
        volume: 0.6,
        transport: .bluetooth
    )

    static let airPodsExampleDevice = AudioOutputDevice(
        id: 1,
        name: "AirPods",
        uid: "guide.bluetooth.airpods",
        isCurrent: true,
        volume: 0.6,
        transport: .bluetooth
    )

    /// The audio device this example draws, if it is a Bluetooth one. The card
    /// that keeps the network symbol still needs a Bluetooth output for its
    /// volume row to take the device colour.
    var exampleDevice: AudioOutputDevice? {
        switch self {
        case .bluetoothHeadphones, .wifiVolumeTint: Self.bluetoothHeadphonesExampleDevice
        case .bluetoothAirPods: Self.airPodsExampleDevice
        default: nil
        }
    }

    var status: MenuBarStatus {
        switch self {
        case .bluetoothHeadphones, .bluetoothAirPods, .wifiVolumeTint:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 82,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .connected, rssi: -50),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.62,
                    isMuted: false,
                    deviceName: exampleDevice?.name,
                    currentDevice: exampleDevice
                )
            )
        case .charging:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 68,
                    isPresent: true,
                    isCharging: true,
                    isLowPowerMode: false,
                    isConnectedToPower: true
                ),
                wifi: WiFiStatus(state: .connected, rssi: -52),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.62,
                    isMuted: false,
                    deviceName: nil
                )
            )
        case .lowBattery:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 12,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .connected, rssi: -58),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.5,
                    isMuted: false,
                    deviceName: nil
                )
            )
        case .ethernet:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 100,
                    isPresent: true,
                    isCharging: false,
                    isCharged: true,
                    isLowPowerMode: false,
                    isConnectedToPower: true
                ),
                wifi: WiFiStatus(state: .off, rssi: nil),
                connection: .ethernet,
                volume: MenuBarVolumeStatus(
                    scalar: 0.75,
                    isMuted: false,
                    deviceName: nil
                )
            )
        case .noInternetMuted:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 74,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .noInternet, rssi: -62),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.35,
                    isMuted: true,
                    deviceName: nil
                )
            )
        case .hotspotLowPower:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 54,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: true,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .hotspot, rssi: -48),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.45,
                    isMuted: false,
                    deviceName: nil
                )
            )
        case .weakWiFi:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 78,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .connected, rssi: -86),
                connection: .wifi,
                volume: MenuBarVolumeStatus(
                    scalar: 0.25,
                    isMuted: false,
                    deviceName: nil
                )
            )
        case .wifiOff:
            MenuBarStatus(
                battery: BatteryStatus(
                    rawPercentage: 91,
                    isPresent: true,
                    isCharging: false,
                    isLowPowerMode: false,
                    isConnectedToPower: false
                ),
                wifi: WiFiStatus(state: .off, rssi: nil),
                connection: .offline,
                volume: MenuBarVolumeStatus(
                    scalar: 0.5,
                    isMuted: false,
                    deviceName: nil
                )
            )
        }
    }
}

/// Two live previews that share one selected part and a static highlight.
struct IconGuideView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var isMenuBarHelpPresented: Bool
    @EnvironmentObject private var localization: Localization
    @State var selectedPart: IconGuidePart = .battery
    private let menuBarHelpPolicy = MenuBarHelpPolicy()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localization.string(.guideAnatomyTitle))
                .font(.title3.weight(.semibold))

            Text(localization.string(.guideAnatomyDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string(.settingsMenuBarTitle))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                MenuBarPreviewBar(
                    status: Self.example,
                    iconSize: 32,
                    batteryOptions: demoBatteryOptions,
                    connectionOptions: settings.connectionIconOptions,
                    volumeOptions: settings.volumeIconOptions,
                    isDarkBackground: true,
                    highlightedPart: selectedPart,
                    highlightOpacity: highlightOpacity
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string(.settingsAppIconDockGroup))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                DockPreviewBar(
                    status: Self.example,
                    batteryOptions: demoBatteryOptions,
                    connectionOptions: settings.connectionIconOptions,
                    volumeOptions: settings.volumeIconOptions,
                    backgroundStyle: resolvedDockBackgroundStyle,
                    isDarkBackground: true,
                    statusIconSize: 56,
                    highlightedPart: selectedPart,
                    highlightOpacity: highlightOpacity
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 8) {
                ForEach(IconGuidePart.allCases) { part in
                    Button {
                        selectedPart = part
                    } label: {
                        Text(localization.string(part.titleKey))
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        selectedPart == part
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.10)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        selectedPart == part
                                            ? Color.accentColor.opacity(0.75)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(localization.string(part.explanationKey(volumeStyle: settings.volumeDisplayStyle)))
                    .accessibilityAddTraits(selectedPart == part ? .isSelected : [])
                }
            }

            Text(localization.string(selectedPart.explanationKey(volumeStyle: settings.volumeDisplayStyle)))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)

            menuBarHelpEntry
        }
    }

    private var highlightOpacity: Double {
        0.88
    }

    private var menuBarHelpEntry: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(localization.string(.guideMenuBarHelpPrompt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                isMenuBarHelpPresented.toggle()
            } label: {
                Label(
                    localization.string(.guideMenuBarHelpOpen),
                    systemImage: "questionmark.circle"
                )
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel(localization.string(.guideMenuBarHelpOpen))
            .accessibilityIdentifier("guide.menuBarHelp.open")
            .popover(
                isPresented: $isMenuBarHelpPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                MenuBarVisibilityHelpView(
                    policy: menuBarHelpPolicy,
                    onClose: { isMenuBarHelpPresented = false },
                    openSettings: { urls in Self.openSystemSettings(urls) }
                )
                .environmentObject(localization)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// System Settings opens even when it cannot resolve a pane, so the first
    /// route does not prove the destination. Every policy keeps the exact
    /// written path in the view and ends with the app itself as the fallback.
    private static func openSystemSettings(_ urls: [URL]) {
        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    private var resolvedDockBackgroundStyle: DockIconBackgroundStyle {
        DockIconBackgroundResolver.style(
            for: settings.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }

    private var demoBatteryOptions: BatteryIconOptions {
        Self.demoBatteryOptions(configured: settings.batteryIconOptions)
    }

    static func demoBatteryOptions(
        configured: BatteryIconOptions
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: true,
            showsChargingIndicator: false,
            usesStatusColors: true,
            criticalThreshold: configured.criticalThreshold,
            showsPercentageWhenConnected: true,
            fullThreshold: configured.fullThreshold,
            textScale: configured.textScale,
            ringStrokeScale: configured.ringStrokeScale
        )
    }

    static let example = MenuBarStatus(
        battery: BatteryStatus(rawPercentage: 75, isPresent: true, isCharging: true,
                               isLowPowerMode: false, isConnectedToPower: true),
        wifi: WiFiStatus(state: .connected, rssi: -55),
        connection: .wifi,
        volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
    )
}

struct IconGuideStateGalleryView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @State private var previewAppearance: IconGuidePreviewAppearance = .dark

    /// Five columns keep the nine examples on two rows, so adding one does not
    /// grow the page past the height the onboarding window is sized for.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 5
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localization.string(.guideStatesTitle))
                .font(.title3.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(localization.string(.guideStatesDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker(
                    localization.string(.settingsPreviewToggleHelp),
                    selection: $previewAppearance
                ) {
                    ForEach(IconGuidePreviewAppearance.allCases) { appearance in
                        Label(
                            localization.string(appearance.titleKey),
                            systemImage: appearance == .dark
                                ? "moon.fill"
                                : "sun.max.fill"
                        )
                        .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
                .accessibilityLabel(
                    localization.string(.settingsPreviewToggleHelp)
                )
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(IconGuideState.all) { state in
                    IconGuideStateCard(
                        state: state,
                        settings: settings,
                        previewAppearance: previewAppearance
                    )
                }
            }
        }
    }
}

/// One state card in the guide grid. Internal, and with an internal memberwise
/// initializer, so a test can host the exact view the grid builds: a `private`
/// stored property anywhere in the card would make that initializer `private`
/// and leave the guide's render behaviour untestable.
struct IconGuideStateCard: View {
    let state: IconGuideState
    @ObservedObject var settings: SettingsStore
    let previewAppearance: IconGuidePreviewAppearance
    var previewCache: DockIconPreviewCache? = nil
    @EnvironmentObject var localization: Localization

    var body: some View {
        VStack(spacing: 10) {
            DockIconTile(
                status: state.status,
                batteryOptions: settings.batteryIconOptions,
                connectionOptions: settings.connectionIconOptions,
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: state.bluetoothAudioOptions(
                    configuring: settings.bluetoothAudioIconOptions
                ),
                backgroundStyle: previewAppearance.dockBackgroundStyle,
                size: 56,
                previewCache: previewCache
            )

            Text(localization.string(state.titleKey))
                .font(.system(size: 11.5, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var volumeOptions: VolumeIconOptions {
        VolumeIconOptions(
            displayStyle: state.volumeDisplayStyleOverride
                ?? settings.volumeDisplayStyle,
            ringStrokeScale: settings.ringStrokeStyle.scale
        )
    }
}
