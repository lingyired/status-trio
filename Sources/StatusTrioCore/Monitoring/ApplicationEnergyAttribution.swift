import Foundation

/// One client's delta inside a sampling interval. `pid` is nil when the creator
/// could not be parsed; its time stays in the denominator and its energy in the
/// unattributed bucket.
struct GPUClientIntervalDelta: Equatable, Sendable {
    let entryID: UInt64
    let pid: Int32?
    let gpuTimeDelta: UInt64
}

struct GPUEnergyAttributionResult: Equatable, Sendable {
    var allocationByPID: [Int32: Double] = [:]
    var unassignedJoules: Double = 0
    /// Readable client time that could be tied to a PID, divided by all
    /// readable client time in this interval.
    var attributionCoverage: Double = 0
}

/// Pure proportional allocation of IOReport GPU energy over GPU client time.
/// Nothing here reads hardware, so it is fully unit-testable.
enum GPUEnergyAttribution {
    static func attribute(totalDeltaJoules: Double,
                          clientDeltas: [GPUClientIntervalDelta]) -> GPUEnergyAttributionResult {
        guard totalDeltaJoules.isFinite, totalDeltaJoules >= 0 else {
            return GPUEnergyAttributionResult()
        }
        let totalTime = clientDeltas.reduce(UInt64(0)) { $0 &+ $1.gpuTimeDelta }
        guard totalTime > 0 else {
            return GPUEnergyAttributionResult(unassignedJoules: totalDeltaJoules,
                                              attributionCoverage: 0)
        }

        var knownTime: UInt64 = 0
        var allocation: [Int32: Double] = [:]
        for delta in clientDeltas {
            guard let pid = delta.pid, delta.gpuTimeDelta > 0 else { continue }
            knownTime &+= delta.gpuTimeDelta
            allocation[pid, default: 0] += totalDeltaJoules * Double(delta.gpuTimeDelta) / Double(totalTime)
        }
        let unknownTime = totalTime - knownTime
        let unassigned = totalDeltaJoules * Double(unknownTime) / Double(totalTime)
        return GPUEnergyAttributionResult(
            allocationByPID: allocation,
            unassignedJoules: unassigned,
            attributionCoverage: Double(knownTime) / Double(totalTime)
        )
    }
}

/// Optional WindowServer correction stage. It is deliberately disabled by
/// default: the plan requires raw proportional attribution until a controlled
/// M3 Max comparison proves the correction reduces systematic bias.
struct GPUAttributionCorrection: Sendable {
    struct Configuration: Sendable, Equatable {
        var isEnabled = false
        var baselineSampleLimit = 20
        var minimumBaselineSamples = 3
        var windowServerMultiplierLimit = 1.5

        init(isEnabled: Bool = false,
             baselineSampleLimit: Int = 20,
             minimumBaselineSamples: Int = 3,
             windowServerMultiplierLimit: Double = 1.5) {
            self.isEnabled = isEnabled
            self.baselineSampleLimit = baselineSampleLimit
            self.minimumBaselineSamples = minimumBaselineSamples
            self.windowServerMultiplierLimit = windowServerMultiplierLimit
        }
    }

    struct Result: Equatable, Sendable {
        var allocationByPID: [Int32: Double]
        var unassignedJoules: Double
        var windowServerRawPowerW: Double?
        var windowServerCorrectedPowerW: Double?
    }

    var configuration: Configuration
    private var windowServerPowerSamples: [Double] = []
    private(set) var baselinePowerW: Double?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func reset() {
        windowServerPowerSamples.removeAll()
        baselinePowerW = nil
    }

    /// Feed an interval in which WindowServer was the only GPU client. Samples
    /// below noise or with no measured time are ignored.
    mutating func observeIdleWindowServer(powerW: Double) {
        guard configuration.isEnabled, powerW.isFinite, powerW > 0 else { return }
        windowServerPowerSamples.append(powerW)
        if windowServerPowerSamples.count > configuration.baselineSampleLimit {
            windowServerPowerSamples.removeFirst(
                windowServerPowerSamples.count - configuration.baselineSampleLimit
            )
        }
        guard windowServerPowerSamples.count >= configuration.minimumBaselineSamples else {
            baselinePowerW = nil
            return
        }
        let sorted = windowServerPowerSamples.sorted()
        let middle = sorted.count / 2
        baselinePowerW = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    func apply(allocationByPID: [Int32: Double],
               gpuTimeDeltaByPID: [Int32: Double],
               windowServerPID: Int32?,
               elapsed: TimeInterval) -> Result {
        guard configuration.isEnabled,
              let windowServerPID,
              let baselinePowerW,
              elapsed > 0 else {
            return Result(allocationByPID: allocationByPID,
                          unassignedJoules: 0,
                          windowServerRawPowerW: nil,
                          windowServerCorrectedPowerW: nil)
        }

        let rawWindowServerJoules = allocationByPID[windowServerPID] ?? 0
        let rawPowerW = rawWindowServerJoules / elapsed
        let capJoules = baselinePowerW * configuration.windowServerMultiplierLimit * elapsed
        guard rawWindowServerJoules > capJoules else {
            return Result(allocationByPID: allocationByPID,
                          unassignedJoules: 0,
                          windowServerRawPowerW: rawPowerW,
                          windowServerCorrectedPowerW: rawPowerW)
        }

        let otherTime = gpuTimeDeltaByPID.reduce(0.0) { sum, item in
            item.key == windowServerPID ? sum : sum + max(0, item.value)
        }
        guard otherTime > 0 else {
            // No competing client to receive the excess: keep it unattributed
            // rather than moving it to an arbitrary app.
            var corrected = allocationByPID
            corrected[windowServerPID] = capJoules
            return Result(allocationByPID: corrected,
                          unassignedJoules: rawWindowServerJoules - capJoules,
                          windowServerRawPowerW: rawPowerW,
                          windowServerCorrectedPowerW: capJoules / elapsed)
        }

        let excess = rawWindowServerJoules - capJoules
        var corrected = allocationByPID
        corrected[windowServerPID] = capJoules
        for (pid, time) in gpuTimeDeltaByPID where pid != windowServerPID && time > 0 {
            corrected[pid, default: 0] += excess * time / otherTime
        }
        return Result(allocationByPID: corrected,
                      unassignedJoules: 0,
                      windowServerRawPowerW: rawPowerW,
                      windowServerCorrectedPowerW: capJoules / elapsed)
    }
}
