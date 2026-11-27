import Foundation

/// Turns two adjacent cumulative snapshots into immutable interval samples.
/// Every reset/failure path drops the affected delta instead of producing a
/// spike: PID reuse, counter rollback, missing counters and long gaps all end
/// the previous baseline.
struct ApplicationEnergyIntervalBuilder: Sendable {
    struct Configuration: Sendable, Equatable {
        /// A gap larger than this invalidates the baseline.
        var maximumGap: TimeInterval = 15
        /// Consecutive samples with GPU client activity but no GPU energy
        /// increase required before the channel is considered stalled.
        var gpuStallTolerance: Int = 2
        /// IOReport and GPU client reads must be reasonably close in time.
        var gpuTimingTolerance: TimeInterval = 1
        var correction = GPUAttributionCorrection.Configuration()

        init(maximumGap: TimeInterval = 15,
             gpuStallTolerance: Int = 2,
             gpuTimingTolerance: TimeInterval = 1,
             correction: GPUAttributionCorrection.Configuration = .init()) {
            self.maximumGap = maximumGap
            self.gpuStallTolerance = gpuStallTolerance
            self.gpuTimingTolerance = gpuTimingTolerance
            self.correction = correction
        }
    }

    private struct CPUAccumulator {
        let app: EnergyApplication
        var isApplication: Bool
        var cpuEnergyJoules: Double = 0
        var cpuActivitySeconds: Double = 0
        var hasCPUEnergy = false
        var hasCPUActivity = false
    }

    private(set) var configuration: Configuration
    private(set) var previous: ApplicationEnergySnapshot?
    private var gpuStallCount = 0
    private var correction: GPUAttributionCorrection

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.correction = GPUAttributionCorrection(configuration: configuration.correction)
    }

    mutating func reset() {
        previous = nil
        gpuStallCount = 0
        correction.reset()
    }

    mutating func setMaximumGap(_ gap: TimeInterval) {
        configuration.maximumGap = gap
    }

    mutating func build(current: ApplicationEnergySnapshot) -> [ApplicationEnergyInterval] {
        guard let previous else {
            self.previous = current
            return []
        }
        defer { self.previous = current }

        let elapsed = current.readAt - previous.readAt
        guard elapsed.isFinite, elapsed > 0, elapsed <= configuration.maximumGap else {
            return []
        }

        var cpuAccumulators: [EnergyApplication: CPUAccumulator] = [:]
        var sawCPUEnergy = false
        var sawCPUActivity = false
        var missingCPUEnergy = false
        var missingCPUActivity = false

        let previousByPID = Dictionary(previous.processes.map { ($0.pid, $0) },
                                       uniquingKeysWith: { _, last in last })
        for process in current.processes {
            guard let prior = previousByPID[process.pid],
                  prior.startedAt == process.startedAt,
                  prior.app == process.app else { continue }

            var accumulator = cpuAccumulators[process.app]
                ?? CPUAccumulator(app: process.app, isApplication: process.isApplication)
            accumulator.isApplication = accumulator.isApplication || process.isApplication

            if process.cpuNanoseconds >= prior.cpuNanoseconds {
                let delta = process.cpuNanoseconds - prior.cpuNanoseconds
                accumulator.cpuActivitySeconds += Double(delta) / 1_000_000_000
                accumulator.hasCPUActivity = true
                sawCPUActivity = true
            } else {
                missingCPUActivity = true
            }

            if let energy = process.energyNanojoules,
               let priorEnergy = prior.energyNanojoules,
               energy >= priorEnergy {
                accumulator.cpuEnergyJoules += Double(energy - priorEnergy) / 1_000_000_000
                accumulator.hasCPUEnergy = true
                sawCPUEnergy = true
            } else {
                missingCPUEnergy = true
            }
            cpuAccumulators[process.app] = accumulator
        }

        var rows: [EnergyApplication: ApplicationEnergyAppInterval] = [:]
        for accumulator in cpuAccumulators.values
        where accumulator.hasCPUEnergy || accumulator.hasCPUActivity {
            var coverage: ApplicationEnergyCoverage = []
            if accumulator.hasCPUEnergy { coverage.insert(.cpuEnergy) }
            if accumulator.hasCPUActivity { coverage.insert(.cpuActivity) }
            rows[accumulator.app] = ApplicationEnergyAppInterval(
                app: accumulator.app,
                isApplication: accumulator.isApplication,
                cpuEnergyJoules: accumulator.hasCPUEnergy ? accumulator.cpuEnergyJoules : nil,
                gpuEnergyJoules: nil,
                cpuActivityFraction: accumulator.hasCPUActivity
                    ? accumulator.cpuActivitySeconds / elapsed : nil,
                coverage: coverage
            )
        }

        var coverage: ApplicationEnergyCoverage = []
        if sawCPUEnergy { coverage.insert(.cpuEnergy) }
        if sawCPUActivity { coverage.insert(.cpuActivity) }
        var partialSources: ApplicationEnergyCoverage = []
        if sawCPUEnergy && missingCPUEnergy { partialSources.insert(.cpuEnergy) }
        if sawCPUActivity && missingCPUActivity { partialSources.insert(.cpuActivity) }

        // GPU clients: match by registry entry ID and process incarnation. A
        // replaced client starts a new baseline instead of inheriting its old
        // accumulated time.
        let previousClients = Dictionary(previous.gpuClients.map { ($0.entryID, $0) },
                                         uniquingKeysWith: { _, last in last })
        var clientDeltas: [GPUClientIntervalDelta] = []
        var gpuTimeByPID: [Int32: Double] = [:]
        var totalClientTime: UInt64 = 0
        for client in current.gpuClients {
            guard let prior = previousClients[client.entryID],
                  prior.pid == client.pid,
                  prior.queueCount == client.queueCount,
                  client.accumulatedGPUTime >= prior.accumulatedGPUTime else { continue }
            let delta = client.accumulatedGPUTime - prior.accumulatedGPUTime
            guard delta > 0 else { continue }
            let hasVerifiedIdentity = client.pid == nil
                || (client.hasStableIdentity && prior.hasStableIdentity)
            let attributablePID = hasVerifiedIdentity ? client.pid : nil
            totalClientTime &+= delta
            clientDeltas.append(GPUClientIntervalDelta(entryID: client.entryID,
                                                       pid: attributablePID,
                                                       gpuTimeDelta: delta))
            if let pid = attributablePID {
                gpuTimeByPID[pid, default: 0] += Double(delta)
            }
        }

        var gpuDeltaJoules: Double?
        if let priorEnergy = previous.gpuEnergy,
           let energy = current.gpuEnergy,
           priorEnergy.unit == energy.unit,
           energy.rawValue >= priorEnergy.rawValue,
           abs(energy.readAt - current.readAt) <= configuration.gpuTimingTolerance {
            gpuDeltaJoules = energy.joules - priorEnergy.joules
        }

        let gpuCapabilityExpected = current.capabilities.contains(.gpuEnergyRuntime)
        if totalClientTime > 0 {
            if let delta = gpuDeltaJoules, delta > 0 {
                gpuStallCount = 0
            } else {
                gpuStallCount += 1
                if gpuStallCount >= configuration.gpuStallTolerance {
                    gpuDeltaJoules = nil
                }
            }
        } else {
            gpuStallCount = 0
        }

        var unassignedGPUJoules = 0.0
        var gpuAttributionCoverage = 1.0
        if let gpuDeltaJoules {
            coverage.insert(.gpuEnergy)
            let attribution = GPUEnergyAttribution.attribute(totalDeltaJoules: gpuDeltaJoules,
                                                             clientDeltas: clientDeltas)
            var allocation = attribution.allocationByPID
            unassignedGPUJoules = attribution.unassignedJoules
            gpuAttributionCoverage = attribution.attributionCoverage

            let windowServerPID = current.gpuClients.first { $0.name == "WindowServer" }?.pid
            let windowServerTime = windowServerPID.map { gpuTimeByPID[$0] ?? 0 } ?? 0
            let otherTime = gpuTimeByPID.reduce(0.0) { sum, item in
                item.key == windowServerPID ? sum : sum + item.value
            }
            if let windowServerPID, windowServerTime > 0, otherTime == 0, elapsed > 0 {
                correction.observeIdleWindowServer(
                    powerW: (allocation[windowServerPID] ?? 0) / elapsed
                )
            }
            let corrected = correction.apply(allocationByPID: allocation,
                                             gpuTimeDeltaByPID: gpuTimeByPID,
                                             windowServerPID: windowServerPID,
                                             elapsed: elapsed)
            allocation = corrected.allocationByPID
            unassignedGPUJoules += corrected.unassignedJoules

            for (pid, joules) in allocation {
                guard let client = current.gpuClients.first(where: { $0.pid == pid }),
                      let app = client.app else { continue }
                let existing = rows[app]
                let row = existing ?? ApplicationEnergyAppInterval(
                    app: app,
                    isApplication: client.isApplication,
                    cpuEnergyJoules: nil,
                    gpuEnergyJoules: 0,
                    cpuActivityFraction: nil,
                    coverage: []
                )
                rows[app] = ApplicationEnergyAppInterval(
                    app: app,
                    isApplication: row.isApplication || client.isApplication,
                    cpuEnergyJoules: row.cpuEnergyJoules,
                    gpuEnergyJoules: (row.gpuEnergyJoules ?? 0) + joules,
                    cpuActivityFraction: row.cpuActivityFraction,
                    coverage: row.coverage.union(.gpuEnergy)
                )
            }
        } else if gpuCapabilityExpected && (totalClientTime > 0 || gpuStallCount > 0) {
            partialSources.insert(.gpuEnergy)
        }

        guard !rows.isEmpty || !coverage.isEmpty || !partialSources.isEmpty else { return [] }
        return [ApplicationEnergyInterval(
            start: previous.readAt,
            duration: elapsed,
            coverage: coverage,
            partialSources: partialSources,
            gpuAttributionCoverage: gpuAttributionCoverage,
            unassignedGPUJoules: unassignedGPUJoules,
            apps: Array(rows.values)
        )]
    }
}
