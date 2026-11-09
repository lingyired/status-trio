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
        guard let sample = Self.statistics() else { return nil }
        guard let percent = Self.percentage(activeBytes: sample.active,
                                            purgeableBytes: sample.purgeable,
                                            wiredBytes: sample.wired,
                                            compressedBytes: sample.compressed,
                                            totalBytes: sample.total) else { return nil }
        let used = Self.usedBytes(activeBytes: sample.active,
                                  purgeableBytes: sample.purgeable,
                                  wiredBytes: sample.wired,
                                  compressedBytes: sample.compressed,
                                  totalBytes: sample.total)
        return Reading(percent: percent, usedBytes: used, totalBytes: sample.total, sampledAt: date)
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