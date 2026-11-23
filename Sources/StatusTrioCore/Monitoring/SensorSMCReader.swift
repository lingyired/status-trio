import Foundation
import Darwin

struct FanReading: Equatable, Sendable {
    let index: Int
    let rpm: Double?
    let minRPM: Double?
    let maxRPM: Double?
    var name: String? = nil
}

enum CPUTemperatureSource: Equatable, Sendable {
    case single
    case average(Int)
}

struct SensorReading: Equatable, Sendable {
    var cpuTemperature: Double?
    var cpuTemperatureSource: CPUTemperatureSource?
    var gpuTemperature: Double?
    /// Battery pack temperature (°C) from the TB*T keys, when present.
    var batteryTemperature: Double? = nil
    var fans: [FanReading]
    /// nil: unreadable/unknown; 0: explicitly fanless.
    var fanCount: Int?
    let sampledAt: Date
    /// Where each on-die temperature actually came from. Defaults to SMC so the
    /// existing SMC-only path and its tests are unchanged.
    var cpuTemperatureOrigin: HardwareMetricSource = .smc
    var gpuTemperatureOrigin: HardwareMetricSource = .smc

    var cpuTemperatureCount: Int {
        switch cpuTemperatureSource {
        case .single: return 1
        case .average(let count): return count
        case nil: return 0
        }
    }

    var cpuTemperatureLabel: String? {
        let hid = cpuTemperatureOrigin == .hid
        switch cpuTemperatureSource {
        case .single: return hid ? "CPU HID sensor" : "CPU sensor"
        case .average: return hid ? "CPU HID average" : "CPU average"
        case nil: return nil
        }
    }

    /// GPU samples have no count type, but the label still records whether the
    /// reading was aggregated from the HID fallback.
    var gpuTemperatureLabel: String {
        gpuTemperatureOrigin == .hid ? "GPU HID" : "GPU area"
    }
}

enum SensorPlatform: Equatable, Sendable {
    case intel
    case appleSilicon(String)
    case unknown

    static func current() -> Self {
        #if arch(x86_64)
        return .intel
        #elseif arch(arm64)
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 0, size < 256 else { return .unknown }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return .unknown }
        // Truncate at NUL and decode UTF-8 rather than String(cString:), which
        // is deprecated. A failed or short read never fabricates a chip name.
        guard let terminator = bytes.firstIndex(of: 0), terminator > 0 else { return .unknown }
        let name = String(decoding: bytes[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if name.hasPrefix("Apple M") || name.hasPrefix("Apple A18") {
            return .appleSilicon(name)
        }
        return .unknown
        #else
        return .unknown
        #endif
    }
}

/// Fixed, conservative community mappings behind `SensorCapabilityCatalog`.
/// A mapped key is still capability-probed; the catalog records whether a key is
/// measured, community-mapped, or only a candidate. M3 Max/Mac15,9 and M3
/// Air/Mac15,12 have local evidence; other machines are not runtime-certified.
struct SensorSMCReader: Sendable {
    /// Battery pack temperature keys; present on Apple Silicon (all flt here) and
    /// most Intel Macs. Probed on demand, never scanned.
    static let batteryTemperatureKeys = ["TB0T", "TB1T", "TB2T"]

    private let platform: SensorPlatform
    private let modelIdentifier: String?
    private let cache: SensorCapabilityCache

    init() {
        platform = .current()
        modelIdentifier = MachineIdentity.currentModelIdentifier()
        cache = SensorCapabilityCache()
    }

    init(platform: SensorPlatform, modelIdentifier: String? = nil,
         cache: SensorCapabilityCache = SensorCapabilityCache()) {
        self.platform = platform
        self.modelIdentifier = modelIdentifier
        self.cache = cache
    }

    var machineIdentity: MachineIdentity {
        MachineIdentity(platform: platform, modelIdentifier: modelIdentifier)
    }

    /// Clears the negative capability cache after sleep/wake or a reader reset.
    /// Positive entries are cheap to re-confirm; stale negative entries are not.
    func resetCapabilities() {
        cache.reset()
    }

    func read(includeTemperature: Bool, includeGPUTemperature: Bool = false,
              includeBatteryTemperature: Bool = false,
              includeFans: Bool, at date: Date = Date()) -> SensorReading {
        guard includeTemperature || includeGPUTemperature || includeBatteryTemperature || includeFans else {
            return Self.read(platform: platform, modelIdentifier: modelIdentifier,
                             includeTemperature: false, includeFans: false, at: date,
                             cache: cache) { _ in nil }
        }
        return SMCReadOnlyClient.withConnection { exchange in
            Self.read(platform: platform, modelIdentifier: modelIdentifier,
                      includeTemperature: includeTemperature,
                      includeGPUTemperature: includeGPUTemperature,
                      includeBatteryTemperature: includeBatteryTemperature,
                      includeFans: includeFans,
                      at: date, cache: cache, nameProvider: { key in
                guard let code = SMCReadOnlyClient.key(key),
                      let data = SMCReadOnlyClient.read(key: code, exchange: exchange) else { return nil }
                // F0ID is a {fds fan descriptor on some Macs and plain text on
                // others; keep the longest printable run so binary headers can
                // never leak into a displayed name.
                let run = data.payload.split(whereSeparator: { $0 < 0x20 || $0 > 0x7e })
                    .max(by: { $0.count < $1.count })
                guard let run, run.count >= 2 else { return nil }
                return String(decoding: run, as: UTF8.self)
            }, valueProvider: { key in
                guard let code = SMCReadOnlyClient.key(key) else { return nil }
                return SMCReadOnlyClient.readValue(key: code, exchange: exchange)
            })
        } ?? Self.read(platform: platform, modelIdentifier: modelIdentifier,
                       includeTemperature: false, includeFans: false, at: date,
                       cache: cache) { _ in nil }
    }

    static func read(platform: SensorPlatform, modelIdentifier: String? = nil,
                     includeTemperature: Bool,
                     includeGPUTemperature: Bool = false, includeBatteryTemperature: Bool = false,
                     includeFans: Bool, at date: Date,
                     cache: SensorCapabilityCache? = nil,
                     nameProvider: (String) -> String? = { _ in nil },
                     valueProvider: (String) -> Double?) -> SensorReading {
        let identity = MachineIdentity(platform: platform, modelIdentifier: modelIdentifier)
        let catalog = SensorCapabilityCatalog.catalog(for: identity)
        var cpuValues: [Double] = []
        var gpuValues: [Double] = []
        if includeTemperature {
            cpuValues = read(plan: catalog.cpuPlan, at: date, cache: cache, valueProvider: valueProvider)
        }
        if includeGPUTemperature {
            gpuValues = read(plan: catalog.gpuPlan, at: date, cache: cache, valueProvider: valueProvider)
        }
        var batteryValues: [Double] = []
        if includeBatteryTemperature {
            batteryValues = catalog.batteryTemperatureKeys.compactMap { key in
                guard cache?.shouldProbe(key, at: date) ?? true else { return nil }
                let value = validTemperature(valueProvider(key))
                cache?.record(key, value: value, at: date)
                return value
            }
        }
        var fans: [FanReading] = []
        var fanCount: Int?
        if includeFans, let count = valueProvider("FNum"), count.isFinite,
           (0...9).contains(count), count.rounded(.towardZero) == count {
            fanCount = Int(count)
            for index in 0..<Int(count) {
                let prefix = "F\(String(index, radix: 16, uppercase: true))"
                // A transient SMC contention can return a false zero; confirm a
                // zero with a second read before reporting a stopped fan.
                var rpm = validRPM(valueProvider(prefix + "Ac"), allowZero: true)
                if rpm == 0 {
                    rpm = validRPM(valueProvider(prefix + "Ac"), allowZero: true)
                }
                let min = validRPM(valueProvider(prefix + "Mn"), allowZero: true)
                let max = validRPM(valueProvider(prefix + "Mx"), allowZero: false)
                fans.append(FanReading(index: index, rpm: rpm, minRPM: min,
                                       maxRPM: max, name: nameProvider(prefix + "ID")))
            }
        }
        let source: CPUTemperatureSource?
        if cpuValues.isEmpty {
            source = nil
        } else if cpuValues.count == 1 {
            source = .single
        } else {
            source = .average(cpuValues.count)
        }
        return SensorReading(cpuTemperature: average(cpuValues), cpuTemperatureSource: source,
                             gpuTemperature: average(gpuValues),
                             batteryTemperature: average(batteryValues), fans: fans,
                             fanCount: fanCount, sampledAt: date)
    }

    /// Reads each group, averages the readable probes inside it, then returns one
    /// representative per group. This is the single place that prevents two
    /// probes for one physical core from counting as two cores.
    private static func read(plan: SensorTemperaturePlan, at date: Date,
                             cache: SensorCapabilityCache?,
                             valueProvider: (String) -> Double?) -> [Double] {
        let primary = representatives(of: plan.groups, at: date, cache: cache,
                                      valueProvider: valueProvider)
        guard primary.isEmpty else { return primary }
        return representatives(of: plan.fallbackGroups, at: date, cache: cache,
                               valueProvider: valueProvider)
    }

    private static func representatives(of groups: [SensorTemperatureGroup], at date: Date,
                                        cache: SensorCapabilityCache?,
                                        valueProvider: (String) -> Double?) -> [Double] {
        groups.compactMap { group in
            var values: [Double] = []
            for definition in group.definitions {
                guard cache?.shouldProbe(definition.key, at: date) ?? true else { continue }
                let value = validTemperature(valueProvider(definition.key))
                    .flatMap { definition.validRange.contains($0) ? $0 : nil }
                cache?.record(definition.key, value: value, at: date)
                if let value { values.append(value) }
            }
            return group.representative(from: values)
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func validTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 150 else { return nil }
        return value
    }

    private static func validRPM(_ value: Double?, allowZero: Bool) -> Double? {
        guard let value, value.isFinite, value >= 0,
              allowZero || value > 0 else { return nil }
        return value
    }
}
