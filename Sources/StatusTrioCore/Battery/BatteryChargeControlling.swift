import Foundation

enum ChargeToFullNowUnavailableReason: Equatable, Sendable {
    case unsupportedSystem
    case unsupportedArchitecture
    case frameworkUnavailable
    case apiUnavailable
    case mclUnsupported
}

enum ChargeToFullNowCapability: Equatable, Sendable {
    case available
    case unavailable(ChargeToFullNowUnavailableReason)

    var isAvailable: Bool {
        self == .available
    }
}

struct ChargeToFullNowDeviceState: Equatable, Sendable {
    let mclEnabledRawValue: UInt
    let mclLimit: Int?
    var availableChargeLimits: [Int] = []
    let chargingOverrideAllowed: Bool?
    var errorMessage: String? = nil

    var reportedChargeLimit: Int? {
        guard let mclLimit,
              (80..<100).contains(mclLimit) else {
            return nil
        }
        if !availableChargeLimits.isEmpty {
            return availableChargeLimits.contains(mclLimit) ? mclLimit : nil
        }
        return [80, 85, 90, 95].contains(mclLimit) ? mclLimit : nil
    }

    var hasActiveChargeLimit: Bool {
        errorMessage == nil
            && mclEnabledRawValue == 1
            && reportedChargeLimit != nil
    }

    var indicatesTemporaryOverride: Bool {
        errorMessage == nil && mclEnabledRawValue == 3
    }
}

enum ChargeToFullNowFailure: Equatable, Sendable {
    case unsupportedLimit
    case limitChanged
    case unavailable
    case verificationFailed
    case rejected
}

struct ChargeToFullNowWriteResult: Equatable, Sendable {
    let succeeded: Bool
    let errorMessage: String?
    var failure: ChargeToFullNowFailure? = nil

    static let success = ChargeToFullNowWriteResult(
        succeeded: true,
        errorMessage: nil
    )

    static let failure = ChargeToFullNowWriteResult(
        succeeded: false,
        errorMessage: nil
    )
}

@MainActor
protocol BatteryChargeControlling: AnyObject {
    var capability: ChargeToFullNowCapability { get }
    func readState() -> ChargeToFullNowDeviceState
    func chargeToFullNow() async -> ChargeToFullNowWriteResult
    /// `expectedLimit` is the sub-100 limit recorded for the running session,
    /// or `nil` when no session recorded one. A cancel can read an intermediate
    /// sub-100 limit that differs from the target (for example the original
    /// limit is still active); when it equals `expectedLimit`, one setting
    /// write is still allowed.
    func restoreChargeLimit(
        to limit: Int,
        expectedLimit: Int?
    ) async -> ChargeToFullNowWriteResult
}

extension BatteryChargeControlling {
    func restoreChargeLimit(
        to limit: Int,
        expectedLimit: Int?
    ) async -> ChargeToFullNowWriteResult {
        .failure
    }
}

@MainActor
final class UnavailableBatteryChargeController: BatteryChargeControlling {
    var capability: ChargeToFullNowCapability { .unavailable(.frameworkUnavailable) }
    func readState() -> ChargeToFullNowDeviceState {
        ChargeToFullNowDeviceState(
            mclEnabledRawValue: 0,
            mclLimit: nil,
            chargingOverrideAllowed: nil
        )
    }
    func chargeToFullNow() async -> ChargeToFullNowWriteResult { .failure }
}
