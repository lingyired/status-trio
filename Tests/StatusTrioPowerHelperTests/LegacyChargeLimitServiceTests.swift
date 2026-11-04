import XCTest
import PowerHelperProtocol
@testable import StatusTrioPowerHelper

/// A deterministic in-memory executor for the helper service tests.
private final class FakeLegacySMCExecutor: LegacySMCExecuting {
    var intelBCLM: Int?
    var stoppingCharging: Bool?
    var autoAccept: Bool = true

    func readIntelBCLM() -> Int? { intelBCLM }
    func writeIntelBCLM(_ limit: Int) -> Int? {
        guard autoAccept else { return nil }
        intelBCLM = limit
        return limit
    }
    func siliconKeySetName() -> LegacySMCInhibitKeySetName? { nil }
    func writeSiliconInhibit(allow: Bool, keySet: LegacySMCInhibitKeySetName) -> Bool { true }
    func siliconChargingAllowed() -> Bool? { !(stoppingCharging ?? false) }
}

@MainActor
final class LegacyChargeLimitServiceTests: XCTestCase {
    func testSetLimitOutOfRangeRejected() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(79, expectedLimit: nil) { replyOut = $0 }
        XCTAssertFalse(replyOut?.succeeded ?? true)
        XCTAssertEqual(replyOut?.errorCode, .limitOutOfRange)
    }

    func testIntelSetLimitWritesAndVerifies() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { replyOut = $0 }
        XCTAssertTrue(replyOut?.succeeded ?? false)
        XCTAssertEqual(replyOut?.observedLimit?.intValue, 80)
        XCTAssertTrue(replyOut?.verified ?? false)
        XCTAssertEqual(executor.intelBCLM, 80)
    }

    func testIntelSetLimitReadbackMismatchFails() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        executor.autoAccept = false // write fails
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { replyOut = $0 }
        XCTAssertFalse(replyOut?.succeeded ?? true)
        XCTAssertEqual(replyOut?.errorCode, .verificationFailed)
    }

    func testNoBackendIsUnsupported() {
        let executor = FakeLegacySMCExecutor() // no BCLM, no silicon keys
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { replyOut = $0 }
        XCTAssertFalse(replyOut?.succeeded ?? true)
        XCTAssertEqual(replyOut?.errorCode, .unsupportedHardware)
    }

    func testChargeToFullThenCancelRestoresCap() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        let service = LegacyChargeLimitService(executor: executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        XCTAssertEqual(executor.intelBCLM, 80)

        var fullReply: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce { fullReply = $0 }
        XCTAssertTrue(fullReply?.succeeded ?? false)
        XCTAssertEqual(executor.intelBCLM, 100)

        var cancelReply: SMLegacyChargeLimitWriteReply?
        service.cancelLegacyChargeToFull { cancelReply = $0 }
        XCTAssertTrue(cancelReply?.succeeded ?? false)
        XCTAssertEqual(executor.intelBCLM, 80)
    }

    func testChargeToFullWithoutActiveCapIsCancelled() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce { replyOut = $0 }
        XCTAssertFalse(replyOut?.succeeded ?? true)
        XCTAssertEqual(replyOut?.errorCode, .cancelled)
    }

    func testDisableRestoresOriginal() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 100
        let service = LegacyChargeLimitService(executor: executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        // In this model originalLimit is recorded as the pre-change value (100
        // becomes "nil" → target falls back to 100 on disable).
        var disableReply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { disableReply = $0 }
        XCTAssertTrue(disableReply?.succeeded ?? false)
        XCTAssertEqual(executor.intelBCLM, 100)
    }

    func testVerifyMatches() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 80
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.verifyLegacyChargeLimit(80) { replyOut = $0 }
        XCTAssertTrue(replyOut?.succeeded ?? false)
        XCTAssertTrue(replyOut?.verified ?? false)
    }

    func testVerifyMismatch() {
        let executor = FakeLegacySMCExecutor()
        executor.intelBCLM = 90
        let service = LegacyChargeLimitService(executor: executor)
        var replyOut: SMLegacyChargeLimitWriteReply?
        service.verifyLegacyChargeLimit(80) { replyOut = $0 }
        XCTAssertFalse(replyOut?.succeeded ?? true)
        XCTAssertEqual(replyOut?.errorCode, .verificationFailed)
    }
}