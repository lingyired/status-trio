import Foundation

/// Which detail page owns a top-application list.
enum TopAppMetric: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case network
}

/// A process incarnation: a PID reused by a new process must not inherit the
/// previous process's cumulative counters.
struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    /// Mach/BSD start time in nanoseconds; nil when the system would not tell us.
    let startedAt: UInt64?

    var isStable: Bool { startedAt != nil }
}

/// Identity metadata read from libproc. No process contents are read.
struct ProcessMetadata: Sendable, Equatable {
    let identity: ProcessIdentity
    let name: String
    let executablePath: String?
    let responsiblePID: Int32?
}

/// A running application as reported by NSWorkspace.
struct ProcessApplication: Equatable, Sendable {
    let pid: Int32
    let path: String
    let bundleID: String?
    let name: String
}

/// Grouping identity for a ranked row. Applications group by canonical bundle
/// path; anything that cannot be attributed safely stays its own process row.
enum TopAppIdentity: Hashable, Sendable {
    case application(path: String)
    case process(ProcessIdentity)

    var stableKey: String {
        switch self {
        case .application(let path):
            return "app:\(path)"
        case .process(let identity):
            return "pid:\(identity.pid):\(identity.startedAt ?? 0)"
        }
    }
}

/// The identity and display metadata produced by application attribution.
struct ProcessAppResolution: Equatable, Sendable {
    let identity: TopAppIdentity
    let name: String
    let applicationPath: String?
}

/// One ranked row. Network rows use `value` for download bytes/second and
/// `upload` for upload bytes/second; every other metric leaves `upload` nil.
struct TopAppRow: Equatable, Identifiable, Sendable {
    let id: TopAppIdentity
    let name: String
    let applicationPath: String?
    let value: Double
    let upload: Double?
}

/// One process's contribution before application grouping.
struct ProcessUsageSample: Sendable, Equatable {
    let metadata: ProcessMetadata
    let value: Double
    let upload: Double?

    init(metadata: ProcessMetadata, value: Double, upload: Double? = nil) {
        self.metadata = metadata
        self.value = value
        self.upload = upload
    }
}

/// Result of one complete top-application read.
enum TopAppsReadResult: Equatable, Sendable {
    /// Cumulative readers need a second sample before they can compute a rate.
    case collecting
    case measured([TopAppRow])
    case unsupported
    case failed
}

/// Observable state published to the detail page.
enum TopAppsState: Equatable, Sendable {
    case idle
    case collecting(TopAppMetric)
    case measured(TopAppMetric, [TopAppRow])
    case unsupported(TopAppMetric)
    case failed(TopAppMetric)
}

/// Errors shared by the command, network and GPU readers.
enum TopAppReadError: Error, Equatable, Sendable {
    case launchOrExit
    case malformedOutput
    case timedOut
    case cancelled
    case outputTooLarge
    case unsupported
}
