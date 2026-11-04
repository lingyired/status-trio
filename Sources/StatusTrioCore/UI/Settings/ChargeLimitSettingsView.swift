import SwiftUI

/// Opt-in charge management, separate from the battery icon's full-ring level.
@MainActor
struct ChargeLimitSettingsView: View {
    @ObservedObject var controller: ManagedChargeLimitController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(
            localization.string(.settingsBatteryChargeLimitTitle),
            footnote: localization.string(.settingsBatteryChargeLimitSupport)
        ) {
            SettingsRow(
                "battery.100",
                tint: .green,
                title: localization.string(.settingsBatteryChargeLimitTarget),
                subtitle: localization.string(.settingsBatteryChargeLimitDescription)
            ) {
                Picker(
                    localization.string(.settingsBatteryChargeLimitTarget),
                    selection: limitSelection
                ) {
                    Text(localization.string(.settingsBatteryChargeLimitSystemManaged))
                        .tag(0)
                    ForEach(controller.availableLimits, id: \.self) { limit in
                        Text("\(limit)%").tag(limit)
                    }
                    if let unavailableLimit {
                        Text(localization.format(
                            .settingsBatteryChargeLimitUnavailableOption,
                            unavailableLimit
                        ))
                        .tag(unavailableLimit)
                        .disabled(true)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(controller.isApplying || !controller.isAvailable)
                .accessibilityLabel(
                    localization.string(.settingsBatteryChargeLimitTarget)
                )
            }

            SettingsDivider()

            SettingsRow(
                "info.circle",
                tint: .green,
                title: localization.string(.settingsBatteryChargeLimitStatus),
                subtitle: statusText
            ) {
                if controller.isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryChargeLimitApplying)
                        )
                } else if controller.selectedLimit != nil {
                    Button(localization.string(.settingsBatteryChargeLimitReapply)) {
                        reapply()
                    }
                    .controlSize(.small)
                    .disabled(!controller.isAvailable || unavailableLimit != nil)
                }
            }

            SettingsHintRow(
                text: localization.string(.settingsBatteryChargeLimitRestoreDescription)
            )

            // This section is only offered on macOS 26.4+ (the PowerUI MCL
            // capability gate). On those systems the built-in battery
            // optimization is usually the better choice, so say so explicitly.
            if controller.isAvailable {
                SettingsHintRow(
                    text: localization.string(
                        .settingsBatteryChargeLimitPreferSystemOptimization
                    )
                )
            }
        }
        .onAppear {
            controller.refresh()
        }
    }

    private var limitSelection: Binding<Int> {
        Binding(
            get: { controller.selectedLimit ?? 0 },
            set: { value in
                selectLimit(value == 0 ? nil : value)
            }
        )
    }

    private var unavailableLimit: Int? {
        guard let selected = controller.selectedLimit,
              !controller.availableLimits.contains(selected) else { return nil }
        return selected
    }

    private var statusText: String {
        if controller.isApplying {
            return localization.string(.settingsBatteryChargeLimitApplying)
        }
        switch controller.status {
        case .systemManaged:
            return localization.string(.settingsBatteryChargeLimitSystemStatus)
        case .checking:
            return localization.string(.settingsBatteryChargeLimitChecking)
        case .active(let limit):
            if let unavailableLimit {
                return localization.format(
                    .settingsBatteryChargeLimitUnavailable,
                    unavailableLimit
                )
            }
            return localization.format(.settingsBatteryChargeLimitActive, limit)
        case .temporarilyOverridden(let limit):
            return localization.format(.settingsBatteryChargeLimitOverridden, limit)
        case .failed:
            return localization.string(.settingsBatteryChargeLimitFailed)
        case .externalChange:
            return localization.string(.settingsBatteryChargeLimitExternalChange)
        }
    }

    private func selectLimit(_ limit: Int?) {
        guard !controller.isApplying else { return }
        Task { @MainActor in
            await controller.selectLimit(limit)
        }
    }

    private func reapply() {
        guard !controller.isApplying else { return }
        Task { @MainActor in
            await controller.reapply()
        }
    }
}
