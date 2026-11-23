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
                errorMessage: "PowerUI is unavailable.",
                failure: .unavailable
            )
        }
        let result = bridge.chargeToFullNow()
        return ChargeToFullNowWriteResult(
            succeeded: result.didSucceed,
            errorMessage: result.didSucceed ? nil : result.errorMessage,
            failure: Self.mapFailure(result.failure)
        )
    }

    func restoreChargeLimit(
        to limit: Int,
        expectedLimit: Int?
    ) async -> ChargeToFullNowWriteResult {
        guard capability.isAvailable else {
            return ChargeToFullNowWriteResult(
                succeeded: false,
                errorMessage: "PowerUI is unavailable.",
                failure: .unavailable
            )
        }
        let result = bridge.restoreChargeLimit(
            limit,
            expectedLimit: expectedLimit ?? 0
        )
        return ChargeToFullNowWriteResult(
            succeeded: result.didSucceed,
            errorMessage: result.didSucceed ? nil : result.errorMessage,
            failure: Self.mapFailure(result.failure)
        )
    }

    private static func mapFailure(
        _ failure: STPowerUIChargeWriteFailure
    ) -> ChargeToFullNowFailure? {
        switch failure {
        case .unsupportedLimit:
            return .unsupportedLimit
        case .limitChanged:
            return .limitChanged
        case .unavailable:
            return .unavailable
        case .verificationFailed:
            return .verificationFailed
        case .rejected:
            return .rejected
        case .none:
            return nil
        @unknown default:
            return nil
        }
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
