import Foundation

/// Localized, presentation-ready contents of the compact battery health card.
/// The view only lays these out; every value comes from the read-only health
/// snapshot, and an unavailable metric becomes an explicit placeholder instead
/// of a fabricated zero.
struct BatteryHealthCardState: Equatable, Sendable {
    struct Metric: Equatable, Sendable, Identifiable {
        let id: String
        let label: String
        let value: String
        let accessibilityValue: String

        init(id: String, label: String, value: String, accessibilityValue: String? = nil) {
            self.id = id
            self.label = label
            self.value = value
            self.accessibilityValue = accessibilityValue ?? "\(label), \(value)"
        }
    }

    let title: String
    let metrics: [Metric]
    let chargeTimeLabel: String
    let chargeTimeValue: String
    /// Visible note under the metrics, e.g. the health-estimate caveat.
    let footnote: String?
    /// Set when this Mac exposes no readable health value at all. The card then
    /// explains why instead of rendering a grid of em dashes.
    let unavailableMessage: String?

    var showsEmptyState: Bool { unavailableMessage != nil }
}
