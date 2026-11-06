import SwiftUI

struct VPNStatusView: View {
    let state: PanelSummaryState
    var onSetPower: (Bool) -> Void = { _ in }
    var onSetMihomoTunnelPower: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            PanelSymbolView(source: state.symbol)
                .foregroundStyle(state.tint.color(caution: .orange))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let failure = state.vpnPower?.failureMessage {
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let power = state.vpnPower {
                powerButton(power)
            }
            if let tun = state.mihomoTunnelPower {
                tunButton(tun)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    private func tunButton(_ power: MihomoTunnelPowerPresentation) -> some View {
        Button {
            onSetMihomoTunnelPower(!power.isOn)
        } label: {
            PanelActionGlyph(systemName: "power")
        }
        .buttonStyle(.plain)
        .foregroundStyle(power.isOn ? Color.accentColor : Color.secondary)
        .disabled(!power.canSetPower || power.isChanging)
        .help(power.actionLabel)
        .accessibilityLabel(power.actionLabel)
        .accessibilityValue(power.isChanging ? power.actionLabel : "")
    }

    private func powerButton(_ power: VPNPowerPresentation) -> some View {
        Button {
            onSetPower(!power.isOn)
        } label: {
            PanelActionGlyph(systemName: "power")
        }
        .buttonStyle(.plain)
        .foregroundStyle(power.isOn ? Color.accentColor : Color.secondary)
        .disabled(!power.canSetPower || power.isChanging)
        .help(power.isChanging
            ? power.changingHelp
            : (power.isOn ? power.turnOffHelp : power.turnOnHelp))
        .accessibilityLabel(power.isOn ? power.turnOffHelp : power.turnOnHelp)
        .accessibilityValue(power.isChanging ? power.changingHelp : "")
    }
}
