import Foundation

/// Pure rolling-window aggregator. It stores only immutable interval samples,
/// so the UI and controller never retain raw PID counters.
struct ApplicationEnergyWindow: Sendable {
    struct Configuration: Sendable, Equatable {
        /// Rolling window length.
        var capacity: TimeInterval = 60
        /// Before this much measured time the UI stays in "collecting".
        var minimumDuration: TimeInterval = 15
        /// A gap larger than this cuts the window and rebuilds the baseline.
        var maximumGap: TimeInterval = 15
        /// 1 mW of energy, or 0.1 % activity, suppresses sampling noise.
        var noiseThreshold: Double = 0.001
        var maximumRows: Int = 10

        init(capacity: TimeInterval = 60,
             minimumDuration: TimeInterval = 15,
             maximumGap: TimeInterval = 15,
             noiseThreshold: Double = 0.001,
             maximumRows: Int = 10) {
            self.capacity = capacity
            self.minimumDuration = minimumDuration
            self.maximumGap = maximumGap
            self.noiseThreshold = noiseThreshold
            self.maximumRows = maximumRows
        }
    }

    private(set) var intervals: [ApplicationEnergyInterval] = []
    private(set) var lastEnd: TimeInterval?
    var configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func reset() {
        intervals.removeAll()
        lastEnd = nil
    }

    /// Appends freshly measured intervals. A gap larger than the configured
    /// tolerance invalidates everything before it: a sleep, a blocked read or a
    /// stopped sampler must never produce a cross-gap energy spike.
    mutating func append(contentsOf newIntervals: [ApplicationEnergyInterval]) {
        guard !newIntervals.isEmpty else { return }
        if let lastEnd,
           let first = newIntervals.first,
           first.start - lastEnd > configuration.maximumGap {
            reset()
        }
        for interval in newIntervals where interval.duration.isFinite && interval.duration > 0 {
            intervals.append(interval)
            lastEnd = max(lastEnd ?? interval.start + interval.duration,
                          interval.start + interval.duration)
        }
        prune()
    }

    /// Removes time older than the capacity, proportionally scaling the one
    /// interval that straddles the window boundary.
    private mutating func prune() {
        guard let lastEnd else { return }
        let cutoff = lastEnd - configuration.capacity
        var kept: [ApplicationEnergyInterval] = []
        for interval in intervals {
            let end = interval.start + interval.duration
            guard end > cutoff else { continue }
            if interval.start < cutoff {
                let fraction = (end - cutoff) / interval.duration
                kept.append(interval.scaled(by: fraction, startingAt: cutoff))
            } else {
                kept.append(interval)
            }
        }
        intervals = kept
    }

    var effectiveDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    var windowAge: TimeInterval {
        guard let first = intervals.first, let lastEnd else { return 0 }
        return min(configuration.capacity, max(0, lastEnd - first.start))
    }

    func ranking() -> ApplicationEnergyRanking {
        guard !intervals.isEmpty else {
            return ApplicationEnergyRanking(
                phase: .sampling,
                windowCapacity: configuration.capacity
            )
        }

        let effectiveDuration = effectiveDuration
        let age = windowAge
        let hasCPUEnergy = intervals.contains { $0.coverage.contains(.cpuEnergy) }
        let hasGPUEnergy = intervals.contains { $0.coverage.contains(.gpuEnergy) }
        let hasCPUActivity = intervals.contains { $0.coverage.contains(.cpuActivity) }

        let basis: ApplicationEnergyBasis
        if hasCPUEnergy && hasGPUEnergy {
            basis = .cpuAndGPU
        } else if hasCPUEnergy {
            basis = .cpuEnergy
        } else if hasGPUEnergy {
            basis = .gpuEnergy
        } else if hasCPUActivity {
            basis = .cpuActivity
        } else {
            return ApplicationEnergyRanking(
                phase: .unavailable,
                windowAge: age,
                effectiveDuration: effectiveDuration,
                windowCapacity: configuration.capacity
            )
        }

        var cpuJoules: [EnergyApplication: Double] = [:]
        var gpuJoules: [EnergyApplication: Double] = [:]
        var activitySeconds: [EnergyApplication: Double] = [:]
        var coverage: [EnergyApplication: ApplicationEnergyCoverage] = [:]
        var isApplication: [EnergyApplication: Bool] = [:]
        var unassignedGPUJoules = 0.0

        for interval in intervals {
            unassignedGPUJoules += interval.unassignedGPUJoules
            for row in interval.apps {
                coverage[row.app, default: []].formUnion(row.coverage)
                isApplication[row.app] = row.isApplication
                if let value = row.cpuEnergyJoules {
                    cpuJoules[row.app, default: 0] += value
                }
                if let value = row.gpuEnergyJoules {
                    gpuJoules[row.app, default: 0] += value
                }
                if let fraction = row.cpuActivityFraction {
                    activitySeconds[row.app, default: 0] += fraction * interval.duration
                }
            }
        }

        var values: [EnergyApplication: Double] = [:]
        let candidates = Set(cpuJoules.keys).union(gpuJoules.keys).union(activitySeconds.keys)
        for app in candidates {
            let value: Double?
            switch basis {
            case .cpuAndGPU:
                guard effectiveDuration > 0 else { continue }
                value = ((cpuJoules[app] ?? 0) + (gpuJoules[app] ?? 0)) / effectiveDuration
            case .cpuEnergy:
                guard effectiveDuration > 0 else { continue }
                value = (cpuJoules[app] ?? 0) / effectiveDuration
            case .gpuEnergy:
                guard effectiveDuration > 0 else { continue }
                value = (gpuJoules[app] ?? 0) / effectiveDuration
            case .cpuActivity:
                guard let seconds = activitySeconds[app], effectiveDuration > 0 else { continue }
                value = seconds / effectiveDuration
            }
            if let value, value.isFinite, value >= configuration.noiseThreshold {
                values[app] = value
            }
        }

        let sorted = values.sorted {
            if $0.value == $1.value { return $0.key.id < $1.key.id }
            return $0.value > $1.value
        }.prefix(configuration.maximumRows)
        let rows = sorted.map {
            ApplicationEnergyRanking.Row(
                app: $0.key,
                value: $0.value,
                coverage: coverage[$0.key] ?? [],
                isApplication: isApplication[$0.key] ?? true
            )
        }

        let phase: ApplicationEnergyPhase
        if effectiveDuration < configuration.minimumDuration {
            phase = .sampling
        } else if rows.isEmpty {
            phase = .empty
        } else {
            let cpuFlags = intervals.map { $0.coverage.contains(.cpuEnergy) }
            let gpuFlags = intervals.map { $0.coverage.contains(.gpuEnergy) }
            let mixedCPU = cpuFlags.contains(true) && cpuFlags.contains(false)
            let mixedGPU = gpuFlags.contains(true) && gpuFlags.contains(false)
            let attributionIncomplete = intervals.contains {
                ($0.coverage.contains(.gpuEnergy) && $0.gpuAttributionCoverage < 0.999)
                    || !$0.partialSources.isEmpty
            }
            phase = (mixedCPU || mixedGPU || attributionIncomplete) ? .partial : .ready
        }

        let gpuIntervals = intervals.filter { $0.coverage.contains(.gpuEnergy) }
        let attributionCoverage = gpuIntervals.isEmpty
            ? 0
            : gpuIntervals.reduce(0) { $0 + $1.gpuAttributionCoverage } / Double(gpuIntervals.count)
        return ApplicationEnergyRanking(
            rows: rows,
            basis: basis,
            phase: phase,
            windowAge: age,
            effectiveDuration: effectiveDuration,
            windowCapacity: configuration.capacity,
            unassignedGPUJoules: unassignedGPUJoules,
            diagnostics: ApplicationEnergyDiagnostics(
                cpuEnergyAvailable: hasCPUEnergy,
                gpuEnergyAvailable: hasGPUEnergy,
                gpuAttributionCoverage: attributionCoverage,
                measuredDuration: effectiveDuration,
                basis: basis
            )
        )
    }
}

extension ApplicationEnergyInterval {
    /// Returns the fraction of this interval that lies inside the rolling
    /// window. Energy is divided proportionally; rates stay unchanged.
    func scaled(by fraction: Double, startingAt newStart: TimeInterval) -> ApplicationEnergyInterval {
        let clamped = min(max(fraction, 0), 1)
        return ApplicationEnergyInterval(
            start: newStart,
            duration: duration * clamped,
            coverage: coverage,
            partialSources: partialSources,
            gpuAttributionCoverage: gpuAttributionCoverage,
            unassignedGPUJoules: unassignedGPUJoules * clamped,
            apps: apps.map { row in
                ApplicationEnergyAppInterval(
                    app: row.app,
                    isApplication: row.isApplication,
                    cpuEnergyJoules: row.cpuEnergyJoules.map { $0 * clamped },
                    gpuEnergyJoules: row.gpuEnergyJoules.map { $0 * clamped },
                    cpuActivityFraction: row.cpuActivityFraction,
                    coverage: row.coverage
                )
            }
        )
    }
}
