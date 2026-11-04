import Foundation
import PowerHelperProtocol

/// The app's view of the legacy charge-limit helper operations. Injected so the
/// controller can be exercised without a registered daemon or real hardware.
protocol LegacyChargeLimitClienting: Sendable {
    func probe() async throws -> LegacyChargeLimitProbeFacts
    func setLimit(_ limit: Int, expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome
    func chargeToFullOnce() async throws -> LegacyChargeLimitWriteOutcome
    func cancelChargeToFull() async throws -> LegacyChargeLimitWriteOutcome
    func disable(expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome
    func verify(_ limit: Int) async throws -> LegacyChargeLimitWriteOutcome
    /// Inhibits charging immediately before system sleep (Silicon only; Intel
    /// firmware manages its own cutoff).
    func prepareForSleep() async throws -> LegacyChargeLimitWriteOutcome
    /// Drops the persistent helper connection. The daemon is allowed to
    /// idle-exit afterwards, so this must only run once no limit is held.
    func releaseConnection()
}

extension LegacyChargeLimitClienting {
    func releaseConnection() {}
}

struct LegacyChargeLimitWriteOutcome: Equatable, Sendable {
    var succeeded: Bool
    var verified: Bool
    var observedLimit: Int?
    var error: LegacyChargeLimitError?

    static let success = LegacyChargeLimitWriteOutcome(
        succeeded: true, verified: true, observedLimit: nil, error: nil
    )
}

enum LegacyChargeLimitClientError: Error, Equatable {
    case helperUnavailable
    case timedOut
    case rejected(String)
}

/// Persistent, authenticated XPC client.
///
/// The plan requires one connection to stay open while a legacy limit is held,
/// so the helper does not idle-exit underneath an active session. The
/// connection is created lazily, recreated after invalidation, and released
/// explicitly once no limit is held.
///
/// Runtime handshakes remain NOT RUN in this session; this type is exercised
/// only structurally, the controller is tested against a fake.
final class XPCPrivilegedLegacyChargeClient: LegacyChargeLimitClienting, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let requestTimeout: Duration

    init(requestTimeout: Duration = .seconds(5)) {
        self.requestTimeout = requestTimeout
    }

    deinit {
        connection?.invalidate()
    }

    func releaseConnection() {
        lock.lock()
        let current = connection
        connection = nil
        lock.unlock()
        current?.invalidate()
    }

    // MARK: Commands

    func probe() async throws -> LegacyChargeLimitProbeFacts {
        try await perform { proxy, finish in
            proxy.probeLegacyChargeLimit { reply, error in
                guard let reply else {
                    finish(.failure(LegacyChargeLimitClientError.rejected(error ?? "probe failed")))
                    return
                }
                finish(.success(LegacyChargeLimitProbeFacts(
                    hasInternalBattery: reply.hasInternalBattery,
                    intelBCLMPresent: reply.intelBCLMPresent,
                    siliconPairPresent: reply.siliconPairPresent,
                    siliconCHTEPresent: reply.siliconCHTEPresent
                )))
            }
        }
    }

    func setLimit(_ limit: Int, expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in
            proxy.setLegacyChargeLimit(
                limit,
                expectedLimit: expectedLimit.map { NSNumber(value: $0) },
                withReply: reply
            )
        }
    }

    func chargeToFullOnce() async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in proxy.legacyChargeToFullOnce(withReply: reply) }
    }

    func cancelChargeToFull() async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in proxy.cancelLegacyChargeToFull(withReply: reply) }
    }

    func disable(expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in
            proxy.disableLegacyChargeLimit(
                expectedLimit: expectedLimit.map { NSNumber(value: $0) },
                withReply: reply
            )
        }
    }

    func verify(_ limit: Int) async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in proxy.verifyLegacyChargeLimit(limit, withReply: reply) }
    }

    /// Inhibits charging immediately before system sleep (Silicon only; Intel
    /// firmware manages its own cutoff).
    func prepareForSleep() async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in proxy.prepareLegacyChargeLimitForSleep(withReply: reply) }
    }

    // MARK: Plumbing

    private func write(
        _ body: @escaping @Sendable (any LegacyChargeLimitXPCProtocol, @escaping @Sendable (SMLegacyChargeLimitWriteReply?) -> Void) -> Void
    ) async throws -> LegacyChargeLimitWriteOutcome {
        try await perform { proxy, finish in
            body(proxy) { reply in
                guard let reply else {
                    finish(.failure(LegacyChargeLimitClientError.rejected("empty reply")))
                    return
                }
                finish(.success(Self.outcome(from: reply)))
            }
        }
    }

    private static func outcome(from reply: SMLegacyChargeLimitWriteReply) -> LegacyChargeLimitWriteOutcome {
        LegacyChargeLimitWriteOutcome(
            succeeded: reply.succeeded,
            verified: reply.verified,
            observedLimit: reply.observedLimit?.intValue,
            error: mapError(reply.errorCode)
        )
    }

    private static func mapError(_ code: SMLegacyChargeLimitErrorCode) -> LegacyChargeLimitError? {
        switch code {
        case .none: return nil
        case .unsupportedHardware: return .unsupportedHardware
        case .helperUnavailable: return .helperUnavailable
        case .limitOutOfRange: return .limitOutOfRange(0)
        case .ownershipConflict: return .ownershipConflict
        case .verificationFailed: return .verificationFailed
        case .restoreFailed: return .restoreFailed
        case .cancelled: return .cancelled
        case .writeDenied: return .writeDenied
        case .readbackMismatch: return .readbackMismatch
        case .validationNotRun, .rejected, .unknown: return .unknown
        }
    }

    private func currentConnection() -> NSXPCConnection? {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let new = NSXPCConnection(
            machServiceName: PowerHelperConstants.machServiceName,
            options: .privileged
        )
        new.remoteObjectInterface = NSXPCInterface(with: PowerHelperCombinedXPCProtocol.self)
        new.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.connection === new { self.connection = nil }
            self.lock.unlock()
        }
        new.resume()
        connection = new
        return new
    }

    private func perform<T: Sendable>(
        _ body: @escaping @Sendable (any LegacyChargeLimitXPCProtocol, @escaping @Sendable (Result<T, any Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = currentConnection()
        guard let connection else {
            throw LegacyChargeLimitClientError.helperUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
            let timer = TimeoutGuard {
                once.run { continuation.resume(throwing: LegacyChargeLimitClientError.timedOut) }
            }
            timer.start(after: requestTimeout.timeInterval)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                timer.cancel()
                once.run {
                    continuation.resume(throwing: LegacyChargeLimitClientError.rejected(
                        error.localizedDescription
                    ))
                }
            }) as? any LegacyChargeLimitXPCProtocol else {
                timer.cancel()
                once.run { continuation.resume(throwing: LegacyChargeLimitClientError.helperUnavailable) }
                return
            }
            body(proxy) { result in
                timer.cancel()
                once.run { continuation.resume(with: result) }
            }
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// Resumes a continuation at most once, even if XPC delivers an error handler,
/// a reply, and the timeout for the same call.
/// Owns the timeout work item so `@Sendable` XPC closures never capture a
/// non-Sendable `DispatchWorkItem`.
private final class TimeoutGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var item: DispatchWorkItem?

    init(_ body: @escaping @Sendable () -> Void) {
        item = DispatchWorkItem(block: body)
    }

    func start(after seconds: TimeInterval) {
        lock.lock()
        let work = item
        lock.unlock()
        guard let work else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func cancel() {
        lock.lock()
        item?.cancel()
        item = nil
        lock.unlock()
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}