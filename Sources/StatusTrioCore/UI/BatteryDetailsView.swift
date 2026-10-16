import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void
    let onCopyValue: (String) -> Void
    let onAppear: () -> Void
    /// The Low Power Mode write path, injected by the popover. Nil in previews
    /// and layout tests, where the read-only row stands in for it.
    private let lowPowerMode: LowPowerModeController?
    private let showsLowPowerControl: Bool

    init(
        state: PanelDetailState,
        onBack: @escaping () -> Void,
        onOpenBatterySettings: @escaping () -> Void,
        onCopyValue: @escaping (String) -> Void,
        onAppear: @escaping () -> Void,
        lowPowerMode: LowPowerModeController? = nil,
        showsLowPowerControl: Bool = false
    ) {
        self.state = state
        self.onBack = onBack
        self.onOpenBatterySettings = onOpenBatterySettings
        self.onCopyValue = onCopyValue
        self.onAppear = onAppear
        self.lowPowerMode = lowPowerMode
        self.showsLowPowerControl = showsLowPowerControl
    }

    private var detailRows: [PanelDetailRow] { state.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )

            VStack(alignment: .leading, spacing: 6) {
                if state.isLoading {
                    Text(localization.string(.batteryDetailsLoading))
                        .foregroundStyle(.secondary)
                }
                PanelDetailRowsView(detailRows: detailRows, onCopyValue: onCopyValue)
                if let explanation = state.explanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption)
            .monospacedDigit()

            if showsLowPowerControl, let lowPowerMode {
                Divider()
                lowPowerControlRow(lowPowerMode)
            }

            Divider()
            Button(localization.string(.batteryActionOpenSettings), action: onOpenBatterySettings)
                .buttonStyle(.plain)
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
}