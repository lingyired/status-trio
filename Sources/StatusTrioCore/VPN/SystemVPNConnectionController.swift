import Foundation
import SystemConfiguration

/// Public SystemConfiguration control path. No helper, private API, or
/// `scutil` subprocess is involved. The connection is confirmed by the
/// framework's status callback, never by the Boolean returned by Start/Stop.
final class SystemVPNConnectionController: VPNConnectionControlling, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.VPNControl")
    private let timeout: DispatchTimeInterval

    init(timeout: DispatchTimeInterval = .seconds(20)) {
        self.timeout = timeout
    }

    func setConnected(_ connected: Bool, serviceID: String) async -> VPNConnectionResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                run(connected: connected, serviceID: serviceID, continuation: continuation)
            }
        }
    }

    private func run(
        connected: Bool,
        serviceID: String,
        continuation: CheckedContinuation<VPNConnectionResult, Never>
    ) {
        let attempt = VPNConnectionAttempt(targetConnected: connected, continuation: continuation, queue: queue)
        let pointer = Unmanaged.passRetained(attempt).toOpaque()
        attempt.retainedPointer = pointer
        var context = SCNetworkConnectionContext(
            version: 0,
            info: pointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let connection = SCNetworkConnectionCreateWithServiceID(
            nil,
            serviceID as CFString,
            vpnConnectionStatusCallback,
            &context
        ) else {
            attempt.abandon()
            return
        }
        attempt.connection = connection
        guard SCNetworkConnectionSetDispatchQueue(connection, queue) else {
            attempt.finish(.rejected)
            return
        }
        attempt.armTimeout(timeout)

        let accepted = connected
            ? SCNetworkConnectionStart(connection, nil, true)
            : SCNetworkConnectionStop(connection, false)
        if !accepted {
            attempt.finish(.rejected)
        }
    }
}

private struct FinishState {
    var shouldFinish = false
    var connection: SCNetworkConnection?
    var timer: DispatchSourceTimer?
    var pointer: UnsafeMutableRawPointer?
}

private final class VPNConnectionAttempt: @unchecked Sendable {
    let targetConnected: Bool
    private let continuation: CheckedContinuation<VPNConnectionResult, Never>
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var finished = false
    private var timer: DispatchSourceTimer?
    var retainedPointer: UnsafeMutableRawPointer?

    init(
        targetConnected: Bool,
        continuation: CheckedContinuation<VPNConnectionResult, Never>,
        queue: DispatchQueue
    ) {
        self.targetConnected = targetConnected
        self.continuation = continuation
        self.queue = queue
    }

    var connection: SCNetworkConnection? {
        get { lock.withLock { _connection } }
        set { lock.withLock { _connection = newValue } }
    }

    private var _connection: SCNetworkConnection?

    func armTimeout(_ interval: DispatchTimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            self?.finish(.timedOut)
        }
        lock.withLock { self.timer = timer }
        timer.resume()
    }

    func handle(_ status: SCNetworkConnectionStatus) {
        switch status {
        case .connected where targetConnected, .disconnected where !targetConnected:
            finish(.confirmed)
        case .invalid:
            finish(.failed)
        default:
            break
        }
    }

    func finish(_ result: VPNConnectionResult) {
        let state = lock.withLock { () -> FinishState in
            guard !finished else { return FinishState() }
            finished = true
            let owned = FinishState(
                shouldFinish: true,
                connection: _connection,
                timer: timer,
                pointer: retainedPointer
            )
            _connection = nil
            self.timer = nil
            retainedPointer = nil
            return owned
        }
        guard state.shouldFinish else { return }
        state.timer?.setEventHandler {}
        state.timer?.cancel()
        if let connection = state.connection {
            SCNetworkConnectionSetDispatchQueue(connection, nil)
        }
        continuation.resume(returning: result)
        let pointer = state.pointer
        // `pointer` owns the only strong reference that lets late callbacks
        // reach this object. Release it once, after the continuation resumes.
        if let pointer {
            Unmanaged<VPNConnectionAttempt>.fromOpaque(pointer).release()
        }
    }

    func abandon() {
        finish(.rejected)
    }
}

private func vpnConnectionStatusCallback(
    _ connection: SCNetworkConnection,
    _ status: SCNetworkConnectionStatus,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let attempt = Unmanaged<VPNConnectionAttempt>.fromOpaque(info).takeUnretainedValue()
    attempt.handle(status)
}
