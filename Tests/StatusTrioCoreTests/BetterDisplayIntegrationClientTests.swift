import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BetterDisplayIntegrationClientTests {
    private let requestName = Notification.Name("pro.betterdisplay.BetterDisplay.request")
    private let responseName = Notification.Name("pro.betterdisplay.BetterDisplay.response")
    private let launchedName = Notification.Name("pro.betterdisplay.BetterDisplay.launched")
    private let terminatedName = Notification.Name("pro.betterdisplay.BetterDisplay.terminated")
    private let osdName = Notification.Name("pro.betterdisplay.BetterDisplay.osd")

    @Test("The request envelope preserves nil parameters and exact field names")
    func requestEnvelopePreservesNilParameters() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["set"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)

        #expect(posted.name == requestName)
        let data = try #require(posted.object?.data(using: .utf8))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == Set(["uuid", "commands", "parameters"]))
        let requestID = try #require(object["uuid"] as? String)
        #expect(UUID(uuidString: requestID) != nil)
        #expect(object["commands"] as? [String] == ["set"])

        let parameters = try #require(object["parameters"] as? [String: Any])
        #expect(parameters["UUID"] as? String == "display-a")
        #expect(parameters["volume"] is NSNull)

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: nil)
        )
        #expect(try await task.value == nil)
        client.stop()
    }

    @Test("The response observer is registered before the request is posted")
    func responseObserverIsRegisteredBeforePost() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        let addObserverIndex = try #require(
            bridge.operations.firstIndex(of: .addObserver(responseName.rawValue))
        )
        let postRequestIndex = try #require(
            bridge.operations.firstIndex(of: .post(requestName.rawValue))
        )
        #expect(addObserverIndex < postRequestIndex)
        #expect(bridge.registeredNames.contains(responseName))
        #expect(bridge.registeredNames.contains(launchedName))
        #expect(bridge.registeredNames.contains(terminatedName))
        #expect(bridge.registeredNames.contains(osdName))
        #expect(
            bridge.registeredNames.allSatisfy {
                $0.rawValue.hasPrefix("pro.betterdisplay.BetterDisplay.")
            }
        )

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: nil)
        )
        _ = try await task.value
        client.stop()
    }

    @Test("Only the matching response UUID resolves a request")
    func unmatchedUUIDDoesNotResolveRequest() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: "another-request", result: true, payload: "wrong")
        )
        let commaSeparatedObjects = #"{"UUID":"display-a","name":"Desk, Main"},{"deviceType":"DisplayGroup","tagID":"group-a"}"#
        bridge.send(
            name: responseName,
            object: try responseJSON(
                uuid: requestID,
                result: true,
                payload: commaSeparatedObjects
            )
        )

        #expect(try await task.value == commaSeparatedObjects)
        client.stop()
    }

    @Test("Malformed JSON is ignored until a valid matching response arrives")
    func malformedJSONDoesNotResolveRequest() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        bridge.send(name: responseName, object: "{not-json")
        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: "valid")
        )

        #expect(try await task.value == "valid")
        client.stop()
    }

    @Test("A false result fails the request")
    func falseResultFailsRequest() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["set"],
                parameters: ["UUID": "display-a", "volume": "0.8"]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: false, payload: "failed")
        )

        await expectFailure(.requestFailed, from: task)
        client.stop()
    }

    @Test("A response without result fails the request")
    func missingResultFailsRequest() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: nil, payload: "ignored")
        )

        await expectFailure(.invalidResponse, from: task)
        client.stop()
    }

    @Test("A successful response may omit a payload")
    func successWithoutPayloadReturnsNil() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["set"],
                parameters: ["UUID": "display-a", "volume": "0.5"]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)

        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: nil)
        )

        #expect(try await task.value == nil)
        client.stop()
    }

    @Test("The default deadline is three seconds and times out the request")
    func requestTimesOutAtDefaultDeadline() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let sleeper = ManualEventSleeper()
        let client = BetterDisplayIntegrationClient(
            bridge: bridge,
            deadlineSleep: { duration in await sleeper.sleep(duration) }
        )
        client.start { _ in }

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        await sleeper.waitForCallCount(1)
        #expect(sleeper.durations == [.seconds(3)])

        sleeper.releaseAll()
        await expectFailure(.timedOut, from: task)
        client.stop()
    }

    @Test("Cancelling a request removes it and permits another request")
    func cancellationRemovesPendingRequest() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge, maximumPendingRequests: 1)
        client.start { _ in }

        let first = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        first.cancel()

        do {
            _ = try await first.value
            Issue.record("Expected cancellation.")
        } catch is CancellationError {
            // Expected cleanup path.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }

        let second = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-b", "volume": nil]
            )
        }
        await bridge.waitForPostCount(2)
        let posted = try #require(bridge.posts.last)
        let requestID = try requestID(from: posted)
        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: "display-b")
        )

        #expect(try await second.value == "display-b")
        client.stop()
    }

    @Test("The pending request map has a hard bound")
    func pendingRequestsAreBounded() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge, maximumPendingRequests: 1)
        client.start { _ in }

        let first = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)

        do {
            _ = try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-b", "volume": nil]
            )
            Issue.record("Expected the pending-request bound to reject the second request.")
        } catch let error as BetterDisplayIntegrationError {
            #expect(error == .tooManyPendingRequests)
        } catch {
            Issue.record("Expected tooManyPendingRequests, received \(error).")
        }
        #expect(bridge.posts.count == 1)

        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)
        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: nil)
        )
        _ = try await first.value
        client.stop()
    }

    @Test("Stopping cancels observers and releases pending requests")
    func stopReleasesObserversAndPendingRequests() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }
        #expect(bridge.activeObserverCount > 0)

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        client.stop()

        await expectFailure(.stopped, from: task)
        await bridge.waitForActiveObserverCount(0)
        #expect(bridge.activeObserverCount == 0)

        do {
            _ = try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
            Issue.record("Expected a stopped client to reject requests.")
        } catch let error as BetterDisplayIntegrationError {
            #expect(error == .notStarted)
        } catch {
            Issue.record("Expected notStarted, received \(error).")
        }
    }

    @Test("A stopped client can restart with fresh observers")
    func clientCanRestartAfterStop() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)
        client.start { _ in }
        client.stop()
        await bridge.waitForActiveObserverCount(0)

        client.start { _ in }
        #expect(bridge.activeObserverCount > 0)

        let task = Task { @MainActor in
            try await client.request(
                commands: ["get"],
                parameters: ["UUID": "display-a", "volume": nil]
            )
        }
        await bridge.waitForPostCount(1)
        let posted = try #require(bridge.posts.first)
        let requestID = try requestID(from: posted)
        bridge.send(
            name: responseName,
            object: try responseJSON(uuid: requestID, result: true, payload: "restarted")
        )

        #expect(try await task.value == "restarted")
        client.stop()
    }

    @Test("Deallocation releases observers")
    func deallocationReleasesObservers() async {
        let bridge = FakeBetterDisplayNotificationBridge()
        var client: BetterDisplayIntegrationClient? = makeClient(bridge: bridge)
        let deinitProbe = DeinitProbe.track(client)
        client?.start { _ in }
        #expect(bridge.activeObserverCount > 0)

        client = nil

        #expect(deinitProbe.value == nil)
        await bridge.waitForActiveObserverCount(0)
        #expect(bridge.activeObserverCount == 0)
    }

    @Test("Launch and termination notifications map without reading their object")
    func lifecycleNotificationsMapToEvents() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)

        let launched = await firstEvent(from: client) {
            bridge.send(name: launchedName, object: "ignored")
        }
        #expect(launched == .launched)

        let terminated = await firstEvent(from: client) {
            bridge.send(name: terminatedName, object: nil)
        }
        #expect(terminated == .terminated)
        client.stop()
    }

    @Test(
        "Valid volume and mute OSD notifications become refresh hints",
        arguments: [
            #"{"systemIconID":3,"value":0.61}"#,
            #"{"systemIconID":4}"#,
            #"{"controlTarget":"volume"}"#
        ]
    )
    func validAudioOSDBecomesRefreshHint(_ object: String) async {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)

        let event = await firstEvent(from: client) {
            bridge.send(name: osdName, object: object)
        }
        #expect(event == .audioChanged)
        client.stop()
    }

    @Test("Non-audio and malformed OSD notifications do not become events")
    func unrelatedOSDDoesNotBecomeEvent() async throws {
        let bridge = FakeBetterDisplayNotificationBridge()
        let client = makeClient(bridge: bridge)

        let event = await firstEvent(from: client) {
            bridge.send(
                name: osdName,
                object: #"{"displayID":7,"systemIconID":1,"value":0.5}"#
            )
            bridge.send(name: osdName, object: #"{"controlTarget":"brightness"}"#)
            bridge.send(name: osdName, object: "{not-json")
            bridge.send(name: launchedName, object: nil)
        }

        #expect(event == .launched)
        client.stop()
    }

    private func makeClient(
        bridge: FakeBetterDisplayNotificationBridge,
        maximumPendingRequests: Int = 32
    ) -> BetterDisplayIntegrationClient {
        BetterDisplayIntegrationClient(
            bridge: bridge,
            maximumPendingRequests: maximumPendingRequests
        )
    }

    private func firstEvent(
        from client: BetterDisplayIntegrationClient,
        after action: @escaping @MainActor () -> Void
    ) async -> BetterDisplayEvent {
        await withCheckedContinuation { continuation in
            client.start { event in
                continuation.resume(returning: event)
            }
            action()
        }
    }

    private func expectFailure(
        _ expected: BetterDisplayIntegrationError,
        from task: Task<String?, any Error>
    ) async {
        do {
            _ = try await task.value
            Issue.record("Expected \(expected).")
        } catch let error as BetterDisplayIntegrationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), received \(error).")
        }
    }

    private func requestID(from posted: FakePostedNotification) throws -> String {
        let data = try #require(posted.object?.data(using: .utf8))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(object["uuid"] as? String)
    }

    private func responseJSON(
        uuid: String?,
        result: Bool?,
        payload: String?
    ) throws -> String {
        var object: [String: Any] = [:]
        if let uuid { object["uuid"] = uuid }
        if let result { object["result"] = result }
        if let payload { object["payload"] = payload }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }
}

private struct FakePostedNotification: Equatable, Sendable {
    let name: Notification.Name
    let object: String?
}

@MainActor
private final class FakeBetterDisplayNotificationBridge: BetterDisplayNotificationBridging {
    enum Operation: Equatable, Sendable {
        case addObserver(String)
        case post(String)
        case removeObserver(String)
    }

    private struct HandlerRecord {
        let name: Notification.Name
        let handler: @Sendable (String?) -> Void
    }

    private(set) var operations: [Operation] = []
    private(set) var posts: [FakePostedNotification] = []
    private var handlers: [UUID: HandlerRecord] = [:]
    private var postWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var observerWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    var registeredNames: [Notification.Name] {
        operations.compactMap {
            guard case let .addObserver(name) = $0 else { return nil }
            return Notification.Name(name)
        }
    }

    var activeObserverCount: Int {
        handlers.count
    }

    func addObserver(
        name: Notification.Name,
        handler: @escaping @Sendable (String?) -> Void
    ) -> any BetterDisplayNotificationObservation {
        let id = UUID()
        handlers[id] = HandlerRecord(name: name, handler: handler)
        operations.append(.addObserver(name.rawValue))
        return FakeBetterDisplayNotificationObservation { [weak self] in
            Task { @MainActor [weak self] in
                self?.removeObserver(id: id, name: name)
            }
        }
    }

    func post(name: Notification.Name, object: String) {
        posts.append(FakePostedNotification(name: name, object: object))
        operations.append(.post(name.rawValue))
        resumePostWaiters()
    }

    func send(name: Notification.Name, object: String?) {
        let matchingHandlers = handlers.values
            .filter { $0.name == name }
            .map(\.handler)
        matchingHandlers.forEach { handler in
            handler(object)
        }
    }

    func waitForPostCount(_ count: Int) async {
        guard posts.count < count else { return }
        await withCheckedContinuation { continuation in
            postWaiters.append((count: count, continuation: continuation))
        }
    }

    func waitForActiveObserverCount(_ count: Int) async {
        guard handlers.count != count else { return }
        await withCheckedContinuation { continuation in
            observerWaiters.append((count: count, continuation: continuation))
        }
    }

    private func removeObserver(id: UUID, name: Notification.Name) {
        guard handlers.removeValue(forKey: id) != nil else { return }
        operations.append(.removeObserver(name.rawValue))
        resumeObserverWaiters()
    }

    private func resumePostWaiters() {
        var remaining: [
            (count: Int, continuation: CheckedContinuation<Void, Never>)
        ] = []
        for waiter in postWaiters {
            if posts.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        postWaiters = remaining
    }

    private func resumeObserverWaiters() {
        var remaining: [
            (count: Int, continuation: CheckedContinuation<Void, Never>)
        ] = []
        for waiter in observerWaiters {
            if handlers.count == waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        observerWaiters = remaining
    }
}

private final class FakeBetterDisplayNotificationObservation:
    BetterDisplayNotificationObservation,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?

    init(cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let cancellation = lock.withLock {
            let cancellation = self.cancellation
            self.cancellation = nil
            return cancellation
        }
        cancellation?()
    }
}
