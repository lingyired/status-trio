import Combine

struct TelemetryConsent: Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sharesAnonymousAnalytics: Bool

    var canShareAnonymousAnalytics: Bool {
        version == Self.currentVersion && sharesAnonymousAnalytics
    }
}
