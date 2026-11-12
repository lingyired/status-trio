import Foundation
import XCTest
@testable import StatusTrioCore

final class WiFiPasswordStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WiFiPasswordStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".status-trio", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    // MARK: File store

    func testDefaultLocationIsDotStatusTrioInTheUsersHomeDirectory() {
        let url = FileWiFiPasswordStore.defaultDirectoryURL
        XCTAssertEqual(url.lastPathComponent, ".status-trio")
        XCTAssertEqual(
            url.deletingLastPathComponent().standardizedFileURL,
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        )
        XCTAssertEqual(
            FileWiFiPasswordStore(directoryURL: url).fileURL.lastPathComponent,
            "wifi-passwords.json"
        )
    }

    func testMissingFileHasNoPasswordsAndCreatesNothingOnRead() {
        let store = FileWiFiPasswordStore(directoryURL: directory)
        XCTAssertNil(store.password(for: "Home"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSavedPasswordRoundTripsAndSurvivesANewInstance() {
        XCTAssertTrue(FileWiFiPasswordStore(directoryURL: directory).save("hunter2!", for: "Home"))
        XCTAssertTrue(FileWiFiPasswordStore(directoryURL: directory).save("pässwörd 密码", for: "咖啡 ☕"))

        let reopened = FileWiFiPasswordStore(directoryURL: directory)
        XCTAssertEqual(reopened.password(for: "Home"), "hunter2!")
        XCTAssertEqual(reopened.password(for: "咖啡 ☕"), "pässwörd 密码")
        XCTAssertNil(reopened.password(for: "Other"))
    }

    /// An SSID is its exact bytes, including surrounding whitespace.
    func testSSIDIdentityIsExact() {
        let store = FileWiFiPasswordStore(directoryURL: directory)
        store.save("a", for: "Home")
        store.save("b", for: " Home ")
        XCTAssertEqual(store.password(for: "Home"), "a")
        XCTAssertEqual(store.password(for: " Home "), "b")
        XCTAssertNil(store.password(for: "home"))
    }

    func testSavingAgainReplacesAndRemoveForgetsOnlyThatNetwork() {
        let store = FileWiFiPasswordStore(directoryURL: directory)
        store.save("old", for: "Home")
        store.save("new", for: "Home")
        store.save("keep", for: "Cafe")
        XCTAssertEqual(store.password(for: "Home"), "new")

        store.remove(ssid: "Home")
        XCTAssertNil(store.password(for: "Home"))
        XCTAssertEqual(store.password(for: "Cafe"), "keep")
        store.remove(ssid: "Never saved")
        XCTAssertEqual(store.password(for: "Cafe"), "keep")
    }

    func testFileIsPrivateToTheOwner() throws {
        let store = FileWiFiPasswordStore(directoryURL: directory)
        store.save("secret", for: "Home")

        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: store.fileURL), 0o600)
    }

    func testAnExistingLooserDirectoryIsTightened() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let store = FileWiFiPasswordStore(directoryURL: directory)
        store.save("secret", for: "Home")

        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: store.fileURL), 0o600)
    }

    func testCorruptFileReadsAsEmptyAndTheNextSaveRecovers() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileWiFiPasswordStore(directoryURL: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.password(for: "Home"))

        XCTAssertTrue(store.save("secret", for: "Home"))
        XCTAssertEqual(store.password(for: "Home"), "secret")
    }

    func testSaveReportsFailureWhenTheDirectoryCannotBeCreated() throws {
        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        // A regular file where the directory should be.
        try Data().write(to: directory)
        XCTAssertFalse(FileWiFiPasswordStore(directoryURL: directory).save("secret", for: "Home"))
    }

    // MARK: Join policy

    func testResolveUsesNoPasswordForOpenAndTheTypedOneAsIs() {
        let store = InMemoryWiFiPasswordStore()
        XCTAssertEqual(WiFiJoinPasswordPolicy.resolve(.none, ssid: "Lobby", store: store), .password(nil))
        XCTAssertEqual(
            WiFiJoinPasswordPolicy.resolve(.typed("typed"), ssid: "Home", store: store),
            .password("typed")
        )
    }

    func testResolveStoredNeedsAPasswordWhenNoneIsSaved() {
        let store = InMemoryWiFiPasswordStore()
        XCTAssertEqual(WiFiJoinPasswordPolicy.resolve(.stored, ssid: "Home", store: store), .needsPassword)
        store.save("saved", for: "Home")
        XCTAssertEqual(WiFiJoinPasswordPolicy.resolve(.stored, ssid: "Home", store: store), .password("saved"))
    }

    func testATypedPasswordIsSavedOnlyAfterTheJoinSucceeded() {
        let store = InMemoryWiFiPasswordStore()
        WiFiJoinPasswordPolicy.record(.rejected, credential: .typed("typo"), ssid: "Home", store: store)
        WiFiJoinPasswordPolicy.record(.notInRange, credential: .typed("typo"), ssid: "Home", store: store)
        WiFiJoinPasswordPolicy.record(.unavailable, credential: .typed("typo"), ssid: "Home", store: store)
        XCTAssertNil(store.password(for: "Home"))

        WiFiJoinPasswordPolicy.record(.joined, credential: .typed("right"), ssid: "Home", store: store)
        XCTAssertEqual(store.password(for: "Home"), "right")
    }

    func testARefusedSavedPasswordIsForgottenButOtherOutcomesKeepIt() {
        let store = InMemoryWiFiPasswordStore()
        store.save("saved", for: "Home")

        WiFiJoinPasswordPolicy.record(.notInRange, credential: .stored, ssid: "Home", store: store)
        WiFiJoinPasswordPolicy.record(.unavailable, credential: .stored, ssid: "Home", store: store)
        WiFiJoinPasswordPolicy.record(.joined, credential: .stored, ssid: "Home", store: store)
        XCTAssertEqual(store.password(for: "Home"), "saved")

        WiFiJoinPasswordPolicy.record(.rejected, credential: .stored, ssid: "Home", store: store)
        XCTAssertNil(store.password(for: "Home"))
    }

    func testOpenNetworkJoinsNeverTouchTheStore() {
        let store = InMemoryWiFiPasswordStore()
        for outcome in [WiFiJoinOutcome.joined, .rejected, .notInRange, .unavailable, .needsPassword] {
            WiFiJoinPasswordPolicy.record(outcome, credential: .none, ssid: "Lobby", store: store)
        }
        XCTAssertTrue(store.isEmpty)
    }
}

final class InMemoryWiFiPasswordStore: WiFiPasswordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String: String] = [:]

    var isEmpty: Bool { lock.withLock { passwords.isEmpty } }

    func password(for ssid: String) -> String? { lock.withLock { passwords[ssid] } }

    @discardableResult
    func save(_ password: String, for ssid: String) -> Bool {
        lock.withLock { passwords[ssid] = password }
        return true
    }

    func remove(ssid: String) { lock.withLock { _ = passwords.removeValue(forKey: ssid) } }

    func removeAll() { lock.withLock { passwords.removeAll() } }
}
