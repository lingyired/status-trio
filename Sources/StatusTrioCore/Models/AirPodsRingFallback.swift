import Foundation

/// What the outer ring falls back to when the AirPods ring is selected but no
/// AirPods battery is readable.
///
/// `battery` keeps the historical behaviour (the Mac battery ring).
/// `hardwareMonitor` falls back to the custom system-monitoring ring.
enum AirPodsRingFallback: String, CaseIterable, Identifiable, Codable, Sendable {
    case battery
    case hardwareMonitor

    var id: Self { self }
}
