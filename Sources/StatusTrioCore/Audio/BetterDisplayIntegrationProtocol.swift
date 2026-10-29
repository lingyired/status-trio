enum BetterDisplayEvent: Equatable, Sendable {
    case launched
    case terminated
    case audioChanged
}

@MainActor
protocol BetterDisplayRequesting: AnyObject {
    func start(onEvent: @escaping @MainActor (BetterDisplayEvent) -> Void)
    func request(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String?
    func stop()
}

/// Inert requester used by the App Store target, where the concrete
/// BetterDisplay bridge is excluded from the build. It never launches a
/// request and never observes another app, so the coordinator stays dormant.
@MainActor
final class UnavailableBetterDisplayClient: BetterDisplayRequesting {
    func start(onEvent _: @escaping @MainActor (BetterDisplayEvent) -> Void) {}
    func request(commands _: [String], parameters _: [String: String?]) async throws -> String? { nil }
    func stop() {}
}
