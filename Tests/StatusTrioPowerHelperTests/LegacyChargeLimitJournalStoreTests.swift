import XCTest
@testable import StatusTrioPowerHelper

/// The helper's recovery record is security- and safety-relevant: a corrupt or
/// foreign file must be an error, never "no session", and a failed save must be
/// detectable before any hardware write.
final class LegacyChargeLimitJournalStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatusTrioJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = chmod(root.path, 0o700)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> FileLegacyChargeLimitJournal {
        FileLegacyChargeLimitJournal(directory: root, expectedOwner: getuid())
    }

    private func sample() -> LegacyChargeLimitJournal {
        LegacyChargeLimitJournal(
            backend: .intelBCLM,
            hardwareModel: "Mac15,9",
            requestedLimit: 80,
            originalRaw: ["BCLM": Data([90])],
            lastWrittenRaw: ["BCLM": Data([80])]
        )
    }

    func testRoundTrip() throws {
        let store = makeStore()
        XCTAssertNil(try store.load())
        try store.save(sample())
        XCTAssertEqual(try store.load(), sample())
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testFileIsOwnerOnlyAndSingleLink() throws {
        let store = makeStore()
        try store.save(sample())
        let file = root.appendingPathComponent("legacy-charge-limit-journal.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(permissions & 0o077, 0, "The journal must not be group/world readable")
    }

    func testCorruptFileIsAnErrorNotAnEmptySession() throws {
        try Data("not json".utf8).write(to: root.appendingPathComponent("legacy-charge-limit-journal.json"))
        _ = chmod(root.appendingPathComponent("legacy-charge-limit-journal.json").path, 0o600)
        XCTAssertThrowsError(try makeStore().load())
    }

    func testOversizedFileIsRejected() throws {
        let file = root.appendingPathComponent("legacy-charge-limit-journal.json")
        try Data(repeating: 0x41, count: 20_000).write(to: file)
        _ = chmod(file.path, 0o600)
        XCTAssertThrowsError(try makeStore().load())
    }

    func testSymlinkedJournalIsRejected() throws {
        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let link = root.appendingPathComponent("legacy-charge-limit-journal.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try makeStore().load())
    }

    func testWorldWritableDirectoryIsRejected() throws {
        _ = chmod(root.path, 0o777)
        XCTAssertThrowsError(try makeStore().save(sample()))
    }

    func testPendingTransactionSurvivesRoundTrip() throws {
        var journal = sample()
        journal.pendingRaw = ["BCLM": Data([80])]
        let store = makeStore()
        try store.save(journal)
        XCTAssertEqual(try store.load(), journal)
    }

    func testForeignOwnerIsRejected() throws {
        let store = makeStore()
        try store.save(sample())
        // Same directory, different expected owner: must not be trusted.
        let foreign = FileLegacyChargeLimitJournal(directory: root, expectedOwner: getuid() &+ 1)
        XCTAssertThrowsError(try foreign.load())
    }
}