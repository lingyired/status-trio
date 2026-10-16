import Foundation
import PowerHelperProtocol

/// The app's view of the privileged power helper. Injected so the controller
/// can be exercised without a registered daemon.
protocol LowPowerModeClienting: Sendable {
    /// Reads Low Power Mode through the helper.
    func readLowPowerMode() async throws -> Bool
    /// Sets Low Power Mode and returns the state the daemon observed after.
    func setLowPowerMode(_ enabled: Bool) async throws -> Bool
}

enum LowPowerModeClientError: LocalizedError {
    case helperUnavailable
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable: "The power helper is not available."
        case let .rejected(reason): reason
        }
    }
}

/// Talks to the registered LaunchDaemon over XPC.
///
/// `.privileged` is required because the daemon lives in the system bootstrap.
/// The daemon enforces the app's code-signing requirement on its side; the app
/// simply reports a connection failure as `helperUnavailable` rather than
/// guessing why.
final class XPCPrivilegedHelperClient: LowPowerModeClienting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.PowerHelper.XPC")
    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 3) {
        self.requestTimeout = requestTimeout
    }

    func readLowPowerMode() async throws -> Bool {
        try await withProxy { proxy, finish in
            proxy.readLowPowerMode { enabled, error in
                finish(Self.result(enabled: enabled, error: error))
            }
        }
    }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        try await withProxy { proxy, finish in
            proxy.setLowPowerMode(enabled) { observed, error in
                finish(Self.result(enabled: observed, error: error))
            }
        }
    }

    private static func result(enabled: Bool, error: String?) -> Result<Bool, any Error> {
        if let error {
            return .failure(LowPowerModeClientError.rejected(error))
        }
        return .success(enabled)
    }

    private func withProxy(
        _ body: @escaping (any PowerHelperXPCProtocol, @escaping (Result<Bool, any Error>) -> Void) -> Void
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let connection = NSXPCConnection(
                    machServiceName: PowerHelperConstants.machServiceName,
                    options: .privileged
                )
                connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPCProtocol.self)

                // A reply, an interruption, and an invalidation can race; the
                // first one to arrive wins and the connection is torn down once.
                let finish = OneShotReply(
                    continuation: continuation,
                    connection: connection,
                    timeout: self.requestTimeout,
                    queue: self.queue
                )
                connection.interruptionHandler = {
                    finish.resolve(.failure(LowPowerModeClientError.helperUnavailable))
                }
                connection.invalidationHandler = {
                    finish.resolve(.failure(LowPowerModeClientError.helperUnavailable))
                }
                connection.resume()

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    finish.resolve(.failure(error))
                }) as? any PowerHelperXPCProtocol else {
                    finish.resolve(.failure(LowPowerModeClientError.helperUnavailable))
                    return
                }
                body(proxy, finish.resolve)
            }
        }
    }
}

/// Resumes the XPC continuation exactly once, then invalidates the connection.
final class OneShotReply: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Bool, any Error>
    private let connection: NSXPCConnection

    init(
        continuation: CheckedContinuation<Bool, any Error>,
        connection: NSXPCConnection,
        timeout: TimeInterval,
        queue: DispatchQueue
    ) {
        self.continuation = continuation
        self.connection = connection
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            resolve(.failure(LowPowerModeClientError.helperUnavailable))
        }
    }

    func resolve(_ result: Result<Bool, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        connection.invalidate()
        continuation.resume(with: result)
    }
}
