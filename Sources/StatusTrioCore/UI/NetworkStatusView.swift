import AppKit
import SwiftUI

struct NetworkStatusView: View {
    @EnvironmentObject private var localization: Localization
    var showsWiFiPowerControl = false
    var wifiPowerIsOn = false
    var wifiPowerCanSet = false
    var wifiPowerRequiresConfirmation = false
    var wifiPowerFailed = false
    var onSetWiFiPower: (Bool) -> Void = { _ in }
    let state: PanelSummaryState
    let onOpenWiFiDetails: (Bool) -> Void
    let onOpenWiredDetails: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    @State private var confirmingPowerOff = false

    private var isWired: Bool { state.intent == .wiredDetails }
    private var hasWiFiDetails: Bool { state.intent == .wifiDetails }
    private var showsPowerToggle: Bool { hasWiFiDetails && showsWiFiPowerControl }
    /// The chevron promises a detail page. A permission row only raises the
    /// system prompt or opens Settings, so it must not advertise navigation.
    private var showsDisclosureChevron: Bool {
        state.intent == .wifiDetails || state.intent == .wiredDetails
    }

    var body: some View {
        HStack(alignment: .center, spacing: PanelSummaryActionMetrics.iconGap) {
            Button(action: { activateRow() }) {
                HStack(alignment: .center, spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(.secondary)
                        .frame(
                            width: PanelSummaryActionMetrics.hitTarget,
                            height: PanelSummaryActionMetrics.hitTarget
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        subtitle
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if showsPowerToggle {
                powerToggle
            }

            // The row already opens the page from its text; the chevron is its
            // visual affordance. It stays a sibling so the power control can sit
            // between the row content and it.
            if showsDisclosureChevron {
                Button(action: { activateRow() }) {
                    PanelActionGlyph(
                        systemName: "chevron.right",
                        font: .caption.weight(.semibold)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }

            if state.showsSettings {
                Button(action: isWired ? onOpenNetworkSettings : onOpenWiFiSettings) {
                    PanelActionGlyph(systemName: "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(isWired ? .ethernetActionOpenSettings : .wifiActionOpenSettings))
                .accessibilityLabel(
                    localization.string(isWired ? .ethernetActionOpenSettings : .wifiActionOpenSettings)
                )
            }
        }
        .alert(
            localization.string(.wifiPowerOffConfirmTitle),
            isPresented: $confirmingPowerOff
        ) {
            Button(localization.string(.wifiPowerOffConfirmAction), role: .destructive) {
                onSetWiFiPower(false)
            }
            Button(localization.string(.commonCancel), role: .cancel) {}
        } message: {
            Text(localization.string(.wifiPowerOffConfirmMessage))
        }
    }

    private var powerToggle: some View {
        Button {
            switch WiFiPowerTogglePolicy.decision(
                isOn: wifiPowerIsOn,
                requiresConfirmation: wifiPowerRequiresConfirmation
            ) {
            case let .set(enabled):
                onSetWiFiPower(enabled)
            case .confirmOff:
                confirmingPowerOff = true
            }
        } label: {
            PanelActionGlyph(systemName: "power")
        }
        .buttonStyle(.plain)
        .foregroundStyle(wifiPowerIsOn ? Color.accentColor : Color.secondary)
        .disabled(!wifiPowerCanSet)
        .help(
            WiFiPowerTogglePolicy.accessibilityLabel(isOn: wifiPowerIsOn, localization: localization)
        )
        .accessibilityLabel(
            WiFiPowerTogglePolicy.accessibilityLabel(isOn: wifiPowerIsOn, localization: localization)
        )
        .accessibilityValue(
            WiFiPowerTogglePolicy.accessibilityValue(isOn: wifiPowerIsOn, localization: localization)
        )
    }

    @ViewBuilder
    private var subtitle: some View {
        if showPowerFailure {
            Text(localization.string(.wifiPowerChangeFailed))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if state.subtitle == " " {
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

    private var showPowerFailure: Bool {
        hasWiFiDetails && wifiPowerFailed
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
        case .none, .batteryDetails,
             .requestBluetoothAuthorization, .openBluetoothPermissionSettings:
            break
        }
    }
}
