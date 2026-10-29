import Foundation

struct SystemPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

protocol SystemPowerReading: Sendable {
    func read() -> SystemPowerSample?
}

struct UnavailableSystemPowerReader: SystemPowerReading {
    func read() -> SystemPowerSample? { nil }
}
