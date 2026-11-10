import Foundation

struct EnergyApplication: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

struct ProcessEnergySample: Equatable, Sendable {
    let pid: Int32
    let startedAt: UInt64
    let app: EnergyApplication
    let cpuNanoseconds: UInt64
    let energyNanojoules: UInt64?
}

struct ApplicationEnergySnapshot: Sendable {
    let readAt: TimeInterval
    let processes: [ProcessEnergySample]
}

struct ApplicationEnergyRanking: Equatable, Sendable {
    enum Basis: Sendable { case cpuEnergy, cpuActivity }
    enum Phase: Sendable { case sampling, ready, unavailable }
    var apps: [EnergyApplication] = []
    var values: [EnergyApplication: Double] = [:]
    var basis: Basis = .cpuEnergy
    var phase: Phase = .sampling

    static func rank(previous: ApplicationEnergySnapshot?, current: ApplicationEnergySnapshot) -> Self {
        guard !current.processes.isEmpty else { return Self(phase: .unavailable) }
        guard let previous else { return Self() }
        let elapsed = current.readAt - previous.readAt
        guard elapsed.isFinite, (0.5...30).contains(elapsed) else { return Self() }
        let old = Dictionary(previous.processes.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        var cpu: [EnergyApplication: Double] = [:]
        var energy: [EnergyApplication: Double] = [:]
        var hasEnergy = false
        var completeEnergyCoverage = true
        for process in current.processes {
            guard let prior = old[process.pid], prior.startedAt == process.startedAt,
                  prior.app == process.app, process.cpuNanoseconds >= prior.cpuNanoseconds else { continue }
            cpu[process.app, default: 0] += Double(process.cpuNanoseconds - prior.cpuNanoseconds) / 1e9 / elapsed
            if let value = process.energyNanojoules, let before = prior.energyNanojoules,
               value >= before, value > 0 {
                hasEnergy = true
                energy[process.app, default: 0] += Double(value - before) / 1e9 / elapsed
            } else {
                completeEnergyCoverage = false
            }
        }
        let usesEnergy = hasEnergy && completeEnergyCoverage
        let values = usesEnergy ? energy : cpu
        // 1 mW of CPU energy, or 0.1 % CPU activity, is small enough to keep
        // otherwise-idle apps on screen but still suppresses sampling noise.
        let ranked = values.filter { $0.value >= 0.001 }.sorted {
            $0.value == $1.value ? $0.key.id < $1.key.id : $0.value > $1.value
        }.prefix(5)
        let apps = ranked.map { $0.key }
        let rankedValues = Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, $0.value) })
        return Self(
            apps: apps,
            values: rankedValues,
            basis: usesEnergy ? .cpuEnergy : .cpuActivity,
            phase: .ready
        )
    }
}
