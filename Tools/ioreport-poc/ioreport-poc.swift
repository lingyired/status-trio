// ioreport-poc — Phase 2 read-only feasibility POC for SoC power via the
// private IOReport framework, cross-checked against AppleSMC and IORegistry.
//
// Development tool only: this file is NOT part of Package.swift, has no
// product target, and must never ship in the app bundle.
//
// Build/run: see run.sh.  Nothing here needs sudo, a helper, a LaunchAgent,
// a TCC prompt, or an entitlement.
//
// What it does
//   groups / list   enumerate live IOReport channels (group, subgroup, name,
//                   unit label, format). No hardcoded channel names.
//   sample          take an absolute baseline sample, wait a window, then take
//                   the second sample and print the interval energy delta in
//                   joules and watts, plus PSTR/PDTR/B0AC/B0AV/AppleSmartBattery
//                   cross-checks and per-sample timing.
//   bench           overhead only: setup time, per-sample time, process CPU%,
//                   peak RSS, own ri_energy_nj.
//   selftest        synthetic baseline / counter-reset / stale-counter cases
//                   for the delta gate (does not touch hardware).
//
// Design notes recorded in docs/io-report-power-poc.md.
//
// SPDX-License-Identifier: none (local experiment, do not distribute)

import Foundation
import IOKit
import Darwin

// MARK: - Small utilities

func nowSeconds() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func monoMicros() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1000 }

func fourCC(_ key: String) -> UInt32 {
    key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        default: out.unicodeScalars.append(ch)
        }
    }
    return out
}

func fmt(_ v: Double, _ digits: Int = 3) -> String {
    String(format: "%.\(digits)f", v)
}

/// Left-justify/pad without passing a temporary C string to String(format:).
func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func padRight(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

// MARK: - IOReport dynamic binding

/// Every symbol we use is resolved at runtime from /usr/lib/libIOReport.dylib.
/// On macOS 27.2 the framework directory
/// /System/Library/PrivateFrameworks/IOReport.framework no longer exists; the
/// dylib lives in the dyld shared cache under /usr/lib/libIOReport.dylib.
final class IOReportShim {
    static let defaultPath = "/usr/lib/libIOReport.dylib"

    typealias CopyAllChannels = @convention(c) (UInt64, UInt64) -> Unmanaged<CFDictionary>?
    typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    typealias CreateSubscription = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    typealias CreateSamples = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias CreateSamplesDelta = @convention(c) (CFDictionary?, CFDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias ChannelGetString = @convention(c) (CFDictionary?) -> Unmanaged<CFString>?
    typealias SimpleGetInteger = @convention(c) (CFDictionary?, Int32) -> Int64
    typealias ChannelGetInt = @convention(c) (CFDictionary?) -> Int64
    typealias StateGetName = @convention(c) (CFDictionary?, Int32) -> Unmanaged<CFString>?
    typealias MergeChannels = @convention(c) (CFMutableDictionary?, CFMutableDictionary?, CFTypeRef?) -> Void

    let handle: UnsafeMutableRawPointer
    let copyAllChannels: CopyAllChannels
    let copyChannelsInGroup: CopyChannelsInGroup
    let createSubscription: CreateSubscription
    let createSamples: CreateSamples
    let createSamplesDelta: CreateSamplesDelta
    let channelGetGroup: ChannelGetString
    let channelGetSubGroup: ChannelGetString
    let channelGetChannelName: ChannelGetString
    let channelGetUnitLabel: ChannelGetString
    let channelGetFormat: ChannelGetInt
    let simpleGetInteger: SimpleGetInteger
    let stateGetCount: ChannelGetInt
    let stateGetNameForIndex: StateGetName
    let stateGetResidency: @convention(c) (CFDictionary?, Int32) -> Int64

    init(handle: UnsafeMutableRawPointer,
         copyAllChannels: @escaping CopyAllChannels,
         copyChannelsInGroup: @escaping CopyChannelsInGroup,
         createSubscription: @escaping CreateSubscription,
         createSamples: @escaping CreateSamples,
         createSamplesDelta: @escaping CreateSamplesDelta,
         channelGetGroup: @escaping ChannelGetString,
         channelGetSubGroup: @escaping ChannelGetString,
         channelGetChannelName: @escaping ChannelGetString,
         channelGetUnitLabel: @escaping ChannelGetString,
         channelGetFormat: @escaping ChannelGetInt,
         simpleGetInteger: @escaping SimpleGetInteger,
         stateGetCount: @escaping ChannelGetInt,
         stateGetNameForIndex: @escaping StateGetName,
         stateGetResidency: @escaping @convention(c) (CFDictionary?, Int32) -> Int64) {
        self.handle = handle
        self.copyAllChannels = copyAllChannels
        self.copyChannelsInGroup = copyChannelsInGroup
        self.createSubscription = createSubscription
        self.createSamples = createSamples
        self.createSamplesDelta = createSamplesDelta
        self.channelGetGroup = channelGetGroup
        self.channelGetSubGroup = channelGetSubGroup
        self.channelGetChannelName = channelGetChannelName
        self.channelGetUnitLabel = channelGetUnitLabel
        self.channelGetFormat = channelGetFormat
        self.simpleGetInteger = simpleGetInteger
        self.stateGetCount = stateGetCount
        self.stateGetNameForIndex = stateGetNameForIndex
        self.stateGetResidency = stateGetResidency
    }

    static func load(path: String = defaultPath) throws -> IOReportShim {
        guard let h = dlopen(path, RTLD_NOW) else {
            throw POCError.ioReportUnavailable("dlopen(\(path)): \(String(cString: dlerror()))")
        }
        func sym<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(h, name) else {
                throw POCError.ioReportUnavailable("dlsym(\(name)) missing in \(path)")
            }
            return unsafeBitCast(p, to: T.self)
        }
        typealias Residency = @convention(c) (CFDictionary?, Int32) -> Int64
        return try IOReportShim(
            handle: h,
            copyAllChannels: sym("IOReportCopyAllChannels", CopyAllChannels.self),
            copyChannelsInGroup: sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self),
            createSubscription: sym("IOReportCreateSubscription", CreateSubscription.self),
            createSamples: sym("IOReportCreateSamples", CreateSamples.self),
            createSamplesDelta: sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self),
            channelGetGroup: sym("IOReportChannelGetGroup", ChannelGetString.self),
            channelGetSubGroup: sym("IOReportChannelGetSubGroup", ChannelGetString.self),
            channelGetChannelName: sym("IOReportChannelGetChannelName", ChannelGetString.self),
            channelGetUnitLabel: sym("IOReportChannelGetUnitLabel", ChannelGetString.self),
            channelGetFormat: sym("IOReportChannelGetFormat", ChannelGetInt.self),
            simpleGetInteger: sym("IOReportSimpleGetIntegerValue", SimpleGetInteger.self),
            stateGetCount: sym("IOReportStateGetCount", ChannelGetInt.self),
            stateGetNameForIndex: sym("IOReportStateGetNameForIndex", StateGetName.self),
            stateGetResidency: sym("IOReportStateGetResidency", Residency.self)
        )
    }

    private func channelStrings(_ dict: CFDictionary?) -> [ChannelEnergy] {
        guard let dict else { return [] }
        let d = dict as NSDictionary
        guard let arr = d["IOReportChannels"] as? NSArray else { return [] }
        let cfArray = arr as CFArray
        var out: [ChannelEnergy] = []
        for i in 0..<CFArrayGetCount(cfArray) {
            guard let raw = CFArrayGetValueAtIndex(cfArray, i) else { continue }
            let item = unsafeBitCast(raw, to: CFDictionary.self)
            out.append(ChannelEnergy(
                group: (channelGetGroup(item)?.takeUnretainedValue() as String?) ?? "",
                subgroup: (channelGetSubGroup(item)?.takeUnretainedValue() as String?) ?? "",
                name: (channelGetChannelName(item)?.takeUnretainedValue() as String?) ?? "",
                unit: (channelGetUnitLabel(item)?.takeUnretainedValue() as String?) ?? "",
                format: Int(channelGetFormat(item)),
                raw: item
            ))
        }
        return out
    }

    /// Absolute sample as returned by IOReportCreateSamples.
    func sampleChannels(subscription: UnsafeMutableRawPointer, channels: CFMutableDictionary) -> [ChannelEnergy] {
        guard let dict = createSamples(subscription, channels, nil)?.takeRetainedValue() else { return [] }
        return channelStrings(dict)
    }

    /// Reads the current integer values of every channel in an absolute sample.
    func integerValues(_ channels: [ChannelEnergy]) -> [ChannelKey: Int64] {
        var out: [ChannelKey: Int64] = [:]
        out.reserveCapacity(channels.count)
        for ch in channels {
            out[ch.key] = simpleGetInteger(ch.raw, 0)
        }
        return out
    }

    func deltaChannels(previous: CFDictionary, current: CFDictionary) -> [ChannelEnergy] {
        guard let d = createSamplesDelta(previous, current, nil)?.takeRetainedValue() else { return [] }
        return channelStrings(d)
    }

    func allChannels() -> (dict: CFDictionary, channels: [ChannelEnergy])? {
        guard let dict = copyAllChannels(0, 0)?.takeRetainedValue() else { return nil }
        return (dict, channelStrings(dict))
    }

    func channelsInGroup(_ group: String, subgroup: String? = nil) -> (dict: CFMutableDictionary, channels: [ChannelEnergy])? {
        guard let dict = copyChannelsInGroup(group as CFString, subgroup as CFString?, 0, 0, 0)?
            .takeRetainedValue() else { return nil }
        guard let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, dict) else { return nil }
        return (mutable, channelStrings(mutable))
    }
}

// MARK: - Models

enum POCError: Error, CustomStringConvertible {
    case ioReportUnavailable(String)
    case subscriptionFailed(String)
    case usage(String)

    var description: String {
        switch self {
        case .ioReportUnavailable(let s): return "IOReport unavailable: \(s)"
        case .subscriptionFailed(let s): return "subscription failed: \(s)"
        case .usage(let s): return s
        }
    }
}

struct ChannelKey: Hashable {
    let group: String
    let subgroup: String
    let name: String
}

struct ChannelEnergy {
    let group: String
    let subgroup: String
    let name: String
    let unit: String
    let format: Int
    let raw: CFDictionary

    var key: ChannelKey { ChannelKey(group: group, subgroup: subgroup, name: name) }

    var isStateFormat: Bool { format != 0 }

    /// Unit label -> joules multiplier. IOReport energy channels emit an integer
    /// count whose unit is named by UnitLabel (nJ / uJ / mJ on Apple Silicon).
    var joulesPerUnit: Double? {
        switch unit.lowercased() {
        case "nj": return 1e-9
        case "uj", "\u{00b5}j", "\u{03bc}j": return 1e-6
        case "mj": return 1e-3
        case "j": return 1
        default: return nil
        }
    }
}

// MARK: - Energy Model sampler with interval baselining

enum DeltaState {
    case baselineEstablished
    case value(dt: Double, channels: [(ChannelEnergy, Int64)])
    case counterReset(detail: String)
    case stale(detail: String)
    case invalid(detail: String)
}

final class EnergySampler {
    let shim: IOReportShim
    let channels: CFMutableDictionary
    let subscription: UnsafeMutableRawPointer
    let setupMicros: UInt64
    private var previousChannels: CFDictionary?
    private var previousValues: [ChannelKey: Int64] = [:]
    private var previousAt: Double?

    init(shim: IOReportShim, group: String, subgroup: String? = nil) throws {
        self.shim = shim
        let began = monoMicros()
        guard let (dict, _) = shim.channelsInGroup(group, subgroup: subgroup) else {
            throw POCError.subscriptionFailed("IOReportCopyChannelsInGroup(\(group)) returned nil")
        }
        var sub: Unmanaged<CFMutableDictionary>?
        guard let subscription = shim.createSubscription(nil, dict, &sub, 0, nil) else {
            throw POCError.subscriptionFailed("IOReportCreateSubscription(\(group)) returned nil")
        }
        sub?.release()
        self.channels = dict
        self.subscription = subscription
        self.setupMicros = monoMicros() - began
    }

    /// Two-phase interval sample. First call establishes the baseline only.
    func takeDelta() -> (state: DeltaState, channels: [ChannelEnergy], dt: Double, sampleMicros: UInt64) {
        let began = monoMicros()
        defer { _ = began }
        guard let rawDict = shim.createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return (.invalid(detail: "IOReportCreateSamples nil"), [], 0, monoMicros() - began)
        }
        let sampleMicros = monoMicros() - began
        let at = nowSeconds()
        let current = shim.sampleChannelsDict(rawDict)
        let currentValues = shim.integerValues(current)
        guard let prevValues = previousValues.isEmpty ? nil : previousValues,
              let prevAt = previousAt, let prevDict = previousChannels else {
            previousValues = currentValues
            previousAt = at
            previousChannels = rawDict
            return (.baselineEstablished, current, 0, sampleMicros)
        }
        let dt = at - prevAt
        _ = prevDict
        // Reset / wrap detection: any channel going backwards means the counter
        // was re-baselined (sleep/wake, IP block power gated, OR the machine
        // crossed an energy-model counter rollover). Discard the interval.
        var backwards: [String] = []
        for (key, cur) in currentValues {
            if let prev = prevValues[key], cur < prev {
                backwards.append("\(key.group)/\(key.name) \(prev)->\(cur)")
            }
        }
        previousValues = currentValues
        previousAt = at
        previousChannels = rawDict
        if !backwards.isEmpty {
            return (.counterReset(detail: backwards.prefix(4).joined(separator: "; ")), current, dt, sampleMicros)
        }
        if dt < 0.05 {
            return (.invalid(detail: "interval too short \(fmt(dt)) s"), current, dt, sampleMicros)
        }
        if dt > 120 {
            return (.invalid(detail: "interval too long \(fmt(dt, 1)) s (stale baseline)"), current, dt, sampleMicros)
        }
        // A non-advancing counter is stale telemetry, not an idle 0 W.
        let advanced = currentValues.contains { key, cur in (prevValues[key] ?? cur) != cur }
        if !advanced {
            return (.stale(detail: "no channel advanced during \(fmt(dt, 2)) s"), current, dt, sampleMicros)
        }
        var deltas: [(ChannelEnergy, Int64)] = []
        deltas.reserveCapacity(current.count)
        for ch in current {
            guard let cur = currentValues[ch.key], let prev = prevValues[ch.key] else { continue }
            deltas.append((ch, cur &- prev))
        }
        return (.value(dt: dt, channels: deltas), current, dt, sampleMicros)
    }

    /// Independent manual delta (current absolute minus previous absolute) used
    /// to verify that IOReportCreateSamplesDelta agrees with plain subtraction.
    func manualDelta(currentValues: [ChannelKey: Int64], previous: [ChannelKey: Int64]) -> [ChannelKey: Int64] {
        var out: [ChannelKey: Int64] = [:]
        for (k, v) in currentValues { if let p = previous[k] { out[k] = v &- p } }
        return out
    }
}

extension IOReportShim {
    /// Same as sampleChannels but keeps the already-retained dictionary, so the
    /// caller can use it as the next delta baseline without re-sampling.
    func sampleChannelsDict(_ dict: CFDictionary) -> [ChannelEnergy] {
        channelStrings(dict)
    }
}

// MARK: - SMC (AppleSMC 80-byte key ABI, same read-only keys as SystemPowerReader)

struct SMCSensor {
    let name: String
    let raw: UInt32
    init(_ name: String) { self.name = name; self.raw = fourCC(name) }
}

struct SMCReading {
    let key: String
    let type: String
    let size: Int
    let value: Double?
}

enum SMCReader {
    static func read(keys: [String]) -> [SMCReading] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return keys.map { SMCReading(key: $0, type: "no-service", size: 0, value: nil) } }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return keys.map { SMCReading(key: $0, type: "open-failed", size: 0, value: nil) }
        }
        defer { IOServiceClose(connection) }
        let exchange: ([UInt8]) -> [UInt8]? = { request in
            var response = [UInt8](repeating: 0, count: 80)
            var size = response.count
            let result = request.withUnsafeBytes { input in
                response.withUnsafeMutableBytes { output in
                    IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count,
                                              output.baseAddress, &size)
                }
            }
            return result == KERN_SUCCESS && size == 80 ? response : nil
        }
        return keys.map { readOne(key: $0, exchange: exchange) }
    }

    private static func u32le(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func typeString(_ t: UInt32) -> String {
        let bytes = [UInt8((t >> 24) & 0xff), UInt8((t >> 16) & 0xff), UInt8((t >> 8) & 0xff), UInt8(t & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08x", t)
    }

    private static func readOne(key: String, exchange: ([UInt8]) -> [UInt8]?) -> SMCReading {
        var request = [UInt8](repeating: 0, count: 80)
        let raw = fourCC(key)
        for offset in 0..<4 { request[offset] = UInt8(truncatingIfNeeded: raw >> (offset * 8)) }
        request[42] = 9 // read key info
        guard let info = exchange(request), info[40] == 0 else {
            return SMCReading(key: key, type: "info-failed", size: 0, value: nil)
        }
        let size = Int(u32le(info, 28))
        let type = u32le(info, 32)
        let tstr = typeString(type)
        request.replaceSubrange(28..<32, with: info[28..<32])
        request[42] = 5 // read bytes only; never write command 6
        guard let response = exchange(request), response[40] == 0 else {
            return SMCReading(key: key, type: tstr, size: size, value: nil)
        }
        let b = Array(response[48..<80])
        let value: Double?
        switch type {
        case 0x666c7420: // 'flt '
            value = Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case 0x73693136: // 'si16' battery current, mA, little-endian
            let raw16 = UInt16(b[0]) | UInt16(b[1]) << 8
            value = Double(Int16(bitPattern: raw16)) / 1000
        case 0x75693136: // 'ui16' battery voltage, mV, little-endian
            let raw16 = UInt16(b[0]) | UInt16(b[1]) << 8
            value = Double(raw16) / 1000
        case 0x66706532: // 'fpe2'
            let raw16 = UInt16(b[0]) << 8 | UInt16(b[1])
            value = Double(raw16) / 4
        case 0x73703738: // 'sp78'
            let raw16 = UInt16(b[0]) << 8 | UInt16(b[1])
            value = Double(Int16(bitPattern: raw16)) / 256
        default:
            value = nil
        }
        return SMCReading(key: key, type: tstr, size: size, value: value)
    }
}

// MARK: - AppleSmartBattery (IORegistry, public)

struct BatteryReading {
    var voltageV: Double?
    var amperageA: Double?
    var instantAmperageA: Double?
    var externalConnected: Bool?
    var isCharging: Bool?
    var currentCapacity: Int?
    var maxCapacity: Int?
    var systemPowerInW: Double?
    var keysSeen: [String] = []

    var powerW: Double? {
        guard let v = voltageV else { return nil }
        if let a = instantAmperageA ?? amperageA { return v * a }
        return nil
    }
}

enum BatteryReader {
    static func read() -> BatteryReading {
        var out = BatteryReading()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return out }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as NSDictionary? as? [String: Any] else { return out }
        out.keysSeen = dict.keys.sorted()
        if let mv = dict["Voltage"] as? NSNumber { out.voltageV = mv.doubleValue / 1000 }
        if let ma = dict["Amperage"] as? NSNumber { out.amperageA = ma.doubleValue / 1000 }
        if let ma = dict["InstantAmperage"] as? NSNumber { out.instantAmperageA = ma.doubleValue / 1000 }
        if let ec = dict["ExternalConnected"] as? NSNumber { out.externalConnected = ec.boolValue }
        if let ch = dict["IsCharging"] as? NSNumber { out.isCharging = ch.boolValue }
        if let cc = dict["CurrentCapacity"] as? NSNumber { out.currentCapacity = cc.intValue }
        if let mc = dict["MaxCapacity"] as? NSNumber { out.maxCapacity = mc.intValue }
        if let tel = dict["PowerTelemetryData"] as? [String: Any],
           let sp = (tel["SystemPowerIn"] as? NSNumber)?.doubleValue {
            out.systemPowerInW = sp / 1000
        }
        return out
    }
}

// MARK: - Self cost

struct SelfCost {
    var userSec: Double
    var sysSec: Double
    var maxRSSBytes: Int64
    var energyNanoJoules: Double?

    static func current() -> SelfCost {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let sys = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        let rss = Int64(usage.ru_maxrss) // bytes on macOS
        // ri_energy_nj is the same per-process energy counter the app already
        // reads for the CPU-energy list; use it to price the POC itself.
        var info = rusage_info_v6()
        var energy: Double? = nil
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { ptr in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V6, ptr)
            }
        }
        if r == 0 { energy = Double(info.ri_energy_nj) / 1e9 }
        return SelfCost(userSec: user, sysSec: sys, maxRSSBytes: rss, energyNanoJoules: energy)
    }

    var cpuSec: Double { userSec + sysSec }
}

// MARK: - Classification of Energy Model channels

/// Chip-family channel layout is NOT stable: names are fourCC-ish codes that
/// differ across M1..M5. We therefore classify by name pattern at runtime and
/// keep the raw per-channel table visible in the report.
struct PowerBreakdown {
    var cpuW: Double = 0
    var gpuW: Double = 0
    var aneW: Double = 0
    var dramW: Double = 0
    var displayW: Double = 0
    var otherW: Double = 0
    var socTotalW: Double = 0
    var counted: [String] = []
    var skipped: [String] = []
}

enum EnergyClassifier {
    /// Channel names that are detail/duplicate rails of a coarser channel. They
    /// are excluded from the total to avoid summing the same joules twice.
    static func isDetailOrDuplicate(_ name: String, all: [String]) -> Bool {
        let n = name.uppercased()
        if n.contains("DTL") { return true }             // per-core per-P-state detail
        if n.hasSuffix("_SRAM") { return true }           // SRAM rails inside a block
        if n == "GPU" && all.contains(where: { $0.uppercased() == "GPU ENERGY" }) { return true }
        if n == "CPU" && all.contains(where: { $0.uppercased() == "CPU ENERGY" }) { return true }
        // Cluster/aggregate duplication: if a whole-CPU channel exists, per-cluster
        // CPU channels are its breakdown.
        let hasCPUAggregate = all.contains { $0.uppercased() == "CPU ENERGY" }
        if hasCPUAggregate, n != "CPU ENERGY" {
            let prefixes = ["MCPU", "PCPU", "ECPU", "PACC", "EACC", "PCPM", "ECPM", "MCPM"]
            if prefixes.contains(where: { n.hasPrefix($0) }) { return true }
        }
        return false
    }

    static func classify(_ deltas: [(name: String, joules: Double)], dt: Double) -> PowerBreakdown {
        let names = deltas.map { $0.name }
        var out = PowerBreakdown()
        for (name, joules) in deltas {
            let watts = joules / dt
            let upper = name.uppercased()
            if isDetailOrDuplicate(name, all: names) {
                out.skipped.append("\(name)=\(fmt(watts))W")
                continue
            }
            out.socTotalW += watts
            out.counted.append(name)
            if upper.contains("GPU") { out.gpuW += watts }
            else if upper.contains("ANE") { out.aneW += watts }
            else if upper.contains("DRAM") || upper.contains("AMCC") || upper.contains("DCS") { out.dramW += watts }
            else if upper.contains("DISP") { out.displayW += watts }
            else if upper.hasPrefix("CPU") || upper.hasPrefix("PCPU") || upper.hasPrefix("ECPU")
                        || upper.hasPrefix("MCPU") || upper.hasPrefix("PACC") || upper.hasPrefix("EACC")
                        || upper.hasPrefix("PCPM") || upper.hasPrefix("ECPM") || upper.hasPrefix("MCPM") {
                out.cpuW += watts
            } else {
                out.otherW += watts
            }
        }
        return out
    }
}

// MARK: - Delta gate selftest (pure logic, no hardware)

struct CounterGate {
    enum Result: Equatable {
        case baseline
        case delta([String: Int64], dt: Double)
        case reset(String)
        case stale(String)
    }
    private var previous: [String: Int64]?
    private var previousAt: Double?

    mutating func update(_ counters: [String: Int64], at: Double) -> Result {
        defer { previous = counters; previousAt = at }
        guard let prev = previous, let prevAt = previousAt else { return .baseline }
        let dt = at - prevAt
        var backwards: [String] = []
        for (k, v) in counters {
            if let p = prev[k], v < p { backwards.append(k) }
        }
        if !backwards.isEmpty { return .reset(backwards.joined(separator: ",")) }
        if dt <= 0 { return .stale("non-positive dt") }
        var delta: [String: Int64] = [:]
        var advanced = false
        for (k, v) in counters {
            let d = v - (prev[k] ?? v)
            delta[k] = d
            if d > 0 { advanced = true }
        }
        if !advanced { return .stale("no counter advanced") }
        return .delta(delta, dt: dt)
    }
}

// MARK: - Commands

struct Options {
    var command = ""
    var group = "Energy Model"
    var window = 3.0
    var warmup = 1.0
    var windows = 1
    var json = false
    var busyThreads = 0
    var allGroups = false
    var raw = false
    var nonzero = false
}

func parse(_ args: [String]) throws -> Options {
    var o = Options()
    var i = 0
    guard let cmd = args.first else { throw POCError.usage(usageText) }
    o.command = cmd
    i = 1
    while i < args.count {
        let a = args[i]
        switch a {
        case "--group": i += 1; o.group = args[i]
        case "--window": i += 1; o.window = Double(args[i]) ?? o.window
        case "--warmup": i += 1; o.warmup = Double(args[i]) ?? o.warmup
        case "--windows": i += 1; o.windows = Int(args[i]) ?? o.windows
        case "--busy": i += 1; o.busyThreads = Int(args[i]) ?? 0
        case "--json": o.json = true
        case "--all-groups": o.allGroups = true
        case "--raw": o.raw = true
        case "--nonzero": o.nonzero = true
        case "-h", "--help": throw POCError.usage(usageText)
        default: throw POCError.usage("unknown option \(a)\n\n\(usageText)")
        }
        i += 1
    }
    return o
}

let usageText = """
usage: ioreport-poc <command> [options]
  groups                          list IOReport group names and channel counts
  list [--group G] [--all-groups] dump channels (group/subgroup/name/unit/format)
  sample --group G [--window 3] [--windows N] [--busy N] [--json]
                                  interval energy delta -> watts + cross-checks
  bench [--window 5]              setup/sample cost, CPU%, RSS, own energy
  selftest                        synthetic baseline/reset/stale gate checks
options:
  --warmup <s>   delay between baseline and window (default 1.0; baseline only)
  --busy <n>     spin n CPU threads during the window (load cross-check)
  --raw          print every channel delta, regardless of unit
  --nonzero      print only channels whose counter advanced
"""

func runGroups(shim: IOReportShim) {
    guard let all = shim.allChannels() else { print("IOReportCopyAllChannels returned nil"); return }
    var counts: [String: Int] = [:]
    var units: [String: Set<String>] = [:]
    for ch in all.channels {
        counts[ch.group, default: 0] += 1
        units[ch.group, default: []].insert(ch.unit)
    }
    print("IOReport total channels: \(all.channels.count)")
    for g in counts.keys.sorted() {
        print("  \(pad(g, 22)) \(String(format: "%4d", counts[g]!))  units=\(units[g]!.sorted().joined(separator: ","))")
    }
}

func runList(shim: IOReportShim, options: Options) {
    guard let all = shim.allChannels() else { print("IOReportCopyAllChannels returned nil"); return }
    let filter: String? = options.allGroups ? nil : options.group
    var shown = 0
    var lastGroup = ""
    for ch in all.channels where filter == nil || ch.group == filter {
        if ch.group != lastGroup {
            print("## group: \(ch.group)")
            lastGroup = ch.group
        }
        print("  sub=\(pad(ch.subgroup, 10)) name=\(pad(ch.name, 24)) unit=\(pad(ch.unit, 10)) format=\(ch.format)")
        shown += 1
    }
    print("# \(shown) channels shown (filter=\(filter ?? "*"))")

    // Second view: the dictionary returned by CopyChannelsInGroup, which is what
    // a subscription actually uses.
    if let (_, chans) = shim.channelsInGroup(options.group) {
        print("# CopyChannelsInGroup(\(options.group)) -> \(chans.count) channels")
    } else {
        print("# CopyChannelsInGroup(\(options.group)) -> nil")
    }
}

final class BusyLoad {
    private var threads: [Thread] = []
    private var running = true
    init(_ count: Int) {
        for _ in 0..<count {
            let t = Thread { [weak self] in
                var x = 0.0
                while self?.running == true { x += 1.0; if x > 1e12 { x = 0 } }
            }
            t.stackSize = 512 * 1024
            threads.append(t)
            t.start()
        }
    }
    func stop() { running = false }
}

func smcSnapshot() -> [SMCReading] {
    SMCReader.read(keys: ["PSTR", "PDTR", "B0AC", "B0AV"])
}

func runSample(shim: IOReportShim, options: Options) {
    let sampler: EnergySampler
    do { sampler = try EnergySampler(shim: shim, group: options.group) }
    catch { print("setup failed: \(error)"); exit(2) }

    if !options.json {
        print("# group=\(options.group) setup=\(sampler.setupMicros)us window=\(fmt(options.window,2))s warmup=\(fmt(options.warmup,2))s")
    }

    for round in 0..<max(options.windows, 1) {
        let load = options.busyThreads > 0 ? BusyLoad(options.busyThreads) : nil
        _ = sampler.takeDelta() // baseline only
        if options.warmup > 0 { Thread.sleep(forTimeInterval: options.warmup) }
        // Re-baseline so the reported interval equals the requested window.
        _ = sampler.takeDelta()
        let before = SelfCost.current()
        Thread.sleep(forTimeInterval: options.window)
        let result = sampler.takeDelta()
        let after = SelfCost.current()
        load?.stop()
        let smcAfter = smcSnapshot()

        switch result.state {
        case .baselineEstablished:
            print("round \(round): baseline only (no delta)")
        case .invalid(let d), .counterReset(let d), .stale(let d):
            print("round \(round): rejected: \(d)")
        case .value(let dt, let channels):
            let energyChannels = channels.compactMap { ch, deltaRaw -> (String, Double, String)? in
                guard let perUnit = ch.joulesPerUnit else { return nil }
                return (ch.name, Double(deltaRaw) * perUnit, ch.unit)
            }
            if options.raw {
                var rows: [(String, String, Int64)] = []
                for (ch, deltaRaw) in channels where !options.nonzero || deltaRaw != 0 {
                    rows.append((ch.name, ch.unit, deltaRaw))
                }
                rows.sort { $0.2 > $1.2 }
                for (name, unit, raw) in rows {
                    print("  RAW \(pad(name, 24)) \(pad(unit, 8)) \(raw)")
                }
                continue
            }
            let breakdown = EnergyClassifier.classify(energyChannels.map { ($0.0, $0.1) }, dt: dt)
            let wall = after.cpuSec - before.cpuSec
            let battery = batteryAfter()
            let smc = smcAfter
            let smcMap = Dictionary(uniqueKeysWithValues: smc.map { ($0.key, $0.value) })
            let pstr = smcMap["PSTR"] ?? nil
            let pdtr = smcMap["PDTR"] ?? nil
            let b0ac = smcMap["B0AC"] ?? nil
            let b0av = smcMap["B0AV"] ?? nil
            let batteryW = (b0av != nil && b0ac != nil) ? b0av! * b0ac! : nil

            if options.json {
                let chans = energyChannels.sorted { $0.1 > $1.1 }.map { name, joules, unit in
                    "{\"name\":\"\(jsonEscape(name))\",\"unit\":\"\(unit)\",\"joules\":\(fmt(joules, 6)),\"watts\":\(fmt(joules / dt, 4))}"
                }.joined(separator: ",")
                print("""
                {"round":\(round),"group":"\(jsonEscape(options.group))","windowRequested":\(options.window),"dt":\(fmt(dt,6)),\
                "busyThreads":\(options.busyThreads),"channels":[\(chans)],\
                "breakdown":{"socTotalW":\(fmt(breakdown.socTotalW,4)),"cpuW":\(fmt(breakdown.cpuW,4)),\
                "gpuW":\(fmt(breakdown.gpuW,4)),"aneW":\(fmt(breakdown.aneW,4)),"dramW":\(fmt(breakdown.dramW,4)),\
                "displayW":\(fmt(breakdown.displayW,4)),"otherW":\(fmt(breakdown.otherW,4))},\
                "counted":\(breakdown.counted.count),"skipped":\(breakdown.skipped.count),\
                "smc":{"PSTR":\(pstr.map { fmt($0, 3) } ?? "null"),"PDTR":\(pdtr.map { fmt($0, 3) } ?? "null"),\
                "B0AC":\(b0ac.map { fmt($0, 4) } ?? "null"),"B0AV":\(b0av.map { fmt($0, 4) } ?? "null"),\
                "batteryW":\(batteryW.map { fmt($0, 3) } ?? "null")},\
                "battery":{"voltageV":\(battery.voltageV.map { fmt($0,4) } ?? "null"),\
                "amperageA":\(battery.amperageA.map { fmt($0,5) } ?? "null"),\
                "instantAmperageA":\(battery.instantAmperageA.map { fmt($0,5) } ?? "null"),\
                "powerW":\(battery.powerW.map { fmt($0,3) } ?? "null"),\
                "externalConnected":\(battery.externalConnected.map { "\($0)" } ?? "null"),\
                "isCharging":\(battery.isCharging.map { "\($0)" } ?? "null"),\
                "percent":\(battery.currentCapacity.map { "\($0)" } ?? "null")},\
                "timing":{"setupUs":\(sampler.setupMicros),"sampleUs":\(result.sampleMicros)},\
                "self":{"cpuSec":\(fmt(wall,6)),"cpuPercent":\(fmt(wall / dt * 100, 3)),\
                "rssMB":\(fmt(Double(after.maxRSSBytes) / 1_048_576, 1)),\
                "energyJ":\(after.energyNanoJoules.map { fmt($0, 4) } ?? "null")}}
                """)
            } else {
                print("\n## round \(round): dt=\(fmt(dt, 4)) s, busy=\(options.busyThreads)")
                print("  \(pad("channel", 24)) \(pad("unit", 8)) \(padRight("delta(unit)", 14)) \(padRight("W", 10))")
                for (name, joules, unit) in energyChannels.sorted(by: { $0.1 > $1.1 }) {
                    let raw = channels.first { $0.0.name == name }?.1 ?? 0
                    print("  \(pad(name, 24)) \(pad(unit, 8)) \(padRight(String(raw), 14)) \(padRight(fmt(joules / dt), 10))")
                }
                print("  --")
                print("  SoC total            \(fmt(breakdown.socTotalW)) W  (counted \(breakdown.counted.count) channels)")
                print("  CPU / GPU / ANE      \(fmt(breakdown.cpuW)) / \(fmt(breakdown.gpuW)) / \(fmt(breakdown.aneW)) W")
                print("  DRAM / display/other \(fmt(breakdown.dramW)) / \(fmt(breakdown.displayW)) / \(fmt(breakdown.otherW)) W")
                if !breakdown.skipped.isEmpty {
                    print("  skipped(detail):     \(breakdown.skipped.joined(separator: ", "))")
                }
                print("  -- cross-check --")
                print("  PSTR (SMC system)    \(pstr.map { "\(fmt($0)) W" } ?? "nil")")
                print("  PDTR (adapter input) \(pdtr.map { "\(fmt($0)) W" } ?? "nil")")
                print("  B0AV*B0AC (battery)  \(batteryW.map { "\(fmt($0)) W" } ?? "nil")")
                print("  IORegistry battery   \(battery.powerW.map { "\(fmt($0)) W" } ?? "nil")  (V=\(battery.voltageV.map { fmt($0, 3) } ?? "?"), A=\(battery.amperageA.map { fmt($0, 4) } ?? "?")), AC=\(battery.externalConnected.map { "\($0)" } ?? "?"), charging=\(battery.isCharging.map { "\($0)" } ?? "?"), \(battery.currentCapacity.map { "\($0)" } ?? "?")%")
                print("  -- self cost --")
                print("  sample=\(result.sampleMicros)us setup=\(sampler.setupMicros)us cpu=\(fmt(wall, 4))s (\(fmt(wall / dt * 100, 3))%) rss=\(fmt(Double(after.maxRSSBytes) / 1_048_576, 1))MB")
            }
        }
    }
    _ = shim
}

func batteryAfter() -> BatteryReading { BatteryReader.read() }

func runBench(shim: IOReportShim, options: Options) {
    let cost0 = SelfCost.current()
    let t0 = monoMicros()
    let sampler: EnergySampler
    do { sampler = try EnergySampler(shim: shim, group: options.group) }
    catch { print("setup failed: \(error)"); exit(2) }
    let setupUs = monoMicros() - t0
    _ = sampler.takeDelta()
    Thread.sleep(forTimeInterval: 0.5)
    _ = sampler.takeDelta()

    let before = SelfCost.current()
    let windowStart = nowSeconds()
    var sampleMicros: [UInt64] = []
    var smcMicros: [UInt64] = []
    var accepted = 0
    var rejected = 0
    while nowSeconds() - windowStart < options.window {
        let r = sampler.takeDelta()
        sampleMicros.append(r.sampleMicros)
        if case .value = r.state { accepted += 1 } else { rejected += 1 }
        let s0 = monoMicros()
        _ = smcSnapshot()
        smcMicros.append(monoMicros() - s0)
        Thread.sleep(forTimeInterval: 0.5)
    }
    let after = SelfCost.current()
    let elapsed = nowSeconds() - windowStart
    func stats(_ v: [UInt64]) -> String {
        guard !v.isEmpty else { return "n/a" }
        let sorted = v.sorted()
        let mean = Double(v.reduce(0, +)) / Double(v.count)
        return "n=\(v.count) mean=\(fmt(mean, 1))us p50=\(sorted[sorted.count / 2])us max=\(sorted.last!)us"
    }
    let cpu = after.cpuSec - before.cpuSec
    print("""
    # bench group=\(options.group)
    setup+subscription  \(setupUs) us
    IOReport sample     \(stats(sampleMicros))
    SMC 4-key read      \(stats(smcMicros))
    self cpu (incl sleep) \(fmt(cpu, 4)) s over \(fmt(elapsed, 2)) s -> \(fmt(cpu / elapsed * 100, 3)) %
    accepted/rejected   \(accepted)/\(rejected)
    rss                 \(fmt(Double(after.maxRSSBytes) / 1_048_576, 1)) MB
    own energy (ri_energy_nj) \(after.energyNanoJoules.map { fmt($0, 4) } ?? "n/a") J, delta=\(fmt((after.energyNanoJoules ?? 0) - (before.energyNanoJoules ?? 0), 4)) J
    started from        \(fmt(cost0.cpuSec, 4)) s cpu
    """)
}

func runSelftest() {
    var gate = CounterGate()
    var failures = 0
    func check(_ label: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures += 1 }
    }
    _ = gate.update(["cpu": 100, "gpu": 50], at: 0)
    // First call returns .baseline by construction.
    check("first sample establishes baseline", {
        var g = CounterGate(); return g.update(["cpu": 100], at: 0) == .baseline
    }())
    check("normal increment yields delta", {
        var g = CounterGate(); _ = g.update(["cpu": 100, "gpu": 50], at: 0)
        if case .delta(let d, let dt) = g.update(["cpu": 160, "gpu": 90], at: 2), dt == 2, d["cpu"] == 60, d["gpu"] == 40 {
            return true
        }
        return false
    }())
    check("counter going backwards is a reset, not a negative watt", {
        var g = CounterGate(); _ = g.update(["cpu": 100], at: 0)
        if case .reset = g.update(["cpu": 10], at: 2) { return true }
        return false
    }())
    check("reset re-establishes baseline (next interval works)", {
        var g = CounterGate(); _ = g.update(["cpu": 100], at: 0)
        _ = g.update(["cpu": 10], at: 2)
        if case .delta(let d, _) = g.update(["cpu": 40], at: 4), d["cpu"] == 30 { return true }
        return false
    }())
    check("non-advancing counters are stale, not 0 W", {
        var g = CounterGate(); _ = g.update(["cpu": 100], at: 0)
        if case .stale = g.update(["cpu": 100], at: 2) { return true }
        return false
    }())
    check("unknown channel appearing later is ignored (no crash)", {
        var g = CounterGate(); _ = g.update(["cpu": 100], at: 0)
        if case .delta(let d, _) = g.update(["cpu": 120, "ane": 5], at: 2) {
            return d["cpu"] == 20 && d["ane"] == 0
        }
        return false
    }())
    _ = gate
    print(failures == 0 ? "# selftest OK" : "# selftest FAILED (\(failures))")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - main

let args = Array(CommandLine.arguments.dropFirst())
do {
    let options = try parse(args)
    let shim = try IOReportShim.load()
    switch options.command {
    case "groups": runGroups(shim: shim)
    case "list": runList(shim: shim, options: options)
    case "sample": runSample(shim: shim, options: options)
    case "bench": runBench(shim: shim, options: options)
    case "selftest": runSelftest()
    default: throw POCError.usage("unknown command \(options.command)\n\n\(usageText)")
    }
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(2)
}
