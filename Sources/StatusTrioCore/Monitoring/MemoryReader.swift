import Foundation
import Darwin

/// Read-only machine memory usage, expressed as a 0–100 percentage of physical RAM.
///
/// Mirrors the common "Memory Used" definition (App Memory + Wired +
/// Compressed): active pages minus purgeable, plus wired and compressed. It is
/// an instantaneous gauge, not a differential, and needs no privilege.
struct MemoryReader: Sendable {
    struct Reading: Equatable, Sendable {
        let percent: Double
        let usedBytes: UInt64
        let totalBytes: UInt64
        let sampledAt: Date
    }

    func read(at date: Date = Date()) -> Reading? {
        // One `host_statistics64` call; the detail path reuses the same struct so
        // opening the memory page never reads the VM statistics a second time.
        guard let stats = Self.detailStatistics() else { return nil }
        return Self.reading(from: stats, at: date)
    }

    /// Pure conversion from one VM statistics snapshot to the gauge reading.
    static func reading(from stats: MemoryStatistics, at date: Date) -> Reading? {
        guard let percent = Self.percentage(activeBytes: stats.activeBytes,
                                            purgeableBytes: stats.purgeableBytes,
                                            wiredBytes: stats.wiredBytes,
                                            compressedBytes: stats.compressedBytes,
                                            totalBytes: stats.totalBytes) else { return nil }
        let used = Self.usedBytes(activeBytes: stats.activeBytes,
                                  purgeableBytes: stats.purgeableBytes,
                                  wiredBytes: stats.wiredBytes,
                                  compressedBytes: stats.compressedBytes,
                                  totalBytes: stats.totalBytes)
        return Reading(percent: percent, usedBytes: used, totalBytes: stats.totalBytes, sampledAt: date)
    }

    /// One-shot combined read for the memory detail page: the gauge and the
    /// breakdown come from a single VM statistics read. Swap and pressure are
    /// detail-only fields, read here but never on the summary path.
    struct Snapshot: Equatable, Sendable {
        let reading: Reading
        let detail: MemoryDetailReading
    }

    func readWithDetail(at date: Date = Date()) -> Snapshot? {
        guard let stats = Self.detailStatistics(),
              let reading = Self.reading(from: stats, at: date) else { return nil }
        let swap = Self.swapUsage()
        let detail = Self.detail(from: stats,
                                 swapUsedBytes: swap.used,
                                 swapTotalBytes: swap.total,
                                 pressure: Self.pressureLevel(),
                                 at: date)
        return Snapshot(reading: reading, detail: detail)
    }

    /// Pure formula so the semantics are unit-testable without host statistics.
    static func usedBytes(activeBytes: UInt64, purgeableBytes: UInt64,
                          wiredBytes: UInt64, compressedBytes: UInt64,
                          totalBytes: UInt64) -> UInt64 {
        let app = activeBytes > purgeableBytes ? activeBytes - purgeableBytes : 0
        let used = app &+ wiredBytes &+ compressedBytes
        return min(used, totalBytes)
    }

    static func percentage(activeBytes: UInt64, purgeableBytes: UInt64,
                           wiredBytes: UInt64, compressedBytes: UInt64,
                           totalBytes: UInt64) -> Double? {
        guard totalBytes > 0 else { return nil }
        let used = usedBytes(activeBytes: activeBytes, purgeableBytes: purgeableBytes,
                             wiredBytes: wiredBytes, compressedBytes: compressedBytes,
                             totalBytes: totalBytes)
        let percent = Double(used) / Double(totalBytes) * 100.0
        return percent.isFinite ? percent : nil
    }

    // MARK: - Detail

    /// Raw page-state inputs for the detail breakdown, in bytes.
    struct MemoryStatistics: Equatable, Sendable {
        var activeBytes: UInt64
        var purgeableBytes: UInt64
        var wiredBytes: UInt64
        var compressedBytes: UInt64
        var internalBytes: UInt64
        var externalBytes: UInt64
        var freeBytes: UInt64
        var totalBytes: UInt64
    }

    func readDetail(at date: Date = Date()) -> MemoryDetailReading? {
        guard let stats = Self.detailStatistics() else { return nil }
        let swap = Self.swapUsage()
        return Self.detail(from: stats,
                           swapUsedBytes: swap.used,
                           swapTotalBytes: swap.total,
                           pressure: Self.pressureLevel(),
                           at: date)
    }

    /// Pure breakdown so the category maths is unit-testable without host stats.
    /// `usedBytes` keeps the existing gauge (app + wired + compressed); cached
    /// files are reclaimable and counted separately, never added to `usedBytes`.
    static func detail(from stats: MemoryStatistics,
                       swapUsedBytes: UInt64,
                       swapTotalBytes: UInt64,
                       pressure: MemoryPressureLevel,
                       at date: Date) -> MemoryDetailReading {
        let app = stats.activeBytes > stats.purgeableBytes ? stats.activeBytes - stats.purgeableBytes : 0
        let used = min(app &+ stats.wiredBytes &+ stats.compressedBytes, stats.totalBytes)
        let percent = stats.totalBytes > 0 ? Double(used) / Double(stats.totalBytes) * 100 : 0
        let cached = stats.externalBytes &+ stats.purgeableBytes
        return MemoryDetailReading(percent: percent.isFinite ? percent : 0,
                                   usedBytes: used,
                                   totalBytes: stats.totalBytes,
                                   appBytes: app,
                                   wiredBytes: stats.wiredBytes,
                                   compressedBytes: stats.compressedBytes,
                                   cachedBytes: cached,
                                   swapUsedBytes: swapUsedBytes,
                                   swapTotalBytes: swapTotalBytes,
                                   pressure: pressure,
                                   sampledAt: date)
    }

    private static func detailStatistics() -> MemoryStatistics? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        return MemoryStatistics(
            activeBytes: UInt64(stats.active_count) * page,
            purgeableBytes: UInt64(stats.purgeable_count) * page,
            wiredBytes: UInt64(stats.wire_count) * page,
            compressedBytes: UInt64(stats.compressor_page_count) * page,
            internalBytes: UInt64(stats.internal_page_count) * page,
            externalBytes: UInt64(stats.external_page_count) * page,
            freeBytes: UInt64(stats.free_count) * page,
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private static func pressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressureLevel.from(rawLevel: level)
    }

    private static func statistics() -> (active: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        return (
            active: UInt64(stats.active_count) * page,
            purgeable: UInt64(stats.purgeable_count) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            total: ProcessInfo.processInfo.physicalMemory
        )
    }
}