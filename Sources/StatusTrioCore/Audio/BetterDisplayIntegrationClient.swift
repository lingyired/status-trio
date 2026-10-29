import Foundation

enum BetterDisplayIntegrationError: Error, Equatable, Sendable {
    case notStarted
    case tooManyPendingRequests
    case timedOut
    case requestFailed
    case invalidResponse
    case stopped
}

struct BetterDisplayRequestEnvelope: Encodable {
    let uuid: String
    let commands: [String]
    let parameters: [String: String?]
}

private struct BetterDisplayResponseEnvelope: Decodable, Sendable {
    let uuid: String?
    let result: Bool?
    let payload: String?
}

private struct BetterDisplayOSDEnvelope: Decodable, Sendable {
    let systemIconID: Int?
    let controlTarget: String?

    var isAudioEvent: Bool {
        systemIconID == 3
            || systemIconID == 4
            || controlTarget == "volume"
            || controlTarget == "mute"
    }
}

private enum BetterDisplayNotificationName {
    static let request = Notification.Name("pro.betterdisplay.BetterDisplay.request")
    static let response = Notification.Name("pro.betterdisplay.BetterDisplay.response")
    static let launched = Notification.Name("pro.betterdisplay.BetterDisplay.launched")
    static let terminated = Notification.Name("pro.betterdisplay.BetterDisplay.terminated")
    static let osd = Notification.Name("pro.betterdisplay.BetterDisplay.osd")
}

@MainActor
protocol BetterDisplayNotificationBridging: AnyObject {
    func addObserver(
        name: Notification.Name,
        handler: @escaping @Sendable (String?) -> Void
    ) -> any BetterDisplayNotificationObservation
    func post(name: Notification.Name, object: String)
}

protocol BetterDisplayNotificationObservation: Sendable {
    func cancel()
}

@MainActor
final class SystemBetterDisplayNotificationBridge: BetterDisplayNotificationBridging {
    private let center: DistributedNotificationCenter

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    func addObserver(
        name: Notification.Name,
        handler: @escaping @Sendable (String?) -> Void
    ) -> any BetterDisplayNotificationObservation {
        let token = center.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { notification in
            let object = notification.object as? String
            handler(object)
        }
        return SystemBetterDisplayNotificationObservation(
            center: center,
            token: token
        )
    }

    func post(name: Notification.Name, object: String) {
        center.postNotificationName(
            name,
            object: object,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

/// Notification removal is documented as thread-safe. The lock makes the
/// single-use observation safe to cancel from the client's nonisolated deinit.
private final class SystemBetterDisplayNotificationObservation:
    BetterDisplayNotificationObservation,
    @unchecked Sendable
{
    private let center: DistributedNotificationCenter
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    init(center: DistributedNotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func cancel() {
        let token = lock.withLock {
            let token = self.token
            self.token = nil
            return token
        }
        if let token {
            center.removeObserver(token)
        }
    }
}

@MainActor
final class BetterDisplayIntegrationClient: BetterDisplayRequesting {
    private struct PendingRequest {
        let continuation: CheckedContinuation<String?, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private static let defaultRequestDeadline: Duration = .seconds(3)
    private static let defaultMaximumPendingRequests = 32

    private let bridge: any BetterDisplayNotificationBridging
    private let requestDeadline: Duration
    private let deadlineSleep: @Sendable (Duration) async throws -> Void
    private let maximumPendingRequests: Int

    private var observations: [any BetterDisplayNotificationObservation] = []
    private var pendingRequests: [String: PendingRequest] = [:]
    private var onEvent: (@MainActor (BetterDisplayEvent) -> Void)?
    private var lifecycleGeneration: UInt64 = 0
    private var isStarted = false

    init(
        bridge: any BetterDisplayNotificationBridging = SystemBetterDisplayNotificationBridge(),
        requestDeadline: Duration = BetterDisplayIntegrationClient.defaultRequestDeadline,
        deadlineSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        maximumPendingRequests: Int = BetterDisplayIntegrationClient.defaultMaximumPendingRequests
    ) {
        precondition(maximumPendingRequests > 0)
        self.bridge = bridge
        self.requestDeadline = requestDeadline
        self.deadlineSleep = deadlineSleep
        self.maximumPendingRequests = maximumPendingRequests
    }

    deinit {
        for observation in observations {
            observation.cancel()
        }
        for pendingRequest in pendingRequests.values {
            pendingRequest.timeoutTask.cancel()
            pendingRequest.continuation.resume(throwing: BetterDisplayIntegrationError.stopped)
        }
    }

    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void) {
        self.onEvent = onEvent
        guard isStarted == false else { return }

        isStarted = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration

        observations.append(
            observeResponses(generation: generation)
        )
        observations.append(
            observeLifecycle(
                name: BetterDisplayNotificationName.launched,
                event: .launched,
                generation: generation
            )
        )
        observations.append(
            observeLifecycle(
                name: BetterDisplayNotificationName.terminated,
                event: .terminated,
                generation: generation
            )
        )
        observations.append(
            observeOSD(generation: generation)
        )
    }

    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String? {
        guard isStarted else {
            throw BetterDisplayIntegrationError.notStarted
        }
        guard pendingRequests.count < maximumPendingRequests else {
            throw BetterDisplayIntegrationError.tooManyPendingRequests
        }

        let requestID = UUID().uuidString
        let envelope = BetterDisplayRequestEnvelope(
            uuid: requestID,
            commands: commands,
            parameters: parameters
        )
        let data = try JSONEncoder().encode(envelope)
        let json = try dataString(data)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = makeTimeoutTask(for: requestID)
                pendingRequests[requestID] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                bridge.post(
                    name: BetterDisplayNotificationName.request,
                    object: json
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestID: requestID)
            }
        }
    }

    func stop() {
        isStarted = false
        lifecycleGeneration &+= 1
        onEvent = nil

        let observations = observations
        self.observations.removeAll()
        for observation in observations {
            observation.cancel()
        }

        let pendingRequests = pendingRequests
        self.pendingRequests.removeAll()
        for pendingRequest in pendingRequests.values {
            pendingRequest.timeoutTask.cancel()
            pendingRequest.continuation.resume(
                throwing: BetterDisplayIntegrationError.stopped
            )
        }
    }

    private func observeResponses(
        generation: UInt64
    ) -> any BetterDisplayNotificationObservation {
        bridge.addObserver(name: BetterDisplayNotificationName.response) {
            [weak self] object in
            guard
                let object,
                let data = object.data(using: .utf8),
                let response = try? JSONDecoder().decode(
                    BetterDisplayResponseEnvelope.self,
                    from: data
                )
            else {
                return
            }

            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.isCurrent(generation: generation)
                else {
                    return
                }
                self.resolve(response)
            }
        }
    }

    private func observeLifecycle(
        name: Notification.Name,
        event: BetterDisplayEvent,
        generation: UInt64
    ) -> any BetterDisplayNotificationObservation {
        bridge.addObserver(name: name) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.isCurrent(generation: generation)
                else {
                    return
                }
                self.onEvent?(event)
            }
        }
    }

    private func observeOSD(
        generation: UInt64
    ) -> any BetterDisplayNotificationObservation {
        bridge.addObserver(name: BetterDisplayNotificationName.osd) {
            [weak self] object in
            guard
                let object,
                let data = object.data(using: .utf8),
                let osd = try? JSONDecoder().decode(
                    BetterDisplayOSDEnvelope.self,
                    from: data
                ),
                osd.isAudioEvent
            else {
                return
            }

            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.isCurrent(generation: generation)
                else {
                    return
                }
                self.onEvent?(.audioChanged)
            }
        }
    }

    private func makeTimeoutTask(for requestID: String) -> Task<Void, Never> {
        let requestDeadline = requestDeadline
        let deadlineSleep = deadlineSleep
        return Task { @MainActor [weak self] in
            do {
                try await deadlineSleep(requestDeadline)
            } catch {
                return
            }
            guard let self, Task.isCancelled == false else { return }
            self.timeOut(requestID: requestID)
        }
    }

    private func resolve(_ response: BetterDisplayResponseEnvelope) {
        guard
            let requestID = response.uuid,
            let pendingRequest = pendingRequests.removeValue(forKey: requestID)
        else {
            return
        }

        pendingRequest.timeoutTask.cancel()
        guard let result = response.result else {
            pendingRequest.continuation.resume(
                throwing: BetterDisplayIntegrationError.invalidResponse
            )
            return
        }
        guard result else {
            pendingRequest.continuation.resume(
                throwing: BetterDisplayIntegrationError.requestFailed
            )
            return
        }
        pendingRequest.continuation.resume(returning: response.payload)
    }

    private func timeOut(requestID: String) {
        guard let pendingRequest = pendingRequests.removeValue(forKey: requestID) else {
            return
        }
        pendingRequest.timeoutTask.cancel()
        pendingRequest.continuation.resume(
            throwing: BetterDisplayIntegrationError.timedOut
        )
    }

    private func cancel(requestID: String) {
        guard let pendingRequest = pendingRequests.removeValue(forKey: requestID) else {
            return
        }
        pendingRequest.timeoutTask.cancel()
        pendingRequest.continuation.resume(throwing: CancellationError())
    }

    private func isCurrent(generation: UInt64) -> Bool {
        isStarted && lifecycleGeneration == generation
    }

    private func dataString(_ data: Data) throws -> String {
        guard let json = String(data: data, encoding: .utf8) else {
            throw BetterDisplayIntegrationError.invalidResponse
        }
        return json
    }
}
