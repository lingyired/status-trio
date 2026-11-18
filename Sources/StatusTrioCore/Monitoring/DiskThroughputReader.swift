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
