import XCTest
import PowerHelperProtocol
@testable import StatusTrioPowerHelper

/// Byte-level SMC double. Keys are raw 4-char names; values are raw payloads.
private final class ByteSMC: LegacySMCExecuting {
    var store: [String: Data]
    var failKeys: Set<String> = []
    var writes: [String] = []

    init(store: [String: Data]) { self.store = store }

    func readKey(_ key: String) -> Data? { store[key] }

    func writeKey(_ key: String, data: Data) -> Bool {
        writes.append(key)
        guard !failKeys.contains(key) else { return false }
        store[key] = data
        return true
    }
}

private final class FakeBatterySource: LegacyBatteryProviding {
    var level: Int?
    var onAC: Bool
    init(level: Int?, onAC: Bool = true) {
        self.level = level
        self.onAC = onAC
    }
    func currentPercent() -> Int? { level }
    func isOnACPower() -> Bool { onAC }
}

private final class MemoryJournal: LegacyChargeLimitJournaling {
    var saved: LegacyChargeLimitJournal?
    var clearCount = 0
    func load() -> LegacyChargeLimitJournal? { saved }
    func save(_ journal: LegacyChargeLimitJournal) { saved = journal }
    func clear() {
        saved = nil
        clearCount += 1
    }
}

private func intelExecutor(_ bclm: UInt8 = 100) -> ByteSMC {
    ByteSMC(store: ["BCLM": Data([bclm])])
}

private func siliconPairExecutor(_ b: UInt8 = 0x00, _ c: UInt8 = 0x00) -> ByteSMC {
    ByteSMC(store: ["CH0B": Data([b]), "CH0C": Data([c])])
}

private func makeService(
    _ executor: ByteSMC,
    battery: FakeBatterySource = FakeBatterySource(level: 50),
    journal: MemoryJournal = MemoryJournal(),
    isIntel: Bool = true,
    allowsLegacy: Bool = true,
    batteryPresent: Bool = true
) -> LegacyChargeLimitService {
    LegacyChargeLimitService(
        executor: executor,
        journal: journal,
        battery: battery,
        hardware: LegacyHardwareFacts(
            isIntel: isIntel,
            allowsLegacyLimiter: allowsLegacy,
            hasInternalBattery: batteryPresent
        )
    )
}

final class LegacyChargeLimitServiceTests: XCTestCase {
    // MARK: - Validation

    func testOutOfRangeLimitIsRejectedWithoutWriting() {
        let executor = intelExecutor()
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(79, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(reply?.errorCode, .limitOutOfRange)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    func testHelperlessOrUnsupportedHardwareReportsUnsupportedWithoutWriting() {
        let executor = intelExecutor()
        let service = makeService(executor, allowsLegacy: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.errorCode, .unsupportedHardware)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    // MARK: - Ownership

    func testStaleExpectedLimitIsRejectedWithoutWriting() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: NSNumber(value: 70)) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        XCTAssertTrue(executor.writes.isEmpty, "A conflict must not write over another controller")
    }

    func testMatchingExpectedLimitSucceeds() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: NSNumber(value: 90)) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(reply?.observedLimit?.intValue, 80)
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))
    }

    // MARK: - Intel ceiling + original restore

    func testDisableRestoresTheValueCapturedBeforeTheFirstWrite() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))

        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(executor.readKey("BCLM"), Data([90]), "Restore the stock ceiling, not the held one")
    }

    func testDisableWithoutASessionFailsWithoutWriting() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty, "No ownership record means no write")
    }

    func testOriginalSurvivesAFailedFirstWrite() {
        let executor = intelExecutor(90)
        executor.failKeys = ["BCLM"]
        let service = makeService(executor)
        var failed: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { failed = $0 }
        XCTAssertEqual(failed?.succeeded, false)

        executor.failKeys = []
        var retried: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { retried = $0 }
        XCTAssertEqual(retried?.succeeded, true)

        var disable: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { disable = $0 }
        XCTAssertEqual(executor.readKey("BCLM"), Data([90]), "A failed write must not lose the stock value")
    }

    func testDisableRestoresStockWhenAnotherControllerChangedTheValue() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        // External app changes the ceiling while we hold the session.
        executor.store["BCLM"] = Data([70])

        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.readKey("BCLM"), Data([70]), "Do not overwrite a foreign value blindly")
    }

    func testDisableIsIdempotentAfterSuccess() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        service.disableLegacyChargeLimit(expectedLimit: nil) { _ in }
        var second: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil) { second = $0 }
        XCTAssertEqual(second?.succeeded, false)
    }

    // MARK: - Journal

    func testPendingJournalIsPersistedBeforeTheWriteAndClearedOnDisable() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)

        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        let saved = journal.saved
        XCTAssertEqual(saved?.requestedLimit, 80)
        XCTAssertEqual(saved?.originalRaw["BCLM"], Data([90]))
        XCTAssertEqual(saved?.lastWrittenRaw["BCLM"], Data([80]))

        service.disableLegacyChargeLimit(expectedLimit: nil) { _ in }
        XCTAssertNil(journal.saved)
    }

    // MARK: - Silicon gate

    func testSiliconInhibitIsVerifiedByReadingTheGateBack() {
        let executor = siliconPairExecutor()
        let battery = FakeBatterySource(level: 90)
        let service = makeService(executor, battery: battery, isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x02]))
        XCTAssertEqual(executor.readKey("CH0C"), Data([0x02]))
    }

    func testSiliconReportsFailureWhenTheGateDoesNotActuallyChange() {
        // Writes report success but the SMC keeps the old bytes: the caller
        // must not be told the cap is active.
        let executor = siliconPairExecutor()
        let sticky = StickyGateSMC()
        let service = LegacyChargeLimitService(
            executor: sticky,
            journal: MemoryJournal(),
            battery: FakeBatterySource(level: 90),
            hardware: LegacyHardwareFacts(
                isIntel: false,
                allowsLegacyLimiter: true,
                hasInternalBattery: true
            )
        )
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertNotEqual(reply?.errorCode, .none)
    }

    func testSiliconPartialPairWriteRollsBackTheFirstKey() {
        let executor = siliconPairExecutor()
        executor.failKeys = ["CH0C"]
        let service = makeService(executor, battery: FakeBatterySource(level: 90), isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x00]), "Roll back the half-applied pair")
    }

    func testSiliconAllowsChargingWellBelowTheLimit() {
        let executor = siliconPairExecutor(0x02, 0x02)
        let service = makeService(executor, battery: FakeBatterySource(level: 40), isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x00]))
    }

    // MARK: - Charge to full / cancel

    func testChargeToFullThenCancelRestoresTheHeldCeiling() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil) { _ in }
        service.legacyChargeToFullOnce { _ in }
        XCTAssertEqual(executor.readKey("BCLM"), Data([100]))
        var cancel: SMLegacyChargeLimitWriteReply?
        service.cancelLegacyChargeToFull { cancel = $0 }
        XCTAssertEqual(cancel?.succeeded, true)
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))
    }

    func testChargeToFullWithoutACapIsRejected() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    // MARK: - Probe

    func testProbeReportsFactsInsteadOfPlaceholders() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitProbeReply?
        service.probeLegacyChargeLimit { value, _ in reply = value }
        XCTAssertEqual(reply?.hasInternalBattery, true)
        XCTAssertEqual(reply?.intelBCLMPresent, true)
        XCTAssertEqual(reply?.architectureName, "intel")
        XCTAssertEqual(reply?.osBandName, "legacy")
    }
}

/// Writes report success but never change the stored bytes.
private final class StickyGateSMC: LegacySMCExecuting {
    private let store: [String: Data] = ["CH0B": Data([0x00]), "CH0C": Data([0x00])]
    func readKey(_ key: String) -> Data? { store[key] }
    func writeKey(_ key: String, data: Data) -> Bool { true }
}