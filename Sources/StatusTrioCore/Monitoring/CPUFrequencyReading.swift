import Foundation

struct CPUFrequencyReading: Equatable, Sendable {
    var efficiencyGHz: Double?
    var performanceGHz: Double?
    var superGHz: Double?
    var sampledAt: Date

    /// IOReport residency is always an estimate, recorded so the UI can label it.
    var isEstimated: Bool { true }
}
