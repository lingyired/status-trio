import Foundation
import IOKit

/// Cumulative byte counters for one physical storage driver, keyed by its
/// stable IORegistry entry ID so a reset/replug is detectable.
struct DiskByteTotals: Equatable, Sendable {
    var read: UInt64
    var written: UInt64
}

/// One aggregate disk read/write throughput sample across physical devices.
struct DiskThroughputReading: Equatable, Sendable {
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var sampledAt: Date
}

/// Reads cumulative read/write byte counters from `IOBlockStorageDriver`
/// statistics and derives aggregate throughput.
///
/// Only the physical driver nodes are counted, never the logical volumes layered
/// on them, so a single write is not counted twice. Device identity is the
/// IORegistry entry ID, so a topology change (device added/removed) invalidates
/// the baseline instead of fabricating a spike. The reader keeps its own previous
/// sample, so a missing/invalid interval or a counter reset yields `nil`.
final class DiskThroughputReader: @unchecked Sendable {
    private static let minimumInterval: TimeInterval = 0.2
    private static let maximumInterval: TimeInterval = 15

    typealias TotalsProvider = () -> [UInt64: DiskByteTotals]?

    private var previous: (totals: [UInt64: DiskByteTotals], at: Date)?
    private let provider: TotalsProvider

    init(provider: @escaping TotalsProvider = DiskThroughputReader.readDeviceTotals) {
        self.provider = provider
    }

    func read(at date: Date) -> DiskThroughputReading? {
        guard let current = provider() else {
            previous = nil
            return nil
        }
        defer { previous = (current, date) }
        guard let previous else { return nil }
        return Self.rates(previous: previous.totals, previousAt: previous.at,
                          current: current, currentAt: date)
    }

    func reset() {
        previous = nil
    }

    /// Pure rate math. Returns `nil` when the interval is unusable, the device
    /// set changed, or any counter went backwards (reset/wrap) so the caller
    /// never shows a fake spike.
    static func rates(previous: [UInt64: DiskByteTotals], previousAt: Date,
                      current: [UInt64: DiskByteTotals], currentAt: Date) -> DiskThroughputReading? {
        let interval = currentAt.timeIntervalSince(previousAt)
        guard interval >= minimumInterval, interval <= maximumInterval else { return nil }
        guard Set(previous.keys) == Set(current.keys) else { return nil }
        var readDelta: UInt64 = 0
        var writeDelta: UInt64 = 0
        for key in previous.keys {
            guard let p = previous[key], let c = current[key] else { return nil }
            guard c.read >= p.read, c.written >= p.written else { return nil }
            readDelta += c.read - p.read
            writeDelta += c.written - p.written
        }
        return DiskThroughputReading(
            readBytesPerSecond: Double(readDelta) / interval,
            writeBytesPerSecond: Double(writeDelta) / interval,
            sampledAt: currentAt)
    }

    /// Reads every physical `IOBlockStorageDriver` node's cumulative counters.
    /// Returns `nil` when the registry cannot be enumerated at all.
    static func readDeviceTotals() -> [UInt64: DiskByteTotals]? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var result: [UInt64: DiskByteTotals] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
               let stats = IORegistryEntryCreateCFProperty(
                    service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
               let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value,
               let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                result[entryID] = DiskByteTotals(read: read, written: written)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result.isEmpty ? nil : result
    }
}

/// Per-volume read/write throughput: every volume is mapped to the physical
/// `IOBlockStorageDriver` that backs its disk, so the internal disk and each
/// external disk report their own rates instead of one aggregate. Device
/// mapping is refreshed only when the mounted volume set changes.
final class DiskVolumeThroughputReader: @unchecked Sendable {
    private static let minimumInterval: TimeInterval = 0.2
    private static let maximumInterval: TimeInterval = 15

    private var previous: (totals: [UInt64: DiskByteTotals], at: Date)?
    private var volumeToDriver: [String: UInt64] = [:]
    private var mappedPaths: [String] = []

    func read(at date: Date, volumes: [DiskVolumeReading]) -> [String: DiskThroughputReading] {
        let paths = volumes.map(\.mountPath)
        if paths != mappedPaths {
            var mapping: [String: UInt64] = [:]
            for path in paths {
                if let id = Self.driverEntryID(forVolumePath: path) { mapping[path] = id }
            }
            volumeToDriver = mapping
            mappedPaths = paths
        }
        guard let current = DiskThroughputReader.readDeviceTotals() else {
            previous = nil
            return [:]
        }
        defer { previous = (current, date) }
        guard let previous else { return [:] }
        let interval = date.timeIntervalSince(previous.at)
        guard interval >= Self.minimumInterval, interval <= Self.maximumInterval else { return [:] }
        var result: [String: DiskThroughputReading] = [:]
        for (path, id) in volumeToDriver {
            guard let now = current[id], let before = previous.totals[id],
                  now.read >= before.read, now.written >= before.written else { continue }
            result[path] = DiskThroughputReading(
                readBytesPerSecond: Double(now.read - before.read) / interval,
                writeBytesPerSecond: Double(now.written - before.written) / interval,
                sampledAt: date)
        }
        return result
    }

    func reset() {
        previous = nil
        volumeToDriver = [:]
        mappedPaths = []
    }

    /// The `IOBlockStorageDriver` registry entry that backs a mounted volume.
    /// Walks up from the volume's `IOMedia` so APFS container volumes resolve to
    /// the physical store driver (e.g. disk3s7 → disk0's driver).
    static func driverEntryID(forVolumePath path: String) -> UInt64? {
        guard let bsd = bsdName(forPath: path),
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsd) else { return nil }
        var current = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard current != 0 else { return nil }
        var depth = 0
        while depth < 16 {
            var buffer = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(current, &buffer) == KERN_SUCCESS,
               String(cString: buffer) == "IOBlockStorageDriver" {
                var entryID: UInt64 = 0
                let ok = IORegistryEntryGetRegistryEntryID(current, &entryID) == KERN_SUCCESS
                IOObjectRelease(current)
                return ok ? entryID : nil
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                IOObjectRelease(current)
                return nil
            }
            IOObjectRelease(current)
            current = parent
            depth += 1
        }
        IOObjectRelease(current)
        return nil
    }

    private static func bsdName(forPath path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        let device = withUnsafePointer(to: &stats.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return (device as NSString).lastPathComponent
    }
}
