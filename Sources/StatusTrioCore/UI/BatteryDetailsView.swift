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
    private let highPowerMode: HighPowerModeController?
    private let showsHighPowerControl: Bool
    private let isConnectedToPower: Bool
    private let chargeToFullNow: ChargeToFullNowPresentation
    private let onChargeToFullNow: () -> Void
    /// The sensor caveats and the energy-ranking caveat live behind the header's
    /// info button instead of taking three lines under the rows.
    @State private var showsInfo = false
    private enum SettingsLink { case system, app }
    /// The expanded button targets overlap, so share one hover selection rather
    /// than letting two independent tracking regions highlight both rows.
    @State private var hoveredSettingsLink: SettingsLink?

    init(
        state: PanelDetailState,
        onBack: @escaping () -> Void,
        onOpenBatterySettings: @escaping () -> Void,
        onOpenAppBatterySettings: @escaping () -> Void = {},
        onCopyValue: @escaping (String) -> Void,
        onAppear: @escaping () -> Void,
        lowPowerMode: LowPowerModeController? = nil,
        showsLowPowerControl: Bool = false,
        highPowerMode: HighPowerModeController? = nil,
        showsHighPowerControl: Bool = false,
        isConnectedToPower: Bool = true,
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
        self.highPowerMode = highPowerMode
        self.showsHighPowerControl = showsHighPowerControl
        self.isConnectedToPower = isConnectedToPower
        self.chargeToFullNow = chargeToFullNow
        self.onChargeToFullNow = onChargeToFullNow
    }

    private var detailRows: [PanelDetailRow] {
        var rows = state.rows
        if state.powerFlow != nil {
            let diagramKeys: Set<String> = [LocalizationKey.batteryDetailsSystemPower.rawValue,
                LocalizationKey.batteryDetailsCharging.rawValue]
            rows = rows.filter { !diagramKeys.contains($0.id) }
        }
        return rows
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

            // Low and High are two states of one system switch. When the Mac
            // supports High Power Mode the page presents the three states
            // together; otherwise only the Low Power toggle exists.
            if showsLowPowerControl, let lowPowerMode,
               showsHighPowerControl, let highPowerMode,
               highPowerMode.isSupported || highPowerMode.needsHelperUpdate
                || highPowerMode.lastError != nil {
                Divider()
                PowerModePickerRow(
                    lowController: lowPowerMode,
                    highController: highPowerMode,
                    isConnectedToPower: isConnectedToPower
                )
            } else if showsLowPowerControl, let lowPowerMode {
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
                BatterySettingsLinkRow(
                    localization.string(.batteryActionOpenSettings),
                    isHovered: hoveredSettingsLink == .system,
                    onHover: { updateSettingsHover(.system, hovering: $0) },
                    action: onOpenBatterySettings
                )
                .zIndex(hoveredSettingsLink == .system ? 1 : 0)
                BatterySettingsLinkRow(
                    localization.string(.batteryActionOpenAppBatterySettings),
                    isHovered: hoveredSettingsLink == .app,
                    onHover: { updateSettingsHover(.app, hovering: $0) },
                    action: onOpenAppBatterySettings
                )
                .zIndex(hoveredSettingsLink == .app ? 1 : 0)
            }
        }
        .task(id: state.lifecycleIdentity) { onAppear() }
    }

    private func updateSettingsHover(_ link: SettingsLink, hovering: Bool) {
        if hovering {
            hoveredSettingsLink = link
        } else if hoveredSettingsLink == link {
            // An exit from the previous row must not clear the new selection.
            hoveredSettingsLink = nil
        }
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
