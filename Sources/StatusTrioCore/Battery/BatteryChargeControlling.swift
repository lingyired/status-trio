import Foundation
import PowerUIPrivateAPI

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

@MainActor
final class PowerUIChargeController: BatteryChargeControlling {
    private let bridge = STPowerUIChargeBridge()
    private var cachedCapability: ChargeToFullNowCapability?

    var capability: ChargeToFullNowCapability {
        if let cachedCapability {
            return cachedCapability
        }
        let capability = Self.mapCapability(bridge.capability())
        cachedCapability = capability
        return capability
    }

    func readState() -> ChargeToFullNowDeviceState {
        guard capability.isAvailable else {
            return ChargeToFullNowDeviceState(
                mclEnabledRawValue: 0,
                mclLimit: nil,
                chargingOverrideAllowed: nil,
                errorMessage: "PowerUI is unavailable."
            )
        }
        let state = bridge.readState()
        return ChargeToFullNowDeviceState(
            mclEnabledRawValue: state.mclEnabledRawValue,
            mclLimit: state.mclLimit >= 0 ? Int(state.mclLimit) : nil,
            availableChargeLimits: state.availableChargeLimits.map(\.intValue),
            chargingOverrideAllowed: state.hasValidState
                ? state.chargingOverrideAllowed
                : nil,
            errorMessage: state.hasValidState ? nil : state.errorMessage
        )
    }

    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        guard capability.isAvailable else {
            return ChargeToFullNowWriteResult(
                succeeded: false,
                errorMessage: "PowerUI is unavailable."
            )
        }
        let result = bridge.temporarilyDisableMCL()
        return ChargeToFullNowWriteResult(
            succeeded: result.didSucceed,
            errorMessage: result.didSucceed ? nil : result.errorMessage
        )
    }

    func restoreChargeLimit(to limit: Int) async -> ChargeToFullNowWriteResult {
        guard capability.isAvailable else {
            return ChargeToFullNowWriteResult(
                succeeded: false,
                errorMessage: "PowerUI is unavailable."
            )
        }
        let result = bridge.restoreChargeLimit(limit)
        return ChargeToFullNowWriteResult(
            succeeded: result.didSucceed,
            errorMessage: result.didSucceed ? nil : result.errorMessage
        )
    }

    private static func mapCapability(
        _ capability: STPowerUIChargeCapability
    ) -> ChargeToFullNowCapability {
        guard !capability.isAvailable else { return .available }
        let reason: ChargeToFullNowUnavailableReason
        switch capability.reason {
        case .unsupportedSystem:
            reason = .unsupportedSystem
        case .unsupportedArchitecture:
            reason = .unsupportedArchitecture
        case .frameworkUnavailable:
            reason = .frameworkUnavailable
        case .mclUnsupported:
            reason = .mclUnsupported
        case .apiUnavailable, .available:
            reason = .apiUnavailable
        @unknown default:
            reason = .apiUnavailable
        }
        return .unavailable(reason)
    }
}
