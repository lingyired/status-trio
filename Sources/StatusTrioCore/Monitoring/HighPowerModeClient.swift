import Foundation
import PowerHelperProtocol

/// The app's view of the helper's High Power Mode surface. Injected so the
/// controller can be exercised without a registered daemon.
protocol HighPowerModeClienting: Sendable {
    /// The XPC protocol version the running daemon reports.
    func protocolVersion() async throws -> Int
    /// Whether this Mac reports High Power Mode support (`pmset -g cap`).
    func highPowerModeSupported() async throws -> Bool
    /// The current High Power Mode state.
    func readHighPowerMode() async throws -> Bool
    /// Sets High Power Mode and returns the state the daemon observed after.
    func setHighPowerMode(_ enabled: Bool) async throws -> Bool
    /// Whether the daemon still answers the original Low Power Mode read.
    ///
    /// A missing answer is the one signal that separates "this helper predates
    /// the version handshake" (it still reads Low Power Mode but cannot name a
    /// version) from "there is no helper at all".
    func canReadLowPowerMode() async -> Bool
}

enum HighPowerModeClientError: LocalizedError {
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

/// The app's view of the helper's `disablesleep` surface (#295). Reuses the same
/// XPC connection plumbing as the power-mode client; the daemon must be protocol
/// version `PowerHelperProtocolVersion.disableSleep` or newer.
protocol DisableSleepClienting: Sendable {
    /// The XPC protocol version the running daemon reports.
    func protocolVersion() async throws -> Int
    /// Whether `pmset -a disablesleep 1` is currently in effect.
    func readDisableSleep() async throws -> Bool
    /// Sets `disablesleep` and returns the state the daemon observed afterwards.
    func setDisableSleep(_ enabled: Bool) async throws -> Bool
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
