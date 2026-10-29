import Foundation

struct ChargeToFullNowSession: Codable, Equatable, Sendable {
    let originalLimit: Int?
    let acceptedAt: Date
}

@MainActor
protocol ChargeToFullNowSessionStoring: AnyObject {
    func load() -> ChargeToFullNowSession?
    func save(_ session: ChargeToFullNowSession)
    func clear()
}

@MainActor
final class UserDefaultsChargeToFullNowSessionStore: ChargeToFullNowSessionStoring {
    static let defaultsKey = "chargeToFullNow.session.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> ChargeToFullNowSession? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let session = try? JSONDecoder().decode(
                ChargeToFullNowSession.self,
                from: data
              ) else {
            return nil
        }
        return session
    }

    func save(_ session: ChargeToFullNowSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

@MainActor
final class VolatileChargeToFullNowSessionStore: ChargeToFullNowSessionStoring {
    private var session: ChargeToFullNowSession?

    init(session: ChargeToFullNowSession? = nil) {
        self.session = session
    }

    func load() -> ChargeToFullNowSession? {
        session
    }

    func save(_ session: ChargeToFullNowSession) {
        self.session = session
    }

    func clear() {
        session = nil
    }
}
