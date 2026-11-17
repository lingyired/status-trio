import Foundation

/// Which system-monitor detail page is open. Used by the router, the sampler's
/// per-route demand and the shared history chart.
enum HardwareDetailKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case cpu
    case gpu
    case memory
    case network
    case disk

    var id: String { rawValue }
}
