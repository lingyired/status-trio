import Foundation

struct SystemChargeLimitReading: Equatable, Sendable {
    let limit: Int
    let reason: String?
}

protocol SystemChargeLimitProviding: Sendable {
    func chargeLimit(from url: URL?) -> Int?
}

struct UnavailableSystemChargeLimitProvider: SystemChargeLimitProviding {
    func chargeLimit(from url: URL?) -> Int? { nil }
}
