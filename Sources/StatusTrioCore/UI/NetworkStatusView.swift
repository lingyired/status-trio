import AppKit
import SwiftUI

struct NetworkStatusView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelSummaryState
    let onOpenWiFiDetails: (Bool) -> Void
    let onOpenWiredDetails: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    private var isWired: Bool { state.intent == .wiredDetails }
    private var hasWiFiDetails: Bool { state.intent == .wifiDetails }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { activateRow() }) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        subtitle
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if state.showsSettings {
                Button(
                    localization.string(isWired ? .ethernetActionOpenSettings : .wifiActionOpenSettings),
                    systemImage: "gearshape",
                    action: isWired ? onOpenNetworkSettings : onOpenWiFiSettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(isWired ? .ethernetActionOpenSettings : .wifiActionOpenSettings))
                .frame(width: 24, height: 24)
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if state.subtitle == " " {
            Text(verbatim: " ")
                .font(.caption)
                .accessibilityHidden(true)
        } else {
            Text(state.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(isWired ? .middle : .tail)
        }
    }

    private func activateRow() {
        switch state.intent {
        case .wifiDetails:
            onOpenWiFiDetails(NSEvent.modifierFlags.contains(.option))
        case .wiredDetails:
            onOpenWiredDetails()
        case .requestWiFiNameAccess:
            onRequestNameAccess()
        case .locationSettings:
            onOpenLocationSettings()
        case .none, .batteryDetails, .requestBluetoothAuthorization, .openBluetoothPermissionSettings:
            break
        }
    }
}
