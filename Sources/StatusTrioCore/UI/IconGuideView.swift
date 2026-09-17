import AppKit
import SwiftUI

enum IconGuidePart: CaseIterable, Identifiable {
    case battery, network, volume
    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .battery: .settingsPopupOrderBattery
        case .network: .wifiTitle
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

    static var all: [Self] { allCases }

    var id: String { rawValue }

    var volumeDisplayStyleOverride: VolumeDisplayStyle? {
        switch self {
        case .charging: .dots
        case .weakWiFi: .arc
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
        }
    }

    var status: MenuBarStatus {
        switch self {
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
        }
    }
}

/// Two live previews that share one selected part and one pulse.
struct IconGuideView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var selectedPart: IconGuidePart = .battery
    @State private var pulse = false

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
                    batteryOptions: settings.batteryIconOptions,
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
                    batteryOptions: settings.batteryIconOptions,
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

            Label(
                localization.string(.guidePlacement),
                systemImage: "arrow.left.arrow.right"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: restartPulse)
        .onChange(of: selectedPart) { _, _ in
            restartPulse()
        }
        .onChange(of: reduceMotion) { _, _ in
            restartPulse()
        }
    }

    private var highlightOpacity: Double {
        guard !reduceMotion else { return 0.88 }
        return pulse ? 0.18 : 0.95
    }

    private var resolvedDockBackgroundStyle: DockIconBackgroundStyle {
        DockIconBackgroundResolver.style(
            for: settings.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }

    private func restartPulse() {
        pulse = false
        guard !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 0.72)
                .repeatForever(autoreverses: true)
        ) {
            pulse = true
        }
    }

    static let example = MenuBarStatus(
        battery: BatteryStatus(rawPercentage: 75, isPresent: true, isCharging: false,
                               isLowPowerMode: false, isConnectedToPower: false),
        wifi: WiFiStatus(state: .connected, rssi: -55),
        connection: .wifi,
        volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
    )
}

struct IconGuideStateGalleryView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @State private var previewAppearance: IconGuidePreviewAppearance = .dark

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 3
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

private struct IconGuideStateCard: View {
    let state: IconGuideState
    @ObservedObject var settings: SettingsStore
    let previewAppearance: IconGuidePreviewAppearance
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(spacing: 10) {
            DockIconTile(
                status: state.status,
                batteryOptions: settings.batteryIconOptions,
                connectionOptions: settings.connectionIconOptions,
                volumeOptions: volumeOptions,
                backgroundStyle: previewAppearance.dockBackgroundStyle,
                size: 56
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
                ?? settings.volumeDisplayStyle
        )
    }
}
