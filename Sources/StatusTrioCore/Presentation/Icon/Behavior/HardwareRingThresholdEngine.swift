import Foundation

/// How loud / hot a metric currently reads, as used by the status colour mode.
enum HardwareLoadLevel: Int, Comparable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: HardwareLoadLevel, rhs: HardwareLoadLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Deterministic threshold / hysteresis engine for the hardware ring.
///
/// Entering a higher level requires `requiredConsecutiveSamples` consecutive
/// samples at or above the new threshold, so a single noisy spike does not flash
/// the arc orange/red. Leaving a level uses a hysteresis margin so a value
/// hovering at the threshold does not chatter. This is a pure value type: the
/// caller owns one instance per surface and feeds it each new sample exactly
/// once. There is no timer — levels only change when samples change.
struct HardwareRingThresholdEngine: Equatable, Sendable {
    /// Entering a level needs this many consecutive crossings.
    static let requiredConsecutiveSamples = 2

    private struct MetricState: Equatable, Sendable {
        var level: HardwareLoadLevel = .normal
        var pendingLevel: HardwareLoadLevel?
        var pendingCount = 0
    }

    private var states: [HardwareMonitorMetric: MetricState] = [:]

    mutating func reset() {
        states.removeAll()
    }

    /// The instantaneous level a raw value maps to (no hysteresis).
    static func immediateLevel(value: Double, options: HardwareMetricRingOptions) -> HardwareLoadLevel {
        if value >= options.criticalThreshold { return .critical }
        if value >= options.warningThreshold { return .warning }
        return .normal
    }

    /// Feed one sample and get the debounced level. `value == nil` (unavailable)
    /// resets the metric to normal so the arc is drawn as an inactive track.
    mutating func ingest(value: Double?, metric: HardwareMonitorMetric,
                         options: HardwareMetricRingOptions) -> HardwareLoadLevel {
        guard let value, value.isFinite else {
            states[metric] = MetricState()
            return .normal
        }
        var state = states[metric] ?? MetricState()
        let candidate = Self.immediateLevel(value: value, options: options)
        let margin = Self.exitMargin(for: metric)
        let warningExit = options.warningThreshold - margin
        let criticalExit = options.criticalThreshold - margin

        if candidate > state.level {
            if state.pendingLevel == candidate {
                state.pendingCount += 1
            } else {
                state.pendingLevel = candidate
                state.pendingCount = 1
            }
            if state.pendingCount >= Self.requiredConsecutiveSamples {
                state.level = candidate
                state.pendingLevel = nil
                state.pendingCount = 0
            }
        } else if candidate < state.level {
            // De-escalate with a hysteresis margin (immediate; only entry is
            // gated on consecutive confirmation).
            switch state.level {
            case .critical:
                if value < criticalExit {
                    state.level = value >= warningExit ? .warning : .normal
                }
            case .warning:
                if value < warningExit {
                    state.level = .normal
                }
            case .normal:
                break
            }
            state.pendingLevel = nil
            state.pendingCount = 0
        } else {
            state.pendingLevel = nil
            state.pendingCount = 0
        }
        states[metric] = state
        return state.level
    }

    /// Percent metrics release 3 points below the threshold; temperatures use a
    /// 2 °C margin; fan uses 200 RPM.
    static func exitMargin(for metric: HardwareMonitorMetric) -> Double {
        switch metric {
        case .cpuUsage, .gpuUsage, .memoryUsage: return 3
        case .cpuTemperature, .batteryTemperature: return 2
        case .fan: return 200
        }
    }
}

/// Runtime wrapper that owns one `HardwareRingThresholdEngine` per icon surface
/// and de-duplicates identical snapshots, so arriving at the same sample twice
/// (live scene + test scene) does not double-count a "consecutive" crossing.
///
/// Main-actor isolated because it is fed from the icon-resolution closure, which
/// runs on the main actor. It never starts sampling and holds no timers.
@MainActor
final class HardwareRingStatusTracker {
    private var engine = HardwareRingThresholdEngine()
    private var lastSnapshot: HardwareMetricsSnapshot?
    private var lastConfiguration: HardwareRingConfiguration?
    private var lastLevels: [HardwareMonitorMetric: HardwareLoadLevel] = [:]

    func levels(
        snapshot: HardwareMetricsSnapshot,
        configuration rawConfiguration: HardwareRingConfiguration,
        now: Date
    ) -> [HardwareMonitorMetric: HardwareLoadLevel] {
        let configuration = rawConfiguration.normalized()
        if snapshot == lastSnapshot, configuration == lastConfiguration {
            return lastLevels
        }
        lastSnapshot = snapshot
        lastConfiguration = configuration
        var result: [HardwareMonitorMetric: HardwareLoadLevel] = [:]
        for metric in configuration.referencedMetrics {
            let sample = HardwareRingMapper.sample(for: metric, in: snapshot)
            let options = configuration.options(for: metric)
            let value = (sample.availability == .measured && sample.isFresh(at: now)) ? sample.value : nil
            result[metric] = engine.ingest(value: value, metric: metric, options: options)
        }
        lastLevels = result
        return result
    }

    func reset() {
        engine.reset()
        lastSnapshot = nil
        lastConfiguration = nil
        lastLevels = [:]
    }
}
