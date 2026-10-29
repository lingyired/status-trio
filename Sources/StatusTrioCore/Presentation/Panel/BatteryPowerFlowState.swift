import Foundation

struct BatteryPowerFlowState: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        let label: String
        let value: String
        let watts: Double?
    }
    let input: Metric?
    let battery: Metric?
    let system: Metric?

    var batteryFlowFraction: Double? { flowFraction(battery?.watts) }
    var systemFlowFraction: Double? { flowFraction(system?.watts) }

    /// Use the same scale even when one destination is hidden. Independent
    /// readings can disagree; retain each value and bound the combined width.
    private func flowFraction(_ watts: Double?) -> Double? {
        guard let input = input?.watts, input.isFinite, input > 0,
              let watts, watts.isFinite, watts >= 0 else { return nil }
        let total = max(0, battery?.watts ?? 0) + max(0, system?.watts ?? 0)
        return watts / max(input, total)
    }
}
