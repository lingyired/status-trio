import XCTest
import PowerHelperProtocol
@testable import StatusTrioPowerHelper

/// Byte-level SMC double. Keys are raw 4-char names; values are raw payloads.
private final class ByteSMC: LegacySMCExecuting {
    var store: [String: Data]
    var failKeys: Set<String> = []
    var writes: [String] = []
    var beforeWrite: ((String, Data) -> Void)?

    init(store: [String: Data]) { self.store = store }

    func readKey(_ key: String) -> Data? { store[key] }

    func writeKey(_ key: String, data: Data) -> Bool {
        beforeWrite?(key, data)
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

private struct JournalWriteFailed: Error {}

private final class MemoryJournal: LegacyChargeLimitJournaling {
    var saved: LegacyChargeLimitJournal?
    var clearCount = 0
    var failSave = false
    func load() -> LegacyChargeLimitJournal? { saved }
    func save(_ journal: LegacyChargeLimitJournal) throws {
        if failSave { throw JournalWriteFailed() }
        saved = journal
    }
    func clear() throws {
        saved = nil
        clearCount += 1
    }
}

private let testOwner = UUID()

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
        service.setLegacyChargeLimit(79, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(reply?.errorCode, .limitOutOfRange)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    func testHelperlessOrUnsupportedHardwareReportsUnsupportedWithoutWriting() {
        let executor = intelExecutor()
        let service = makeService(executor, allowsLegacy: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.errorCode, .unsupportedHardware)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    // MARK: - Ownership

    func testStaleExpectedLimitIsRejectedWithoutWriting() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: NSNumber(value: 70), ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        XCTAssertTrue(executor.writes.isEmpty, "A conflict must not write over another controller")
    }

    func testMatchingExpectedLimitSucceeds() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: NSNumber(value: 90), ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(reply?.observedLimit?.intValue, 80)
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))
    }

    // MARK: - Intel ceiling + original restore

    func testDisableRestoresTheValueCapturedBeforeTheFirstWrite() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))

        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(executor.readKey("BCLM"), Data([90]), "Restore the stock ceiling, not the held one")
    }

    func testDisableWithoutASessionFailsWithoutWriting() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty, "No ownership record means no write")
    }

    func testOriginalSurvivesAFailedFirstWrite() {
        let executor = intelExecutor(90)
        executor.failKeys = ["BCLM"]
        let service = makeService(executor)
        var failed: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { failed = $0 }
        XCTAssertEqual(failed?.succeeded, false)

        executor.failKeys = []
        var retried: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { retried = $0 }
        XCTAssertEqual(retried?.succeeded, true)

        var disable: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { disable = $0 }
        XCTAssertEqual(executor.readKey("BCLM"), Data([90]), "A failed write must not lose the stock value")
    }

    func testDisableRestoresStockWhenAnotherControllerChangedTheValue() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        // External app changes the ceiling while we hold the session.
        executor.store["BCLM"] = Data([70])

        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.readKey("BCLM"), Data([70]), "Do not overwrite a foreign value blindly")
    }

    func testDisableIsIdempotentAfterSuccess() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { _ in }
        var second: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { second = $0 }
        XCTAssertEqual(second?.succeeded, false)
    }

    // MARK: - Stale journal identity

    func testJournalFromAnotherModelIsIgnoredAndNeverWritten() throws {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let foreign = LegacyChargeLimitJournal(
            backend: .intelBCLM,
            hardwareModel: "MacBookPro16,1",
            requestedLimit: 80,
            originalRaw: ["BCLM": Data([40])],
            lastWrittenRaw: ["BCLM": Data([40])]
        )
        try journal.save(foreign)

        let service = LegacyChargeLimitService(
            executor: executor,
            journal: journal,
            battery: FakeBatterySource(level: 50),
            hardware: LegacyHardwareFacts(isIntel: true, allowsLegacyLimiter: true, hasInternalBattery: true),
            hardwareModel: "Mac15,9"
        )
        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty, "A foreign journal must not drive a write")

        var full: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce(ownerID: testOwner) { full = $0 }
        XCTAssertEqual(full?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    func testJournalOnTheSameModelIsHonoured() throws {
        // The hardware sits at the value this journal last wrote (80).
        let executor = intelExecutor(80)
        let journal = MemoryJournal()
        try journal.save(LegacyChargeLimitJournal(
            backend: .intelBCLM,
            hardwareModel: "Mac15,9",
            requestedLimit: 80,
            originalRaw: ["BCLM": Data([90])],
            lastWrittenRaw: ["BCLM": Data([80])]
        ))
        // Hardware is at the held value, so disable may restore the stock one.
        let service = LegacyChargeLimitService(
            executor: executor,
            journal: journal,
            battery: FakeBatterySource(level: 50),
            hardware: LegacyHardwareFacts(isIntel: true, allowsLegacyLimiter: true, hasInternalBattery: true),
            hardwareModel: "Mac15,9"
        )
        var reply: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
    }

    // MARK: - Review regressions (run against the real service)

    func testIntelDisableAcceptsHeldValueAsExpectedAndRestoresStock() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: NSNumber(value: 90), ownerID: testOwner) { _ in }
        var result: SMLegacyChargeLimitWriteReply?
        // The app only knows its held ceiling. expectedLimit always describes
        // the current value, never the pre-management restore destination.
        service.disableLegacyChargeLimit(expectedLimit: NSNumber(value: 80), ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.succeeded, true)
        XCTAssertEqual(executor.readKey("BCLM"), Data([90]))
    }

    func testSiliconSetRefusesForeignGateEvenWithMatchingRequestedLimit() {
        let executor = siliconPairExecutor()
        let service = makeService(executor, battery: FakeBatterySource(level: 90), isIntel: false)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        executor.store["CH0B"] = Data([0])
        executor.store["CH0C"] = Data([0])
        let before = executor.writes.count
        var result: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(85, expectedLimit: NSNumber(value: 80), ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.writes.count, before)
    }

    func testNilExpectedCannotBypassAnExistingIntelSessionOwnership() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        executor.store["BCLM"] = Data([85])
        let before = executor.writes.count
        var result: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(95, expectedLimit: nil, ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.writes.count, before)
    }

    func testCancelDoesNotOverwriteAnExternalCeilingDuringFullCharge() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        service.legacyChargeToFullOnce(ownerID: testOwner) { _ in }
        executor.store["BCLM"] = Data([85])
        let before = executor.writes.count
        var result: SMLegacyChargeLimitWriteReply?
        service.cancelLegacyChargeToFull(ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.writes.count, before)
    }

    func testFullChargeDoesNotOverwriteAnExternalCeiling() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        executor.store["BCLM"] = Data([85])
        let before = executor.writes.count
        var result: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce(ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.errorCode, .ownershipConflict)
        XCTAssertEqual(executor.writes.count, before)
    }

    func testFailedFullChargeDoesNotPersistAnAcceptedOverride() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        executor.failKeys = ["BCLM"]
        var result: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce(ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.succeeded, false)
        XCTAssertEqual(journal.saved?.isTemporarilyOverridden, false)
    }

    func testDisableRequiresSuccessfulFreshReadOfEveryOwnedKey() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        executor.store["BCLM"] = nil // unavailable or transient read failure
        let before = executor.writes.count
        var result: SMLegacyChargeLimitWriteReply?
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.succeeded, false)
        XCTAssertEqual(executor.writes.count, before)
    }

    func testMissingSiliconBatteryReadingNeverInventsZeroPercent() {
        let executor = siliconPairExecutor(2, 2)
        let service = makeService(executor, battery: FakeBatterySource(level: nil), isIntel: false)
        var result: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty)
    }

    func testBothSiliconFamiliesPresentUsesTheRecordedPairOnly() {
        let executor = ByteSMC(store: [
            "CH0B": Data([0x00]), "CH0C": Data([0x00]),
            "CHTE": Data([0, 0, 0, 0]),
        ])
        let service = makeService(executor, battery: FakeBatterySource(level: 90), isIntel: false)
        var result: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { result = $0 }
        XCTAssertEqual(result?.succeeded, true)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x02]))
        XCTAssertEqual(executor.readKey("CHTE"), Data([0, 0, 0, 0]), "Do not mix key families")
    }

    // MARK: - Connection ownership

    func testUnrelatedLPMConnectionLossDoesNotRestoreAnActiveChargeSession() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        let chargeOwner = UUID()
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: chargeOwner) { _ in }
        let writes = executor.writes.count
        XCTAssertTrue(service.restoreForClientLoss(owner: UUID()))
        XCTAssertEqual(executor.store["BCLM"], Data([80]))
        XCTAssertEqual(executor.writes.count, writes)
        XCTAssertTrue(service.restoreForClientLoss(owner: chargeOwner))
        XCTAssertEqual(executor.store["BCLM"], Data([90]))
    }

    func testSecondConnectionCannotMutateOrReleaseTheFirstOwnersLimit() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        let owner = UUID()
        let other = UUID()
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: owner) { _ in }
        let writes = executor.writes.count
        service.setLegacyChargeLimit(85, expectedLimit: nil, ownerID: other) { reply in
            XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        }
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: other) { reply in
            XCTAssertEqual(reply?.errorCode, .ownershipConflict)
        }
        XCTAssertTrue(service.restoreForClientLoss(owner: other))
        XCTAssertEqual(executor.writes.count, writes)
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: owner) { reply in
            XCTAssertEqual(reply?.succeeded, true)
        }
        XCTAssertEqual(executor.store["BCLM"], Data([90]))
        // A new owner may acquire the hardware only after verified restoration.
        service.setLegacyChargeLimit(85, expectedLimit: nil, ownerID: other) { reply in
            XCTAssertEqual(reply?.succeeded, true)
        }
    }

    func testFailedClientLossRestoreRetainsRecoveryDemandUntilExplicitRecovery() {
        let executor = intelExecutor(90)
        let demand = RecoveryDemandRecorder()
        let service = LegacyChargeLimitService(
            executor: executor, journal: MemoryJournal(), battery: FakeBatterySource(level: 50),
            hardware: LegacyHardwareFacts(isIntel: true, allowsLegacyLimiter: true, hasInternalBattery: true),
            recoveryDemandChanged: { demand.record($0) }
        )
        let owner = UUID()
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: owner) { _ in }
        executor.failKeys = ["BCLM"]
        XCTAssertFalse(service.restoreForClientLoss(owner: owner))
        XCTAssertEqual(demand.last, true)
        executor.failKeys = []
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: UUID()) { reply in
            XCTAssertEqual(reply?.succeeded, true)
        }
        XCTAssertEqual(demand.last, false)
        XCTAssertEqual(executor.store["BCLM"], Data([90]))
    }

    // MARK: - Journal failure injection

    func testInitialJournalSaveFailureBlocksEveryHardwareWrite() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        journal.failSave = true
        let service = makeService(executor, journal: journal)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertTrue(executor.writes.isEmpty)
        XCTAssertNil(journal.saved)
        XCTAssertEqual(executor.store["BCLM"], Data([90]))
    }

    func testOriginalAndPendingTargetAreDurableBeforeEnteringTheExecutor() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)
        executor.beforeWrite = { key, value in
            XCTAssertEqual(key, "BCLM")
            XCTAssertEqual(value, Data([80]))
            XCTAssertEqual(journal.saved?.originalRaw, ["BCLM": Data([90])])
            XCTAssertEqual(journal.saved?.lastWrittenRaw, ["BCLM": Data([90])])
            XCTAssertEqual(journal.saved?.pendingRaw, ["BCLM": Data([80])])
        }
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply in
            XCTAssertEqual(reply?.succeeded, true)
        }
    }

    func testSaveFailureBlocksSetFullCancelAndDisableForAnExistingSession() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        let saved = journal.saved
        let initialWrites = executor.writes.count
        journal.failSave = true
        service.setLegacyChargeLimit(85, expectedLimit: NSNumber(value: 80), ownerID: testOwner) { reply in
            XCTAssertEqual(reply?.succeeded, false)
        }
        service.legacyChargeToFullOnce(ownerID: testOwner) { reply in XCTAssertEqual(reply?.succeeded, false) }
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply in
            XCTAssertEqual(reply?.succeeded, false)
        }
        XCTAssertEqual(executor.writes.count, initialWrites)
        XCTAssertEqual(journal.saved, saved)

        journal.failSave = false
        service.legacyChargeToFullOnce(ownerID: testOwner) { _ in }
        let fullRecord = journal.saved
        let fullWrites = executor.writes.count
        journal.failSave = true
        service.cancelLegacyChargeToFull(ownerID: testOwner) { reply in XCTAssertEqual(reply?.succeeded, false) }
        XCTAssertEqual(executor.writes.count, fullWrites)
        XCTAssertEqual(journal.saved, fullRecord)
    }

    func testPostWriteSaveFailureRetainsPendingRecoveryUntilExplicitDisable() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)
        executor.beforeWrite = { _, _ in journal.failSave = true }
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply in
            XCTAssertEqual(reply?.succeeded, false)
        }
        XCTAssertEqual(executor.store["BCLM"], Data([80]))
        XCTAssertEqual(journal.saved?.originalRaw, ["BCLM": Data([90])])
        XCTAssertEqual(journal.saved?.pendingRaw, ["BCLM": Data([80])])
        let before = executor.writes.count
        service.verifyLegacyChargeLimit(80) { reply in XCTAssertEqual(reply?.succeeded, false) }
        XCTAssertEqual(executor.writes.count, before, "Verification never repairs a pending write")

        executor.beforeWrite = nil
        journal.failSave = false
        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { reply in
            XCTAssertEqual(reply?.succeeded, true)
        }
        XCTAssertEqual(executor.store["BCLM"], Data([90]))
        XCTAssertNil(journal.saved)
    }

    // MARK: - Journal

    func testPendingJournalIsPersistedBeforeTheWriteAndClearedOnDisable() {
        let executor = intelExecutor(90)
        let journal = MemoryJournal()
        let service = makeService(executor, journal: journal)

        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        let saved = journal.saved
        XCTAssertEqual(saved?.requestedLimit, 80)
        XCTAssertEqual(saved?.originalRaw["BCLM"], Data([90]))
        XCTAssertEqual(saved?.lastWrittenRaw["BCLM"], Data([80]))

        service.disableLegacyChargeLimit(expectedLimit: nil, ownerID: testOwner) { _ in }
        XCTAssertNil(journal.saved)
    }

    // MARK: - Silicon gate

    func testSiliconInhibitIsVerifiedByReadingTheGateBack() {
        let executor = siliconPairExecutor()
        let battery = FakeBatterySource(level: 90)
        let service = makeService(executor, battery: battery, isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
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
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertNotEqual(reply?.errorCode, .none)
    }

    func testSiliconPartialPairWriteRollsBackTheFirstKey() {
        let executor = siliconPairExecutor()
        executor.failKeys = ["CH0C"]
        let service = makeService(executor, battery: FakeBatterySource(level: 90), isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, false)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x00]), "Roll back the half-applied pair")
    }

    func testSiliconAllowsChargingWellBelowTheLimit() {
        let executor = siliconPairExecutor(0x02, 0x02)
        let service = makeService(executor, battery: FakeBatterySource(level: 40), isIntel: false)
        var reply: SMLegacyChargeLimitWriteReply?
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { reply = $0 }
        XCTAssertEqual(reply?.succeeded, true)
        XCTAssertEqual(executor.readKey("CH0B"), Data([0x00]))
    }

    // MARK: - Charge to full / cancel

    func testChargeToFullThenCancelRestoresTheHeldCeiling() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        service.setLegacyChargeLimit(80, expectedLimit: nil, ownerID: testOwner) { _ in }
        service.legacyChargeToFullOnce(ownerID: testOwner) { _ in }
        XCTAssertEqual(executor.readKey("BCLM"), Data([100]))
        var cancel: SMLegacyChargeLimitWriteReply?
        service.cancelLegacyChargeToFull(ownerID: testOwner) { cancel = $0 }
        XCTAssertEqual(cancel?.succeeded, true)
        XCTAssertEqual(executor.readKey("BCLM"), Data([80]))
    }

    func testChargeToFullWithoutACapIsRejected() {
        let executor = intelExecutor(90)
        let service = makeService(executor)
        var reply: SMLegacyChargeLimitWriteReply?
        service.legacyChargeToFullOnce(ownerID: testOwner) { reply = $0 }
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

private final class RecoveryDemandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    var last: Bool? { lock.withLock { value } }
    func record(_ pending: Bool) { lock.withLock { value = pending } }
}

/// Writes report success but never change the stored bytes.
private final class StickyGateSMC: LegacySMCExecuting {
    private let store: [String: Data] = ["CH0B": Data([0x00]), "CH0C": Data([0x00])]
    func readKey(_ key: String) -> Data? { store[key] }
    func writeKey(_ key: String, data: Data) -> Bool { true }
}