import Foundation
import PowerHelperProtocol

/// The single object the daemon exports. It forwards each protocol surface to
/// the service that owns it so Low Power Mode stays independent of the charge
/// limiter: an error or a stalled charge session must not degrade Low Power
/// Mode, and vice versa.
final class PowerHelperService: NSObject, PowerHelperCombinedXPCProtocol {
    private let lowPowerMode: PowerModeService
    private let legacy: LegacyChargeConnection

    init(lowPowerMode: PowerModeService, legacy: LegacyChargeConnection) {
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

    func prepareLegacyChargeLimitForSleep(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.prepareLegacyChargeLimitForSleep(withReply: reply)
    }

    func verifyLegacyChargeLimit(
        _ limit: Int,
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        legacy.verifyLegacyChargeLimit(limit, withReply: reply)
    }
}
/// Per-connection legacy proxy.
///
/// NSXPC exports one object per connection, so the daemon can assign each
/// connection its own hardware-ownership id. The client never supplies one, and
/// a second connection (Low Power Mode) can neither disable the cap nor trigger
/// its recovery when it disconnects.
final class LegacyChargeConnection: @unchecked Sendable {
    let ownerID = UUID()
    private let service: LegacyChargeLimitService?

    init(service: LegacyChargeLimitService?) {
        self.service = service
    }

    func probeLegacyChargeLimit(
        withReply reply: @escaping (SMLegacyChargeLimitProbeReply?, String?) -> Void
    ) {
        service?.probeLegacyChargeLimit(withReply: reply)
    }

    func setLegacyChargeLimit(
        _ limit: Int, expectedLimit: NSNumber?, withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        service?.setLegacyChargeLimit(limit, expectedLimit: expectedLimit, ownerID: ownerID, withReply: reply)
    }

    func legacyChargeToFullOnce(withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void) {
        service?.legacyChargeToFullOnce(ownerID: ownerID, withReply: reply)
    }

    func cancelLegacyChargeToFull(withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void) {
        service?.cancelLegacyChargeToFull(ownerID: ownerID, withReply: reply)
    }

    func disableLegacyChargeLimit(
        expectedLimit: NSNumber?, withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        service?.disableLegacyChargeLimit(expectedLimit: expectedLimit, ownerID: ownerID, withReply: reply)
    }

    func prepareLegacyChargeLimitForSleep(
        withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        service?.prepareForSleep(ownerID: ownerID, withReply: reply)
    }

    func verifyLegacyChargeLimit(
        _ limit: Int, withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void
    ) {
        service?.verifyLegacyChargeLimit(limit, ownerID: ownerID, withReply: reply)
    }

    /// Called once when this connection ends. Only the owning connection may
    /// release a held cap.
    func release() {
        service?.restoreForClientLoss(owner: ownerID)
    }
}
