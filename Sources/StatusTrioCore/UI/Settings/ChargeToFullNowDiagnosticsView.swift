import SwiftUI

/// Reads only while the Battery settings page is mounted. No timer or charge
/// limit write is needed to explain why the summary action is hidden.
struct ChargeToFullNowDiagnosticsView: View {
    @ObservedObject var controller: ChargeToFullNowController
    let battery: BatteryStatus
    let batterySectionVisible: Bool
    let enabled: Bool
    @EnvironmentObject private var localization: Localization
    @State private var reasons: [ChargeToFullNowHiddenReason] = []

    /// Everything a refresh depends on, as one equatable value. `presentation`
    /// participates because an in-flight charge or cancel changes how the live
    /// limit state should be read.
    private struct RefreshInput: Equatable {
        let battery: BatteryStatus
        let batterySectionVisible: Bool
        let enabled: Bool
        let presentation: ChargeToFullNowPresentation
    }

    private var refreshInput: RefreshInput {
        RefreshInput(
            battery: battery,
            batterySectionVisible: batterySectionVisible,
            enabled: enabled,
            presentation: controller.presentation
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if enabled {
                ForEach(reasons.indices, id: \.self) { index in
                    Text(ChargeToFullNowHiddenReasonText.text(
                        for: reasons[index],
                        localization: localization
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.bottom, enabled && !reasons.isEmpty ? 8 : 0)
        .task(id: refreshInput) {
            reasons = enabled
                ? controller.hiddenReasons(
                    battery: battery,
                    batterySectionVisible: batterySectionVisible
                )
                : []
        }
    }
}

/// Keeps user-facing diagnostic strings in one place so the view stays layout
/// only. Each reason maps to the same localized sentence a person reads under
/// the toggle.
@MainActor
enum ChargeToFullNowHiddenReasonText {
    static func text(
        for reason: ChargeToFullNowHiddenReason,
        localization: Localization
    ) -> String {
        switch reason {
        case .unsupportedSystem:
            return localization.string(.settingsBatteryChargeHiddenUnsupportedSystem)
        case .unsupportedArchitecture:
            return localization.string(.settingsBatteryChargeHiddenUnsupportedArchitecture)
        case .frameworkUnavailable:
            return localization.string(.settingsBatteryChargeHiddenFrameworkUnavailable)
        case .apiUnavailable:
            return localization.string(.settingsBatteryChargeHiddenApiUnavailable)
        case .mclUnsupported:
            return localization.string(.settingsBatteryChargeHiddenMclUnsupported)
        case .noBattery:
            return localization.string(.settingsBatteryChargeHiddenNoBattery)
        case .batterySectionHidden:
            return localization.string(.settingsBatteryChargeHiddenBatterySectionHidden)
        case .disconnectedFromPower:
            return localization.string(.settingsBatteryChargeHiddenDisconnectedFromPower)
        case .fullyCharged:
            return localization.string(.settingsBatteryChargeHiddenFullyCharged)
        case .stateReadFailed:
            return localization.string(.settingsBatteryChargeHiddenStateReadFailed)
        case .noActiveChargeLimit:
            return localization.string(.settingsBatteryChargeHiddenNoActiveChargeLimit)
        case .unrecognizedChargeLimitState:
            return localization.string(
                .settingsBatteryChargeHiddenUnrecognizedChargeLimitState
            )
        }
    }
}
