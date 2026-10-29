import Foundation
import PowerUIPrivateAPI

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
