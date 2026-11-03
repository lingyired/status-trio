import Foundation

struct BatteryPowerFlowState: Equatable, Sendable {
    /// Which rail a branch represents. The view maps this to a symbol and tint;
    /// the state itself stays free of AppKit concerns.
    enum Kind: Equatable, Sendable {
        /// The left-hand source node fed by the power adapter.
        case input
        /// The left-hand source node fed by the pack when it is discharging.
        /// Shares the outer power bar's plain-battery glyph and orange tint so
        /// the two surfaces agree.
        case batterySource
        case charging
        case display
        case usb
        /// System total: the residual split branch, or the legacy total when no
        /// reliable split exists.
        case system
    }

    struct Metric: Equatable, Sendable {
        let label: String
        let value: String
        let watts: Double?
        var kind: Kind = .system
        /// Longer, unambiguous wording for the tooltip and VoiceOver when the
        /// card label has to stay short.
        var help: String? = nil
    }

    let input: Metric?
    /// Every branch drawn to the right of the input, top to bottom. One to
    /// five entries; a branch without a trustworthy reading is absent.
    let destinations: [Metric]

    init(input: Metric?, destinations: [Metric]) {
        self.input = input
        self.destinations = destinations
    }

    /// Legacy two-branch shape, still used by the fallback diagram.
    init(input: Metric?, battery: Metric?, system: Metric?) {
        var destinations: [Metric] = []
        if var battery { battery.kind = .charging; destinations.append(battery) }
        if var system { system.kind = .system; destinations.append(system) }
        self.init(input: input, destinations: destinations)
    }

    var battery: Metric? { destination(.charging) }
    var system: Metric? { destination(.system) }

    var batteryFlowFraction: Double? { flowFraction(battery?.watts) }
    var systemFlowFraction: Double? { flowFraction(system?.watts) }

    func flowFraction(for metric: Metric) -> Double? { flowFraction(metric.watts) }

    private func destination(_ kind: Kind) -> Metric? {
        destinations.first { $0.kind == kind }
    }

    /// Use the same scale even when a destination is hidden. Independent
    /// readings can disagree; retain each value and bound the combined width.
    private func flowFraction(_ watts: Double?) -> Double? {
        guard let input = input?.watts, input.isFinite, input > 0,
              let watts, watts.isFinite, watts >= 0 else { return nil }
        let total = destinations.reduce(0) { $0 + max(0, $1.watts ?? 0) }
        return watts / max(input, total)
    }
}
