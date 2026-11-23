import Foundation
import PowerHelperProtocol

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
final class OneShotReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Value, any Error>
    private let connection: NSXPCConnection

    init(
        continuation: CheckedContinuation<Value, any Error>,
        connection: NSXPCConnection,
        timeout: TimeInterval,
        queue: DispatchQueue,
        timeoutError: any Error = LowPowerModeClientError.helperUnavailable
    ) {
        self.continuation = continuation
        self.connection = connection
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            resolve(.failure(timeoutError))
        }
    }

    func resolve(_ result: Result<Value, any Error>) {
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

/// Talks to the registered LaunchDaemon over XPC.
///
/// `.privileged` is required because the daemon lives in the system bootstrap.
/// The daemon enforces the app's code-signing requirement on its side; the app
/// reports a connection failure as `helperUnavailable` rather than guessing why.
final class XPCPrivilegedHighPowerClient: HighPowerModeClienting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.PowerHelper.HighPower.XPC")
    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 3) {
        self.requestTimeout = requestTimeout
    }

    func protocolVersion() async throws -> Int {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.readProtocolVersion { version, error in
                finish(Self.result(version, error: error))
            }
        }
    }

    func highPowerModeSupported() async throws -> Bool {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.readHighPowerModeSupport { supported, error in
                finish(Self.result(supported, error: error))
            }
        }
    }

    func readHighPowerMode() async throws -> Bool {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.readHighPowerMode { enabled, error in
                finish(Self.result(enabled, error: error))
            }
        }
    }

    func setHighPowerMode(_ enabled: Bool) async throws -> Bool {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.setHighPowerMode(enabled) { observed, error in
                finish(Self.result(observed, error: error))
            }
        }
    }

    func canReadLowPowerMode() async -> Bool {
        do {
            _ = try await request(
                timeoutError: HighPowerModeClientError.helperUnavailable
            ) { proxy, finish -> Void in
                proxy.readLowPowerMode { enabled, error in
                    finish(Self.result(enabled, error: error))
                }
            }
            return true
        } catch {
            return false
        }
    }

    private static func result<Value: Sendable>(
        _ value: Value,
        error: String?
    ) -> Result<Value, any Error> {
        if let error {
            return .failure(HighPowerModeClientError.rejected(error))
        }
        return .success(value)
    }

    private func request<Value: Sendable>(
        timeoutError: any Error,
        _ body: @escaping (
            any PowerHelperXPCProtocol,
            @escaping (Result<Value, any Error>) -> Void
        ) -> Void
    ) async throws -> Value {
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
                    queue: self.queue,
                    timeoutError: timeoutError
                )
                connection.interruptionHandler = {
                    finish.resolve(.failure(HighPowerModeClientError.helperUnavailable))
                }
                connection.invalidationHandler = {
                    finish.resolve(.failure(HighPowerModeClientError.helperUnavailable))
                }
                connection.resume()

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    finish.resolve(.failure(error))
                }) as? any PowerHelperXPCProtocol else {
                    finish.resolve(.failure(HighPowerModeClientError.helperUnavailable))
                    return
                }
                body(proxy, finish.resolve)
            }
        }
    }
}


extension XPCPrivilegedHighPowerClient: DisableSleepClienting {
    func readDisableSleep() async throws -> Bool {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.readDisableSleep { enabled, error in
                finish(Self.result(enabled, error: error))
            }
        }
    }

    func setDisableSleep(_ enabled: Bool) async throws -> Bool {
        try await request(
            timeoutError: HighPowerModeClientError.helperUnavailable
        ) { proxy, finish in
            proxy.setDisableSleep(enabled) { observed, error in
                finish(Self.result(observed, error: error))
            }
        }
    }
}
