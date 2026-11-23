import Foundation
import os

/// One display's brightness update, published to the owning monitor.
///
/// `scalar` is only ever a value the display actually reported for a read, so a
/// write is never represented as an optimistic success. `source` doubles as the
/// capability/availability signal: `.directDDC` means a valid brightness reply
/// was read, `.unavailable(reason)` means it could not be.
struct DDCBrightnessUpdate: Sendable, Equatable {
    /// Stable external-display identity (EDID-derived UID).
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
    private var timerTask: Task<Void, Never>?
    private var failures = 0
    private let onWatchdogTimeout: WatchdogTimeoutHandler
    private var displayID: String?
    private(set) var generation: UInt64 = 0
    private var displayAsleep = false
    private var stopped = false
    private var watchdogTask: Task<Void, Never>?
    private var pacingTask: Task<Void, Never>?
    private var pendingScalar: Double?
    private var pendingCommandID: UInt64?
    private var nextCommandID: UInt64 = 0
    private var latestCommandID: UInt64?
    // This gate describes physical transport work and survives generation changes.
    // A watchdog reports failure without releasing it; only the callback does so.
    private var busy = false
    private var refreshQueued = false
    private var flushRequested = false
    private var lastWriteStart: ContinuousClock.Instant?
    private var confirmedReply: DDCVolumeReply?

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
        worker = DDCBrightnessWorker(transport: transport, beforeReadValidation: beforeReadValidation)
        self.debounce = debounce
        self.readWatchdog = readWatchdog
        self.watchdogSleep = watchdogSleep
        self.onWatchdogTimeout = onWatchdogTimeout
        self.sleep = sleep
        self.onUpdate = onUpdate
        self.pollInterval = pollInterval
    }

    func select(displayID: String) {
        guard !stopped else { return }
        resetGeneration()
        self.displayID = displayID
        worker.setIdentity(displayID: displayAsleep ? nil : displayID, generation: generation)
        guard !displayID.isEmpty, !displayAsleep else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.resolveFailed))
            return
        }
        refresh()
    }

    func topologyChanged() {
        guard !stopped else { return }
        resetGeneration()
        worker.setIdentity(displayID: displayAsleep ? nil : displayID, generation: generation)
        worker.invalidateTarget()
        refresh()
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard !stopped, displayAsleep != asleep else { return }
        displayAsleep = asleep
        resetGeneration()
        worker.setIdentity(displayID: asleep ? nil : displayID, generation: generation)
        if asleep {
            worker.invalidateTarget()
            emit(scalar: nil, canAdjust: false, source: .unavailable(.unresponsive))
        } else {
            refresh()
        }
    }

    private func resetGeneration() {
        generation &+= 1
        timerTask?.cancel()
        pendingScalar = nil
        pendingCommandID = nil
        latestCommandID = nil
        refreshQueued = false
        flushRequested = false
        confirmedReply = nil
        lastWriteStart = nil
        pacingTask?.cancel()
        pacingTask = nil
        watchdogTask?.cancel()
    }

    @discardableResult
    func setBrightness(_ scalar: Double) -> UInt64? {
        guard isAvailable, scalar.isFinite else { return nil }
        timerTask?.cancel()
        nextCommandID &+= 1
        latestCommandID = nextCommandID
        pendingScalar = min(1, max(0, scalar))
        pendingCommandID = nextCommandID
        drain()
        return nextCommandID
    }

    /// Release bypasses pacing, including when the current transaction finishes
    /// later. Consuming the one pending slot makes repeated release calls a no-op.
    func flushPendingBrightness() {
        guard pendingScalar != nil else { return }
        flushRequested = true
        pacingTask?.cancel()
        pacingTask = nil
        drain()
    }

    func refresh() {
        guard isAvailable else { return }
        timerTask?.cancel()
        refreshQueued = true
        drain()
    }

    private var isAvailable: Bool {
        !stopped && !displayAsleep && displayID?.isEmpty == false
    }

    /// There is one physical transaction and one replaceable pending value.
    /// Pacing is measured from a write start, so new input cannot postpone it.
    private func drain() {
        guard isAvailable, !busy, let displayID else { return }
        if refreshQueued {
            refreshQueued = false
            startRead(displayID: displayID, commandID: nil, requested: nil)
            return
        }
        guard let scalar = pendingScalar, let commandID = pendingCommandID else { return }
        if !flushRequested, let lastWriteStart {
            let remaining = debounce - lastWriteStart.duration(to: .now)
            if remaining > .zero {
                guard pacingTask == nil else { return }
                let sleep = self.sleep
                pacingTask = Task { [weak self] in
                    do { try await sleep(remaining) } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    self.pacingTask = nil
                    self.drain()
                }
                return
            }
        }
        pacingTask?.cancel()
        pacingTask = nil
        pendingScalar = nil
        pendingCommandID = nil
        flushRequested = false
        if let reply = confirmedReply, reply.targetValue(for: scalar) == reply.current {
            // A new command still needs an asynchronous, exact read confirmation.
            let expectedValue = reply.current
            startRead(displayID: displayID, commandID: commandID, requested: expectedValue)
            return
        }
        confirmedReply = nil
        busy = true
        lastWriteStart = .now
        let token = generation
        worker.write(scalar: scalar, displayID: displayID, generation: token) { [weak self] result in
            guard let self else { return }
            self.busy = false
            guard self.accepts(displayID: displayID, generation: token) else {
                self.drain()
                return
            }
            switch result {
            case .acknowledged(let value):
                self.startRead(displayID: displayID, commandID: commandID, requested: value)
            case .failed(let failure):
                if commandID == self.latestCommandID {
                    self.emit(scalar: nil, canAdjust: false, source: .unavailable(Self.reason(for: failure)), commandID: commandID)
                }
                self.drain()
                self.schedulePollIfIdle(after: self.nextFailureInterval())
            }
        }
    }

    private func startRead(displayID: String, commandID: UInt64?, requested: UInt16?) {
        busy = true
        let token = generation
        let sleep = watchdogSleep
        let timeout = readWatchdog
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            guard !Task.isCancelled, let self,
                  self.accepts(displayID: displayID, generation: token), self.busy else { return }
            let affectedCommand = self.pendingCommandID ?? commandID
            self.emit(scalar: nil, canAdjust: false, source: .unavailable(.timeout), commandID: affectedCommand)
            self.onWatchdogTimeout(token, affectedCommand)
            // The blocked call still owns the slot. Never queue another read or
            // write merely because the watchdog fired.
        }
        worker.read(displayID: displayID, generation: token) { [weak self] result in
            guard let self else { return }
            self.busy = false
            self.watchdogTask?.cancel()
            guard self.accepts(displayID: displayID, generation: token) else {
                self.drain()
                return
            }
            switch result {
            case .reply(let reply):
                self.failures = 0
                let resolved = Self.resolve(reply: reply, requested: requested)
                self.confirmedReply = commandID != nil && resolved.scalar != nil ? reply : nil
                // A verified in-flight write can also confirm the latest command
                // if it quantizes to the same value, without programming it twice.
                var confirmedCommand = commandID
                if requested != nil, resolved.scalar != nil,
                   let pending = self.pendingScalar,
                   reply.targetValue(for: pending) == reply.current {
                    confirmedCommand = self.pendingCommandID
                    self.pendingScalar = nil
                    self.pendingCommandID = nil
                    self.flushRequested = false
                }
                if (confirmedCommand == nil && self.pendingScalar == nil) ||
                    (confirmedCommand != nil && confirmedCommand == self.latestCommandID) {
                    self.emit(scalar: resolved.scalar, canAdjust: resolved.scalar != nil,
                              source: resolved.source, commandID: confirmedCommand)
                }
            case .failure(let failure):
                self.confirmedReply = nil
                if (commandID == nil && self.pendingScalar == nil) ||
                    (commandID != nil && commandID == self.latestCommandID) {
                    self.emit(scalar: nil, canAdjust: false, source: .unavailable(Self.reason(for: failure)), commandID: commandID)
                }
            }
            self.drain()
            self.schedulePollIfIdle(after: result.replyValue == nil ? self.nextFailureInterval() : self.pollInterval)
        }
    }

    private func nextFailureInterval() -> Duration {
        let intervals: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)]
        let interval = intervals[min(failures, intervals.count - 1)]
        failures += 1
        return interval
    }

    private func schedulePollIfIdle(after interval: Duration) {
        guard isAvailable, !busy, pendingScalar == nil, !refreshQueued else { return }
        timerTask?.cancel()
        let sleep = self.sleep
        timerTask = Task { [weak self] in
            do { try await sleep(interval) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
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
        resetGeneration()
        worker.setIdentity(displayID: nil, generation: generation)
    }

    private func accepts(displayID: String, generation: UInt64) -> Bool {
        isAvailable && self.displayID == displayID && self.generation == generation
    }

    private func emit(scalar: Double?, canAdjust: Bool, source: BrightnessControlSource, commandID: UInt64? = nil) {
        guard let displayID else { return }
        onUpdate(DDCBrightnessUpdate(displayID: displayID, generation: generation, scalar: scalar,
                                     canAdjust: canAdjust, source: source, commandID: commandID))
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

/// Cross-instance admission gate for one stable external display (EDID UID).
/// At most one physical operation runs and at most one newer operation waits;
/// replacing the waiter fails its completion. Closures are invoked outside the
/// lock, so a blocked display never blocks the main actor or another display.
private final class DDCTransportGate: @unchecked Sendable {
    private struct PendingOperation {
        let ownerID: UUID
        let run: @Sendable () -> Void
        let cancelled: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var active = false
    private var pending: PendingOperation?

    func submit(ownerID: UUID, run: @escaping @Sendable () -> Void,
                cancelled: @escaping @Sendable () -> Void) {
        var start = false
        var replaced: (@Sendable () -> Void)?
        lock.lock()
        if active {
            replaced = pending?.cancelled
            pending = PendingOperation(ownerID: ownerID, run: run, cancelled: cancelled)
        } else {
            active = true
            start = true
        }
        lock.unlock()
        replaced?()
        if start { run() }
    }

    func cancelPending(ownerID: UUID) {
        var cancelled: (@Sendable () -> Void)?
        lock.lock()
        if pending?.ownerID == ownerID {
            cancelled = pending?.cancelled
            pending = nil
        }
        lock.unlock()
        cancelled?()
    }

    /// Called exactly once by the running operation after it finishes or is
    /// cancelled by generation validation. Hands the single pending slot over.
    func finish() {
        var next: PendingOperation?
        lock.lock()
        if let pending {
            self.pending = nil
            next = pending
        } else {
            active = false
        }
        lock.unlock()
        next?.run()
    }
}

/// Weak registry: gates live only while an operation is active or pending.
private final class DDCTransportGateRegistry: @unchecked Sendable {
    static let shared = DDCTransportGateRegistry()

    private final class WeakGate {
        weak var gate: DDCTransportGate?
        init(_ gate: DDCTransportGate) { self.gate = gate }
    }

    private let lock = NSLock()
    private var gates: [String: WeakGate] = [:]

    func gate(for uid: String) -> DDCTransportGate {
        lock.lock()
        defer { lock.unlock() }
        gates = gates.filter { $0.value.gate != nil }
        if let existing = gates[uid]?.gate { return existing }
        let gate = DDCTransportGate()
        gates[uid] = WeakGate(gate)
        return gate
    }

    func cancelPending(uid: String, ownerID: UUID) {
        lock.lock()
        let gate = gates[uid]?.gate
        lock.unlock()
        gate?.cancelPending(ownerID: ownerID)
    }
}

/// The transport and its non-Sendable target are only touched by this queue.
private final class DDCBrightnessWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.status-trio.ddc-brightness", qos: .utility)
    private let transport: DDCFeatureTransport
    private let beforeReadValidation: @Sendable () -> Void
    private let gateRegistry: DDCTransportGateRegistry
    private var target: DDCDisplayTarget?
    private var lastReply: DDCVolumeReply?
    private let identityLock = NSLock()
    private var currentDisplayID: String?
    private var currentGeneration: UInt64 = 0
    private var operationOwnerID = UUID()
    private let admissionGroup = DispatchGroup()

    init(transport: DDCFeatureTransport, beforeReadValidation: @escaping @Sendable () -> Void,
         gateRegistry: DDCTransportGateRegistry = .shared) {
        self.transport = transport
        self.beforeReadValidation = beforeReadValidation
        self.gateRegistry = gateRegistry
    }

    func barrier(completion: @escaping @MainActor () -> Void) {
        // Includes operations waiting for admission: the group leaves only when
        // the worker's queue actually starts them, or when they are cancelled.
        admissionGroup.notify(queue: queue) {
            Task { @MainActor in completion() }
        }
    }

    func setIdentity(displayID: String?, generation: UInt64) {
        identityLock.lock()
        let previousDisplayID = currentDisplayID
        let previousOwner = operationOwnerID
        operationOwnerID = UUID()
        currentDisplayID = displayID
        currentGeneration = generation
        identityLock.unlock()
        if let previousDisplayID {
            gateRegistry.cancelPending(uid: previousDisplayID, ownerID: previousOwner)
        }
        queue.async { [self] in
            if target?.uid != displayID { target = nil }
            lastReply = nil
        }
    }

    func invalidateTarget() {
        queue.async { [self] in target = nil; lastReply = nil }
    }

    private func currentOwner() -> UUID {
        identityLock.lock(); defer { identityLock.unlock() }
        return operationOwnerID
    }

    func read(displayID: String, generation: UInt64,
              completion: @escaping @MainActor (DDCVolumeReadResult) -> Void) {
        let owner = currentOwner()
        let gate = gateRegistry.gate(for: displayID)
        let group = admissionGroup
        group.enter()
        gate.submit(
            ownerID: owner,
            run: { [weak self, gate, group] in
                guard let self else {
                    group.leave()
                    gate.finish()
                    Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                    return
                }
                self.queue.async {
                    defer { group.leave(); gate.finish() }
                    self.beforeReadValidation()
                    guard self.matches(displayID: displayID, generation: generation) else {
                        Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                        return
                    }
                    if self.target?.uid != displayID { self.target = self.transport.resolve(uid: displayID) }
                    guard let target = self.target else {
                        self.lastReply = nil
                        Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                        return
                    }
                    // resolve may block while the generation changes; do not
                    // start a hardware read for a stale command.
                    guard self.matches(displayID: displayID, generation: generation) else {
                        Task { @MainActor in completion(.failure(.serviceUnavailable)) }
                        return
                    }
                    let result = self.transport.read(target, feature: DDCPacket.brightnessVCP)
                    self.lastReply = result.replyValue
                    Task { @MainActor in completion(result) }
                }
            },
            cancelled: {
                group.leave()
                Task { @MainActor in completion(.failure(.serviceUnavailable)) }
            }
        )
    }

    func write(scalar: Double, displayID: String, generation: UInt64,
               completion: @escaping @MainActor (DDCWriteResult) -> Void) {
        let owner = currentOwner()
        let gate = gateRegistry.gate(for: displayID)
        let group = admissionGroup
        group.enter()
        gate.submit(
            ownerID: owner,
            run: { [weak self, gate, group] in
                guard let self else {
                    group.leave()
                    gate.finish()
                    Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                    return
                }
                self.queue.async {
                    defer { group.leave(); gate.finish() }
                    guard self.matches(displayID: displayID, generation: generation) else {
                        Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                        return
                    }
                    if self.target?.uid != displayID { self.target = self.transport.resolve(uid: displayID) }
                    guard let target = self.target else {
                        Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                        return
                    }
                    guard self.matches(displayID: displayID, generation: generation) else {
                        Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                        return
                    }
                    let reply: DDCVolumeReply
                    if let lastReply = self.lastReply {
                        reply = lastReply
                    } else {
                        let freshResult = self.transport.read(target, feature: DDCPacket.brightnessVCP)
                        guard let freshReply = freshResult.replyValue else {
                            Task { @MainActor in completion(.failed(freshResult.failureReason ?? .replyReadFailed)) }
                            return
                        }
                        reply = freshReply
                        self.lastReply = freshReply
                    }
                    // The range pre-read may have blocked while the generation
                    // changed: never program the old command after it returns.
                    guard self.matches(displayID: displayID, generation: generation) else {
                        Task { @MainActor in completion(.failed(.serviceUnavailable)) }
                        return
                    }
                    let value = reply.targetValue(for: scalar)
                    let acknowledged = self.transport.write(target, value: value, feature: DDCPacket.brightnessVCP)
                    self.lastReply = nil
                    Task { @MainActor in
                        completion(acknowledged ? .acknowledged(value: value) : .failed(.requestWriteFailed))
                    }
                }
            },
            cancelled: {
                group.leave()
                Task { @MainActor in completion(.failed(.serviceUnavailable)) }
            }
        )
    }

    private func matches(displayID: String, generation: UInt64) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        return currentDisplayID == displayID && currentGeneration == generation
    }
}