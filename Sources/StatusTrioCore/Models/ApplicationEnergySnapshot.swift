import Foundation

/// A ranked row identity. Applications are keyed by their canonical bundle
/// path; processes that cannot be attributed to an app stay independent so two
/// same-named apps or helpers never collapse into one row.
struct EnergyApplication: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

/// One process's cumulative counters at a single sampling instant.
struct ProcessEnergySample: Equatable, Sendable {
    let pid: Int32
    let startedAt: UInt64
    let app: EnergyApplication
    let cpuNanoseconds: UInt64
    /// `nil` means the energy counter could not be read. It must never be
    /// interpreted as zero energy.
    let energyNanojoules: UInt64?
    /// False for system processes (for example WindowServer), which must not
    /// offer Force Quit even though they can appear in the GPU ranking.
    let isApplication: Bool

    init(pid: Int32,
         startedAt: UInt64,
         app: EnergyApplication,
         cpuNanoseconds: UInt64,
         energyNanojoules: UInt64?,
         isApplication: Bool = true) {
        self.pid = pid
        self.startedAt = startedAt
        self.app = app
        self.cpuNanoseconds = cpuNanoseconds
        self.energyNanojoules = energyNanojoules
        self.isApplication = isApplication
    }
}

/// One IOAccelerator client. `pid` is nil when `IOUserClientCreator` cannot be
/// parsed; that client's GPU time still belongs in the attribution denominator
/// as an unattributed bucket.
struct GPUClientSample: Equatable, Sendable {
    let entryID: UInt64
    let pid: Int32?
    let startedAt: UInt64?
    let name: String
    let executablePath: String?
    let responsiblePID: Int32?
    let queueCount: Int
    let accumulatedGPUTime: UInt64
    /// Resolved ranking identity. Nil for an unparseable creator; that client's
    /// time still belongs in the attribution denominator.
    let app: EnergyApplication?
    let isApplication: Bool

    var hasStableIdentity: Bool {
        pid != nil && startedAt != nil
    }
}

enum GPUEnergyUnit: String, Sendable, Equatable {
    case millijoule = "mJ"
    case microjoule = "uJ"
    case nanojoule = "nJ"

    /// Only unit labels seen from the `Energy Model` group are accepted. An
    /// unknown label must make the channel unavailable rather than guessing nJ.
    static func parse(_ label: String) -> GPUEnergyUnit? {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "µ", with: "u")
        switch normalized.lowercased() {
        case "mj", "millijoule", "millijoules": return .millijoule
        case "uj", "microjoule", "microjoules": return .microjoule
        case "nj", "nanojoule", "nanojoules": return .nanojoule
        default: return nil
        }
    }

    func joules(for rawValue: UInt64) -> Double {
        switch self {
        case .millijoule: return Double(rawValue) / 1_000
        case .microjoule: return Double(rawValue) / 1_000_000
        case .nanojoule: return Double(rawValue) / 1_000_000_000
        }
    }
}

struct GPUEnergyReading: Equatable, Sendable {
    let rawValue: UInt64
    let unit: GPUEnergyUnit
    let joules: Double
    /// Monotonic uptime at which the IOReport sample was taken.
    let readAt: TimeInterval
}

struct ApplicationEnergyCapabilities: OptionSet, Sendable, Equatable {
    let rawValue: Int

    static let cpuEnergy = ApplicationEnergyCapabilities(rawValue: 1 << 0)
    static let cpuActivity = ApplicationEnergyCapabilities(rawValue: 1 << 1)
    static let gpuClients = ApplicationEnergyCapabilities(rawValue: 1 << 2)
    static let gpuEnergy = ApplicationEnergyCapabilities(rawValue: 1 << 3)
    /// IOReport symbols are present, even if this particular sample failed or
    /// the GPU energy channel could not be read. Used only to surface partial
    /// coverage instead of silently calling the result complete.
    static let gpuEnergyRuntime = ApplicationEnergyCapabilities(rawValue: 1 << 4)
}

struct ApplicationEnergySnapshot: Equatable, Sendable {
    let readAt: TimeInterval
    let processes: [ProcessEnergySample]
    let gpuClients: [GPUClientSample]
    let gpuEnergy: GPUEnergyReading?
    let capabilities: ApplicationEnergyCapabilities

    init(readAt: TimeInterval,
         processes: [ProcessEnergySample],
         gpuClients: [GPUClientSample] = [],
         gpuEnergy: GPUEnergyReading? = nil,
         capabilities: ApplicationEnergyCapabilities = []) {
        self.readAt = readAt
        self.processes = processes
        self.gpuClients = gpuClients
        self.gpuEnergy = gpuEnergy
        self.capabilities = capabilities
    }
}

struct ApplicationEnergyCoverage: OptionSet, Sendable, Equatable {
    let rawValue: Int

    static let cpuEnergy = ApplicationEnergyCoverage(rawValue: 1 << 0)
    static let gpuEnergy = ApplicationEnergyCoverage(rawValue: 1 << 1)
    static let cpuActivity = ApplicationEnergyCoverage(rawValue: 1 << 2)
}

enum ApplicationEnergyBasis: String, Sendable, Equatable {
    case cpuAndGPU
    case cpuEnergy
    case gpuEnergy
    case cpuActivity
}

enum ApplicationEnergyPhase: Sendable, Equatable {
    case sampling
    case ready
    case partial
    case empty
    case unavailable
}

struct ApplicationEnergyAppInterval: Equatable, Sendable {
    let app: EnergyApplication
    let isApplication: Bool
    let cpuEnergyJoules: Double?
    let gpuEnergyJoules: Double?
    let cpuActivityFraction: Double?
    let coverage: ApplicationEnergyCoverage
}

/// One immutable slice of measured time. The window only ever stores these,
/// never raw PIDs or cumulative counters.
struct ApplicationEnergyInterval: Equatable, Sendable {
    let start: TimeInterval
    let duration: TimeInterval
    /// Sources that produced at least some usable data for this interval.
    let coverage: ApplicationEnergyCoverage
    /// Sources that were usable but not complete for every process/client.
    let partialSources: ApplicationEnergyCoverage
    /// Fraction of all readable GPU client time that could be tied to a PID.
    let gpuAttributionCoverage: Double
    /// GPU joules that could not be attributed to any client.
    let unassignedGPUJoules: Double
    let apps: [ApplicationEnergyAppInterval]

    init(start: TimeInterval,
         duration: TimeInterval,
         coverage: ApplicationEnergyCoverage,
         partialSources: ApplicationEnergyCoverage = [],
         gpuAttributionCoverage: Double = 1,
         unassignedGPUJoules: Double = 0,
         apps: [ApplicationEnergyAppInterval]) {
        self.start = start
        self.duration = duration
        self.coverage = coverage
        self.partialSources = partialSources
        self.gpuAttributionCoverage = gpuAttributionCoverage
        self.unassignedGPUJoules = unassignedGPUJoules
        self.apps = apps
    }
}

struct ApplicationEnergyDiagnostics: Equatable, Sendable {
    var cpuEnergyAvailable: Bool
    var gpuEnergyAvailable: Bool
    var gpuAttributionCoverage: Double
    var measuredDuration: TimeInterval
    var basis: ApplicationEnergyBasis
}

struct ApplicationEnergyRanking: Equatable, Sendable {
    typealias Basis = ApplicationEnergyBasis
    typealias Phase = ApplicationEnergyPhase

    struct Row: Equatable, Sendable, Identifiable {
        let app: EnergyApplication
        let value: Double
        let coverage: ApplicationEnergyCoverage
        let isApplication: Bool

        var id: String { app.id }
    }

    var rows: [Row] = []
    var basis: ApplicationEnergyBasis = .cpuEnergy
    var phase: ApplicationEnergyPhase = .sampling
    var windowAge: TimeInterval = 0
    var effectiveDuration: TimeInterval = 0
    var windowCapacity: TimeInterval = 60
    var unassignedGPUJoules: Double = 0
    var diagnostics: ApplicationEnergyDiagnostics?

    init(rows: [Row] = [],
         basis: ApplicationEnergyBasis = .cpuEnergy,
         phase: ApplicationEnergyPhase = .sampling,
         windowAge: TimeInterval = 0,
         effectiveDuration: TimeInterval = 0,
         windowCapacity: TimeInterval = 60,
         unassignedGPUJoules: Double = 0,
         diagnostics: ApplicationEnergyDiagnostics? = nil) {
        self.rows = rows
        self.basis = basis
        self.phase = phase
        self.windowAge = windowAge
        self.effectiveDuration = effectiveDuration
        self.windowCapacity = windowCapacity
        self.unassignedGPUJoules = unassignedGPUJoules
        self.diagnostics = diagnostics
    }

    /// Compatibility initializer for previews and presentation tests that only
    /// need a list of application rows.
    init(apps: [EnergyApplication],
         values: [EnergyApplication: Double] = [:],
         basis: ApplicationEnergyBasis = .cpuEnergy,
         phase: ApplicationEnergyPhase = .sampling) {
        self.rows = apps.map {
            Row(app: $0, value: values[$0] ?? 0, coverage: [], isApplication: true)
        }
        self.basis = basis
        self.phase = phase
    }

    var apps: [EnergyApplication] { rows.map(\.app) }
    var values: [EnergyApplication: Double] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.app, $0.value) })
    }

    var isWindowComplete: Bool {
        windowCapacity > 0 && effectiveDuration >= windowCapacity - 0.001
    }

    func coverage(for app: EnergyApplication) -> ApplicationEnergyCoverage {
        rows.first { $0.app == app }?.coverage ?? []
    }

    func isApplication(_ app: EnergyApplication) -> Bool {
        rows.first { $0.app == app }?.isApplication ?? true
    }
}
