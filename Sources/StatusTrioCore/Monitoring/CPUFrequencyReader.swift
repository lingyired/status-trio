import CoreFoundation
import Foundation
import IOKit

// Private but long-stable IOReport entry points, linked from the system
// `IOReport` stub. These are not a public frequency API; every read is guarded
// and failure degrades to "unavailable" instead of affecting CPU utilisation.
@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: CFString?, _ subgroup: CFString?,
                                         _ a: UInt64, _ b: UInt64, _ c: UInt64) -> Unmanaged<CFMutableDictionary>?
@_silgen_name("IOReportMergeChannels")
private func IOReportMergeChannels(_ a: CFMutableDictionary, _ b: CFMutableDictionary,
                                   _ c: UnsafeRawPointer?) -> Void
@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeMutableRawPointer?, _ channels: CFMutableDictionary,
                                        _ subbed: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
                                        _ n: UInt64, _ b: CFTypeRef?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subscription: CFTypeRef, _ channels: CFMutableDictionary,
                                   _ a: CFTypeRef?) -> Unmanaged<CFDictionary>?
@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ previous: CFDictionary, _ current: CFDictionary,
                                        _ a: CFTypeRef?) -> Unmanaged<CFDictionary>?
@_silgen_name("IOReportChannelGetGroup")
private func IOReportChannelGetGroup(_ channel: CFDictionary) -> Unmanaged<CFString>?
@_silgen_name("IOReportChannelGetSubGroup")
private func IOReportChannelGetSubGroup(_ channel: CFDictionary) -> Unmanaged<CFString>?
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ channel: CFDictionary) -> Unmanaged<CFString>?
@_silgen_name("IOReportStateGetCount")
private func IOReportStateGetCount(_ channel: CFDictionary) -> Int32
@_silgen_name("IOReportStateGetNameForIndex")
private func IOReportStateGetNameForIndex(_ channel: CFDictionary, _ index: Int32) -> Unmanaged<CFString>?
@_silgen_name("IOReportStateGetResidency")
private func IOReportStateGetResidency(_ channel: CFDictionary, _ index: Int32) -> Int64

/// Estimated operating frequency of each CPU core cluster.
///
/// Values are a residency-weighted average over the DVFS performance states
/// seen between two adjacent IOReport samples, so they are an *estimate* of the
/// live clock, never the chip's nominal peak. Any unsupported or mismatched
/// state list yields `nil` for that cluster and the UI shows "—".

/// Owns the IOReport subscription for CPU complex performance states. Lives on
/// the sampler's utility queue; nothing here blocks (no fixed sleep) — each read
/// diffs against the previous tick's sample, so a 2–5 s cadence costs one cheap
/// state read per tick.
final class CPUFrequencyReader: @unchecked Sendable {
    /// Minimum spacing between two residency samples used for one average.
    static let minimumSampleInterval: TimeInterval = 2.0

    private var channels: CFMutableDictionary?
    private var subscription: CFTypeRef?
    private var previousSample: CFDictionary?
    private var previousAt: Date?
    private var lastReading: CPUFrequencyReading?
    private var frequencyTablesLoaded = false
    private var efficiencyFrequencies: [Int32] = []
    private var performanceFrequencies: [Int32] = []
    private var setupFailed = false

    /// Releases every CoreFoundation object. Idempotent; called on sleep/teardown
    /// and when the CPU detail page stops needing frequency.
    func reset() {
        channels = nil
        subscription = nil
        previousSample = nil
        previousAt = nil
        lastReading = nil
        frequencyTablesLoaded = false
        efficiencyFrequencies = []
        performanceFrequencies = []
        setupFailed = false
    }

    deinit { reset() }

    /// One read on the sampling tick. Returns a new average only once a full
    /// interval has elapsed since the baseline sample; otherwise returns the
    /// cached reading (or `nil` while warming up / unavailable).
    func read(at date: Date) -> CPUFrequencyReading? {
        guard ensureReady() else { return nil }
        if let previousSample, let previousAt {
            let elapsed = date.timeIntervalSince(previousAt)
            guard elapsed >= Self.minimumSampleInterval else { return lastReading }
            guard let current = sample() else { return lastReading }
            defer {
                self.previousSample = current
                self.previousAt = date
            }
            guard let delta = IOReportCreateSamplesDelta(previousSample, current, nil)?.takeRetainedValue() else {
                return lastReading
            }
            let reading = makeReading(from: delta, at: date)
            lastReading = reading
            return reading
        }
        // First tick: establish the baseline, no average yet.
        if let initial = sample() {
            previousSample = initial
            previousAt = date
        }
        return lastReading
    }

    private func ensureReady() -> Bool {
        if subscription != nil { return true }
        guard !setupFailed else { return false }
        let created = Self.createChannels()
        guard let created else {
            setupFailed = true
            return false
        }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let rawSubscription = IOReportCreateSubscription(nil, created, &subbed, 0, nil) else {
            subbed?.release()
            setupFailed = true
            return false
        }
        subbed?.release()
        channels = created
        subscription = rawSubscription.takeRetainedValue()
        loadFrequencyTablesIfNeeded()
        return true
    }

    private func sample() -> CFDictionary? {
        guard let subscription, let channels else { return nil }
        return IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue()
    }

    private static func createChannels() -> CFMutableDictionary? {
        let groups: [(String, String)] = [
            ("CPU Stats", "CPU Complex Performance States"),
            ("CPU Stats", "CPU Core Performance States")
        ]
        var merged: CFMutableDictionary?
        for (group, subgroup) in groups {
            guard let channel = IOReportCopyChannelsInGroup(group as CFString, subgroup as CFString, 0, 0, 0)?
                .takeRetainedValue() else { continue }
            if let merged {
                IOReportMergeChannels(merged, channel, nil)
            } else {
                merged = channel
            }
        }
        guard let merged else { return nil }
        let size = CFDictionaryGetCount(merged)
        guard size > 0 else { return nil }
        return CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, merged)
    }

    private func makeReading(from delta: CFDictionary, at date: Date) -> CPUFrequencyReading {
        var efficiency: Double?
        var performance: Double?
        let superFrequency: Double? = nil
        let dictionary = delta as NSDictionary
        if let list = dictionary["IOReportChannels"] as? NSArray {
            let array = list as CFArray
            for index in 0..<CFArrayGetCount(array) {
                let channel = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: CFDictionary.self)
                let group = IOReportChannelGetGroup(channel)?.takeUnretainedValue() as String? ?? ""
                let subgroup = IOReportChannelGetSubGroup(channel)?.takeUnretainedValue() as String? ?? ""
                guard group == "CPU Stats", subgroup.contains("Complex") else { continue }
                let name = IOReportChannelGetChannelName(channel)?.takeUnretainedValue() as String? ?? ""
                switch name {
                case "ECPU":
                    efficiency = Self.averageFrequency(channel: channel, table: efficiencyFrequencies)
                case "PCPU":
                    if performance == nil {
                        performance = Self.averageFrequency(channel: channel, table: performanceFrequencies)
                    }
                default:
                    continue
                }
            }
        }
        return CPUFrequencyReading(efficiencyGHz: efficiency,
                                   performanceGHz: performance,
                                   superGHz: superFrequency,
                                   sampledAt: date)
    }

    /// Residency-weighted average frequency (GHz) for one channel. Mirrors the
    /// Stats SystemKit approach: skip leading IDLE/DOWN/OFF states, then require
    /// the remaining state count to match the DVFS table exactly.
    static func averageFrequency(channel: CFDictionary, table: [Int32]) -> Double? {
        guard !table.isEmpty else { return nil }
        let count = Int(IOReportStateGetCount(channel))
        guard count > 0 else { return nil }
        var residencies: [(name: String, value: Int64)] = []
        residencies.reserveCapacity(count)
        for index in 0..<count {
            let name = IOReportStateGetNameForIndex(channel, Int32(index))?.takeUnretainedValue() as String? ?? ""
            residencies.append((name, IOReportStateGetResidency(channel, Int32(index))))
        }
        guard let offset = residencies.firstIndex(where: {
            let name = $0.name.uppercased()
            return name != "IDLE" && name != "DOWN" && name != "OFF"
        }) else { return nil }
        guard residencies.count - offset == table.count else { return nil }
        let activeStates = residencies[offset...]
        let total = activeStates.reduce(Int64(0)) { $0 + max(0, $1.value) }
        guard total > 0 else {
            // Every active-state residency is zero: report the idle floor rather
            // than inventing a clock. This is still an estimate.
            return table.first.map { Double($0) / 1000 }
        }
        var weighted = 0.0
        for (index, entry) in activeStates.enumerated() {
            let share = Double(max(0, entry.value)) / Double(total)
            weighted += share * Double(table[index])
        }
        return weighted / 1000
    }

    private func loadFrequencyTablesIfNeeded() {
        guard !frequencyTablesLoaded else { return }
        frequencyTablesLoaded = true
        var iterator = io_iterator_t(0)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("pmgr"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        var service = io_iterator_t(0)
        while true {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            defer { IOObjectRelease(service) }
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }
            if efficiencyFrequencies.isEmpty, let data = props["voltage-states1-sram"] as? Data {
                efficiencyFrequencies = Self.decodeFrequencyTable(data)
            }
            if performanceFrequencies.isEmpty, let data = props["voltage-states5-sram"] as? Data {
                performanceFrequencies = Self.decodeFrequencyTable(data)
            }
        }
    }

    /// Decodes a `voltage-states` blob. Pre-M4 entries are 8 bytes: a little
    /// endian UInt32 frequency in Hz followed by a UInt32 voltage. A blob whose
    /// length is not a multiple of 8 is left empty (newer layout), so frequency
    /// shows unavailable rather than wrong numbers.
    static func decodeFrequencyTable(_ data: Data) -> [Int32] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty, bytes.count % 8 == 0 else { return [] }
        var frequencies: [Int32] = []
        var offset = 0
        while offset + 8 <= bytes.count {
            let hz = bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
            frequencies.append(Int32(Double(hz) / 1_000_000))
            offset += 8
        }
        return frequencies
    }
}
