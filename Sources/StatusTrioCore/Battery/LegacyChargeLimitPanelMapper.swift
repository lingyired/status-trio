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

    static let hidden = LegacyChargeLimitPanelState(
        isVisible: false, status: nil, action: .none, isBusy: false
    )
}

enum LegacyChargeLimitPanelMapper {
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
            isBusy: isApplying
        )
    }
}