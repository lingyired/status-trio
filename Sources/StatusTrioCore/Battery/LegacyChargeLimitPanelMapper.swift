import Foundation

/// What the battery details page shows for the legacy charge limiter.
///
/// The panel reuses the controller's published state; it must not start a
/// second battery monitor or a polling timer of its own.
struct LegacyChargeLimitPanelState: Equatable {
    enum Status: Equatable {
        case holding(Int)
        case temporarilyFull
        case checking
        case failed
        case externalChange
        case restoreFailed
        case unverified
    }

    enum Action: Equatable {
        case chargeToFull
        case cancelFullCharge
        case none

        var isEnabled: Bool { self != .none }
    }

    let isVisible: Bool
    let status: Status?
    let action: Action
    let isBusy: Bool
    /// Kept independently of status so temporary full, busy and failed states
    /// still show the ceiling that will be restored.
    let targetLimit: Int?

    static let hidden = LegacyChargeLimitPanelState(
        isVisible: false, status: nil, action: .none, isBusy: false, targetLimit: nil
    )
}

enum LegacyChargeLimitPanelMapper {
    /// The card's one-tap action. It is deliberately the only thing the card
    /// shows for legacy systems: no ceiling, no status row.
    static func cardAction(
        availability: LegacyChargeLimitAvailability,
        status: LegacyChargeLimitStatus,
        selectedLimit: Int?
    ) -> LegacyChargeLimitPanelState.Action {
        guard availability.isAvailable, selectedLimit != nil else { return .none }
        switch status {
        case .holding:
            return .chargeToFull
        case .temporarilyChargingToFull:
            return .cancelFullCharge
        default:
            return .none
        }
    }

    static func actionTitleKey(for action: LegacyChargeLimitPanelState.Action) -> LocalizationKey? {
        switch action {
        case .chargeToFull: return .settingsBatteryLegacyChargeLimitChargeToFull
        case .cancelFullCharge: return .settingsBatteryLegacyChargeLimitCancel
        case .none: return nil
        }
    }

    /// Only an opted-in, available controller appears on the panel. Settings
    /// remains the place to discover and enable the feature.
    static func map(
        availability: LegacyChargeLimitAvailability,
        status: LegacyChargeLimitStatus,
        selectedLimit: Int?,
        isApplying: Bool
    ) -> LegacyChargeLimitPanelState {
        guard availability.isAvailable, selectedLimit != nil else { return .hidden }
        let mappedStatus: LegacyChargeLimitPanelState.Status
        let action: LegacyChargeLimitPanelState.Action
        switch status {
        case let .holding(limit):
            mappedStatus = .holding(limit)
            action = .chargeToFull
        case .temporarilyChargingToFull:
            mappedStatus = .temporarilyFull
            action = .cancelFullCharge
        case .checkingHardware:
            mappedStatus = .checking
            action = .none
        case .failed:
            mappedStatus = .failed
            action = .none
        case .externalChange:
            mappedStatus = .externalChange
            action = .none
        case .restoreFailed:
            mappedStatus = .restoreFailed
            action = .none
        case .unverified:
            mappedStatus = .unverified
            action = .none
        case .notEnabled, .unsupported, .helperApprovalRequired:
            return .hidden
        }
        return LegacyChargeLimitPanelState(
            isVisible: true,
            status: mappedStatus,
            action: isApplying ? .none : action,
            isBusy: isApplying,
            targetLimit: selectedLimit
        )
    }
}
/// Phase 8: an explicit recovery entry. Whenever the app cannot claim the cap is
/// held (failed verification, a failed restore, or a foreign change), the
/// settings page offers a one-click "restore original charging behaviour".
/// Turning the limit off is the same operation; the dedicated entry makes the
/// path discoverable when the toggle already looks off.
enum LegacyChargeLimitRecovery {
    static func showsRestoreAction(status: LegacyChargeLimitStatus) -> Bool {
        switch status {
        case .restoreFailed, .unverified, .externalChange, .failed:
            return true
        default:
            return false
        }
    }
}
