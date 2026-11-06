import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BetterDisplayBrightnessTests: XCTestCase {
    func testPendingTargetSuppressesSupersededReadSuccessAndFailure() async {
        for oldResponse: Result<String?, BetterDisplayIntegrationError> in [
            .success("0.40,0,1"), .failure(.timedOut)
        ] {
            for latestResponse: Result<String?, BetterDisplayIntegrationError> in [
                .success("0.90,0,1"), .failure(.timedOut)
            ] {
                let client = DelayedBrightnessClient(responses: [
                    .success("0.40,0,1"), oldResponse, .success(nil), latestResponse
                ], heldRequestIndex: 1)
                var updates: [BetterDisplayBrightnessCoordinator.Update] = []
                let coordinator = BetterDisplayBrightnessCoordinator(
                    client: client, displayUUID: "read-uuid"
                ) { updates.append($0) }
                coordinator.start()
                await waitUntil { updates.count == 1 }
                coordinator.refresh()
                await waitUntil { client.hasHeldRequest }
                coordinator.setBrightness(0.9)
                client.releaseRequest()
                await waitUntil { client.requests.count == 4 && updates.count >= 2 }
                XCTAssertEqual(client.requests, [["get"], ["get"], ["set"], ["get"]])
                XCTAssertEqual(updates.count, 2, "The superseded read must publish neither its old scalar nor its failure")
                assertLatestResponse(latestResponse, update: updates.last)
                coordinator.stop()
            }
        }
    }

    func testPendingTargetSuppressesSupersededWriteSuccessAndFailure() async {
        for oldSetResponse: Result<String?, BetterDisplayIntegrationError> in [
            .success(nil), .failure(.timedOut)
        ] {
            for latestResponse: Result<String?, BetterDisplayIntegrationError> in [
                .success("0.90,0,1"), .failure(.timedOut)
            ] {
                var responses: [Result<String?, BetterDisplayIntegrationError>] = [
                    .success("0.40,0,1"), oldSetResponse
                ]
                if case .success = oldSetResponse { responses.append(.success("0.60,0,1")) }
                responses.append(contentsOf: [.success(nil), latestResponse])
                let client = DelayedBrightnessClient(responses: responses, heldRequestIndex: 1)
                var updates: [BetterDisplayBrightnessCoordinator.Update] = []
                let coordinator = BetterDisplayBrightnessCoordinator(
                    client: client, displayUUID: "write-uuid"
                ) { updates.append($0) }
                coordinator.start()
                await waitUntil { updates.count == 1 }
                coordinator.setBrightness(0.6)
                await waitUntil { client.hasHeldRequest }
                coordinator.setBrightness(0.9)
                client.releaseRequest()
                await waitUntil { client.requests.count == responses.count && updates.count >= 2 }
                XCTAssertEqual(updates.count, 2, "The superseded write must publish neither its old confirmation nor its failure")
                XCTAssertEqual(client.writtenScalars, [0.6, 0.9])
                assertLatestResponse(latestResponse, update: updates.last)
                coordinator.stop()
            }
        }
    }

    private func assertLatestResponse(
        _ response: Result<String?, BetterDisplayIntegrationError>,
        update: BetterDisplayBrightnessCoordinator.Update?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch response {
        case .success:
            XCTAssertEqual(update?.scalar ?? -1, 0.9, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(update?.source, .betterDisplay, file: file, line: line)
            XCTAssertEqual(update?.canSet, true, file: file, line: line)
        case .failure:
            XCTAssertNil(update?.scalar, file: file, line: line)
            XCTAssertEqual(update?.source, .unavailable(.timeout), file: file, line: line)
            XCTAssertEqual(update?.canSet, false, file: file, line: line)
        }
    }

    // MARK: - Read

    func testReadUsesGetKeyedByDisplayUUID() async {
        let client = BrightnessRecordingClient()
        client.responder = { _, commands, _ in
            XCTAssertEqual(commands, ["get"])
            return "0.50,0.0,1.0"
        }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].commands, ["get"])
        XCTAssertEqual(client.requests[0].parameters["UUID"] ?? nil, "builtin-uuid")
        // The brightness/value/min/max keys are present (with nil values).
        let keys = Set(client.requests[0].parameters.keys)
        XCTAssertTrue(keys.isSuperset(of: ["UUID", "brightness", "value", "min", "max"]))

        let update = updates[0]
        XCTAssertEqual(update.displayUUID, "builtin-uuid")
        XCTAssertEqual(update.scalar ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertTrue(update.canSet)
        XCTAssertEqual(update.source, .betterDisplay)
        XCTAssertNotNil(update.commandID)
        coordinator.stop()
    }

    // MARK: - Write + read-back

    func testSetWritesThenReadsBackConfirmed() async {
        let state = Box(0.40)
        let client = BrightnessRecordingClient()
        client.responder = { _, commands, parameters in
            if commands == ["set"] {
                if let raw = parameters["brightness"] ?? nil, let value = Double(raw) {
                    state.value = value
                }
                return nil
            }
            return "\(state.value),0.0,1.0"
        }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }
        XCTAssertEqual(updates[0].scalar ?? -1, 0.40, accuracy: 0.0001)

        coordinator.setBrightness(0.8)
        await waitUntil { updates.count == 2 }

        XCTAssertEqual(client.requests.count, 3)
        XCTAssertEqual(client.requests[1].commands, ["set"])
        XCTAssertEqual(client.requests[1].parameters["UUID"] ?? nil, "builtin-uuid")
        XCTAssertEqual(client.requests[1].parameters["brightness"] ?? nil, "0.8")
        XCTAssertEqual(client.requests[1].parameters["min"] ?? nil, "0.0")
        XCTAssertEqual(client.requests[1].parameters["max"] ?? nil, "1.0")
        // Third request is the read-back confirmation.
        XCTAssertEqual(client.requests[2].commands, ["get"])

        XCTAssertEqual(updates[1].scalar ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertTrue(updates[1].canSet)
        XCTAssertEqual(updates[1].source, .betterDisplay)
        coordinator.stop()
    }

    func testSetUnconfirmedReadBackMapsToWriteNotConfirmed() async {
        let client = BrightnessRecordingClient()
        // The device ignores writes: reads always report 0.60.
        client.responder = { _, commands, _ in
            if commands == ["set"] { return nil }
            return "0.60,0.0,1.0"
        }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        coordinator.setBrightness(0.8)
        await waitUntil { updates.count == 2 }

        XCTAssertEqual(
            updates[1].source,
            .unavailable(.writeNotConfirmed)
        )
        // The reported value is the read-back, never the optimistic target.
        XCTAssertEqual(updates[1].scalar ?? -1, 0.60, accuracy: 0.0001)
        coordinator.stop()
    }

    func testSetWithinToleranceIsConfirmed() async {
        // A device that lands on the nearest native step (0.8 -> 0.79) still
        // counts as confirmed within the 2% tolerance.
        let client = BrightnessRecordingClient()
        client.responder = { _, commands, _ in
            if commands == ["set"] { return nil }
            return "0.79,0.0,1.0"
        }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        coordinator.setBrightness(0.8)
        await waitUntil { updates.count == 2 }

        XCTAssertEqual(updates[1].source, .betterDisplay)
        coordinator.stop()
    }

    // MARK: - Failure mapping

    func testTimeoutMapsToTimeout() async {
        let client = BrightnessRecordingClient()
        client.responder = { _, _, _ in throw BetterDisplayIntegrationError.timedOut }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        XCTAssertEqual(updates[0].source, .unavailable(.timeout))
        XCTAssertFalse(updates[0].canSet)
        XCTAssertNil(updates[0].scalar)
        coordinator.stop()
    }

    func testRequestFailureMapsToUnresponsive() async {
        let client = BrightnessRecordingClient()
        client.responder = { _, _, _ in
            throw BetterDisplayIntegrationError.requestFailed
        }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        XCTAssertEqual(updates[0].source, .unavailable(.unresponsive))
        XCTAssertFalse(updates[0].canSet)
        coordinator.stop()
    }

    func testInvalidPayloadMapsToReadFailed() async {
        let client = BrightnessRecordingClient()
        client.responder = { _, _, _ in "not-a-brightness-reply" }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }

        XCTAssertEqual(updates[0].source, .unavailable(.readFailed))
        XCTAssertFalse(updates[0].canSet)
        XCTAssertNil(updates[0].scalar)
        coordinator.stop()
    }

    // MARK: - Lifecycle

    func testTerminationMapsToAppAbsent() async {
        let client = BrightnessRecordingClient()
        client.responder = { _, _, _ in "0.50,0.0,1.0" }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }
        XCTAssertEqual(updates[0].source, .betterDisplay)

        client.send(.terminated)
        await waitUntil { updates.count == 2 }

        XCTAssertEqual(updates[1].source, .unavailable(.appAbsent))
        XCTAssertFalse(updates[1].canSet)
        XCTAssertNil(updates[1].scalar)
        coordinator.stop()
    }

    // MARK: - OSD hint wiring

    func testBrightnessOSDHintTriggersRefresh() async {
        let client = BrightnessHintRecordingClient()
        client.responder = { _, _, _ in "0.50,0.0,1.0" }
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "builtin-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.count == 1 }
        let initialRequests = client.requests.count

        client.fireBrightnessOSDHint()
        await waitUntil { client.requests.count > initialRequests }

        XCTAssertGreaterThan(client.requests.count, initialRequests)
        XCTAssertEqual(client.requests.last?.commands, ["get"])
        coordinator.stop()
    }

    // MARK: - Client OSD recognition (T2.2)

    func testClientRecognizesBrightnessOSDAsHintWithoutAudioEvent() async {
        let bridge = BrightnessFakeBridge()
        let client = BetterDisplayIntegrationClient(bridge: bridge)
        var events: [BetterDisplayEvent] = []
        var hintCount = 0
        client.start { events.append($0) }
        client.setBrightnessOSDHandler { hintCount += 1 }

        bridge.send(
            BrightnessFakeBridge.osd,
            #"{"controlTarget":"brightness"}"#
        )
        await settle()

        XCTAssertEqual(hintCount, 1)
        XCTAssertTrue(events.isEmpty)
        client.stop()
    }

    func testClientKeepsVolumeOSDAsAudioEvent() async {
        let bridge = BrightnessFakeBridge()
        let client = BetterDisplayIntegrationClient(bridge: bridge)
        var events: [BetterDisplayEvent] = []
        var hintCount = 0
        client.start { events.append($0) }
        client.setBrightnessOSDHandler { hintCount += 1 }

        bridge.send(
            BrightnessFakeBridge.osd,
            #"{"controlTarget":"volume"}"#
        )
        await settle()

        XCTAssertEqual(hintCount, 0)
        XCTAssertEqual(events, [.audioChanged])
        client.stop()
    }

    func testClientIgnoresUnrelatedOSD() async {
        let bridge = BrightnessFakeBridge()
        let client = BetterDisplayIntegrationClient(bridge: bridge)
        var events: [BetterDisplayEvent] = []
        var hintCount = 0
        client.start { events.append($0) }
        client.setBrightnessOSDHandler { hintCount += 1 }

        bridge.send(
            BrightnessFakeBridge.osd,
            #"{"displayID":7,"systemIconID":1,"value":0.5}"#
        )
        await settle()

        XCTAssertEqual(hintCount, 0)
        XCTAssertTrue(events.isEmpty)
        client.stop()
    }

    // MARK: - Helpers

    private func waitUntil(
        _ condition: () -> Bool,
        rounds: Int = 1000
    ) async {
        for _ in 0..<rounds {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

// MARK: - Test doubles

private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Holds one selected get/set request until the test supplies its completion.
/// The other scripted responses make superseded and latest failures independent.
@MainActor
private final class DelayedBrightnessClient: BetterDisplayRequesting {
    private let responses: [Result<String?, BetterDisplayIntegrationError>]
    private let heldRequestIndex: Int
    private var continuation: CheckedContinuation<String?, Error>?
    private(set) var requests: [[String]] = []
    private(set) var writtenScalars: [Double] = []
    var hasHeldRequest: Bool { continuation != nil }

    init(responses: [Result<String?, BetterDisplayIntegrationError>], heldRequestIndex: Int) {
        self.responses = responses
        self.heldRequestIndex = heldRequestIndex
    }

    func request(commands: [String], parameters: [String: String?]) async throws -> String? {
        let index = requests.count
        requests.append(commands)
        if commands == ["set"], let raw = parameters["brightness"] ?? nil, let value = Double(raw) {
            writtenScalars.append(value)
        }
        guard index < responses.count else {
            XCTFail("Unexpected BetterDisplay request at index \(index)")
            throw BetterDisplayIntegrationError.timedOut
        }
        if index == heldRequestIndex {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return try responses[index].get()
    }

    func releaseRequest() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: responses[heldRequestIndex].mapError { $0 as Error })
    }

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {}
    func stop() {}
}

@MainActor
private final class BrightnessRecordingClient: BetterDisplayRequesting {
    struct RecordedRequest {
        let commands: [String]
        let parameters: [String: String?]
    }

    private(set) var requests: [RecordedRequest] = []
    private(set) var isStarted = false
    var responder:
        ((Int, [String], [String: String?]) throws -> String?)!

    private var eventHandler: (@MainActor (BetterDisplayEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {
        eventHandler = onEvent
        isStarted = true
    }

    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String? {
        let index = requests.count
        requests.append(
            RecordedRequest(commands: commands, parameters: parameters)
        )
        return try responder(index, commands, parameters)
    }

    func stop() {
        isStarted = false
        eventHandler = nil
    }

    func send(_ event: BetterDisplayEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class BrightnessHintRecordingClient:
    BetterDisplayRequesting,
    BetterDisplayBrightnessHintSource
{
    struct RecordedRequest {
        let commands: [String]
        let parameters: [String: String?]
    }

    private(set) var requests: [RecordedRequest] = []
    private(set) var isStarted = false
    var responder:
        ((Int, [String], [String: String?]) throws -> String?)!

    private var eventHandler: (@MainActor (BetterDisplayEvent) -> Void)?
    private var brightnessHandler: (@MainActor () -> Void)?

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {
        eventHandler = onEvent
        isStarted = true
    }

    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String? {
        let index = requests.count
        requests.append(
            RecordedRequest(commands: commands, parameters: parameters)
        )
        return try responder(index, commands, parameters)
    }

    func stop() {
        isStarted = false
        eventHandler = nil
    }

    func setBrightnessOSDHandler(_ handler: (@MainActor () -> Void)?) {
        brightnessHandler = handler
    }

    func fireBrightnessOSDHint() {
        brightnessHandler?()
    }
}

@MainActor
private final class BrightnessFakeBridge: BetterDisplayNotificationBridging {
    static let osd = Notification.Name("pro.betterdisplay.BetterDisplay.osd")

    private final class Token:
        BetterDisplayNotificationObservation,
        @unchecked Sendable
    {
        func cancel() {}
    }

    private var handlers: [String: [@Sendable (String?) -> Void]] = [:]

    func addObserver(
        name: Notification.Name,
        handler: @escaping @Sendable (String?) -> Void
    ) -> any BetterDisplayNotificationObservation {
        handlers[name.rawValue, default: []].append(handler)
        return Token()
    }

    func post(name: Notification.Name, object: String) {}

    func send(_ name: Notification.Name, _ object: String?) {
        for handler in handlers[name.rawValue] ?? [] {
            handler(object)
        }
    }
}

/// A client whose `set` requests can be held open, so a slider drag can be
/// simulated while a previous write is still in flight.
@MainActor
private final class GatedBrightnessClient: BetterDisplayRequesting {
    var gateClosed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var writes: [Double] = []
    private var current = 0.4

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {}
    func stop() {}

    func request(commands: [String], parameters: [String: String?]) async throws -> String? {
        if commands == ["set"] {
            if let raw = parameters["brightness"] ?? nil, let value = Double(raw) {
                writes.append(value)
                current = value
            }
            if gateClosed {
                await withCheckedContinuation { waiters.append($0) }
            }
            return nil
        }
        return "\(current),0.0,1.0"
    }

    func release() {
        gateClosed = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

extension BetterDisplayBrightnessTests {
    func testLatestDragValueIsSentAfterAnInFlightWriteFinishes() async {
        let client = GatedBrightnessClient()
        var updates: [BetterDisplayBrightnessCoordinator.Update] = []
        let coordinator = BetterDisplayBrightnessCoordinator(
            client: client,
            displayUUID: "external-uuid"
        ) { updates.append($0) }

        coordinator.start()
        await waitUntil { updates.contains { ($0.scalar ?? -1) == 0.4 } }

        client.gateClosed = true
        coordinator.setBrightness(0.5)
        await waitUntil { client.writes.count == 1 }

        // A second drag while the first write is still open must not be dropped.
        coordinator.setBrightness(0.9)
        client.release()

        await waitUntil { client.writes == [0.5, 0.9] }
        XCTAssertEqual(client.writes, [0.5, 0.9])
        await waitUntil { updates.last?.scalar.map { abs($0 - 0.9) < 0.001 } ?? false }
        coordinator.stop()
    }
}
