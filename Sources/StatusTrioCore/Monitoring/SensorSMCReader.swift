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
    let cpuTemperature: Double?
    let cpuTemperatureSource: CPUTemperatureSource?
    let gpuTemperature: Double?
    /// Battery pack temperature (°C) from the TB*T keys, when present.
    var batteryTemperature: Double? = nil
    let fans: [FanReading]
    /// nil: unreadable/unknown; 0: explicitly fanless.
    let fanCount: Int?
    let sampledAt: Date

    var cpuTemperatureCount: Int {
        switch cpuTemperatureSource {
        case .single: return 1
        case .average(let count): return count
        case nil: return 0
        }
    }

    var cpuTemperatureLabel: String? {
        switch cpuTemperatureSource {
        case .single: return "CPU sensor"
        case .average: return "CPU average"
        case nil: return nil
        }
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
        return name.hasPrefix("Apple M") ? .appleSilicon(name) : .unknown
        #else
        return .unknown
        #endif
    }
}

/// Fixed, conservative community mappings, checked against Stats' sensor table:
/// https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
/// A mapped key is still capability-probed on every read. M3 Max/Mac15,9 was
/// measured locally; these tables are not runtime certification of other Macs.
struct SensorSMCReader: Sendable {
    /// Battery pack temperature keys; present on Apple Silicon (all flt here) and
    /// most Intel Macs. Probed on every read, never scanned.
    static let batteryTemperatureKeys = ["TB0T", "TB1T", "TB2T"]

    private let platform: SensorPlatform

    init() {
        platform = .current()
    }

    func read(includeTemperature: Bool, includeGPUTemperature: Bool = false,
              includeBatteryTemperature: Bool = false,
              includeFans: Bool, at date: Date = Date()) -> SensorReading {
        guard includeTemperature || includeGPUTemperature || includeBatteryTemperature || includeFans else {
            return Self.read(platform: platform, includeTemperature: false, includeFans: false, at: date) { _ in nil }
        }
        return SMCReadOnlyClient.withConnection { exchange in
            Self.read(platform: platform, includeTemperature: includeTemperature,
                      includeGPUTemperature: includeGPUTemperature,
                      includeBatteryTemperature: includeBatteryTemperature,
                      includeFans: includeFans,
                      at: date, nameProvider: { key in
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
        } ?? Self.read(platform: platform, includeTemperature: false, includeFans: false, at: date) { _ in nil }
    }

    static func read(platform: SensorPlatform, includeTemperature: Bool,
                     includeGPUTemperature: Bool = false, includeBatteryTemperature: Bool = false,
                     includeFans: Bool, at date: Date,
                     nameProvider: (String) -> String? = { _ in nil },
                     valueProvider: (String) -> Double?) -> SensorReading {
        var cpuValues: [Double] = []
        var gpuValues: [Double] = []
        let keys = includeTemperature || includeGPUTemperature ? temperatureKeys(for: platform) : (cpu: [], gpu: [])
        if includeTemperature {
            cpuValues = keys.cpu.compactMap { validTemperature(valueProvider($0)) }
            // Intel package/diode fallback is used only when no core die exists;
            // never average proximity, battery, heatsink or ambient sensors.
            if cpuValues.isEmpty, platform == .intel {
                for key in ["TCAD", "TC0D", "TC0E", "TC0F"] {
                    if let value = validTemperature(valueProvider(key)) {
                        cpuValues = [value]
                        break
                    }
                }
            }
        }
        if includeGPUTemperature {
            gpuValues = keys.gpu.compactMap { validTemperature(valueProvider($0)) }
        }
        var batteryValues: [Double] = []
        if includeBatteryTemperature {
            batteryValues = Self.batteryTemperatureKeys.compactMap { validTemperature(valueProvider($0)) }
        }
        var fans: [FanReading] = []
        var fanCount: Int?
        if includeFans, let count = valueProvider("FNum"), count.isFinite,
           (0...9).contains(count), count.rounded(.towardZero) == count {
            fanCount = Int(count)
            for index in 0..<Int(count) {
                let prefix = "F\(String(index, radix: 16, uppercase: true))"
                let rpm = validRPM(valueProvider(prefix + "Ac"), allowZero: true)
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

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func validTemperature(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 150 else { return nil }
        return value
    }

    private static func validRPM(_ value: Double?, allowZero: Bool) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 30_000,
              allowZero || value > 0 else { return nil }
        return value
    }

    private static func temperatureKeys(for platform: SensorPlatform) -> (cpu: [String], gpu: [String]) {
        switch platform {
        case .intel:
            return ((0...9).map { "TC\($0)C" } + (0...9).map { "TC\($0)c" } + ["TCAC", "TCBC"],
                    ["TCGC", "TG0D", "TGDD"])
        case .appleSilicon(let chip):
            // Exact brand names prevent an unknown future generation from
            // silently inheriting sensor meanings from a different chip.
            switch chip {
            case "Apple M1", "Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra":
                return (["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
                        ["Tg05", "Tg0D", "Tg0L", "Tg0T"])
            case "Apple M2", "Apple M2 Pro", "Apple M2 Max", "Apple M2 Ultra":
                return (["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
                        ["Tg0f", "Tg0j"])
            case "Apple M3", "Apple M3 Pro", "Apple M3 Max", "Apple M3 Ultra":
                return (["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
                        ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"])
            case "Apple M4", "Apple M4 Pro", "Apple M4 Max":
                // M4 base and Pro/Max share the CPU mapping; GPU keys differ by
                // variant, and unmapped keys simply fail their capability probe.
                let gpu = ["Tg0G", "Tg0H", "Tg0J", "Tg0K", "Tg0L", "Tg0T",
                           "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg1U", "Tg1k"]
                return (["Te05", "Te0S", "Te09", "Te0H",
                         "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
                        gpu)
            default:
                return ([], [])
            }
        case .unknown:
            return ([], [])
        }
    }
}
