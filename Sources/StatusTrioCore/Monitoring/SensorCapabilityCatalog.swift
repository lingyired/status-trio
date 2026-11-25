import Foundation
import Darwin

/// The chip generation a temperature plan belongs to. Unknown generations never
/// inherit a neighbouring generation's keys: a wrong key can read a plausible
/// number for a different physical sensor, which is worse than no reading.
enum SensorChipFamily: String, Equatable, Sendable {
    case intel
    case m1
    case m2
    case m3
    case m4
    case m5
    case m6
    case a18Pro
    case unknown
}

enum SensorChipVariant: String, Equatable, Sendable {
    case base
    case pro
    case max
    case ultra
    case unknown
}

/// Everything the catalog uses to select a plan. `modelIdentifier` is kept even
/// where the brand string is enough, because some SKUs share a brand name and
/// only the model identifier (or a real-device dump) separates their key layout.
struct MachineIdentity: Equatable, Sendable {
    let chipName: String?
    let chipFamily: SensorChipFamily
    let chipVariant: SensorChipVariant
    let modelIdentifier: String?
    let architecture: String

    init(chipName: String?, modelIdentifier: String? = nil, architecture: String = MachineIdentity.currentArchitecture) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.architecture = architecture
        let parsed = Self.parse(chipName: chipName)
        chipFamily = parsed.family
        chipVariant = parsed.variant
    }

    init(platform: SensorPlatform, modelIdentifier: String? = nil) {
        switch platform {
        case .intel:
            self.init(chipName: "Intel", modelIdentifier: modelIdentifier, architecture: "x86_64")
        case .appleSilicon(let name):
            self.init(chipName: name, modelIdentifier: modelIdentifier)
        case .unknown:
            self.init(chipName: nil, modelIdentifier: modelIdentifier)
        }
    }

    static func current() -> MachineIdentity {
        let platform = SensorPlatform.current()
        let model = currentModelIdentifier()
        switch platform {
        case .appleSilicon(let name):
            return MachineIdentity(chipName: name, modelIdentifier: model)
        case .intel:
            return MachineIdentity(chipName: "Intel", modelIdentifier: model, architecture: "x86_64")
        case .unknown:
            return MachineIdentity(chipName: nil, modelIdentifier: model)
        }
    }

    var isAppleSilicon: Bool {
        chipFamily != .intel && chipFamily != .unknown
    }

    /// `hw.model` is stable for the lifetime of a boot; reading it once per
    /// reader construction is enough and keeps the sampling path free of sysctl.
    static func currentModelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 128 else {
            return nil
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0,
              let terminator = bytes.firstIndex(of: 0), terminator > 0 else { return nil }
        return String(decoding: bytes[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static var currentArchitecture: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }

    private static func parse(chipName: String?) -> (family: SensorChipFamily, variant: SensorChipVariant) {
        guard let chipName, !chipName.isEmpty else { return (.unknown, .unknown) }
        if chipName == "Intel" || chipName.localizedCaseInsensitiveContains("Intel") {
            return (.intel, .unknown)
        }
        // A18 Pro is the only A-series part currently relevant to macOS
        // diagnostics. Do not map A17/A19 into its sensor layout.
        if chipName == "Apple A18 Pro" {
            return (.a18Pro, .pro)
        }
        guard chipName.hasPrefix("Apple M") else { return (.unknown, .unknown) }
        let parts = chipName.split(separator: " ")
        guard parts.count >= 2, parts[1].hasPrefix("M"),
              let generation = Int(parts[1].dropFirst()), (1...6).contains(generation) else {
            return (.unknown, .unknown)
        }
        let family: SensorChipFamily
        switch generation {
        case 1: family = .m1
        case 2: family = .m2
        case 3: family = .m3
        case 4: family = .m4
        case 5: family = .m5
        default: family = .m6
        }
        let variant: SensorChipVariant
        if parts.count >= 3 {
            switch parts[2] {
            case "Pro": variant = .pro
            case "Max": variant = .max
            case "Ultra": variant = .ultra
            default: variant = .unknown
            }
        } else {
            variant = .base
        }
        return (family, variant)
    }
}

/// The physical quantity a key measures. This is deliberately narrower than a
/// generic SMC catalog: only keys used by the shipping sampling path are here.
enum SensorMetric: String, Equatable, Sendable {
    case cpuCore
    case cpuCluster
    case cpuPerformanceCluster
    case cpuEfficiencyCluster
    case gpuCore
    case gpuCluster
    case batteryTemperature
    case fan
    case backlightPower
    case systemPower
    case inputPower
    case batteryPower
}

/// How a key participates in aggregation.
enum SensorAggregationRole: String, Equatable, Sendable {
    /// Used as the primary representative for its group.
    case preferred
    /// Read only when the preferred key in the same group is unavailable.
    case secondary
    /// A cluster/die aggregate, not a single core.
    case derived
    /// Kept for diagnostics but never averaged into a user-facing value.
    case excluded
}

/// Evidence level. `measured` means a real device produced a plausible value
/// under a load or idle/load comparison; `communityMapped` means multiple
/// independent projects agree on the key; `candidate` means the key exists in a
/// static table but its physical meaning has not been verified here.
enum SensorEvidence: String, Equatable, Sendable {
    case measured
    case communityMapped
    case candidate
    case unsupported
}

/// One key and its semantics. `expectedTypes` are the SMC data types known to
/// carry this quantity (`flt `, `sp78`, `fpe2`, `ui16`, ...). A key is never
/// decoded as a temperature just because it returned bytes.
struct SensorDefinition: Equatable, Sendable {
    let key: String
    let metric: SensorMetric
    let clusterID: String
    let probeID: String
    let role: SensorAggregationRole
    let evidence: SensorEvidence
    let expectedTypes: Set<UInt32>
    let validRange: ClosedRange<Double>
    /// Short provenance note, kept next to the data so future edits do not
    /// silently drop the reason a key was chosen.
    let reference: String

    init(key: String, metric: SensorMetric, clusterID: String, probeID: String,
         role: SensorAggregationRole = .preferred, evidence: SensorEvidence,
         expectedTypes: Set<UInt32> = SensorDefinition.temperatureTypes,
         validRange: ClosedRange<Double> = 0.01...150,
         reference: String) {
        self.key = key
        self.metric = metric
        self.clusterID = clusterID
        self.probeID = probeID
        self.role = role
        self.evidence = evidence
        self.expectedTypes = expectedTypes
        self.validRange = validRange
        self.reference = reference
    }

    /// `flt ` (0x666C7420), `sp78` (0x73703738), `fpe2` (0x66706532),
    /// `ui16` (0x75693136). The decoder still rejects an unknown type; this set
    /// documents the accepted shapes rather than bypassing the check.
    static let temperatureTypes: Set<UInt32> = [0x666C7420, 0x73703738, 0x66706532, 0x75693136]
}

/// A group of probes that describe one physical location. Averaging happens
/// inside the group first, then across groups, so two probes for one core do not
/// count as two cores in the CPU/GPU average.
struct SensorTemperatureGroup: Equatable, Sendable {
    let id: String
    let metric: SensorMetric
    let definitions: [SensorDefinition]
    let aggregation: Aggregation
    let evidence: SensorEvidence

    enum Aggregation: String, Equatable, Sendable {
        case mean
        case maximum
        case firstReadable
    }

    init(id: String, metric: SensorMetric, definitions: [SensorDefinition],
         aggregation: Aggregation = .mean, evidence: SensorEvidence) {
        self.id = id
        self.metric = metric
        self.definitions = definitions
        self.aggregation = aggregation
        self.evidence = evidence
    }

    var keys: [String] { definitions.map(\.key) }

    func representative(from values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        switch aggregation {
        case .mean:
            return values.reduce(0, +) / Double(values.count)
        case .maximum:
            return values.max()
        case .firstReadable:
            return values.first
        }
    }
}

/// The ordered plan for one metric. `fallback` is consulted only when no group
/// in `groups` produced a value; a working primary path never pays for it.
struct SensorTemperaturePlan: Equatable, Sendable {
    let metric: SensorMetric
    let groups: [SensorTemperatureGroup]
    let fallbackGroups: [SensorTemperatureGroup]
    let evidence: SensorEvidence
    let notes: String

    init(metric: SensorMetric, groups: [SensorTemperatureGroup],
         fallbackGroups: [SensorTemperatureGroup] = [],
         evidence: SensorEvidence, notes: String) {
        self.metric = metric
        self.groups = groups
        self.fallbackGroups = fallbackGroups
        self.evidence = evidence
        self.notes = notes
    }

    var keys: [String] { groups.flatMap(\.keys) }
    var allKeys: [String] { keys + fallbackGroups.flatMap(\.keys) }
}

/// Per-machine temperature plans. The catalog is pure data; probing and caching
/// live in `SensorCapabilityCache` and `SensorSMCReader`.
struct SensorCapabilityCatalog: Equatable, Sendable {
    let identity: MachineIdentity
    let cpuPlan: SensorTemperaturePlan
    let gpuPlan: SensorTemperaturePlan
    let batteryTemperatureKeys: [String]

    static func catalog(for identity: MachineIdentity) -> SensorCapabilityCatalog {
        switch identity.chipFamily {
        case .intel:
            return intel(identity)
        case .m1:
            return m1(identity)
        case .m2:
            return m2(identity)
        case .m3:
            return identity.chipVariant == .base ? m3Base(identity) : m3ProMax(identity)
        case .m4:
            return m4(identity)
        case .m5:
            return identity.chipVariant == .base ? m5Base(identity) : m5ProMax(identity)
        case .m6:
            return m6(identity)
        case .a18Pro:
            return a18Pro(identity)
        case .unknown:
            return unknown(identity)
        }
    }

    // MARK: - Builders

    private static func group(_ id: String, _ metric: SensorMetric, keys: [String],
                              evidence: SensorEvidence, reference: String,
                              aggregation: SensorTemperatureGroup.Aggregation = .mean,
                              expectedTypes: Set<UInt32> = SensorDefinition.temperatureTypes,
                              validRange: ClosedRange<Double> = 0.01...150) -> SensorTemperatureGroup {
        let definitions = keys.enumerated().map { index, key in
            SensorDefinition(key: key, metric: metric, clusterID: id,
                             probeID: "\(id)-\(index)", evidence: evidence,
                             expectedTypes: expectedTypes, validRange: validRange,
                             reference: reference)
        }
        return SensorTemperatureGroup(id: id, metric: metric, definitions: definitions,
                                      aggregation: aggregation, evidence: evidence)
    }

    /// One key per core/cluster: the pre-existing behaviour for generations
    /// whose mapping was already in production.
    private static func singleKeyGroups(_ metric: SensorMetric, keys: [String],
                                        evidence: SensorEvidence, reference: String) -> [SensorTemperatureGroup] {
        keys.enumerated().map { index, key in
            group("\(metric.rawValue)-\(index)", metric, keys: [key], evidence: evidence, reference: reference)
        }
    }

    private static func plan(_ metric: SensorMetric, _ groups: [SensorTemperatureGroup],
                             fallback: [SensorTemperatureGroup] = [],
                             evidence: SensorEvidence, notes: String) -> SensorTemperaturePlan {
        SensorTemperaturePlan(metric: metric, groups: groups, fallbackGroups: fallback,
                              evidence: evidence, notes: notes)
    }

    // MARK: - Intel

    private static func intel(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let hex = (0...15).map { String($0, radix: 16, uppercase: true) }
        let cpuKeys = hex.map { "TC\($0)C" } + hex.map { "TC\($0)c" }
        let cpu = plan(.cpuCore,
                       singleKeyGroups(.cpuCore, keys: cpuKeys,
                                       evidence: .communityMapped,
                                       reference: "Stats TC%C/TC%c Intel core-die keys"),
                       fallback: [group("intel-package-fallback", .cpuCluster,
                                        keys: ["TCAD", "TC0D", "TC0E", "TC0F"],
                                        evidence: .candidate,
                                        reference: "Intel package/diode fallback; first readable only",
                                        aggregation: .firstReadable)],
                       evidence: .communityMapped,
                       notes: "Intel keeps the existing core-die mapping; package/diode is used only when no core key answers.")
        let gpu = plan(.gpuCore,
                       singleKeyGroups(.gpuCore, keys: ["TCGC", "TG0D", "TGDD"],
                                       evidence: .communityMapped,
                                       reference: "Stats Intel iGPU / discrete GPU diode"),
                       evidence: .communityMapped,
                       notes: "Intel GPU types differ; the three community keys are probed independently.")
        return SensorCapabilityCatalog(identity: identity, cpuPlan: cpu, gpuPlan: gpu,
                                       batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"])
    }

    // MARK: - M1

    private static func m1(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let cpuKeys = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        let gpuKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore,
                          singleKeyGroups(.cpuCore, keys: cpuKeys, evidence: .communityMapped,
                                          reference: "Stats M1 CPU core table; M1 base HID fallback verified"),
                          evidence: .communityMapped,
                          notes: "Base M1 keeps the HID fallback. M1 Pro/Max/Ultra use the same SMC keys."),
            gpuPlan: plan(.gpuCore,
                          singleKeyGroups(.gpuCore, keys: gpuKeys, evidence: .communityMapped,
                                          reference: "Stats M1 GPU cluster table"),
                          evidence: .communityMapped,
                          notes: "Four GPU cluster probes; no M1 Ultra die-2 keys are included."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - M2

    private static func m2(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let cpuKeys = ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D",
                       "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        let gpuKeys = ["Tg0f", "Tg0j"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore,
                          singleKeyGroups(.cpuCore, keys: cpuKeys, evidence: .candidate,
                                          reference: "Existing Stats-derived M2 table; base vs Pro/Max layout differs"),
                          evidence: .candidate,
                          notes: "Kept unchanged to avoid a regression on working M2 Macs; base M2 P/E layout still needs a loaded dump."),
            gpuPlan: plan(.gpuCore,
                          singleKeyGroups(.gpuCore, keys: gpuKeys, evidence: .candidate,
                                          reference: "Existing two-key M2 GPU mapping"),
                          evidence: .candidate,
                          notes: "Only two GPU probes are mapped; this is not a claim of full M2 GPU coverage."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - M3

    private static func m3Base(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        // The M3 Air (Mac15,12) exposes Te05 but none of the Tf14/Tf18/... GPU
        // keys. The twelve Tg* keys below are the owner's verified-readable set,
        // grouped as six probe pairs so the average is six GPU zones, not twelve.
        let gpuPairs: [(String, [String])] = [
            ("gpu-0O-0P", ["Tg0O", "Tg0P"]),
            ("gpu-0C-0D", ["Tg0C", "Tg0D"]),
            ("gpu-0W-0X", ["Tg0W", "Tg0X"]),
            ("gpu-0a-0b", ["Tg0a", "Tg0b"]),
            ("gpu-0i-0j", ["Tg0i", "Tg0j"]),
            ("gpu-0u-0v", ["Tg0u", "Tg0v"])
        ]
        let gpuGroups = gpuPairs.map { id, keys in
            group(id, .gpuCluster, keys: keys, evidence: .communityMapped,
                  reference: "Mac15,12 M3 Air owner dump: all 12 Tg* readable, second probe +4.40 °C; pair representative not load-verified")
        }
        let cpuKeys = ["Te05", "Te0L", "Te0P", "Te0S",
                       "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                       "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore,
                          singleKeyGroups(.cpuCore, keys: cpuKeys, evidence: .candidate,
                                          reference: "Existing M3 CPU table; Te05 verified on Mac15,12"),
                          evidence: .candidate,
                          notes: "On Mac15,12 only Te05 has been confirmed; the Tf* CPU fabric keys may be absent. The M3 base Tp* P-core layout is documented by iSMC but not loaded-tested here."),
            gpuPlan: plan(.gpuCluster, gpuGroups, evidence: .communityMapped,
                          notes: "Six Tg* probe pairs from the M3 Air dump; each pair is one GPU zone. Readability is measured, but which probe best represents the zone still needs a loaded comparison. Tf14/Tf18/Tf19/Tf1A/Tf24/Tf28/Tf29/Tf2A are KEY_INFO_FAILED on this SKU and are not probed."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    private static func m3ProMax(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let cpuKeys = ["Te05", "Te0L", "Te0P", "Te0S",
                       "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                       "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        let gpuKeys = ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        // M3 Max Mac15,9 measured Tf04/Tf14 as flt and working. Keep Tf* as the
        // primary path; the iSMC Tg* pairs are a fallback for SKUs that do not
        // expose the fabric keys.
        let fallbackPairs = [
            group("gpu-fallback-0C-0D", .gpuCluster, keys: ["Tg0C", "Tg0D"],
                  evidence: .communityMapped, reference: "iSMC M3 GPU pairs"),
            group("gpu-fallback-0K-0L", .gpuCluster, keys: ["Tg0K", "Tg0L"],
                  evidence: .communityMapped, reference: "iSMC M3 GPU pairs"),
            group("gpu-fallback-0U-0V", .gpuCluster, keys: ["Tg0U", "Tg0V"],
                  evidence: .communityMapped, reference: "iSMC M3 Pro GPU pairs"),
            group("gpu-fallback-0u-0v", .gpuCluster, keys: ["Tg0u", "Tg0v"],
                  evidence: .communityMapped, reference: "iSMC M3 Pro GPU pairs")
        ]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore,
                          singleKeyGroups(.cpuCore, keys: cpuKeys, evidence: .communityMapped,
                                          reference: "Existing M3 Pro/Max CPU table; Mac15,9 measured Te05/Tf04"),
                          evidence: .communityMapped,
                          notes: "Independent from M3 base; Tf* fabric keys are the primary path on Pro/Max."),
            gpuPlan: plan(.gpuCluster,
                          singleKeyGroups(.gpuCluster, keys: gpuKeys, evidence: .communityMapped,
                                          reference: "Existing M3 Pro/Max Tf* GPU table; Mac15,9 measured Tf14"),
                          fallback: fallbackPairs,
                          evidence: .communityMapped,
                          notes: "Tf* stays primary because Mac15,9 measured it. Tg* pairs are consulted only if no Tf* key answers."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - M4

    private static func m4(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        // Exact production set carried over from the pre-catalog reader. Changing
        // it would risk a regression on working M4 Macs without a loaded dump.
        let cpuKeys = ["Te05", "Te0S", "Te09", "Te0H",
                       "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        let gpuKeys = ["Tg0G", "Tg0H", "Tg0J", "Tg0K", "Tg0L", "Tg0T",
                       "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg1U", "Tg1k"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore,
                          singleKeyGroups(.cpuCore, keys: cpuKeys, evidence: .candidate,
                                          reference: "Existing M4 table; not re-verified on every SKU"),
                          evidence: .candidate,
                          notes: "Kept unchanged. M4 Pro 14-core uses a different Tp00-scheme; this table is the existing production set."),
            gpuPlan: plan(.gpuCore,
                          singleKeyGroups(.gpuCore, keys: gpuKeys, evidence: .candidate,
                                          reference: "Existing M4 GPU table"),
                          evidence: .candidate,
                          notes: "Twelve GPU probes; base M4 may expose fewer, which the capability cache records."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - M5

    private static func m5Base(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let superCores = ["Tp00", "Tp04", "Tp0C", "Tp0G"]
        let efficiency = ["Te04", "Te08", "Te0C", "Te0R"]
        let cpuGroups = superCores.enumerated().map { index, key in
            group("super-\(index)", .cpuCore, keys: [key], evidence: .communityMapped,
                  reference: "iSMC M5 base: four S-cores at Tp00/04/0C/0G")
        } + efficiency.enumerated().map { index, key in
            group("efficiency-\(index)", .cpuEfficiencyCluster, keys: [key], evidence: .communityMapped,
                  reference: "iSMC M5 base: four Te E-core slots")
        }
        // iSMC's loaded MacBook Air/Pro runs show Tp0O-Tp1E follow GPU, not a
        // CPU tier. They are deliberately absent from the CPU average.
        let gpuKeys = ["Tg04", "Tg0G", "Tg0K", "Tg0m", "Tg0p", "Tg1A", "Tg1g", "Tg1s"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore, cpuGroups, evidence: .communityMapped,
                          notes: "Four Super + four Efficiency cores. The former Tp0O-Tp1E probes are GPU-following and are not averaged as CPU cores."),
            gpuPlan: plan(.gpuCluster,
                          singleKeyGroups(.gpuCluster, keys: gpuKeys, evidence: .candidate,
                                          reference: "iSMC M5 base GPU slots Tg04...Tg1s"),
                          evidence: .candidate,
                          notes: "Base M5 GPU slots; single-key scheme, no core count claimed."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    private static func m5ProMax(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let superTriplets: [(String, [String])] = [
            ("super-0", ["Tp00", "Tp04", "Tp08"]),
            ("super-1", ["Tp0C", "Tp0G", "Tp0K"]),
            ("super-2", ["Tp0O", "Tp0R", "Tp0U"]),
            ("super-3", ["Tp0X", "Tp0a", "Tp0d"]),
            ("super-4", ["Tp0g", "Tp0j", "Tp0m"]),
            ("super-5", ["Tp0p", "Tp0u", "Tp0y"])
        ]
        let superGroups = superTriplets.map { id, keys in
            group(id, .cpuCore, keys: keys, evidence: .communityMapped,
                  reference: "iSMC M5 Pro/Max: six Super-core triplets; third key hottest")
        }
        // The 12 P-cores are covered by two 19-probe clusters; which probe maps
        // to which core is unresolved. Use a spread subset per cluster and
        // aggregate the cluster, never the individual probes.
        let performanceGroups = [
            group("performance-0", .cpuPerformanceCluster,
                  keys: ["Tm00", "Tm0G", "Tm0X", "Tm1I"], evidence: .candidate,
                  reference: "iSMC M5 Pro/Max P cluster 1; probe-to-core unresolved"),
            group("performance-1", .cpuPerformanceCluster,
                  keys: ["Tm1M", "Tm1Y", "Tm21", "Tm2j"], evidence: .candidate,
                  reference: "iSMC M5 Pro/Max P cluster 2; probe-to-core unresolved")
        ]
        let gpuKeys = ["Tg08", "Tg0C", "Tg0O", "Tg0R", "Tg0U", "Tg0X", "Tg0a", "Tg0d"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore, superGroups + performanceGroups, evidence: .candidate,
                          notes: "Six Super-core groups plus two P-cluster groups. Tp1E-1g are P-cluster aggregates and are not averaged as Super cores."),
            gpuPlan: plan(.gpuCluster,
                          singleKeyGroups(.gpuCluster, keys: gpuKeys, evidence: .candidate,
                                          reference: "iSMC M5 Pro/Max GPU slots Tg08...Tg0d"),
                          evidence: .candidate,
                          notes: "Pro/Max GPU slots are disjoint from base M5; the base list is not reused."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - M6

    private static func m6(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let superGroups = [
            group("super-0", .cpuCore, keys: ["Tp07", "Tp09"], evidence: .communityMapped,
                  reference: "iSMC M6: two probes per Super core"),
            group("super-1", .cpuCore, keys: ["Tp0j", "Tp0g"], evidence: .communityMapped,
                  reference: "iSMC M6: two probes per Super core")
        ]
        let performanceGroups = [
            group("performance-0", .cpuCore, keys: ["Tp0I", "Tp0E"], evidence: .candidate,
                  reference: "iSMC M6 P-core pair; probe-to-core unresolved"),
            group("performance-1", .cpuCore, keys: ["Tp0L", "Tp0G"], evidence: .candidate,
                  reference: "iSMC M6 P-core pair; probe-to-core unresolved"),
            group("performance-2", .cpuCore, keys: ["Tp0d", "Tp05"], evidence: .candidate,
                  reference: "iSMC M6 P-core pair; probe-to-core unresolved"),
            group("performance-3", .cpuCore, keys: ["Tp0m", "Tp0b"], evidence: .candidate,
                  reference: "iSMC M6 P-core pair; probe-to-core unresolved")
        ]
        // Te07/08/09 are E-cluster probes, not per-core sensors; Te0c/0e/0f/0h/0i
        // and Ts00-Ts08 are SoC die probes and must not enter the CPU average.
        let efficiencyGroup = group("efficiency-cluster", .cpuEfficiencyCluster,
                                    keys: ["Te07", "Te08", "Te09"], evidence: .communityMapped,
                                    reference: "iSMC M6: E-cluster probes; no per-core E sensors")
        let gpuKeys = ["Tg01", "Tg07", "Tg08", "Tg09", "Tg0a", "Tg0b", "Tg0c", "Tg0d", "Tg10",
                       "Tg17", "Tg1a", "Tg1b", "Tg1c", "Tg1d", "Tg1e", "Tg1f", "Tg1g", "Tg1h"]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore, superGroups + performanceGroups + [efficiencyGroup],
                          evidence: .candidate,
                          notes: "2 Super + 4 Performance groups + one E-cluster group. SoC die probes are excluded from the CPU average."),
            gpuPlan: plan(.gpuCluster,
                          singleKeyGroups(.gpuCluster, keys: gpuKeys, evidence: .communityMapped,
                                          reference: "iSMC M6: 18 Tg* slots, one row per key"),
                          evidence: .communityMapped,
                          notes: "Single-key GPU slots, not 18 cores. TfC1/TfCD are SoC fabric and are not used."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - A18 Pro

    private static func a18Pro(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        let performanceGroups = [
            group("performance-0", .cpuCore, keys: ["Tp00", "Tp01", "Tp02"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro P-core triplet"),
            group("performance-1", .cpuCore, keys: ["Tp04", "Tp05", "Tp06"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro P-core triplet")
        ]
        let efficiencyGroups = [
            group("efficiency-0", .cpuEfficiencyCluster, keys: ["Te04", "Te05", "Te06"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro E-core triplet"),
            group("efficiency-1", .cpuEfficiencyCluster, keys: ["Te0R", "Te0S", "Te0T"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro E-core triplet"),
            group("efficiency-2", .cpuEfficiencyCluster, keys: ["Tp0l", "Tp0m", "Tp0n"], evidence: .candidate,
                  reference: "iSMC A18 Pro E-core Tp triplet"),
            group("efficiency-3", .cpuEfficiencyCluster, keys: ["Tp0o", "Tp0q", "Tp0t"], evidence: .candidate,
                  reference: "iSMC A18 Pro E-core Tp triplet")
        ]
        let gpuGroups = [
            group("gpu-0", .gpuCluster, keys: ["Tg04", "Tg05"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro GPU pair"),
            group("gpu-1", .gpuCluster, keys: ["Tg0C", "Tg0D"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro GPU pair"),
            group("gpu-2", .gpuCluster, keys: ["Tg0K", "Tg0L"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro GPU pair"),
            group("gpu-3", .gpuCluster, keys: ["Tg0d", "Tg0e"], evidence: .communityMapped,
                  reference: "iSMC A18 Pro GPU pair")
        ]
        return SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore, performanceGroups + efficiencyGroups, evidence: .communityMapped,
                          notes: "A18 Pro 2P+4E layout. Unknown A-series chips never inherit this plan."),
            gpuPlan: plan(.gpuCluster, gpuGroups, evidence: .communityMapped,
                          notes: "Four A18 Pro GPU probe pairs; PBwo is the expected backlight rail."),
            batteryTemperatureKeys: ["TB0T", "TB1T", "TB2T"]
        )
    }

    // MARK: - Unknown

    private static func unknown(_ identity: MachineIdentity) -> SensorCapabilityCatalog {
        SensorCapabilityCatalog(
            identity: identity,
            cpuPlan: plan(.cpuCore, [], evidence: .unsupported,
                          notes: "Unknown chip: no key is assumed to mean a temperature."),
            gpuPlan: plan(.gpuCore, [], evidence: .unsupported,
                          notes: "Unknown chip: no key is assumed to mean a temperature."),
            batteryTemperatureKeys: []
        )
    }
}

/// Caches which candidate keys actually answered. A key that failed is not
/// retried on every two-second tick; failures back off, and a wake/reset clears
/// the negative state so a transient SMC failure does not hide a sensor for the
/// rest of the session.
final class SensorCapabilityCache: @unchecked Sendable {
    struct Entry: Equatable, Sendable {
        var failures: Int = 0
        var nextProbeAt: Date = .distantPast
        var wasReadable: Bool = false
        var lastType: UInt32?
        var lastSuccessAt: Date?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let backoff: [TimeInterval]

    init(backoff: [TimeInterval] = [30, 120, 600, 1800, 3600]) {
        self.backoff = backoff
    }

    func shouldProbe(_ key: String, at now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return true }
        if entry.wasReadable { return true }
        return now >= entry.nextProbeAt
    }

    func record(_ key: String, value: Double?, type: UInt32? = nil, at now: Date) {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[key] ?? Entry()
        if value != nil {
            entry.failures = 0
            entry.wasReadable = true
            entry.nextProbeAt = .distantPast
            entry.lastSuccessAt = now
            if let type { entry.lastType = type }
        } else {
            entry.failures += 1
            let delay: TimeInterval
            if backoff.isEmpty {
                delay = 60
            } else {
                delay = backoff[min(entry.failures - 1, backoff.count - 1)]
            }
            entry.nextProbeAt = now.addingTimeInterval(delay)
        }
        entries[key] = entry
    }

    func reset() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func entry(for key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    /// Number of keys whose last probe failed. Used by tests and diagnostics,
    /// not by the sampling path.
    var unavailableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.filter { !$0.wasReadable && $0.failures > 0 }.count
    }
}
