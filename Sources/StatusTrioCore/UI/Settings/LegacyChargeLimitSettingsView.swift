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
    /// Shows/hides the "立即充满电" button in the battery panel (low versions).
    @Binding var showsPanelButton: Bool
    /// Sleep behaviour while a ceiling is held (low versions).
    @Binding var sleepPolicy: LegacySleepPolicy
    /// Opens System Settings → Battery so the user can turn off Optimized
    /// Battery Charging. No detection is attempted.
    var openBatterySettings: () -> Void = {}
    @EnvironmentObject private var localization: Localization
    @ObservedObject private var helper: PrivilegedHelperManager = .shared

    var body: some View {
        SettingsGroup(
            localization.string(.settingsBatteryLegacyChargeLimitTitle),
            footnote: localization.string(.settingsBatteryLegacyChargeLimitBeta)
        ) {
            // Probes only while this pane is visible; an idle app never
            // spawns the root helper.
            Color.clear
                .frame(height: 0)
                .task { await controller.refreshAvailability() }
            SettingsToggleRow(
                symbol: "battery.100",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitToggle),
                subtitle: localization.string(.settingsBatteryLegacyChargeLimitDescription),
                isOn: isEnabledBinding
            )
            .disabled(controller.isApplying || !controller.isAvailable)

            SettingsDivider()

            SettingsRow(
                "gauge.medium",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitTarget),
                subtitle: localization.string(.settingsBatteryLegacyChargeLimitTargetSliderNote)
            ) {
                HStack(spacing: 10) {
                    Text("\(displayedLimit)%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                    Slider(value: limitSlider, in: 80...100, step: 5)
                        .frame(width: 150)
                }
                .disabled(controller.isApplying || !controller.isAvailable)
            }

            SettingsDivider()
            SettingsRow(
                "moon.zzz.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitSleepPolicy),
                subtitle: localization.string(.settingsBatteryLegacyChargeLimitSleepPolicyDescription)
            ) {
                Picker("", selection: $sleepPolicy) {
                    Text(localization.string(.settingsBatteryLegacyChargeLimitSleepPause))
                        .tag(LegacySleepPolicy.pauseCharging)
                    Text(localization.string(.settingsBatteryLegacyChargeLimitSleepKeepAwake))
                        .tag(LegacySleepPolicy.keepAwakeUntilLimit)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            if LegacyChargeLimitRecovery.showsRestoreAction(status: controller.status) {
                SettingsDivider()
                SettingsRow(
                    "arrow.counterclockwise",
                    tint: .orange,
                    title: localization.string(.settingsBatteryLegacyChargeLimitRestoreOriginal),
                    subtitle: nil
                ) {
                    Button(localization.string(.settingsBatteryLegacyChargeLimitRestoreOriginal)) {
                        run { await controller.disable() }
                    }
                    .controlSize(.small)
                    .disabled(controller.isApplying)
                }
            }

            // Low versions only (macOS 13–15): a toggle that decides whether the
            // battery panel shows the "立即充满电" button. The button itself does
            // the same job as the high-version one; only its backing logic is the
            // legacy limiter (temporary lift, restored the next day).
            if controller.selectedLimit != nil, !needsHelperApproval {
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "bolt.badge.clock.fill",
                    tint: .orange,
                    title: localization.string(.settingsBatteryLegacyChargeLimitShowPanelButton),
                    subtitle: localization.string(.settingsBatteryLegacyChargeLimitTemporaryNote),
                    isOn: $showsPanelButton
                )
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
                    Button(localization.string(.settingsBatteryFullThresholdOpenSystemSettings)) {
                        // Requesting registration is not enough on its own: macOS
                        // asks the user to approve the daemon under Login Items,
                        // so open that pane instead of appearing to do nothing.
                        requestHelperApproval()
                        helper.openLoginItemsSettings()
                        run { await controller.refresh() }
                    }
                    .controlSize(.small)
                }
            }

            SettingsDivider()
            SettingsRow(
                "info.circle",
                tint: .orange,
                title: localization.string(.settingsBatteryLegacyChargeLimitOptimizedChargingNote),
                subtitle: nil
            ) {
                Button(localization.string(.settingsBatteryFullThresholdOpenSystemSettings)) {
                    openBatterySettings()
                }
                .controlSize(.small)
            }
        }
    }

    /// Switch semantics: on = lift the ceiling for 24h, off = resume at once.
    private var temporaryFullBinding: Binding<Bool> {
        Binding(
            get: { controller.isTemporarilyCharging },
            set: { enabled in
                if enabled {
                    run { await controller.chargeToFullOnce() }
                } else {
                    run { await controller.cancelChargeToFull() }
                }
            }
        )
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

    /// 100% means "no ceiling": the slider then simply turns limiting off.
    private var displayedLimit: Int { controller.selectedLimit ?? 100 }

    private var limitSlider: Binding<Double> {
        Binding(
            get: { Double(controller.selectedLimit ?? 100) },
            set: { raw in
                let limit = Int(raw.rounded())
                if limit >= 100 {
                    run { await controller.disable() }
                } else {
                    run { await controller.setLimit(limit) }
                }
            }
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