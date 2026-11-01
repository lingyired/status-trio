import Foundation

struct ManagedChargeLimitSession: Codable, Equatable, Sendable {
    var limit: Int
    let originalLimit: Int
    var isTemporarilyOverridden = false
    var isPaused = false
    /// Persisted before issuing a write; interruption requires verification or explicit retry.
    var isPending = false
    var isRestoringSystem = false
    var overrideAcceptedAt: Date? = nil

    var isValid: Bool {
        (80..<100).contains(limit) && (80...100).contains(originalLimit)
    }
}

@MainActor
protocol ManagedChargeLimitSessionStoring: AnyObject {
    func load() -> ManagedChargeLimitSession?
    func save(_ session: ManagedChargeLimitSession)
    func clear()
}

@MainActor
final class UserDefaultsManagedChargeLimitSessionStore: ManagedChargeLimitSessionStoring {
    static let defaultsKey = "managedChargeLimit.session.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load() -> ManagedChargeLimitSession? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let session = try? JSONDecoder().decode(ManagedChargeLimitSession.self, from: data),
              session.isValid else { return nil }
        return session
    }

    func save(_ session: ManagedChargeLimitSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() { defaults.removeObject(forKey: Self.defaultsKey) }
}

@MainActor
final class VolatileManagedChargeLimitSessionStore: ManagedChargeLimitSessionStoring {
    private var session: ManagedChargeLimitSession?
    func load() -> ManagedChargeLimitSession? { session }
    func save(_ session: ManagedChargeLimitSession) { self.session = session }
    func clear() { session = nil }
}
