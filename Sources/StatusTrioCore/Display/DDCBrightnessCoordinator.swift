import Foundation
import os

/// One display's brightness update, published to the owning monitor.
///
/// `scalar` is only ever a value the display actually reported for a read, so a
/// write is never represented as an optimistic success. `source` doubles as the
/// capability/availability signal: `.directDDC` means a valid brightness reply
/// was read, `.unavailable(reason)` means it could not be.
struct DDCBrightnessUpdate: Sendable, Equatable {
    /// Stable display identity (the `CGDisplayCreateUUID` string == DDC UID).
    let displayID: String
    let generation: UInt64
    /// 0...1 brightness, or nil when the display did not return a valid reading.
    let scalar: Double?
    /// Whether a brightness read succeeded. Writing still requires read-back.
    let canAdjust: Bool
    let source: BrightnessControlSource
    /// Set when this update confirms (or fails to confirm) a specific write.
    let commandID: UInt64?
}

/// Per-display, serial DDC brightness backend (VCP `0x10`).
///
/// The flow for a write mirrors `DDCVolumeCoordinator`: resolve the display's
/// DDC service, read the current brightness to learn the valid range, write the
/// requested scalar, then read back and only report success when the display
/// echoes exactly the value that was written. Every failure is fail-closed and
/// tagged with a `BrightnessUnavailableReason`; stale-generation reads and writes
/// are discarded.
///
/// Real-hardware I2C behaviour is NOT verified here: the transport talks to a
/// display over IOAVService, which this environment cannot exercise. Unit tests
/// drive a mock `DDCFeatureTransport`; the on-device effect is NOT RUN.
@MainActor
final class DDCBrightnessCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias WatchdogSleep = @Sendable (Duration) async throws -> Void
    typealias WatchdogTimeoutHandler = @MainActor (_ generation: UInt64, _ commandID: UInt64?) -> Void

    private let worker: DDCBrightnessWorker
    private let sleep: Sleep
    private let watchdogSleep: WatchdogSleep
    private let onUpdate: @MainActor (DDCBrightnessUpdate) -> Void
    private let debounce: Duration
    private let readWatchdog: Duration
    private let pollInterval: Duration
    private let onWatchdogTimeout: WatchdogTimeoutHandler
    private var displayID: String?
    private(set) var generation: UInt64 = 0
    private var displayAsleep = false
    private var stopped = false
    private var timerTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pendingScalar: Double?
    private var pendingCommandID: UInt64?
    private var nextCommandID: UInt64 = 0
    private var failures = 0
    private var readInFlight = false
    private var refreshQueued = false
    private var refreshQueuedCommandID: UInt64?
    private var refreshQueuedRequestedValue: UInt16?
    private var readToken: UInt64 = 0

    init(
        transport: DDCFeatureTransport = DDCDisplayTransport(),
        debounce: Duration = .milliseconds(150),
        readWatchdog: Duration = .seconds(2),
        pollInterval: Duration = .seconds(10),
        watchdogSleep: @escaping WatchdogSleep = { try await Task.sleep(for: $0) },
        onWatchdogTimeout: @escaping WatchdogTimeoutHandler = { _, _ in },
        beforeReadValidation: @escaping @Sendable () -> Void = {},
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        onUpdate: @escaping @MainActor (DDCBrightnessUpdate) -> Void
    ) {
        self.worker = DDCBrightnessWorker(transport: transport, beforeReadValidation: beforeReadValidation)
        self.debounce = debounce
        self.readWatchdog = readWatchdog
        self.pollInterval = pollInterval
        self.watchdogSleep = watchdogSleep
        self.onWatchdogTimeout = onWatchdogTimeout
        self.sleep = sleep
        self.onUpdate = onUpdate
    }

    /// Attach this coordinator to one display and immediately read its current
    /// brightness. Resolves the DDC service by the display's stable UUID.
    func select(displayID: String) {
        guard !stopped else { return }
        generation &+= 1
        self.displayID = displayID
        pendingScalar = nil
        pendingCommandID = nil
        debounceTask?.cancel()
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(displayID: displayID, generation: generation)
        timerTask?.cancel()
        guard !displayID.isEmpty, !displayAsleep else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.resolveFailed))
            return
        }
        refresh()
    }

    func topologyChanged() {
        guard !stopped else { return }
        generation &+= 1
        pendingScalar = nil
        pendingCommandID = nil
        debounceTask?.cancel()
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(displayID: displayID, generation: generation)
        worker.invalidateTarget()
        timerTask?.cancel()
        guard displayID != nil, !displayAsleep else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.resolveFailed))
            return
        }
        refresh()
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard !stopped, displayAsleep != asleep else { return }
        displayAsleep = asleep
        timerTask?.cancel()
        generation &+= 1
        pendingScalar = nil
        pendingCommandID = nil
        debounceTask?.cancel()
        watchdogTask?.cancel()
        refreshQueued = false
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(displayID: asleep ? nil : displayID, generation: generation)
        if asleep {
            worker.invalidateTarget()
            emit(scalar: nil, canAdjust: false, source: .unavailable(.unresponsive))
        } else if displayID != nil {
            refresh()
        }
    }

    /// Queue a debounced brightness write. Returns the command id used to
    /// correlate the confirming read-back, or nil when nothing can be written.
    @discardableResult
    func setBrightness(_ scalar: Double) -> UInt64? {
        guard !stopped, !displayAsleep, displayID != nil, scalar.isFinite else { return nil }
        nextCommandID &+= 1
        let commandID = nextCommandID
        pendingScalar = min(1, max(0, scalar))
        pendingCommandID = commandID
        debounceTask?.cancel()
        let delay = debounce
        let sleep = self.sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushPendingBrightness()
        }
        return commandID
    }

    func flushPendingBrightness() {
        guard !stopped, !displayAsleep, let scalar = pendingScalar,
              let commandID = pendingCommandID,
              let displayID else { return }
        pendingScalar = nil
        pendingCommandID = nil
        debounceTask?.cancel()
        let token = generation
        worker.write(scalar: scalar, displayID: displayID, generation: token) { [weak self] result in
            guard let self else { return }
            guard self.accepts(displayID: displayID, generation: token) else { return }
            switch result {
            case .acknowledged(let value):
                // One read-back decides whether the write landed. The optimistic
                // value is never trusted on its own.
                self.refresh(confirming: commandID, requested: value)
            case .failed(let failure):
                self.emit(scalar: nil, canAdjust: false, source: .unavailable(Self.reason(for: failure)), commandID: commandID)
                self.schedulePoll(after: self.nextFailureInterval())
            }
        }
    }

    func refresh() { refresh(confirming: nil) }

    private func refresh(confirming commandID: UInt64?, requested: UInt16? = nil) {
        guard !stopped, !displayAsleep, let displayID, !displayID.isEmpty else { return }
        timerTask?.cancel()
        guard !readInFlight else {
            refreshQueued = true
            if let commandID {
                refreshQueuedCommandID = commandID
                refreshQueuedRequestedValue = requested
            }
            scheduleWatchdog(request: readToken, displayID: displayID, generation: generation, commandID: commandID)
            return
        }
        startRead(displayID: displayID, confirming: commandID, requested: requested)
    }

    private func startRead(displayID: String, confirming commandID: UInt64?, requested: UInt16?) {
        readInFlight = true
        refreshQueued = false
        readToken &+= 1
        let request = readToken
        let token = generation
        scheduleWatchdog(request: request, displayID: displayID, generation: token, commandID: commandID)
        worker.read(displayID: displayID, generation: token) { [weak self] result in
            guard let self else { return }
            guard self.readToken == request else { return }
            self.readInFlight = false
            self.watchdogTask?.cancel()
            if self.refreshQueued && !self.stopped && !self.displayAsleep {
                self.refreshQueued = false
                let confirmingCommandID = self.refreshQueuedCommandID
                self.refreshQueuedCommandID = nil
                let confirmingValue = self.refreshQueuedRequestedValue
                self.refreshQueuedRequestedValue = nil
                guard let currentDisplayID = self.displayID else { return }
                self.startRead(displayID: currentDisplayID, confirming: confirmingCommandID, requested: confirmingValue)
                return
            }
            guard self.accepts(displayID: displayID, generation: token) else { return }
            switch result {
            case .reply(let reply):
                self.failures = 0
                let resolved = Self.resolve(reply: reply, requested: requested)
                // A write whose read-back did not confirm resolves to a nil
                // scalar and `.writeNotConfirmed`; never keep `canAdjust` true
                // then, or the row loses both the slider and the error text.
                self.emit(
                    scalar: resolved.scalar,
                    canAdjust: resolved.scalar != nil,
                    source: resolved.source,
                    commandID: commandID
                )
                self.schedulePoll(after: self.pollInterval)
            case .failure(let failure):
                if let requested {
                    ddcTargetLogger.info(
                        "ddc.brightness.readback stage=readback result=failed reason=\(failure.diagnosticName, privacy: .public) requested=\(requested, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
                    )
                }
                self.emit(scalar: nil, canAdjust: false, source: .unavailable(Self.reason(for: failure)), commandID: commandID)
                self.schedulePoll(after: self.nextFailureInterval())
            }
        }
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
        pendingScalar = nil
        pendingCommandID = nil
        refreshQueued = false
        refreshQueuedCommandID = nil
        refreshQueuedRequestedValue = nil
        worker.setIdentity(displayID: nil, generation: generation)
    }

    private func scheduleWatchdog(request: UInt64, displayID: String, generation: UInt64,
                                  commandID: UInt64? = nil) {
        watchdogTask?.cancel()
        let sleep = watchdogSleep
        let interval = readWatchdog
        watchdogTask = Task { [weak self] in
            do { try await sleep(interval) } catch { return }
            guard !Task.isCancelled, let self, self.readToken == request,
                  self.readInFlight, self.accepts(displayID: displayID, generation: generation) else { return }
            self.emit(scalar: nil, canAdjust: false, source: .unavailable(.timeout), commandID: commandID)
            self.onWatchdogTimeout(generation, commandID)
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

    private func accepts(displayID: String, generation: UInt64) -> Bool {
        !stopped && !displayAsleep && self.displayID == displayID && self.generation == generation
    }

    private func emit(scalar: Double?, canAdjust: Bool, source: BrightnessControlSource, commandID: UInt64? = nil) {
        guard let displayID else { return }
        onUpdate(DDCBrightnessUpdate(
            displayID: displayID,
            generation: generation,
            scalar: scalar,
            canAdjust: canAdjust,
            source: source,
            commandID: commandID
        ))
    }

    /// A read-back only counts as verified when the display reports exactly the
    /// register value that was written.
    private static func resolve(reply: DDCVolumeReply, requested: UInt16?) -> (scalar: Double?, source: BrightnessControlSource) {
        guard let requested else { return (reply.scalar, .directDDC) }
        let verified = reply.current == requested
        ddcTargetLogger.info(
            "ddc.brightness.readback stage=readback result=\(verified ? "verified" : "mismatch", privacy: .public) requested=\(requested, privacy: .public) readBack=\(reply.current, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
        return verified ? (reply.scalar, .directDDC) : (nil, .unavailable(.writeNotConfirmed))
    }

    private static func reason(for failure: DDCReadFailure) -> BrightnessUnavailableReason {
        switch failure {
        case .serviceUnavailable: .resolveFailed
        case .requestWriteFailed: .unresponsive
        case .replyReadFailed: .readFailed
        case .replyRejected(let kind):
            switch kind {
            case .vcpRefused: .unsupportedVCP
            default: .readFailed
            }
        case .vcpRejected: .unsupportedVCP
        case .timeout: .timeout
        }
    }
}

/// The transport and its non-Sendable target are only touched by this queue.
private final class DDCBrightnessWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.status-trio.ddc-brightness", qos: .utility)
    private let transport: DDCFeatureTransport
    private let beforeReadValidation: @Sendable () -> Void
    private var target: DDCDisplayTarget?
    private var lastReply: DDCVolumeReply?
    private let identityLock = NSLock()
    private var currentDisplayID: String?
    private var currentGeneration: UInt64 = 0

    init(transport: DDCFeatureTransport, beforeReadValidation: @escaping @Sendable () -> Void) {
        self.transport = transport
        self.beforeReadValidation = beforeReadValidation
    }

    func barrier(completion: @escaping @MainActor () -> Void) {
        queue.async { Task { @MainActor in completion() } }
    }

    func setIdentity(displayID: String?, generation: UInt64) {
        identityLock.lock()
        currentDisplayID = displayID
        currentGeneration = generation
        identityLock.unlock()
        queue.async { [self] in
            if target?.uid != displayID { target = nil; lastReply = nil }
        }
    }

    func invalidateTarget() {
        queue.async { [self] in target = nil; lastReply = nil }
    }

    func read(displayID: String, generation: UInt64, completion: @escaping @MainActor (DDCVolumeReadResult) -> Void) {
        queue.async { [self] in
            beforeReadValidation()
            guard matches(displayID: displayID, generation: generation) else {
                Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                return
            }
            if target?.uid != displayID { target = transport.resolve(uid: displayID) }
            guard let target else {
                lastReply = nil
                Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                return
            }
            let result = transport.read(target, feature: DDCPacket.brightnessVCP)
            lastReply = result.replyValue
            Task { @MainActor in completion(result) }
        }
    }

    func write(scalar: Double, displayID: String, generation: UInt64, completion: @escaping @MainActor (DDCWriteResult) -> Void) {
        queue.async { [self] in
            guard matches(displayID: displayID, generation: generation) else { return }
            if target?.uid != displayID { target = transport.resolve(uid: displayID) }
            guard let target else {
                Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                return
            }
            let reply: DDCVolumeReply
            if let lastReply { reply = lastReply }
            else {
                let freshResult = transport.read(target, feature: DDCPacket.brightnessVCP)
                guard let freshReply = freshResult.replyValue else {
                    Task { @MainActor in completion(.failed(freshResult.failureReason ?? .replyReadFailed)) }
                    return
                }
                reply = freshReply
                lastReply = freshReply
            }
            guard matches(displayID: displayID, generation: generation) else { return }
            let value = reply.targetValue(for: scalar)
            let acknowledged = transport.write(target, value: value, feature: DDCPacket.brightnessVCP)
            lastReply = nil
            Task { @MainActor in
                completion(acknowledged ? .acknowledged(value: value) : .failed(.requestWriteFailed))
            }
        }
    }

    private func matches(displayID: String, generation: UInt64) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        return currentDisplayID == displayID && currentGeneration == generation
    }
}
