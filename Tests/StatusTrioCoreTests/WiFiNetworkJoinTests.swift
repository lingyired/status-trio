import Foundation
import XCTest
@testable import StatusTrioCore

/// The in-app join flow of `WiFiNetworkController`: which credential a tap
/// asks the worker for, how each outcome moves the published state, and that a
/// closed list drops a late result.
@MainActor
final class WiFiNetworkJoinTests: XCTestCase {
    private let home = WiFiNetworkIdentity(ssid: "Home", security: .wpa2Personal)
    private let lobby = WiFiNetworkIdentity(ssid: "Lobby", security: .open)

    private func makeController(
        worker: JoinScriptedWorker = JoinScriptedWorker()
    ) -> (WiFiNetworkController, JoinScriptedWorker) {
        (WiFiNetworkController(scanWorker: worker, periodicRefreshSleep: { _ in
            try await Task.sleep(for: .seconds(3600))
        }), worker)
    }

    private func activate(_ controller: WiFiNetworkController, _ worker: JoinScriptedWorker) async {
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(worker.scanCount, 1)
    }

    func testOpenNetworkJoinsWithNoCredentialAndRescans() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.joined]

        var result: Bool?
        controller.join(lobby) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(worker.joins, [.init(ssid: "Lobby", credential: JoinCredentialRecord.none)])
        XCTAssertEqual(result, true)
        XCTAssertEqual(controller.joinState, .idle)
        await waitUntil { worker.scanCount == 2 }
        controller.deactivate()
    }

    func testPersonalNetworkWithoutASavedPasswordAsksForOne() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.needsPassword]

        var result: Bool?
        controller.join(home) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(worker.joins.map(\.credential), [.stored])
        XCTAssertEqual(result, false)
        XCTAssertEqual(controller.joinState, .needsPassword(home, retry: false))
        controller.deactivate()
    }

    func testPersonalNetworkJoinsWithTheSavedPasswordWhenOneExists() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.joined]

        var result: Bool?
        controller.join(home) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(worker.joins.map(\.credential), [.stored])
        XCTAssertEqual(result, true)
        XCTAssertEqual(controller.joinState, .idle)
        controller.deactivate()
    }

    func testSubmittingAPasswordSendsItTypedAndFinishesIdle() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.needsPassword, .joined]
        controller.join(home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: false) }

        var result: Bool?
        controller.submitPassword("hunter2!", for: home) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(worker.joins.map(\.credential), [.stored, .typed("hunter2!")])
        XCTAssertEqual(result, true)
        XCTAssertEqual(controller.joinState, .idle)
        controller.deactivate()
    }

    func testARefusedTypedPasswordAsksAgainAndSaysSo() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.needsPassword, .rejected]
        controller.join(home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: false) }

        controller.submitPassword("wrong", for: home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: true) }
        controller.deactivate()
    }

    func testARefusedSavedPasswordAsksAgain() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.rejected]

        controller.join(home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: true) }
        controller.deactivate()
    }

    func testARefusedOpenJoinAndOtherFailuresReportAFailure() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)

        worker.outcomes = [.rejected]
        controller.join(lobby)
        await waitUntil { controller.joinState == .failed(lobby, .rejected) }
        controller.cancelJoin()

        worker.outcomes = [.notInRange]
        controller.join(lobby)
        await waitUntil { controller.joinState == .failed(lobby, .notInRange) }
        controller.cancelJoin()

        worker.outcomes = [.unavailable]
        controller.join(lobby)
        await waitUntil { controller.joinState == .failed(lobby, .unavailable) }
        controller.deactivate()
    }

    func testNetworksTheJoinDoesNotCoverNeverReachTheWorker() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)

        for identity in [
            WiFiNetworkIdentity(ssid: "Corp", security: .wpa2Enterprise),
            WiFiNetworkIdentity(ssid: "Old", security: .wep),
            WiFiNetworkIdentity(ssid: "", security: .wpa2Personal)
        ] {
            var result: Bool?
            controller.join(identity) { result = $0 }
            await waitUntil { result != nil }
            XCTAssertEqual(result, false)
        }
        XCTAssertTrue(worker.joins.isEmpty)
        XCTAssertEqual(controller.joinState, .idle)
        controller.deactivate()
    }

    func testASecondJoinIsIgnoredWhileOneIsRunning() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.holdsJoin = true

        controller.join(lobby)
        XCTAssertEqual(controller.joinState, .joining(lobby))
        var second: Bool?
        controller.join(home) { second = $0 }
        await waitUntil { second != nil }

        XCTAssertEqual(second, false)
        XCTAssertEqual(worker.joins.count, 1)
        // A running association cannot be cancelled.
        controller.cancelJoin()
        XCTAssertEqual(controller.joinState, .joining(lobby))

        worker.finishHeldJoin(.joined)
        await waitUntil { controller.joinState == .idle }
        controller.deactivate()
    }

    func testSubmitIsIgnoredWithoutAMatchingPromptOrWithAnEmptyPassword() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)

        var result: Bool?
        controller.submitPassword("secret", for: home) { result = $0 }
        await waitUntil { result != nil }
        XCTAssertEqual(result, false)

        worker.outcomes = [.needsPassword]
        controller.join(home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: false) }

        result = nil
        controller.submitPassword("", for: home) { result = $0 }
        await waitUntil { result != nil }
        result = nil
        controller.submitPassword("secret", for: lobby) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(worker.joins.count, 1)
        XCTAssertEqual(controller.joinState, .needsPassword(home, retry: false))
        controller.deactivate()
    }

    func testCancelDismissesThePasswordForm() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.outcomes = [.needsPassword]
        controller.join(home)
        await waitUntil { controller.joinState == .needsPassword(home, retry: false) }

        controller.cancelJoin()
        XCTAssertEqual(controller.joinState, .idle)
        controller.deactivate()
    }

    func testClosingTheListDropsTheFormAndALateResultButStillReportsTheJoin() async {
        let (controller, worker) = makeController()
        await activate(controller, worker)
        worker.holdsJoin = true

        var result: Bool?
        controller.join(lobby) { result = $0 }
        XCTAssertEqual(controller.joinState, .joining(lobby))

        controller.deactivate()
        XCTAssertEqual(controller.joinState, .idle)

        worker.finishHeldJoin(.joined)
        await waitUntil { result != nil }
        // The caller still learns the join worked (so the status monitor can
        // refresh), but the closed list is not touched or rescanned.
        XCTAssertEqual(result, true)
        XCTAssertEqual(controller.joinState, .idle)
        XCTAssertEqual(worker.scanCount, 1)
    }

    func testJoinIsIgnoredWhileTheListIsClosed() async {
        let (controller, worker) = makeController()
        var result: Bool?
        controller.join(lobby) { result = $0 }
        await waitUntil { result != nil }

        XCTAssertEqual(result, false)
        XCTAssertTrue(worker.joins.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Wi-Fi join flow")
    }
}

private enum JoinCredentialRecord: Equatable, Sendable {
    case none
    case stored
    case typed(String)

    init(_ credential: WiFiJoinCredential) {
        switch credential {
        case .none: self = .none
        case .stored: self = .stored
        case .typed(let password): self = .typed(password)
        }
    }
}

private final class JoinScriptedWorker: WiFiNetworkScanning, @unchecked Sendable {
    struct Join: Equatable {
        let ssid: String
        let credential: JoinCredentialRecord
    }

    private let lock = NSLock()
    private var recordedJoins: [Join] = []
    private var scans = 0
    private var scriptedOutcomes: [WiFiJoinOutcome] = []
    private var held: (@Sendable (WiFiJoinOutcome) -> Void)?
    private var holds = false

    var joins: [Join] { lock.withLock { recordedJoins } }
    var scanCount: Int { lock.withLock { scans } }
    var outcomes: [WiFiJoinOutcome] {
        get { lock.withLock { scriptedOutcomes } }
        set { lock.withLock { scriptedOutcomes = newValue } }
    }
    var holdsJoin: Bool {
        get { lock.withLock { holds } }
        set { lock.withLock { holds = newValue } }
    }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        lock.withLock { scans += 1 }
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
        let outcome: WiFiJoinOutcome? = lock.withLock {
            recordedJoins.append(Join(ssid: ssid, credential: JoinCredentialRecord(credential)))
            if holds {
                held = completion
                return nil
            }
            return scriptedOutcomes.isEmpty ? .unavailable : scriptedOutcomes.removeFirst()
        }
        if let outcome { completion(outcome) }
    }

    func finishHeldJoin(_ outcome: WiFiJoinOutcome) {
        let completion = lock.withLock { () -> (@Sendable (WiFiJoinOutcome) -> Void)? in
            defer { held = nil }
            return held
        }
        completion?(outcome)
    }
}
