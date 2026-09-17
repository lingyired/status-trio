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

/// A clearly labeled example shares the production renderer and current icon options.
struct IconGuideView: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.colorScheme) private var colorScheme
    @State var selectedPart: IconGuidePart = .battery
    @FocusState private var focusedPart: IconGuidePart?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: StatusIconRenderer.image(
                    menuBarStatus: Self.example,
                    size: 56,
                    options: settings.batteryIconOptions,
                    connectionOptions: settings.connectionIconOptions,
                    volumeOptions: settings.volumeIconOptions,
                    appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
                ))
                .accessibilityHidden(true)

                Text(localization.string(.guideExample))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                ForEach(IconGuidePart.allCases) { part in
                    Button(localization.string(part.titleKey)) {
                        selectedPart = part
                    }
                    .accessibilityHint(localization.string(part.explanationKey(volumeStyle: settings.volumeDisplayStyle)))
                    .focused($focusedPart, equals: part)
                    .tint(selectedPart == part ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(selectedPart == part ? .isSelected : [])
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .onChange(of: focusedPart) { _, newValue in
                if let newValue { selectedPart = newValue }
            }

            Text(localization.string(selectedPart.explanationKey(volumeStyle: settings.volumeDisplayStyle)))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        // No animated selection or forced focus: Reduce Motion and keyboard users
        // get the same explanation without requiring a pointer or timed steps.
    }

    static let example = MenuBarStatus(
        battery: BatteryStatus(rawPercentage: 75, isPresent: true, isCharging: false,
                               isLowPowerMode: false, isConnectedToPower: false),
        wifi: WiFiStatus(state: .connected, rssi: -55),
        connection: .wifi,
        volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
    )
}
