import SwiftUI

/// Legacy charge limit (macOS 13–15). Experimental: the hardware backends have
/// not been validated on real Intel/Apple Silicon machines, so the group says so
/// and stays off until the user opts in.
@MainActor
struct LegacyChargeLimitSettingsView: View {
    @ObservedObject var controller: LegacyChargeLimitController
    /// Registers the shared helper through the existing Login Items approval
    /// flow. The helper is one signed resource for both Low Power Mode and the
    /// charge limiter, so the legacy group reuses that affordance instead of
    /// introducing a second approval mechanism.
    var requestHelperApproval: () -> Void = {}
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsGroup(
            localization.string(.settingsBatteryLegacyChargeLimitTitle),
            footnote: localization.string(.settingsBatteryLegacyChargeLimitBeta)
        ) {
            SettingsRow(
                "battery.100",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitToggle),
                subtitle: localization.string(.settingsBatteryLegacyChargeLimitDescription)
            ) {
                Toggle("", isOn: isEnabledBinding)
                    .labelsHidden()
                    .disabled(controller.isApplying || !controller.isAvailable)
                    .accessibilityLabel(
                        localization.string(.settingsBatteryLegacyChargeLimitToggle)
                    )
            }

            SettingsDivider()

            SettingsRow(
                "gauge.medium",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitTarget),
                subtitle: nil
            ) {
                Picker(
                    localization.string(.settingsBatteryLegacyChargeLimitTarget),
                    selection: limitSelection
                ) {
                    ForEach(LegacyChargeLimitController.limits, id: \.self) { limit in
                        Text("\(limit)%").tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(controller.isApplying || !controller.isAvailable)
            }

            SettingsDivider()

            SettingsRow(
                "info.circle",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitStatus),
                subtitle: statusText
            ) {
                if controller.isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryLegacyChargeLimitChecking)
                        )
                } else if needsHelperApproval {
                    Button(localization.string(.settingsBatteryLegacyChargeLimitHelperRequired)) {
                        requestHelperApproval()
                        run { await controller.refresh() }
                    }
                    .controlSize(.small)
                } else if controller.selectedLimit != nil {
                    Button(localization.string(.settingsBatteryLegacyChargeLimitChargeToFull)) {
                        run { await controller.chargeToFullOnce() }
                    }
                    .controlSize(.small)
                    .disabled(!controller.isAvailable)
                }
            }
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.selectedLimit != nil },
            set: { enabled in
                if enabled {
                    run { await controller.setLimit(80) }
                } else {
                    run { await controller.disable() }
                }
            }
        )
    }

    private var limitSelection: Binding<Int> {
        Binding(
            get: { controller.selectedLimit ?? 80 },
            set: { limit in run { await controller.setLimit(limit) } }
        )
    }

    private var needsHelperApproval: Bool {
        controller.availability == .unavailable(.helperUnavailable)
    }

    private var statusText: String {
        if needsHelperApproval {
            return localization.string(.settingsBatteryLegacyChargeLimitHelperRequired)
        }
        switch controller.status {
        case .notEnabled:
            return localization.string(.settingsBatteryLegacyChargeLimitNotEnabled)
        case .helperApprovalRequired:
            return localization.string(.settingsBatteryLegacyChargeLimitHelperRequired)
        case .checkingHardware:
            return localization.string(.settingsBatteryLegacyChargeLimitChecking)
        case let .holding(limit):
            return localization.format(.settingsBatteryLegacyChargeLimitHolding, limit)
        case .temporarilyChargingToFull:
            return localization.string(.settingsBatteryLegacyChargeLimitTemporaryFull)
        case .unsupported:
            return localization.string(.settingsBatteryLegacyChargeLimitUnsupported)
        case .restoreFailed:
            return localization.string(.settingsBatteryLegacyChargeLimitRestoreFailed)
        case .failed:
            return localization.string(.settingsBatteryLegacyChargeLimitFailed)
        case .externalChange:
            return localization.string(.settingsBatteryLegacyChargeLimitExternalChange)
        case .unverified:
            return localization.string(.settingsBatteryLegacyChargeLimitUnverified)
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        Task { @MainActor in await operation() }
    }
}