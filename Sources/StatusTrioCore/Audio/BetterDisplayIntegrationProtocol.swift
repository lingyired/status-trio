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
