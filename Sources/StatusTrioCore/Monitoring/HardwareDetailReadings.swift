import Foundation

/// Memory-pressure bucket, mapped from `kern.memorystatus_vm_pressure_level`.
enum MemoryPressureLevel: String, Equatable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    /// 1 = normal, 2 = warning, 4 = critical (XNU pressure levels).
    static func from(rawLevel: Int32) -> MemoryPressureLevel {
        switch rawLevel {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }
}

/// Per-device GPU detail. Unified-memory Macs have no dedicated VRAM, so the
/// memory field is labelled as shared system memory, never "VRAM".
struct GPUDetailReading: Equatable, Sendable {
    var deviceName: String?
    var usage: Double?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var inUseSystemMemoryBytes: UInt64?
    var sampledAt: Date
}

/// Structured memory detail. Categories are deliberately NOT presented as an
/// exhaustive partition of physical RAM: `usedBytes` keeps the existing
/// "App + Wired + Compressed" gauge, while `cachedBytes` (file-backed,
/// reclaimable) and swap are shown separately.
struct MemoryDetailReading: Equatable, Sendable {
    var percent: Double
    var usedBytes: UInt64
    var totalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var cachedBytes: UInt64
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var pressure: MemoryPressureLevel
    var sampledAt: Date
}

/// Network detail. Session totals accumulate only across valid, interval-bounded
/// deltas of the counted physical interfaces; a topology change or reset drops
/// the baseline and does not add a fabricated spike.
struct NetworkDetailReading: Equatable, Sendable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    var sessionReceivedBytes: UInt64
    var sessionSentBytes: UInt64
    var interfaces: [String]
    var sampledAt: Date
}

/// Disk capacity for the detail page (system volume), separate from the I/O
/// rates which are measured on the physical drivers.
struct DiskCapacityReading: Equatable, Sendable {
    var totalBytes: UInt64
    var freeBytes: UInt64
    var usedBytes: UInt64
    var fileSystem: String?
    var sampledAt: Date

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

/// Combined disk detail: capacity (system volume) plus read/write throughput
/// (physical drivers). These two measure different objects and are labelled
/// separately in the UI.
struct DiskDetailReading: Equatable, Sendable {
    var capacity: DiskCapacityReading?
    var readBytesPerSecond: Double?
    var writeBytesPerSecond: Double?
    var sampledAt: Date
}
