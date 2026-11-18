import Darwin
import Foundation
import IOKit

/// The class of a logical CPU as reported by the platform's core topology.
///
/// The model is intentionally extensible: Apple Silicon can expose a third
/// ("super") core class on newer generations, and any class we cannot identify
/// stays `.unknown` rather than being folded into performance cores.
enum CPUCoreKind: String, Equatable, Sendable {
    case efficiency
    case performance
    case superCore
    /// A clustered class newer than the ones we name today.
    case other
    case unknown
}

/// Logical-core topology, index-aligned to the core order returned by
/// `host_processor_info`. The index is the numeric suffix of the IORegistry
/// `cpuN` node, which is the same logical-CPU order the Mach host API uses.
struct CPUCoreTopology: Equatable, Sendable {
    let kinds: [CPUCoreKind]
    /// Diagnostic provenance, e.g. "ioreg.AppleARMPE".
    let source: String

    init(kinds: [CPUCoreKind], source: String = "ioreg.AppleARMPE") {
        self.kinds = kinds
        self.source = source
    }

    var efficiencyCoreCount: Int { kinds.filter { $0 == .efficiency }.count }
    var performanceCoreCount: Int { kinds.filter { $0 == .performance }.count }
    var superCoreCount: Int { kinds.filter { $0 == .superCore }.count }
    var otherCoreCount: Int { kinds.filter { $0 == .other }.count }
    /// True when at least one core was positively classified. A topology made
    /// only of `.unknown` is not usable and must be treated as unavailable.
    var isRecognized: Bool { kinds.contains { $0 != .unknown } }
}

/// Per-group average utilisation derived from `CPUCoreTopology`. A missing
/// group (no cores of that class, or no usable topology) stays `nil`; it is
/// never inferred from core counts.
struct CPUCoreGroupUsage: Equatable, Sendable {
    var efficiencyAverage: Double?
    var performanceAverage: Double?
    var superAverage: Double?
    var otherAverage: Double?

    var hasAny: Bool {
        efficiencyAverage != nil || performanceAverage != nil || superAverage != nil || otherAverage != nil || superAverage != nil
    }
}

/// Aggregate CPU time split. Values are percentages that sum to ~100 for a
/// single sample window (subject to per-counter wrap handling).
struct CPUTimeBreakdown: Equatable, Sendable {
    var user: Double
    var system: Double
    var idle: Double
    var nice: Double

    static let zero = Self(user: 0, system: 0, idle: 0, nice: 0)
}

struct CPUReading: Equatable, Sendable {
    /// Percent, 0...100. Aggregated by elapsed ticks, not by averaging cores.
    let usage: Double
    let perCoreUsage: [Double]
    let sampledAt: Date
    /// User/System/Idle/Nice split over the same tick window as `usage`.
    let breakdown: CPUTimeBreakdown
    /// Resolved core topology, or `nil` on Intel / unrecognised hardware.
    let topology: CPUCoreTopology?
    /// E/P/Super grouped averages, or `nil` when the topology is unusable.
    let groupUsage: CPUCoreGroupUsage?

    init(usage: Double, perCoreUsage: [Double], sampledAt: Date,
         breakdown: CPUTimeBreakdown = .zero,
         topology: CPUCoreTopology? = nil,
         groupUsage: CPUCoreGroupUsage? = nil) {
        self.usage = usage
        self.perCoreUsage = perCoreUsage
        self.sampledAt = sampledAt
        self.breakdown = breakdown
        self.topology = topology
        self.groupUsage = groupUsage
    }
}

struct CPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

/// Value state owned by the service's serial sampling queue.
struct CPUReader: Sendable {
    private var previous: [CPUTicks]?
    private var previousAt: Date?
    private var cachedTopology: CPUCoreTopology?
    private var cachedCoreCount: Int = -1

    mutating func reset() {
        previous = nil
        previousAt = nil
    }

    mutating func read(at date: Date = Date()) -> CPUReading? {
        guard let ticks = Self.readTicks() else {
            reset()
            return nil
        }
        return sample(ticks, at: date, topology: topology(for: ticks.count))
    }

    /// Pure differential seam; preserves each 32-bit counter until after wrap
    /// handling. Long gaps (including sleep) and resets establish a new baseline.
    ///
    /// `topology` is injected so the pure path (tests) never touches IOKit. When
    /// it is not index-aligned to `ticks`, grouping is left unavailable rather
    /// than guessed.
    mutating func sample(_ ticks: [CPUTicks], at date: Date,
                         topology: CPUCoreTopology? = nil) -> CPUReading? {
        let old = previous
        let oldAt = previousAt
        defer {
            previous = ticks.isEmpty ? nil : ticks
            previousAt = ticks.isEmpty ? nil : date
        }
        guard !ticks.isEmpty, let old, let oldAt, old.count == ticks.count,
              date.timeIntervalSince(oldAt) > 0, date.timeIntervalSince(oldAt) <= 15 else { return nil }
        var totalBusy: UInt64 = 0
        var totalTicks: UInt64 = 0
        var aggregateUser: UInt64 = 0
        var aggregateSystem: UInt64 = 0
        var aggregateIdle: UInt64 = 0
        var aggregateNice: UInt64 = 0
        var cores: [Double] = []
        for (current, prior) in zip(ticks, old) {
            guard let user = Self.delta(current.user, prior.user),
                  let system = Self.delta(current.system, prior.system),
                  let idle = Self.delta(current.idle, prior.idle),
                  let nice = Self.delta(current.nice, prior.nice) else { return nil }
            let busy = user + system + nice
            let total = busy + idle
            // No ticks is not a measured 0%. Rebaseline the entire frame.
            guard total > 0 else { return nil }
            cores.append(Double(busy) / Double(total) * 100)
            totalBusy += busy
            totalTicks += total
            aggregateUser += user
            aggregateSystem += system
            aggregateIdle += idle
            aggregateNice += nice
        }
        guard totalTicks > 0 else { return nil }
        let axis = Double(totalTicks)
        let breakdown = CPUTimeBreakdown(
            user: Double(aggregateUser) / axis * 100,
            system: Double(aggregateSystem) / axis * 100,
            idle: Double(aggregateIdle) / axis * 100,
            nice: Double(aggregateNice) / axis * 100
        )
        return CPUReading(usage: Double(totalBusy) / axis * 100,
                          perCoreUsage: cores,
                          sampledAt: date,
                          breakdown: breakdown,
                          topology: topology,
                          groupUsage: Self.groupUsage(cores: cores, topology: topology))
    }

    /// Averages per-core utilisation by class. Only a topology whose kind list
    /// is exactly index-aligned to `cores` is used; anything else is unavailable.
    static func groupUsage(cores: [Double], topology: CPUCoreTopology?) -> CPUCoreGroupUsage? {
        guard let topology, topology.isRecognized, topology.kinds.count == cores.count,
              !cores.isEmpty else { return nil }
        var eSum = 0.0, eCount = 0
        var pSum = 0.0, pCount = 0
        var sSum = 0.0, sCount = 0
        var oSum = 0.0, oCount = 0
        for (index, core) in cores.enumerated() {
            switch topology.kinds[index] {
            case .efficiency:
                eSum += core; eCount += 1
            case .performance:
                pSum += core; pCount += 1
            case .superCore:
                sSum += core; sCount += 1
            case .other:
                oSum += core; oCount += 1
            case .unknown:
                continue
            }
        }
        let group = CPUCoreGroupUsage(
            efficiencyAverage: eCount > 0 ? eSum / Double(eCount) : nil,
            performanceAverage: pCount > 0 ? pSum / Double(pCount) : nil,
            superAverage: sCount > 0 ? sSum / Double(sCount) : nil,
            otherAverage: oCount > 0 ? oSum / Double(oCount) : nil
        )
        return group.hasAny ? group : nil
    }

    private mutating func topology(for coreCount: Int) -> CPUCoreTopology? {
        if let cachedTopology, cachedCoreCount == coreCount { return cachedTopology }
        let resolved = Self.resolveTopology(coreCount: coreCount)
        cachedTopology = resolved
        cachedCoreCount = coreCount
        return resolved
    }

    /// Reads the Apple Silicon core topology from IORegistry. Returns `nil`
    /// when `AppleARMPE` is absent (Intel) or the core set does not match the
    /// enumerated logical-core count; the caller then shows unavailable grouping.
    static func resolveTopology(coreCount: Int) -> CPUCoreTopology? {
        guard coreCount > 0 else { return nil }
        var iterator = io_iterator_t(0)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMPE"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var kinds: [Int: CPUCoreKind] = [:]
        var service = io_iterator_t(0)
        while true {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            var childIterator = io_iterator_t(0)
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == KERN_SUCCESS {
                var child = io_iterator_t(0)
                while true {
                    child = IOIteratorNext(childIterator)
                    guard child != 0 else { break }
                    let name = Self.ioName(child)
                    if name.hasPrefix("cpu"), let index = Int(name.dropFirst(3)), index >= 0, index < coreCount {
                        if let props = Self.ioProperties(child),
                           let data = props["cluster-type"] as? Data,
                           let raw = String(data: data, encoding: .utf8)?
                               .trimmingCharacters(in: .whitespacesAndNewlines) {
                            kinds[index] = Self.coreKind(fromClusterType: raw)
                        }
                    }
                    IOObjectRelease(child)
                }
                IOObjectRelease(childIterator)
            }
            IOObjectRelease(service)
        }
        // Require a complete, index-aligned mapping. A partial map (some cores
        // missing) is not trustworthy, so grouping stays unavailable.
        guard kinds.count == coreCount else { return nil }
        let aligned = (0..<coreCount).map { kinds[$0] ?? .unknown }
        let topology = CPUCoreTopology(kinds: aligned)
        return topology.isRecognized ? topology : nil
    }

    /// Maps the IORegistry `cluster-type` token to a core class. "E" is
    /// efficiency and "P" is performance on M1–M4. "M" (M5+ performance) maps to
    /// performance. Any other non-empty token ("S" today, a future class
    /// tomorrow) is reported as a super core rather than folded into P-cores or
    /// dropped, so the most powerful extra class still gets its own card.
    static func coreKind(fromClusterType raw: String) -> CPUCoreKind {
        // The IORegistry value is a fixed-width buffer and can carry a trailing
        // NUL; strip NULs and surrounding whitespace before matching.
        let token = raw
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        switch token {
        case "E": return .efficiency
        case "P": return .performance
        case "M": return .performance
        case "S": return .superCore
        default: return token.isEmpty ? .unknown : .other
        }
    }

    private static func ioName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ioProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    private static func delta(_ current: UInt32, _ previous: UInt32) -> UInt64? {
        if current >= previous { return UInt64(current - previous) }
        // Only a counter close to UInt32.max rolling over near zero is a wrap.
        // An ordinary backwards jump is a reset, never a huge utilization delta.
        guard previous >= 0xf000_0000, current <= 0x0fff_ffff else { return nil }
        return UInt64(current &- previous)
    }

    private static func readTicks() -> [CPUTicks]? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            // infoCount is integer_t elements, NOT logical-core count.
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        let stride = Int(CPU_STATE_MAX)
        guard count > 0, Int(infoCount) >= Int(count) * stride else { return nil }
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(count))
        for core in 0..<Int(count) {
            let base = core * stride
            ticks.append(CPUTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                  system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                  idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                  nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        return ticks
    }
}
