import Foundation
import PowerHelperProtocol

/// The single object the daemon exports. It forwards each protocol surface to
/// the service that owns it so Low Power Mode stays independent of the charge
/// limiter: an error or a stalled charge session must not degrade Low Power
/// Mode, and vice versa.
final class PowerHelperService: NSObject, PowerHelperCombinedXPCProtocol {
    private let lowPowerMode: PowerModeService
    private let legacy: LegacyChargeLimitService

    init(lowPowerMode: PowerModeService, legacy: LegacyChargeLimitService) {
        self.lowPowerMode = lowPowerMode
        self.legacy = legacy
    }

    // MARK: Low Power Mode

    func readLowPowerMode(withReply reply: @escaping (Bool, String?) -> Void) {
        lowPowerMode.readLowPowerMode(withReply: reply)
    }

    func setLowPowerMode(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        lowPowerMode.setLowPowerMode(enabled, withReply: reply)
    }

    // MARK: Legacy charge limit

    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    ) {
        legacy.probeLegacyChargeLimit(withReply: reply)
    }

    func setLegacyChargeLimit(
        _ limit: Int,
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.setLegacyChargeLimit(limit, expectedLimit: expectedLimit, withReply: reply)
    }

    func legacyChargeToFullOnce(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.legacyChargeToFullOnce(withReply: reply)
    }

    func cancelLegacyChargeToFull(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.cancelLegacyChargeToFull(withReply: reply)
    }

    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.disableLegacyChargeLimit(expectedLimit: expectedLimit, withReply: reply)
    }

    func verifyLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.verifyLegacyChargeLimit(limit, withReply: reply)
    }
}