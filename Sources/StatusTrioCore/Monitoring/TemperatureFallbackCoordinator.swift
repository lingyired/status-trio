import Foundation

/// Which of the two on-die temperatures a fallback decision concerns. CPU and
/// GPU are evaluated independently: one may stay on SMC while the other is
/// already served by HID.
enum TemperatureMetric: String, CaseIterable, Sendable {
    case cpu
    case gpu
}

/// One aggregated HID temperature reading plus how many sensors produced it.
struct TemperatureMeasurement: Equatable, Sendable {
    let value: Double
    let count: Int

    init(value: Double, count: Int) {
        self.value = value
        self.count = count
    }
}

/// The source a single sampling tick settled on for one temperature metric.
enum TemperatureDecision: Equatable, Sendable {
    /// Keep using the SMC reading the caller already obtained.
    case smc
    /// Use this HID aggregate instead.
    case hid(TemperatureMeasurement)
    /// Neither source produced a usable value this tick.
    case unavailable
}

/// Per-metric state machine that decides when a confirmed-broken SMC
/// temperature should be replaced by the HID fallback, and when it should be
/// retried.
final class TemperatureFallbackCoordinator: @unchecked Sendable {
    struct Configuration: Sendable {
        var smcFailureThreshold: Int = 2
        var smcRecoveryInterval: TimeInterval = 600
        var hidRetryDelays: [TimeInterval] = [30, 60, 120, 240, 300]

        init(smcFailureThreshold: Int = 2,
             smcRecoveryInterval: TimeInterval = 600,
             hidRetryDelays: [TimeInterval] = [30, 60, 120, 240, 300]) {
            self.smcFailureThreshold = smcFailureThreshold
            self.smcRecoveryInterval = smcRecoveryInterval
            self.hidRetryDelays = hidRetryDelays
        }
    }

    private enum Mode: Sendable {
        case smcPreferred
        case hidFallback
    }

    private struct MetricState {
        var mode: Mode = .smcPreferred
        var smcConsecutiveFailures = 0
        var nextSMCProbe: Date?
        var hidRetryIndex = 0
        var hidRetryNotBefore: Date?
    }

    private let configuration: Configuration
    private let isEligible: (TemperatureMetric) -> Bool
    private var states: [TemperatureMetric: MetricState] = [:]

    init(configuration: Configuration = Configuration(),
         isEligible: @escaping (TemperatureMetric) -> Bool) {
        self.configuration = configuration
        self.isEligible = isEligible
    }

    static func isEligible(platform: SensorPlatform) -> Bool {
        if case .appleSilicon(let chip) = platform, chip == "Apple M1" {
            return true
        }
        return false
    }

    static func production(platform: SensorPlatform) -> TemperatureFallbackCoordinator {
        let eligible = Self.isEligible(platform: platform)
        return TemperatureFallbackCoordinator(isEligible: { _ in eligible })
    }

    var activeHIDMetrics: Set<TemperatureMetric> {
        var result: Set<TemperatureMetric> = []
        for (metric, state) in states where state.mode == .hidFallback {
            result.insert(metric)
        }
        return result
    }

    func needsHID(_ metric: TemperatureMetric) -> Bool {
        states[metric]?.mode == .hidFallback
    }

    func setDemandedMetrics(_ demanded: Set<TemperatureMetric>) {
        for metric in TemperatureMetric.allCases where !demanded.contains(metric) {
            states.removeValue(forKey: metric)
        }
    }

    func reset() {
        states.removeAll()
    }

    func resolve(demanded: Set<TemperatureMetric>,
                 at date: Date,
                 smc: (Set<TemperatureMetric>, Date) -> [TemperatureMetric: Double?],
                 hid: (Set<TemperatureMetric>, Date) -> [TemperatureMetric: TemperatureMeasurement])
        -> [TemperatureMetric: TemperatureDecision] {
        guard !demanded.isEmpty else { return [:] }

        let smcRequest = Set(demanded.filter { shouldReadSMC($0, at: date) })
        let smcResults = smc(smcRequest, date)

        var decisions: [TemperatureMetric: TemperatureDecision] = [:]
        var hidRequest: Set<TemperatureMetric> = []

        for metric in demanded {
            var state = states[metric] ?? MetricState()
            switch state.mode {
            case .smcPreferred:
                if let value = smcResults[metric] ?? nil, value.isFinite {
                    state.smcConsecutiveFailures = 0
                    decisions[metric] = .smc
                } else {
                    state.smcConsecutiveFailures += 1
                    if state.smcConsecutiveFailures >= configuration.smcFailureThreshold,
                       isEligible(metric) {
                        state.mode = .hidFallback
                        state.nextSMCProbe = date.addingTimeInterval(configuration.smcRecoveryInterval)
                        state.hidRetryIndex = 0
                        state.hidRetryNotBefore = nil
                        hidRequest.insert(metric)
                    } else {
                        decisions[metric] = .unavailable
                    }
                }
            case .hidFallback:
                var recovered = false
                if let probe = state.nextSMCProbe, date >= probe {
                    if let value = smcResults[metric] ?? nil, value.isFinite {
                        state = MetricState()
                        decisions[metric] = .smc
                        recovered = true
                    } else {
                        state.nextSMCProbe = date.addingTimeInterval(configuration.smcRecoveryInterval)
                    }
                }
                if !recovered {
                    if let notBefore = state.hidRetryNotBefore, date < notBefore {
                        decisions[metric] = .unavailable
                    } else {
                        hidRequest.insert(metric)
                    }
                }
            }
            states[metric] = state
        }

        if !hidRequest.isEmpty {
            let hidResults = hid(hidRequest, date)
            for metric in hidRequest {
                var state = states[metric] ?? MetricState()
                if let measurement = hidResults[metric],
                   measurement.value.isFinite,
                   measurement.count > 0 {
                    state.hidRetryIndex = 0
                    state.hidRetryNotBefore = nil
                    decisions[metric] = .hid(measurement)
                } else {
                    let delay = hidRetryDelay(for: state.hidRetryIndex)
                    state.hidRetryNotBefore = date.addingTimeInterval(delay)
                    if state.hidRetryIndex < configuration.hidRetryDelays.count - 1 {
                        state.hidRetryIndex += 1
                    }
                    decisions[metric] = .unavailable
                }
                states[metric] = state
            }
        }

        return decisions
    }

    private func shouldReadSMC(_ metric: TemperatureMetric, at date: Date) -> Bool {
        guard let state = states[metric] else { return true }
        switch state.mode {
        case .smcPreferred:
            return true
        case .hidFallback:
            guard let probe = state.nextSMCProbe else { return true }
            return date >= probe
        }
    }

    private func hidRetryDelay(for index: Int) -> TimeInterval {
        guard !configuration.hidRetryDelays.isEmpty else { return 300 }
        let clamped = min(max(index, 0), configuration.hidRetryDelays.count - 1)
        return configuration.hidRetryDelays[clamped]
    }
}
