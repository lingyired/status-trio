import Foundation
import IOBluetooth

/// One long-lived Redmi control channel, owned by the transport for the lifetime
/// of the listening-mode surface.
///
/// This mirrors the reference `BudsConnection`: the RFCOMM channel is opened
/// once, the `0x50`/`0x51` challenge handshake is completed once, and the session
/// then stays connected — receiving state notifications and replying ACK — until
/// the surface goes away. Read and write requests reuse the live channel instead
/// of opening and closing a fresh one per operation, which is what let a phone
/// that connects to the earbuds steal the single control slot between our reads.
/// If the connection drops, the next request reconnects.
///
/// Concurrency: `IOBluetooth` delivers callbacks on arbitrary threads, so all
/// receive state is guarded by `lock`. Locked critical sections never span an
/// `await`; delegate paths mutate under the lock, unlock, then resume
/// continuations exactly once.
final class RedmiControlSession: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    let address: String
    private let device: any RedmiBluetoothDevice
    private let lock = NSLock()

    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = RedmiBudsFrameDecoder()
    private var engine = RedmiBudsProtocol()
    private var writes: [UnsafeMutableRawPointer: NSData] = [:]
    private var stopped = false
    private var ready = false
    private var connecting = false

    // Connection setup waiters, resumed together once authenticated or on failure.
    private var connectWaiters: [CheckedContinuation<Void, any Error>] = []
    private var connectTimeout: Task<Void, Never>?

    // The one in-flight operation (the controller serialises reads/writes per
    // device, and `acquireOperation` orders them here regardless).
    private enum PendingKind {
        case read
        case set(RedmiNoiseMode)
    }
    private var pendingKind: PendingKind?
    private var pendingContinuation: CheckedContinuation<RedmiNoiseState, any Error>?
    private var pendingToken: UInt64 = 0
    private var pendingTimeout: Task<Void, Never>?

    // Serialises operations without blocking a thread.
    private var operationBusy = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    private let readTimeoutSeconds: TimeInterval
    private let setTimeoutSeconds: TimeInterval
    private let connectTimeoutSeconds: TimeInterval

    init(
        device: any RedmiBluetoothDevice,
        address: String,
        readTimeoutSeconds: TimeInterval = 2.0,
        setTimeoutSeconds: TimeInterval = 5.0,
        connectTimeoutSeconds: TimeInterval = 15.0
    ) {
        self.device = device
        self.address = address
        self.readTimeoutSeconds = readTimeoutSeconds
        self.setTimeoutSeconds = setTimeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        super.init()
    }

    // MARK: - Async API

    func readState() async throws -> RedmiNoiseState {
        await acquireOperation()
        defer { releaseOperation() }
        try await ensureConnected()
        // Notifications keep the cached state live while the session is held, so a
        // refresh is free once we have a mode. Only a fresh session needs a read.
        if let cached = cachedMode() {
            return RedmiNoiseState(mode: cached)
        }
        return try await runRead()
    }

    func setMode(_ mode: RedmiNoiseMode) async throws -> RedmiNoiseState {
        await acquireOperation()
        defer { releaseOperation() }
        try await ensureConnected()
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

    private func performConnect() async {
        do {
            let record = try await resolveRecord()
            let id = try openChannelID(for: record)
            resetProtocolForConnection()
            let status = device.openControlChannel(id: id, delegate: self)
            guard status == kIOReturnSuccess else {
                throw RedmiListeningModeError.channelConnectionFailed(status)
            }
            armConnectTimeout()
        } catch {
            finishConnectFailure(error)
        }
    }

    /// Clears any receive state from a previous connection before a new one is
    /// opened, so a reconnect authenticates from scratch instead of trusting the
    /// old session's `authenticated` flag and stale mode.
    private func resetProtocolForConnection() {
        lock.lock()
        engine = RedmiBudsProtocol()
        decoder = RedmiBudsFrameDecoder()
        writes.removeAll()
        lock.unlock()
    }

    private func cachedMode() -> RedmiNoiseMode? {
        lock.lock()
        defer { lock.unlock() }
        return engine.state.mode
    }

    /// Synchronous critical section: validates we are still allowed to open and
    /// resolves the RFCOMM channel id. Kept out of the async function so `NSLock`
    /// is only ever taken in synchronous code.
    private func openChannelID(for record: IOBluetoothSDPServiceRecord) throws -> BluetoothRFCOMMChannelID {
        lock.lock()
        defer { lock.unlock() }
        if stopped { throw CancellationError() }
        guard let id = device.rfcommChannelID(for: record) else {
            throw RedmiListeningModeError.noRFCOMMChannel
        }
        return id
    }

    private func armConnectTimeout() {
        let seconds = connectTimeoutSeconds
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.finishConnectFailure(RedmiListeningModeError.authenticationTimeout)
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

    private func runRead() async throws -> RedmiNoiseState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RedmiNoiseState, any Error>) in
            lock.lock()
            if stopped || !ready {
                lock.unlock()
                continuation.resume(throwing: RedmiListeningModeError.notOpen)
                return
            }
            beginPendingLocked(.read, continuation: continuation)
            if !sendLocked(engine.readMode()) {
                failPendingLocked(RedmiListeningModeError.writeFailed(-1))
                lock.unlock()
                return
            }
            armPendingTimeoutLocked(seconds: readTimeoutSeconds)
            lock.unlock()
        }
    }

    private func runSet(_ mode: RedmiNoiseMode) async throws -> RedmiNoiseState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RedmiNoiseState, any Error>) in
            lock.lock()
            if stopped || !ready {
                lock.unlock()
                continuation.resume(throwing: RedmiListeningModeError.notOpen)
                return
            }
            beginPendingLocked(.set(mode), continuation: continuation)
            if !sendLocked(engine.setMode(mode)) {
                failPendingLocked(RedmiListeningModeError.writeFailed(-1))
                lock.unlock()
                return
            }
            // Ask for a read-back shortly after the write so a device that only
            // answers explicit reads still confirms the change.
            let token = pendingToken
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self else { return }
                self.sendReadBackIfStillPending(token)
            }
            armPendingTimeoutLocked(seconds: setTimeoutSeconds)
            lock.unlock()
        }
    }

    private func sendReadBackIfStillPending(_ token: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard pendingToken == token, pendingContinuation != nil, ready, !stopped else { return }
        _ = sendLocked(engine.readMode())
    }

    // MARK: - Pending operation helpers (lock held by caller)

    private func beginPendingLocked(
        _ kind: PendingKind,
        continuation: CheckedContinuation<RedmiNoiseState, any Error>
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

    /// Completes the pending operation from the current confirmed engine state if
    /// its completion condition is met. Caller must hold the lock.
    private func evaluatePendingLocked() {
        guard let kind = pendingKind, let continuation = pendingContinuation else { return }
        let satisfied: Bool
        switch kind {
        case .read:
            satisfied = engine.state.mode != nil
        case .set(let target):
            satisfied = engine.state.mode == target
        }
        guard satisfied, let mode = engine.state.mode else { return }
        pendingContinuation = nil
        pendingKind = nil
        let timeout = pendingTimeout
        pendingTimeout = nil
        lock.unlock()
        timeout?.cancel()
        continuation.resume(returning: RedmiNoiseState(mode: mode))
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

    private func timeoutPending(_ token: UInt64) {
        lock.lock()
        guard pendingToken == token, let continuation = pendingContinuation, let kind = pendingKind else {
            lock.unlock()
            return
        }
        let mode = engine.state.mode
        pendingContinuation = nil
        pendingKind = nil
        pendingTimeout = nil
        lock.unlock()

        switch kind {
        case .read:
            if let mode {
                continuation.resume(returning: RedmiNoiseState(mode: mode))
            } else {
                continuation.resume(throwing: RedmiListeningModeError.timeout)
            }
        case .set:
            // Return whatever the device last reported; the controller treats a
            // mismatch with the requested mode as an unconfirmed write and rolls
            // the UI back. No report at all is a hard timeout.
            if let mode {
                continuation.resume(returning: RedmiNoiseState(mode: mode))
            } else {
                continuation.resume(throwing: RedmiListeningModeError.timeout)
            }
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
            finishConnectFailure(RedmiListeningModeError.channelConnectionFailed(error))
            return
        }
        channel = rfcommChannel
        let sent = sendLocked(engine.begin())
        lock.unlock()
        if !sent {
            finishConnectFailure(RedmiListeningModeError.writeFailed(-1))
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
            if !engine.authenticated,
               [UInt8(0x50), 0x51].contains(frame.opcode),
               frame.type == 0x04, frame.status != 0 {
                lock.unlock()
                finishConnectFailure(RedmiListeningModeError.authenticationRejected(frame.status))
                return
            }
            let replies = engine.receive(frame)
            for reply in replies {
                if !sendLocked(reply) {
                    // A write failure means the link is unusable; reconnect on
                    // the next request rather than half-surviving.
                    lock.unlock()
                    finishConnectFailure(RedmiListeningModeError.writeFailed(-1))
                    return
                }
            }
            if engine.authenticated, !ready {
                // Inline (lock held): NSLock is not reentrant, so we cannot call
                // the locking `becomeReady()` here. Resume waiters outside the lock.
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
        // Putting the buds back in the case (lid closed) disconnects them, which
        // arrives here. Mark the session dead and release its channel; a later
        // request reconnects when the buds come back.
        finishConnectFailure(RedmiListeningModeError.connectionClosedByDevice)
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
            finishConnectFailure(RedmiListeningModeError.writeFailed(error))
        }
    }

    // MARK: - SDP + writes

    private func resolveRecord() async throws -> IOBluetoothSDPServiceRecord {
        if let cached = device.cachedControlService() { return cached }
        guard device.queryForControlService() else {
            throw RedmiListeningModeError.serviceQueryFailed
        }
        for _ in 0..<24 {
            if let record = device.cachedControlService() { return record }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RedmiListeningModeError.controlServiceNotFound
    }

    /// Sends one frame. Returns `false` if the channel is unavailable, the MTU is
    /// too small, or the synchronous write reports an error. Caller holds the lock;
    /// on `false` the caller fails the pending operation/connection.
    private func sendLocked(_ frame: RedmiBudsFrame) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        let bytes = frame.bytes
        guard bytes.count <= Int(channel.getMTU()) else { return false }
        let data = NSData(bytes: bytes, length: bytes.count)
        let pointer = UnsafeMutableRawPointer(mutating: data.bytes)
        writes[pointer] = data
        // Async write like the reference implementation: never block the caller
        // (which may be the main thread or a callback thread) on RFCOMM I/O.
        let result = channel.writeAsync(pointer, length: UInt16(bytes.count), refcon: pointer)
        if result != kIOReturnSuccess {
            writes.removeValue(forKey: pointer)
            return false
        }
        return true
    }
}
