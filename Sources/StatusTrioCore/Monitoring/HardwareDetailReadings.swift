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
/// exhaustive partition of physical RAM: `usedBytes` is the Activity Monitor
/// "Memory Used" gauge ("App + Wired + Compressed"), with `appBytes` taken from
/// anonymous/internal pages minus purgeable, while `cachedBytes` (file-backed,
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

/// One mounted volume shown on the disk detail page. Capacity comes from the
/// same `FileManager` volume keys as `DiskCapacityReading`; `isExternal` comes
/// from the volume's `volumeIsInternal` flag so a USB/Thunderbolt disk is
/// labelled without any extra probing.
struct DiskVolumeReading: Equatable, Sendable, Identifiable {
    var name: String
    var mountPath: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var fileSystem: String?
    var isExternal: Bool
    var isReadOnly: Bool

    var id: String { mountPath }

    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }
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
    /// Every mounted local volume (internal + external), startup volume first.
    /// Empty when the volume enumeration produced nothing; the UI then falls
    /// back to the single `capacity` summary.
    var volumes: [DiskVolumeReading] = []
    /// Per-volume read/write throughput, keyed by the volume's mount path, so
    /// each disk reports its own rate instead of one aggregate.
    var volumeSpeeds: [String: DiskThroughputReading] = [:]
    var sampledAt: Date
}

/// Last structured payload built for one detail page, retained by the monitor
/// after that page closes so reopening paints the previous reading instead of an
/// empty card. Payloads are a few dozen numbers; they are refreshed only while
/// their page is open, so retaining them adds no sampling work.
enum HardwareDetailPayload: Equatable, Sendable {
    case cpu(CPUDetailReading)
    case gpu(GPUDetailReading)
    case memory(MemoryDetailReading)
    case network(NetworkDetailReading)
    case disk(DiskDetailReading)

    /// How long a retained payload may be restored on reopen. Matches the
    /// summary sample cache: a bounded previous reading beats a blank page, and
    /// the page refreshes immediately anyway; past this the value is dropped.
    static let cacheLifetime: TimeInterval = 300

    /// The payload this snapshot carries for `kind`, if it has one.
    init?(snapshot: HardwareMetricsSnapshot, kind: HardwareDetailKind) {
        switch kind {
        case .cpu:
            guard let detail = snapshot.cpuDetail else { return nil }
            self = .cpu(detail)
        case .gpu:
            guard let detail = snapshot.gpuDetail else { return nil }
            self = .gpu(detail)
        case .memory:
            guard let detail = snapshot.memoryDetail else { return nil }
            self = .memory(detail)
        case .network:
            guard let detail = snapshot.networkDetail else { return nil }
            self = .network(detail)
        case .disk:
            guard let detail = snapshot.diskDetail else { return nil }
            self = .disk(detail)
        case .fan:
            // The fan page renders fan samples, not a structured payload.
            return nil
        }
    }

    var sampledAt: Date {
        switch self {
        case let .cpu(detail): return detail.sampledAt
        case let .gpu(detail): return detail.sampledAt
        case let .memory(detail): return detail.sampledAt
        case let .network(detail): return detail.sampledAt
        case let .disk(detail): return detail.sampledAt
        }
    }

    /// Writes this payload into a snapshot, leaving other pages' fields alone.
    func apply(to snapshot: inout HardwareMetricsSnapshot) {
        switch self {
        case let .cpu(detail): snapshot.cpuDetail = detail
        case let .gpu(detail): snapshot.gpuDetail = detail
        case let .memory(detail): snapshot.memoryDetail = detail
        case let .network(detail): snapshot.networkDetail = detail
        case let .disk(detail): snapshot.diskDetail = detail
        }
    }
}
