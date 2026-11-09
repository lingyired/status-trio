import Foundation
import IOBluetooth

/// Owns one Redmi control-channel lifecycle and coerces the device's
/// event-driven RFCOMM callbacks into the single `async` value the transport
/// exposes.
///
/// Concurrency model: a session is created per transport operation and is never
/// shared between operations. `IOBluetooth` may deliver callbacks on arbitrary
/// threads, so all mutable receive state is guarded by `lock`. Every delegate
/// path follows one discipline: mutate under the lock, decide whether to finish,
/// then unlock and resume the outstanding continuation exactly once, outside the
/// lock. No helper unlocks and re-locks.
final class RedmiControlSession: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private let device: any RedmiBluetoothDevice
    private let address: String
    private let lock = NSLock()

    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = RedmiBudsFrameDecoder()
    private var engine = RedmiBudsProtocol()
    private var writes: [UnsafeMutableRawPointer: NSData] = [:]
    private var stopped = false
    private var finished = false

    /// How the current operation should complete.
    private enum Operation {
        case read
        case set(RedmiNoiseMode)
    }

    private var operation: Operation?
    private var completion: CheckedContinuation<RedmiNoiseState, any Error>?
    /// Set once auth finished and the operation has issued its read/write, so the
    /// target frames are sent exactly once.
    private var issuedTarget = false

    init(device: any RedmiBluetoothDevice, address: String) {
        self.device = device
        self.address = address
        super.init()
    }

    // MARK: - Async API

    func readState() async throws -> RedmiNoiseState {
        try await runOperation(.read)
    }

    func setMode(_ mode: RedmiNoiseMode) async throws -> RedmiNoiseState {
        try await runOperation(.set(mode))
    }

    func cancel() {
        lock.lock()
        stopped = true
        let completion = self.completion
        self.completion = nil
        let channel = self.channel
        lock.unlock()
        channel?.close()
        completion?.resume(throwing: CancellationError())
    }

    func close() {
        lock.lock()
        stopped = true
        let channel = self.channel
        self.channel = nil
        lock.unlock()
        channel?.close()
    }

    // MARK: - Operation driver

    private func runOperation(_ operation: Operation) async throws -> RedmiNoiseState {
        // SDP lookup may await without holding the channel lock. The channel open
        // and the protocol exchange are then driven entirely by delegate callbacks.
        let record: IOBluetoothSDPServiceRecord
        if let cached = device.cachedControlService() {
            record = cached
        } else {
            record = try await queryForControlService()
        }
        guard let id = device.rfcommChannelID(for: record) else {
            throw RedmiListeningModeError.noRFCOMMChannel
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RedmiNoiseState, Error>) in
            lock.lock()
            self.operation = operation
            self.completion = continuation
            self.engine = RedmiBudsProtocol()
            self.decoder = RedmiBudsFrameDecoder()
            self.stopped = false
            self.finished = false
            self.issuedTarget = false
            lock.unlock()

            let status = device.openControlChannel(id: id, delegate: self)
            if status != kIOReturnSuccess {
                finish(.failure(RedmiListeningModeError.channelConnectionFailed(status)))
            }
        }
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        lock.lock()
        guard !stopped, !finished else { lock.unlock(); _ = rfcommChannel.close(); return }
        guard error == kIOReturnSuccess else {
            lock.unlock()
            finish(.failure(RedmiListeningModeError.channelConnectionFailed(error)))
            return
        }
        channel = rfcommChannel
        let started = sendLocked(engine.begin())
        lock.unlock()
        if !started {
            finish(.failure(RedmiListeningModeError.writeFailed(-1)))
        }
    }

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard dataLength > 0, let dataPointer else { return }

        var outcome: Result<RedmiNoiseState, any Error>?

        lock.lock()
        if stopped || finished { lock.unlock(); return }
        let input = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self),
            count: dataLength
        ))

        loop: for frame in decoder.append(input) {
            // A rejected handshake fails the operation immediately.
            if !engine.authenticated,
               [UInt8(0x50), 0x51].contains(frame.opcode),
               frame.type == 0x04, frame.status != 0 {
                outcome = .failure(RedmiListeningModeError.authenticationRejected(frame.status))
                break loop
            }

            let replies = engine.receive(frame)
            for reply in replies {
                if !sendLocked(reply) {
                    outcome = .failure(RedmiListeningModeError.writeFailed(-1))
                    break loop
                }
            }

            // Once authentication completes, issue the operation's target frames
            // exactly once: a mode write (for `set`) and a mode read-back.
            if engine.authenticated, !issuedTarget {
                issuedTarget = true
                if case .set(let mode) = operation {
                    if !sendLocked(engine.setMode(mode)) {
                        outcome = .failure(RedmiListeningModeError.writeFailed(-1))
                        break loop
                    }
                }
                if !sendLocked(engine.readMode()) {
                    outcome = .failure(RedmiListeningModeError.writeFailed(-1))
                    break loop
                }
            }

            // Complete from the latest confirmed state.
            switch operation {
            case .set(let desired):
                if engine.state.mode == desired {
                    outcome = .success(RedmiNoiseState(mode: desired))
                    break loop
                }
            case .read:
                if let mode = engine.state.mode {
                    outcome = .success(RedmiNoiseState(mode: mode))
                    break loop
                }
            case nil:
                break
            }
        }
        lock.unlock()

        if let outcome { finish(outcome) }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        lock.lock()
        let stop = stopped || finished
        lock.unlock()
        if stop { return }
        finish(.failure(RedmiListeningModeError.connectionClosedByDevice))
    }

    // MARK: - Finishing (resumes exactly once)

    /// Resumes the outstanding continuation with `outcome` if this session has not
    /// already finished. Safe to call from any thread.
    private func finish(_ outcome: Result<RedmiNoiseState, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        stopped = true
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        guard let completion else { return }
        switch outcome {
        case .success(let state): completion.resume(returning: state)
        case .failure(let error): completion.resume(throwing: error)
        }
    }

    // MARK: - SDP + writes

    private func queryForControlService() async throws -> IOBluetoothSDPServiceRecord {
        guard device.queryForControlService() else {
            throw RedmiListeningModeError.serviceQueryFailed
        }
        // `performSDPQuery` resolves the record asynchronously; re-poll the system
        // cache over a bounded window. This matches the HUAWEI transport's fixed
        // settle before opening the channel.
        for _ in 0..<24 {
            if let record = device.cachedControlService() { return record }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RedmiListeningModeError.controlServiceNotFound
    }

    /// Sends one frame. Returns `false` if the channel is unavailable, the MTU is
    /// too small, or the synchronous write reports an error. Callers translate a
    /// `false` into a failure outcome.
    private func sendLocked(_ frame: RedmiBudsFrame) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        let bytes = frame.bytes
        guard bytes.count <= Int(channel.getMTU()) else { return false }
        let data = NSData(bytes: bytes, length: bytes.count)
        let pointer = UnsafeMutableRawPointer(mutating: data.bytes)
        writes[pointer] = data
        let result = channel.writeSync(pointer, length: UInt16(bytes.count))
        if result != kIOReturnSuccess {
            writes.removeValue(forKey: pointer)
            return false
        }
        return true
    }
}