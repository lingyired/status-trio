import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void
    let onOpenAppBatterySettings: () -> Void
    let onCopyValue: (String) -> Void
    let onAppear: () -> Void
    /// The Low Power Mode write path, injected by the popover. Nil in previews
    /// and layout tests, where the read-only row stands in for it.
    private let lowPowerMode: LowPowerModeController?
    private let showsLowPowerControl: Bool
    private let chargeToFullNow: ChargeToFullNowPresentation
    private let onChargeToFullNow: () -> Void
    /// The sensor caveats and the energy-ranking caveat live behind the header's
    /// info button instead of taking three lines under the rows.
    @State private var showsInfo = false

    init(
        state: PanelDetailState,
        onBack: @escaping () -> Void,
        onOpenBatterySettings: @escaping () -> Void,
        onOpenAppBatterySettings: @escaping () -> Void = {},
        onCopyValue: @escaping (String) -> Void,
        onAppear: @escaping () -> Void,
        lowPowerMode: LowPowerModeController? = nil,
        showsLowPowerControl: Bool = false,
        chargeToFullNow: ChargeToFullNowPresentation = .hidden,
        onChargeToFullNow: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onBack = onBack
        self.onOpenBatterySettings = onOpenBatterySettings
        self.onOpenAppBatterySettings = onOpenAppBatterySettings
        self.onCopyValue = onCopyValue
        self.onAppear = onAppear
        self.lowPowerMode = lowPowerMode
        self.showsLowPowerControl = showsLowPowerControl
        self.chargeToFullNow = chargeToFullNow
        self.onChargeToFullNow = onChargeToFullNow
    }

    private var detailRows: [PanelDetailRow] {
        guard state.powerFlow != nil else { return state.rows }
        let diagramKeys: Set<String> = [LocalizationKey.batteryDetailsSystemPower.rawValue,
            LocalizationKey.batteryDetailsCharging.rawValue]
        return state.rows.filter { !diagramKeys.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )
            .overlay(alignment: .trailing) {
                if showsInfoButton {
                    infoButton
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let powerFlow = state.powerFlow {
                    BatteryPowerFlowView(state: powerFlow)
                }
                if state.isLoading {
                    Text(localization.string(.batteryDetailsLoading))
                        .foregroundStyle(.secondary)
                }
                PanelDetailRowsView(detailRows: detailRows, onCopyValue: onCopyValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption)
            .monospacedDigit()

            if let ranking = state.energyApps {
                Divider()
                HighEnergyAppsView(ranking: ranking)
            }

            if showsLowPowerControl, let lowPowerMode {
                Divider()
                lowPowerControlRow(lowPowerMode)
            }

            if chargeToFullNow.showsActionArea {
                Divider()
                ChargeToFullNowActionView(
                    presentation: chargeToFullNow,
                    onAction: onChargeToFullNow
                )
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button(
                    localization.string(.batteryActionOpenSettings),
                    action: onOpenBatterySettings
                )
                .buttonStyle(.plain)
                Button(
                    localization.string(.batteryActionOpenAppBatterySettings),
                    action: onOpenAppBatterySettings
                )
                .buttonStyle(.plain)
            }
        }
        .task(id: state.lifecycleIdentity) { onAppear() }
    }

    private func lowPowerControlRow(_ controller: LowPowerModeController) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                localization.string(.lowPowerModeToggle),
                isOn: Binding(
                    get: { controller.isLowPowerMode },
                    set: { controller.setLowPowerMode($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(controller.isApplying)
            .help(localization.string(.lowPowerModeToggleDescription))

            if let error = controller.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Anything the page used to spell out under the rows.
    private var showsInfoButton: Bool {
        state.explanation != nil || state.energyApps != nil
    }

    private var infoButton: some View {
        Button {
            showsInfo.toggle()
        } label: {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(localization.string(.batteryDetailsInfo))
        .help(localization.string(.batteryDetailsInfo))
        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
            infoContent
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
    }

    @ViewBuilder private var infoContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let explanation = state.explanation {
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.powerFlow?.system != nil {
                Text(localization.string(.batteryPowerSystemExplanation))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ranking = state.energyApps {
                Text(localization.string(ranking.basis == .cpuEnergy
                    ? .batteryEnergyCPUExplanation : .batteryEnergyActivityExplanation))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
