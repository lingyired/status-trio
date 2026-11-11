import Foundation
import IOBluetooth

/// One long-lived OPPO control channel, owned by the transport for the lifetime
/// of the listening-mode surface.
///
/// The sequence is the one the reference implementation verified on hardware:
/// open the vendor SPP channel, handshake (`0x0100`) to learn the capability
/// bitmap, read the product ID (`0x0103`), read the long-press cycle (`0x010C`
/// sub-type `2`) that decides whether this model can be driven at all, then
/// subscribe to events and read the current mode. The channel is held open so the
/// buds report stem and phone changes, and so a phone that connects cannot take
/// the single control slot between our reads.
///
/// Concurrency matches `RedmiControlSession`: `IOBluetooth` delivers callbacks on
/// arbitrary threads, so all receive state is guarded by `lock`. No critical
/// section spans an `await`; a delegate path mutates under the lock, unlocks, then
/// resumes its continuation exactly once.
final class OppoControlSession: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    let address: String
    private let device: any OppoBluetoothDevice
    private let lock = NSLock()

    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = OppoFrameDecoder()
    private var engine = OppoSessionEngine()
    private var writes: [UnsafeMutableRawPointer: NSData] = [:]
    private var stopped = false
    /// The handshake has been acknowledged. The profile may still be in flight;
    /// `awaitProfile` is what turns "talked to it" into "can drive it".
    private var ready = false
    private var connecting = false

    private var connectWaiters: [CheckedContinuation<Void, any Error>] = []
    private var connectTimeout: Task<Void, Never>?

    private enum PendingKind {
        case read
        case set(BluetoothListeningMode)
    }
    private var pendingKind: PendingKind?
    private var pendingContinuation: CheckedContinuation<OppoNoiseState, any Error>?
    private var pendingToken: UInt64 = 0
    private var pendingTimeout: Task<Void, Never>?

    private var operationBusy = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    private let readTimeoutSeconds: TimeInterval
    private let setTimeoutSeconds: TimeInterval
    private let connectTimeoutSeconds: TimeInterval
    private let profileTimeoutSeconds: TimeInterval

    init(
        device: any OppoBluetoothDevice,
        address: String,
        readTimeoutSeconds: TimeInterval = 2.0,
        setTimeoutSeconds: TimeInterval = 5.0,
        connectTimeoutSeconds: TimeInterval = 15.0,
        profileTimeoutSeconds: TimeInterval = 2.5
    ) {
        self.device = device
        self.address = address
        self.readTimeoutSeconds = readTimeoutSeconds
        self.setTimeoutSeconds = setTimeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.profileTimeoutSeconds = profileTimeoutSeconds
        super.init()
    }

    // MARK: - Async API

    func readState() async throws -> OppoNoiseState {
        await acquireOperation()
        defer { releaseOperation() }
        try await ensureConnected()
        try await awaitProfile()
        if let cached = cachedMode() {
            return OppoNoiseState(listeningMode: cached)
        }
        return try await runRead()
    }

    func setMode(_ mode: BluetoothListeningMode) async throws -> OppoNoiseState {
        await acquireOperation()
        defer { releaseOperation() }
        try await ensureConnected()
        try await awaitProfile()
        return try await runSet(mode)
    }

    /// Closes the channel and fails any waiters. Idempotent.
    func close() {
        lock.lock()
        stopped = true
        ready = false
        connecting = false
        let channel = self.channel
        self.channel = nil
        let connectWaiters = self.connectWaiters
        self.connectWaiters.removeAll()
        let pending = pendingContinuation
        pendingContinuation = nil
        pendingKind = nil
        let connectTimeout = self.connectTimeout; self.connectTimeout = nil
        let pendingTimeout = self.pendingTimeout; self.pendingTimeout = nil
        let opWaiters = self.operationWaiters
        self.operationWaiters.removeAll()
        self.operationBusy = false
        lock.unlock()

        connectTimeout?.cancel()
        pendingTimeout?.cancel()
        channel?.close()
        connectWaiters.forEach { $0.resume(throwing: CancellationError()) }
        pending?.resume(throwing: CancellationError())
        opWaiters.forEach { $0.resume() }
    }

    // MARK: - Operation serialisation

    private func acquireOperation() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if operationBusy {
                operationWaiters.append(continuation)
                lock.unlock()
            } else {
                operationBusy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    private func releaseOperation() {
        lock.lock()
        if operationWaiters.isEmpty {
            operationBusy = false
            lock.unlock()
        } else {
            let next = operationWaiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }

    // MARK: - Connection lifecycle

    private func ensureConnected() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if ready {
                lock.unlock()
                continuation.resume()
                return
            }
            if stopped {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            connectWaiters.append(continuation)
            let shouldStart = !connecting
            connecting = true
            lock.unlock()
            if shouldStart {
                Task { await self.performConnect() }
            }
        }
    }

    /// Waits for the profile the cycle answer resolves.
    ///
    /// A device that completes the handshake but never names a cycle it is willing
    /// to switch between cannot be driven safely, so this ends in
    /// `unsupportedModel` rather than guessing at indices — the controller then
    /// draws no capsules at all.
    private func awaitProfile() async throws {
        let deadline = Date().addingTimeInterval(profileTimeoutSeconds)
        while true {
            if stoppedNow() { throw CancellationError() }
            if profileNow() != nil { return }
            guard Date() < deadline else { throw OppoListeningModeError.unsupportedModel }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Synchronous snapshot helpers: `NSLock` may only be taken outside an async
    /// context, which is why the async paths above never touch the lock directly.
    private func profileNow() -> OppoNoiseProfile? {
        lock.lock()
        defer { lock.unlock() }
        return engine.profile
    }

    private func stoppedNow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func performConnect() async {
        do {
            let id = try await resolveChannelID()
            resetProtocolForConnection()
            let status = device.openControlChannel(id: id, delegate: self)
            guard status == kIOReturnSuccess else {
                throw OppoListeningModeError.channelConnectionFailed(status)
            }
            armConnectTimeout()
        } catch {
            finishConnectFailure(error)
        }
    }

    /// Opens the vendor SPP channel.
    ///
    /// SDP is tried first because it is the documented path (`0x1107`), but the
    /// reference implementations disagree on whether the record is always
    /// published — one of them probes channels `12 → 15 → 1…30` because it never
    /// does an SDP query at all. Falling back to the documented fixed channel `15`
    /// keeps a device that hides its record usable; anything else fails closed.
    private func resolveChannelID() async throws -> BluetoothRFCOMMChannelID {
        if let cached = device.cachedControlService(), let id = device.rfcommChannelID(for: cached) {
            return id
        }
        if device.queryForControlService() {
            for _ in 0..<24 {
                if let record = device.cachedControlService(),
                   let id = device.rfcommChannelID(for: record) {
                    return id
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        if stoppedNow() { throw CancellationError() }
        return Self.fallbackChannelID
    }

    /// Clears receive state from a previous connection before a new one opens, so
    /// a reconnect re-handshakes instead of trusting the old session's profile.
    private func resetProtocolForConnection() {
        lock.lock()
        engine = OppoSessionEngine()
        decoder = OppoFrameDecoder()
        writes.removeAll()
        lock.unlock()
    }

    private func cachedMode() -> BluetoothListeningMode? {
        lock.lock()
        defer { lock.unlock() }
        return engine.currentMode
    }

    private func armConnectTimeout() {
        let seconds = connectTimeoutSeconds
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.finishConnectFailure(OppoListeningModeError.handshakeTimeout)
        }
        lock.lock()
        if ready || stopped {
            lock.unlock()
            task.cancel()
        } else {
            connectTimeout?.cancel()
            connectTimeout = task
            lock.unlock()
        }
    }

    private func finishConnectFailure(_ error: any Error) {
        lock.lock()
        ready = false
        connecting = false
        let waiters = connectWaiters
        connectWaiters.removeAll()
        let timeout = connectTimeout
        connectTimeout = nil
        let channel = self.channel
        self.channel = nil
        let pending = pendingContinuation
        pendingContinuation = nil
        pendingKind = nil
        let pendingTimeout = self.pendingTimeout
        self.pendingTimeout = nil
        lock.unlock()
        timeout?.cancel()
        pendingTimeout?.cancel()
        channel?.close()
        waiters.forEach { $0.resume(throwing: error) }
        pending?.resume(throwing: error)
    }

    // MARK: - Read / set

    private func runRead() async throws -> OppoNoiseState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OppoNoiseState, any Error>) in
            lock.lock()
            if stopped || !ready {
                lock.unlock()
                continuation.resume(throwing: OppoListeningModeError.notOpen)
                return
            }
            beginPendingLocked(.read, continuation: continuation)
            if !sendLocked(engine.queryMode()) {
                failPendingLocked(OppoListeningModeError.writeFailed(-1))
                lock.unlock()
                return
            }
            armPendingTimeoutLocked(seconds: readTimeoutSeconds)
            lock.unlock()
        }
    }

    private func runSet(_ mode: BluetoothListeningMode) async throws -> OppoNoiseState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OppoNoiseState, any Error>) in
            lock.lock()
            if stopped || !ready {
                lock.unlock()
                continuation.resume(throwing: OppoListeningModeError.notOpen)
                return
            }
            guard engine.profile?.index(for: mode) != nil, let frame = engine.setMode(mode) else {
                lock.unlock()
                continuation.resume(throwing: OppoListeningModeError.modeUnavailable)
                return
            }
            beginPendingLocked(.set(mode), continuation: continuation)
            if !sendLocked(frame) {
                failPendingLocked(OppoListeningModeError.writeFailed(-1))
                lock.unlock()
                return
            }
            armPendingTimeoutLocked(seconds: setTimeoutSeconds)
            lock.unlock()
        }
    }

    // MARK: - Pending operation helpers (lock held by caller)

    private func beginPendingLocked(
        _ kind: PendingKind,
        continuation: CheckedContinuation<OppoNoiseState, any Error>
    ) {
        pendingToken &+= 1
        pendingKind = kind
        pendingContinuation = continuation
    }

    private func armPendingTimeoutLocked(seconds: TimeInterval) {
        let token = pendingToken
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.timeoutPending(token)
        }
        pendingTimeout?.cancel()
        pendingTimeout = task
    }

    /// Completes the pending operation from the confirmed engine state when its
    /// condition is met. Caller must hold the lock.
    private func evaluatePendingLocked() {
        guard let kind = pendingKind, let continuation = pendingContinuation else { return }
        let observed = engine.currentMode
        let satisfied: Bool
        switch kind {
        case .read:
            satisfied = observed != nil
        case .set(let target):
            satisfied = observed == target
        }
        guard satisfied, let observed else { return }
        pendingContinuation = nil
        pendingKind = nil
        let timeout = pendingTimeout
        pendingTimeout = nil
        lock.unlock()
        timeout?.cancel()
        continuation.resume(returning: OppoNoiseState(listeningMode: observed))
        lock.lock()
    }

    private func failPendingLocked(_ error: any Error) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingKind = nil
        let timeout = pendingTimeout
        pendingTimeout = nil
        lock.unlock()
        timeout?.cancel()
        continuation.resume(throwing: error)
        lock.lock()
    }

    /// Settles on whatever the device last reported.
    ///
    /// A write that never reads back as its target is *not* a failure here: the
    /// caller compares the returned mode with what it asked for, and rolls the UI
    /// back. Only "the device never said anything" is a hard timeout.
    private func timeoutPending(_ token: UInt64) {
        lock.lock()
        guard pendingToken == token, let continuation = pendingContinuation else {
            lock.unlock()
            return
        }
        let mode = engine.currentMode
        pendingContinuation = nil
        pendingKind = nil
        pendingTimeout = nil
        lock.unlock()

        if let mode {
            continuation.resume(returning: OppoNoiseState(listeningMode: mode))
        } else {
            continuation.resume(throwing: OppoListeningModeError.timeout)
        }
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        lock.lock()
        if stopped {
            lock.unlock()
            _ = rfcommChannel.close()
            return
        }
        guard error == kIOReturnSuccess else {
            lock.unlock()
            finishConnectFailure(OppoListeningModeError.channelConnectionFailed(error))
            return
        }
        channel = rfcommChannel
        let sent = sendLocked(engine.handshake())
        lock.unlock()
        if !sent {
            finishConnectFailure(OppoListeningModeError.writeFailed(-1))
        }
    }

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard dataLength > 0, let dataPointer else { return }

        lock.lock()
        guard !stopped else { lock.unlock(); return }
        let input = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self),
            count: dataLength
        ))

        for frame in decoder.append(input) {
            let replies = engine.receive(frame)
            for reply in replies {
                if !sendLocked(reply) {
                    lock.unlock()
                    finishConnectFailure(OppoListeningModeError.writeFailed(-1))
                    return
                }
            }
            if engine.handshaken, !ready {
                ready = true
                connecting = false
                let waiters = connectWaiters
                connectWaiters.removeAll()
                let timeout = connectTimeout
                connectTimeout = nil
                lock.unlock()
                timeout?.cancel()
                waiters.forEach { $0.resume() }
                lock.lock()
            }
            evaluatePendingLocked()
        }
        lock.unlock()
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        lock.lock()
        let wasStopped = stopped
        lock.unlock()
        guard !wasStopped else { return }
        // Putting the buds back in the case disconnects them and arrives here.
        // Mark the session dead; a later request reconnects when they return.
        finishConnectFailure(OppoListeningModeError.connectionClosedByDevice)
    }

    func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        lock.lock()
        if let refcon { writes.removeValue(forKey: refcon) }
        let wasStopped = stopped
        lock.unlock()
        if error != kIOReturnSuccess, !wasStopped {
            finishConnectFailure(OppoListeningModeError.writeFailed(error))
        }
    }

    // MARK: - Writes

    /// Sends one frame. Returns `false` when the channel is unavailable, the MTU
    /// is too small, or the asynchronous write is rejected. Caller holds the lock.
    private func sendLocked(_ frame: OppoFrame) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        let bytes = frame.bytes
        guard bytes.count <= Int(channel.getMTU()) else { return false }
        let data = NSData(bytes: bytes, length: bytes.count)
        let pointer = UnsafeMutableRawPointer(mutating: data.bytes)
        writes[pointer] = data
        let result = channel.writeAsync(pointer, length: UInt16(bytes.count), refcon: pointer)
        if result != kIOReturnSuccess {
            writes.removeValue(forKey: pointer)
            return false
        }
        return true
    }
}

extension OppoControlSession {
    /// The channel the reference implementations open when SDP publishes no
    /// record for the vendor service (`opooctl` probes 12 → 15 → 1…30 and settles
    /// on 15; the specification documents 15 / DLCI 30).
    static let fallbackChannelID: BluetoothRFCOMMChannelID = 15
}
