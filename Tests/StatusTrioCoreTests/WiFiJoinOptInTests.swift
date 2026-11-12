import Foundation
import XCTest
@testable import StatusTrioCore

/// Joining Wi-Fi networks from the panel is opt-in, because it saves typed
/// passwords as plain text. These tests pin that it is off until the person
/// opts in, that the first-launch guide records the choice once, that settings
/// import cannot turn it on, and that turning it off forgets the passwords.
@MainActor
final class WiFiJoinOptInTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "StatusTrioCoreTests.WiFiJoinOptIn.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return defaults
    }

    func testOffAndUnansweredByDefault() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertFalse(store.joinsWiFiInApp)
        XCTAssertFalse(store.hasAnsweredWiFiJoinPrompt)
    }

    func testTheChoiceIsPersistedAcrossLaunches() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.completeWiFiJoinPrompt(joinsInApp: true)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.joinsWiFiInApp)
        XCTAssertTrue(reloaded.hasAnsweredWiFiJoinPrompt)

        reloaded.joinsWiFiInApp = false
        XCTAssertFalse(SettingsStore(defaults: defaults).joinsWiFiInApp)
    }

    func testDecliningStillRecordsThatTheGuideAsked() {
        let defaults = makeDefaults()
        SettingsStore(defaults: defaults).completeWiFiJoinPrompt(joinsInApp: false)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.joinsWiFiInApp)
        XCTAssertTrue(reloaded.hasAnsweredWiFiJoinPrompt)
    }

    func testTheGuideDraftStartsUncheckedAndAsksOnlyOnce() {
        let store = SettingsStore(defaults: makeDefaults())
        var draft = WiFiJoinChoiceDraft()
        XCTAssertFalse(draft.joinsInApp)

        draft.joinsInApp = true
        draft.acknowledge(settings: store)
        XCTAssertTrue(store.joinsWiFiInApp)
        XCTAssertTrue(store.hasAnsweredWiFiJoinPrompt)

        // A later guide with a different draft must not overwrite the choice.
        store.joinsWiFiInApp = false
        var again = WiFiJoinChoiceDraft()
        again.joinsInApp = true
        again.acknowledge(settings: store)
        XCTAssertFalse(store.joinsWiFiInApp)
    }

    func testAnUncheckedDraftLeavesItOff() {
        let store = SettingsStore(defaults: makeDefaults())
        WiFiJoinChoiceDraft().acknowledge(settings: store)
        XCTAssertFalse(store.joinsWiFiInApp)
        XCTAssertTrue(store.hasAnsweredWiFiJoinPrompt)
    }

    func testSettingsTransferCanNeitherExportNorImportTheOptIn() {
        let store = SettingsStore(defaults: makeDefaults())
        store.completeWiFiJoinPrompt(joinsInApp: true)
        XCTAssertNil(SettingsPreferenceCatalog.snapshot(store)["joinsWiFiInApp"])
        XCTAssertNil(SettingsPreferenceCatalog.snapshot(store)["hasAnsweredWiFiJoinPrompt"])

        let off = SettingsStore(defaults: makeDefaults())
        let prepared = SettingsPreferenceCatalog.prepare([
            "joinsWiFiInApp": .bool(true),
            "hasAnsweredWiFiJoinPrompt": .bool(true)
        ])
        XCTAssertTrue(prepared.values.isEmpty)
        SettingsPreferenceCatalog.apply(prepared.values, to: off)
        XCTAssertFalse(off.joinsWiFiInApp)
    }

    func testTurningItOffForgetsSavedPasswordsAndClosesAnOpenForm() async {
        let worker = ForgettingWorker()
        let controller = WiFiNetworkController(scanWorker: worker, periodicRefreshSleep: { _ in
            try await Task.sleep(for: .seconds(3600))
        })
        controller.activate(nameAccess: .authorized)
        for _ in 0..<500 where controller.state != .ready {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let home = WiFiNetworkIdentity(ssid: "Home", security: .wpa2Personal)
        worker.nextOutcome = .needsPassword
        controller.join(home)
        for _ in 0..<500 where controller.joinState != .needsPassword(home, retry: false) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(controller.joinState, .needsPassword(home, retry: false))

        controller.forgetSavedPasswords()

        XCTAssertEqual(worker.forgetCount, 1)
        XCTAssertEqual(controller.joinState, .idle)
        controller.deactivate()
    }

    func testFileStoreRemoveAllDeletesTheFileAndStaysUsable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WiFiJoinOptInTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".status-trio", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let store = FileWiFiPasswordStore(directoryURL: directory)
        store.save("one", for: "Home")
        store.save("two", for: "Cafe")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))

        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertNil(store.password(for: "Home"))
        XCTAssertNil(store.password(for: "Cafe"))

        // Removing again, with nothing there, is harmless; later saves work.
        store.removeAll()
        XCTAssertTrue(store.save("three", for: "Home"))
        XCTAssertEqual(store.password(for: "Home"), "three")
    }
}

private final class ForgettingWorker: WiFiNetworkScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var forgets = 0
    private var outcome: WiFiJoinOutcome = .unavailable

    var forgetCount: Int { lock.withLock { forgets } }
    var nextOutcome: WiFiJoinOutcome {
        get { lock.withLock { outcome } }
        set { lock.withLock { outcome = newValue } }
    }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        completion(.success(WiFiScanPayload(networks: [], details: .unavailable)))
    }

    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        completion(true)
    }

    func join(
        ssid: String,
        credential: WiFiJoinCredential,
        completion: @escaping @Sendable (WiFiJoinOutcome) -> Void
    ) {
        completion(nextOutcome)
    }

    func forgetSavedPasswords() {
        lock.withLock { forgets += 1 }
    }
}
