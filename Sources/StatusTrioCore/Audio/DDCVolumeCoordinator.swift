import CoreAudio
import Foundation
import os

/// Serializes all display discovery and I2C operations away from the main actor.
@MainActor
final class DDCVolumeCoordinator: DDCVolumeCoordinating {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let worker: DDCWorker
    private let sleep: Sleep
    private let onUpdate: @MainActor (DDCVolumeUpdate) -> Void
    private let debounce: Duration
    private let readWatchdog: Duration
    private let onReadCompletion: @MainActor (AudioDeviceID, String, UInt64) -> Void
    private let onDebounceSettled: @MainActor () -> Void
    private var outputID: AudioDeviceID?
    private var uid: String?
    private(set) var generation: UInt64 = 0
    private var detailsVisible = false
    private var displayAsleep = false
    private var stopped = false
    private var timerTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pendingVolume: Double?
    private var pendingVolumeCommandID: UInt64?
    private var nextVolumeCommandID: UInt64 = 0
    private var failures = 0
    private var readInFlight = false
    private var refreshQueued = false
    private var refreshQueuedCommandID: UInt64?
    private var refreshQueuedRequestedValue: UInt16?
    private var readToken: UInt64 = 0

    init(
        transport: DDCVolumeTransport = DDCDisplayTransport(),
        debounce: Duration = .milliseconds(150),
        readWatchdog: Duration = .seconds(2),
        beforeReadValidation: @escaping @Sendable () -> Void = {},
        onReadCompletion: @escaping @MainActor (AudioDeviceID, String, UInt64) -> Void = { _, _, _ in },
        onDebounceSettled: @escaping @MainActor () -> Void = {},
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void
    ) {
        self.worker = DDCWorker(transport: transport, beforeReadValidation: beforeReadValidation)
        self.debounce = debounce
        self.readWatchdog = readWatchdog
        self.onReadCompletion = onReadCompletion
        self.onDebounceSettled = onDebounceSettled
        self.sleep = sleep
        self.onUpdate = onUpdate
    }

    convenience init(
        onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void,
        configuration: DDCVolumeCoordinatorConfiguration
    ) {
        self.init(
            transport: DDCDisplayTransport(),
            debounce: configuration.debounce,
            readWatchdog: configuration.readWatchdog,
            beforeReadValidation: configuration.beforeReadValidation,
            onReadCompletion: configuration.onReadCompletion,
            onDebounceSettled: configuration.onDebounceSettled,
            sleep: configuration.sleep,
            onUpdate: onUpdate
        )
    }

    func select(outputID: AudioDeviceID, uid: String?) {
        guard !stopped else { return }
        generation &+= 1
        self.outputID = outputID
        self.uid = uid
        pendingVolume = nil
        pendingVolumeCommandID = nil
        debounceTask?.cancel()
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(outputID: outputID, uid: uid, generation: generation)
        timerTask?.cancel()
        guard let uid, !uid.isEmpty, !displayAsleep else { emit(.unknown); return }
        refresh()
    }

    func topologyChanged() {
        guard !stopped else { return }
        generation &+= 1
        pendingVolume = nil
        pendingVolumeCommandID = nil
        debounceTask?.cancel()
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(outputID: outputID, uid: uid, generation: generation)
        worker.invalidateTarget()
        timerTask?.cancel()
        guard uid != nil, !displayAsleep else { emit(.unknown); return }
        refresh()
    }

    func setDetailsVisible(_ visible: Bool) {
        guard !stopped, detailsVisible != visible else { return }
        detailsVisible = visible
        timerTask?.cancel()
        if outputID != nil, uid != nil, !displayAsleep { refresh() }
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard !stopped, displayAsleep != asleep else { return }
        displayAsleep = asleep
        timerTask?.cancel()
        generation &+= 1
        pendingVolume = nil
        pendingVolumeCommandID = nil
        debounceTask?.cancel()
        watchdogTask?.cancel()
        refreshQueued = false
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(outputID: asleep ? nil : outputID, uid: asleep ? nil : uid, generation: generation)
        if asleep {
            worker.invalidateTarget()
            emit(.unknown)
        } else if outputID != nil, uid != nil {
            refresh()
        }
    }

    @discardableResult
    func setVolume(_ scalar: Double) -> UInt64? {
        guard !stopped, !displayAsleep, uid != nil, scalar.isFinite else { return nil }
        nextVolumeCommandID &+= 1
        let commandID = nextVolumeCommandID
        pendingVolume = min(1, max(0, scalar))
        pendingVolumeCommandID = commandID
        debounceTask?.cancel()
        let delay = debounce
        let sleep = self.sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch {
                self?.onDebounceSettled()
                return
            }
            guard !Task.isCancelled else {
                self?.onDebounceSettled()
                return
            }
            self?.flushPendingVolume()
            self?.onDebounceSettled()
        }
        return commandID
    }

    func flushPendingVolume() {
        guard !stopped, !displayAsleep, let scalar = pendingVolume,
              let commandID = pendingVolumeCommandID,
              let outputID, let uid else { return }
        pendingVolume = nil
        pendingVolumeCommandID = nil
        debounceTask?.cancel()
        let token = generation
        worker.write(scalar: scalar, outputID: outputID, uid: uid, generation: token) { [weak self] result in
            guard let self else { return }
            guard self.accepts(outputID: outputID, uid: uid, generation: token) else { return }
            switch result {
            case .acknowledged(let value):
                // One read-back decides whether the write landed. There is no
                // retry loop: the optimistic value is never trusted on its own.
                self.refresh(confirming: commandID, requested: value)
            case .failed(let failure):
                self.emit(.unavailable(failure), commandID: commandID)
                self.schedulePoll(after: self.nextFailureInterval())
            }
        }
    }

    func refresh() { refresh(confirming: nil) }

    private func refresh(confirming commandID: UInt64?, requested: UInt16? = nil) {
        guard !stopped, !displayAsleep, let outputID, let uid, !uid.isEmpty else { return }
        timerTask?.cancel()
        guard !readInFlight else {
            refreshQueued = true
            if let commandID {
                refreshQueuedCommandID = commandID
                refreshQueuedRequestedValue = requested
            }
            scheduleWatchdog(request: readToken, outputID: outputID, uid: uid, generation: generation,
                             commandID: commandID)
            return
        }
        startRead(outputID: outputID, uid: uid, confirming: commandID, requested: requested)
    }

    private func startRead(outputID: AudioDeviceID, uid: String, confirming commandID: UInt64?, requested: UInt16?) {
        readInFlight = true
        refreshQueued = false
        readToken &+= 1
        let request = readToken
        let token = generation
        scheduleWatchdog(request: request, outputID: outputID, uid: uid, generation: token,
                         commandID: commandID)
        worker.read(outputID: outputID, uid: uid, generation: token) { [weak self] result in
            guard let self else { return }
            self.onReadCompletion(outputID, uid, token)
            guard self.readToken == request else { return }
            self.readInFlight = false
            self.watchdogTask?.cancel()
            if self.refreshQueued && !self.stopped && !self.displayAsleep {
                self.refreshQueued = false
                let confirmingCommandID = self.refreshQueuedCommandID
                self.refreshQueuedCommandID = nil
                let confirmingValue = self.refreshQueuedRequestedValue
                self.refreshQueuedRequestedValue = nil
                guard let currentOutputID = self.outputID, let currentUID = self.uid else { return }
                self.startRead(outputID: currentOutputID, uid: currentUID,
                               confirming: confirmingCommandID, requested: confirmingValue)
                return
            }
            guard self.accepts(outputID: outputID, uid: uid, generation: token) else { return }
            switch result {
            case .reply(let reply):
                self.failures = 0
                let resolvedCapability = self.resolveCapability(for: reply, requested: requested)
                self.onUpdate(DDCVolumeUpdate(
                    outputID: outputID,
                    uid: uid,
                    generation: token,
                    capability: resolvedCapability,
                    commandID: commandID
                ))
                self.schedulePoll(after: self.detailsVisible ? .seconds(2) : .seconds(10))
            case .failure(let failure):
                if let requested {
                    ddcTargetLogger.info(
                        "ddc.readback stage=readback result=failed reason=\(failure.diagnosticName, privacy: .public) requested=\(requested, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
                    )
                }
                self.emit(.unavailable(failure), commandID: commandID)
                self.schedulePoll(after: self.nextFailureInterval())
            }
        }
    }

    /// A read-back only counts as verified when the display reports exactly the
    /// register value that was written. Audible output is never inferred here.
    private func resolveCapability(for reply: DDCVolumeReply, requested: UInt16?) -> DDCVolumeCapability {
        guard let requested else { return .readable(reply) }
        let verified = reply.current == requested
        ddcTargetLogger.info(
            "ddc.readback stage=readback result=\(verified ? "verified" : "mismatch", privacy: .public) requested=\(requested, privacy: .public) readBack=\(reply.current, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
        return verified ? .writeVerified(reply) : .writeUnverified(reply)
    }

    func waitForWorkerIdle() async {
        await withCheckedContinuation { continuation in
            worker.barrier { continuation.resume() }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        generation &+= 1
        timerTask?.cancel()
        watchdogTask?.cancel()
        debounceTask?.cancel()
        pendingVolume = nil
        pendingVolumeCommandID = nil
        refreshQueued = false
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(outputID: nil, uid: nil, generation: generation)
    }

    private func scheduleWatchdog(request: UInt64, outputID: AudioDeviceID, uid: String, generation: UInt64,
                                  commandID: UInt64? = nil) {
        watchdogTask?.cancel()
        let sleep = self.sleep
        let interval = readWatchdog
        watchdogTask = Task { [weak self] in
            do { try await sleep(interval) } catch { return }
            guard !Task.isCancelled, let self, self.readToken == request,
                  self.readInFlight, self.accepts(outputID: outputID, uid: uid, generation: generation) else { return }
            self.emit(.unavailable(.timeout), commandID: commandID)
        }
    }

    private func nextFailureInterval() -> Duration {
        let intervals: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)]
        let result = intervals[min(failures, intervals.count - 1)]
        failures += 1
        return result
    }

    private func schedulePoll(after duration: Duration) {
        timerTask?.cancel()
        let sleep = self.sleep
        timerTask = Task { [weak self] in
            do { try await sleep(duration) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func accepts(outputID: AudioDeviceID, uid: String, generation: UInt64) -> Bool {
        !stopped && !displayAsleep && self.outputID == outputID && self.uid == uid && self.generation == generation
    }

    private func emit(_ capability: DDCVolumeCapability, commandID: UInt64? = nil) {
        guard let outputID, let uid else { return }
        onUpdate(DDCVolumeUpdate(outputID: outputID, uid: uid, generation: generation, capability: capability, commandID: commandID))
    }
}

/// The transport and its non-Sendable target are only touched by this queue.
private final class DDCWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.status-trio.ddc-volume", qos: .utility)
    private let transport: DDCVolumeTransport
    private let beforeReadValidation: @Sendable () -> Void
    private var target: DDCDisplayTarget?
    private var lastReply: DDCVolumeReply?
    private let identityLock = NSLock()
    private var currentOutputID: AudioDeviceID?
    private var currentUID: String?
    private var currentGeneration: UInt64 = 0

    init(transport: DDCVolumeTransport, beforeReadValidation: @escaping @Sendable () -> Void) {
        self.transport = transport
        self.beforeReadValidation = beforeReadValidation
    }

    func barrier(completion: @escaping @MainActor () -> Void) {
        queue.async { Task { @MainActor in completion() } }
    }

    func setIdentity(outputID: AudioDeviceID?, uid: String?, generation: UInt64) {
        identityLock.lock()
        currentOutputID = outputID
        currentUID = uid
        currentGeneration = generation
        identityLock.unlock()
        queue.async { [self] in
            if target?.uid != uid { target = nil; lastReply = nil }
        }
    }

    func invalidateTarget() {
        queue.async { [self] in target = nil; lastReply = nil }
    }

    func read(outputID: AudioDeviceID, uid: String, generation: UInt64, completion: @escaping @MainActor (DDCVolumeReadResult) -> Void) {
        queue.async { [self] in
            beforeReadValidation()
            guard matches(outputID: outputID, uid: uid, generation: generation) else {
                Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                return
            }
            if target?.uid != uid { target = transport.resolve(uid: uid) }
            guard let target else {
                lastReply = nil
                Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                return
            }
            let result = transport.read(target)
            lastReply = result.replyValue
            Task { @MainActor in completion(result) }
        }
    }

    func write(scalar: Double, outputID: AudioDeviceID, uid: String, generation: UInt64, completion: @escaping @MainActor (DDCWriteResult) -> Void) {
        queue.async { [self] in
            guard matches(outputID: outputID, uid: uid, generation: generation) else { return }
            if target?.uid != uid { target = transport.resolve(uid: uid) }
            guard let target else {
                Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                return
            }
            let reply: DDCVolumeReply
            if let lastReply { reply = lastReply }
            else {
                let freshResult = transport.read(target)
                guard let freshReply = freshResult.replyValue else {
                    Task { @MainActor in completion(.failed(freshResult.failureReason ?? .replyReadFailed)) }
                    return
                }
                reply = freshReply
                lastReply = freshReply
            }
            guard matches(outputID: outputID, uid: uid, generation: generation) else { return }
            let value = reply.targetValue(for: scalar)
            let acknowledged = transport.write(target, value: value)
            lastReply = nil
            Task { @MainActor in
                completion(acknowledged ? .acknowledged(value: value) : .failed(.requestWriteFailed))
            }
        }
    }

    private func matches(outputID: AudioDeviceID, uid: String, generation: UInt64) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        return currentOutputID == outputID && currentUID == uid && currentGeneration == generation
    }
}
