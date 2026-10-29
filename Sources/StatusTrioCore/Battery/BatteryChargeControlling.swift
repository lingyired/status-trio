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

struct ChargeToFullNowWriteResult: Equatable, Sendable {
    let succeeded: Bool
    let errorMessage: String?

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
    func restoreChargeLimit(to limit: Int) async -> ChargeToFullNowWriteResult
}

extension BatteryChargeControlling {
    func restoreChargeLimit(to limit: Int) async -> ChargeToFullNowWriteResult {
        .failure
    }
}

