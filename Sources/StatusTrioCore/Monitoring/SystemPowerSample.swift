import Foundation

/// A single best-effort SMC power reading. Pure value type, shared by the
/// battery/power UI and readers; the SMC access itself lives in the Direct-only
/// `SystemPowerReader`.
struct SystemPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}
