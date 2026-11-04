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
    case rejected(String)
}

/// Talks to the registered LaunchDaemon over the combined XPC surface.
///
/// Runtime behaviour (a real daemon handshake) is NOT RUN in this session; the
/// type exists so the app has a real adapter and the controller can be tested
/// against a fake.
final class XPCPrivilegedLegacyChargeClient: LegacyChargeLimitClienting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.PowerHelper.LegacyCharge")
    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 5) {
        self.requestTimeout = requestTimeout
    }

    func probe() async throws -> LegacyChargeLimitProbeFacts {
        try await withProxy { proxy, finish in
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
        try await write { proxy, reply in
            proxy.legacyChargeToFullOnce(withReply: reply)
        }
    }

    func cancelChargeToFull() async throws -> LegacyChargeLimitWriteOutcome {
        try await write { proxy, reply in
            proxy.cancelLegacyChargeToFull(withReply: reply)
        }
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
        try await write { proxy, reply in
            proxy.verifyLegacyChargeLimit(limit, withReply: reply)
        }
    }

    // MARK: - Plumbing

    private func write(
        _ body: @escaping @Sendable (any LegacyChargeLimitXPCProtocol, @escaping @Sendable (SMLegacyChargeLimitWriteReply?) -> Void) -> Void
    ) async throws -> LegacyChargeLimitWriteOutcome {
        try await withProxy { proxy, finish in
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

    private func withProxy<T: Sendable>(
        _ body: @escaping @Sendable (any LegacyChargeLimitXPCProtocol, @escaping @Sendable (Result<T, any Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let connection = NSXPCConnection(
                    machServiceName: PowerHelperConstants.machServiceName,
                    options: .privileged
                )
                connection.remoteObjectInterface = NSXPCInterface(
                    with: PowerHelperCombinedXPCProtocol.self
                )
                connection.resume()
                defer { connection.invalidate() }
                let errorOnce = ResumeOnce()
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    errorOnce.run {
                        continuation.resume(throwing: LegacyChargeLimitClientError.rejected(
                            error.localizedDescription
                        ))
                    }
                }) as? any LegacyChargeLimitXPCProtocol else {
                    continuation.resume(throwing: LegacyChargeLimitClientError.helperUnavailable)
                    return
                }
                let once = ResumeOnce()
                body(proxy) { result in
                    once.run { continuation.resume(with: result) }
                }
            }
        }
    }
}
/// Resumes a continuation at most once, even if XPC delivers an error handler
/// and a reply for the same call.
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
