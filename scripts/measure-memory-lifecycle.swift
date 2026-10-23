#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation

private let usageText = """
Usage: measure-memory-lifecycle.swift --pid <pid> --seconds <duration> \
--interval-ms <100...1000> --output <jsonl>

Reads process memory, identity, and on-screen window counts without reading
window titles or contents. Sampling stops without publishing output when the
target exits, execs, or its process identity changes.
"""

private struct Options {
    let pid: pid_t
    let seconds: TimeInterval
    let intervalMilliseconds: Int
    let output: URL
#if MEMORY_LIFECYCLE_TEST_HOOKS
    let registrationReady: URL?
    let registrationRelease: URL?
    let beforeFinalBoundaryReady: URL?
    let beforeFinalBoundaryRelease: URL?
    let afterPublicationReady: URL?
    let afterPublicationRelease: URL?
#endif
}

private struct UsageError: Error {
    let message: String
}

private struct MeasurementError: Error {
    let message: String
}

private struct ProcessIdentity: Equatable {
    let pid: pid_t
    let executablePath: String
    let executableUUID: String
    let startAbstime: UInt64
}

private struct ProcessState {
    let identity: ProcessIdentity
    let footprintBytes: UInt64
    let rssBytes: UInt64
    let lifetimePeakFootprintBytes: UInt64
}

private struct ObserverIdentity {
    let pid: pid_t
    let executablePath: String
}

private final class ProcessEventMonitor {
    private static let pollTimeout = timespec(tv_sec: 0, tv_nsec: 0)

    private let queue: Int32
    private(set) var failed = false

    init(pid: pid_t) throws {
        queue = kqueue()
        guard queue >= 0 else {
            throw MeasurementError(
                message: "cannot create process event queue: \(posixMessage("kqueue"))"
            )
        }

        let event = kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR),
            fflags: UInt32(NOTE_EXEC) | UInt32(NOTE_EXIT),
            data: 0,
            udata: nil
        )
        let result = withUnsafePointer(to: event) { pointer in
            withUnsafePointer(to: Self.pollTimeout) { timeout in
                kevent(queue, pointer, 1, nil, 0, timeout)
            }
        }
        guard result == 0 else {
            let code = errno
            close(queue)
            throw MeasurementError(
                message: "cannot observe PID \(pid) process exec/exit: " +
                    posixMessage("kevent", code: code)
            )
        }
    }

    deinit {
        close(queue)
    }

    func check() throws {
        guard !failed else {
            throw MeasurementError(message: "process exec/exit event detection failed")
        }
        var events = (kevent(), kevent(), kevent(), kevent())
        let count = withUnsafeMutableBytes(of: &events) { bytes in
            withUnsafePointer(to: Self.pollTimeout) { timeout in
                kevent(
                    queue,
                    nil,
                    0,
                    bytes.baseAddress?.assumingMemoryBound(to: kevent.self),
                    4,
                    timeout
                )
            }
        }
        guard count >= 0 else {
            failed = true
            throw MeasurementError(
                message: "cannot read process exec/exit events: \(posixMessage("kevent"))"
            )
        }
        guard count == 0 else {
            let flags = withUnsafeBytes(of: events) { bytes in
                let eventBuffer = bytes.bindMemory(to: kevent.self)
                return eventBuffer.prefix(Int(count)).reduce(UInt32(0)) {
                    $0 | UInt32($1.fflags)
                }
            }
            let detail = if flags & UInt32(NOTE_EXIT) != 0 {
                "target exited"
            } else if flags & UInt32(NOTE_EXEC) != 0 {
                "target exec changed process identity"
            } else {
                "target process event observed"
            }
            throw MeasurementError(
                message: "\(detail); discard this run and do not publish output"
            )
        }
    }
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    if arguments == ["--help"] {
        print(usageText)
        exit(0)
    }

    let required = ["--pid", "--seconds", "--interval-ms", "--output"]
    var allowed = Set(required)
#if MEMORY_LIFECYCLE_TEST_HOOKS
    allowed.formUnion([
        "--test-registration-ready",
        "--test-registration-release",
        "--test-before-final-boundary-ready",
        "--test-before-final-boundary-release",
        "--test-after-publication-ready",
        "--test-after-publication-release",
    ])
#endif
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--") else {
            throw UsageError(message: "unexpected argument: \(key)")
        }
        guard allowed.contains(key) else {
            throw UsageError(message: "unknown option: \(key)")
        }
        guard values[key] == nil else {
            throw UsageError(message: "duplicate option: \(key)")
        }
        guard index + 1 < arguments.count else {
            throw UsageError(message: "missing value for \(key)")
        }
        values[key] = arguments[index + 1]
        index += 2
    }

    for key in required where values[key] == nil {
        throw UsageError(message: "missing required option: \(key)")
    }
    guard let rawPID = values["--pid"],
          let parsedPID = Int64(rawPID),
          parsedPID > 0,
          parsedPID <= Int64(Int32.max)
    else {
        throw UsageError(message: "--pid must be a positive 32-bit integer")
    }
    guard let rawSeconds = values["--seconds"],
          let seconds = Double(rawSeconds),
          seconds.isFinite,
          seconds > 0
    else {
        throw UsageError(message: "--seconds must be a positive finite number")
    }
    guard let rawInterval = values["--interval-ms"],
          let interval = Int(rawInterval),
          (100 ... 1000).contains(interval)
    else {
        throw UsageError(message: "--interval-ms must be an integer from 100 through 1000")
    }
    guard let outputPath = values["--output"], !outputPath.isEmpty else {
        throw UsageError(message: "--output must be a nonempty path")
    }

#if MEMORY_LIFECYCLE_TEST_HOOKS
    let hookKeys = [
        "--test-registration-ready",
        "--test-registration-release",
        "--test-before-final-boundary-ready",
        "--test-before-final-boundary-release",
        "--test-after-publication-ready",
        "--test-after-publication-release",
    ]
    let hookValues = hookKeys.map { key in
        values[key].map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
    for pairIndex in stride(from: 0, to: hookValues.count, by: 2) {
        let ready = hookValues[pairIndex]
        let release = hookValues[pairIndex + 1]
        guard (ready == nil && release == nil) || (ready != nil && release != nil) else {
            throw UsageError(
                message: "test hook ready/release paths must be supplied together"
            )
        }
    }
#endif

#if MEMORY_LIFECYCLE_TEST_HOOKS
    return Options(
        pid: pid_t(parsedPID),
        seconds: seconds,
        intervalMilliseconds: interval,
        output: URL(fileURLWithPath: outputPath).standardizedFileURL,
        registrationReady: hookValues[0],
        registrationRelease: hookValues[1],
        beforeFinalBoundaryReady: hookValues[2],
        beforeFinalBoundaryRelease: hookValues[3],
        afterPublicationReady: hookValues[4],
        afterPublicationRelease: hookValues[5]
    )
#else
    return Options(
        pid: pid_t(parsedPID),
        seconds: seconds,
        intervalMilliseconds: interval,
        output: URL(fileURLWithPath: outputPath).standardizedFileURL
    )
#endif
}

private func posixMessage(_ operation: String, code: Int32 = errno) -> String {
    let detail = String(cString: strerror(code))
    return "\(operation) failed: \(detail) (errno \(code))"
}

private func executablePath(for pid: pid_t) throws -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = buffer.withUnsafeMutableBytes { bytes in
        proc_pidpath(pid, bytes.baseAddress, UInt32(bytes.count))
    }
    guard length > 0 else {
        throw MeasurementError(
            message: "cannot identify executable for PID \(pid): \(posixMessage("proc_pidpath"))"
        )
    }
    return String(cString: buffer)
}

private func readProcessState(pid: pid_t) throws -> ProcessState {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
        let rawUsage = UnsafeMutableRawPointer(pointer)
            .assumingMemoryBound(to: rusage_info_t?.self)
        return proc_pid_rusage(pid, RUSAGE_INFO_V4, rawUsage)
    }
    guard result == 0 else {
        throw MeasurementError(
            message: "proc_pid_rusage failed for PID \(pid): \(posixMessage("proc_pid_rusage"))"
        )
    }

    let processPath = try executablePath(for: pid)
    let uuid = withUnsafeBytes(of: usage.ri_uuid) { bytes in
        bytes.map { String(format: "%02x", $0) }.joined()
    }
    return ProcessState(
        identity: ProcessIdentity(
            pid: pid,
            executablePath: processPath,
            executableUUID: uuid,
            startAbstime: usage.ri_proc_start_abstime
        ),
        footprintBytes: usage.ri_phys_footprint,
        rssBytes: usage.ri_resident_size,
        lifetimePeakFootprintBytes: usage.ri_lifetime_max_phys_footprint
    )
}

private func validateMemory(_ state: ProcessState) throws {
    guard state.footprintBytes > 0,
          state.rssBytes > 0,
          state.lifetimePeakFootprintBytes > 0
    else {
        throw MeasurementError(
            message: "PID \(state.identity.pid) returned zero or missing memory data"
        )
    }
}

private func visibleWindowCount(for pid: pid_t) throws -> Int {
    guard let rows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        throw MeasurementError(message: "CGWindowListCopyWindowInfo returned no window metadata")
    }

    return rows.reduce(into: 0) { count, row in
        let ownerPID = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        if ownerPID == pid {
            count += 1
        }
    }
}

private func verifyIdentity(_ expected: ProcessIdentity, pid: pid_t) throws {
    let current = try readProcessState(pid: pid).identity
    guard current == expected else {
        throw MeasurementError(
            message: "process identity changed during sampling; discard this run"
        )
    }
}

private func jsonLine(
    state: ProcessState,
    visibleWindowCount: Int,
    observer: ObserverIdentity,
    timestamp: TimeInterval,
    elapsed: TimeInterval
) throws -> Data {
    let object: [String: Any] = [
        "timestamp": NSNumber(value: timestamp),
        "clock": "systemUptimeMonotonicSeconds",
        "elapsed": NSNumber(value: elapsed),
        "pid": Int(state.identity.pid),
        "executablePath": state.identity.executablePath,
        "executableUUID": state.identity.executableUUID,
        "startAbstime": NSNumber(value: state.identity.startAbstime),
        "footprintBytes": NSNumber(value: state.footprintBytes),
        "footprintMiB": NSNumber(value: Double(state.footprintBytes) / 1_048_576.0),
        "rssBytes": NSNumber(value: state.rssBytes),
        "rssMiB": NSNumber(value: Double(state.rssBytes) / 1_048_576.0),
        "lifetimePeakFootprintBytes": NSNumber(value: state.lifetimePeakFootprintBytes),
        "lifetimePeakFootprintMiB": NSNumber(
            value: Double(state.lifetimePeakFootprintBytes) / 1_048_576.0
        ),
        "visibleWindowCount": visibleWindowCount,
        "observer": [
            "pid": Int(observer.pid),
            "executablePath": observer.executablePath,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: object, options: [])
}

private func publishExclusively(from temporaryOutput: URL, to output: URL) -> Int32 {
    temporaryOutput.withUnsafeFileSystemRepresentation { source in
        output.withUnsafeFileSystemRepresentation { destination in
            guard let source, let destination else {
                errno = EINVAL
                return -1
            }
            return renameatx_np(
                AT_FDCWD,
                source,
                AT_FDCWD,
                destination,
                UInt32(RENAME_EXCL)
            )
        }
    }
}

private func waitForFile(_ url: URL, failure: String) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !FileManager.default.fileExists(atPath: url.path) {
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            throw MeasurementError(message: failure)
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
}

#if MEMORY_LIFECYCLE_TEST_HOOKS
private func runTestHandshake(
    ready: URL?,
    release: URL?,
    timeoutFailure: String
) throws {
    guard let ready, let release else {
        return
    }
    try Data().write(to: ready, options: .withoutOverwriting)
    try waitForFile(release, failure: timeoutFailure)
}
#endif

private func writeAtomically(options: Options) throws -> Int {
    let observer = ObserverIdentity(pid: getpid(), executablePath: try executablePath(for: getpid()))
    let processEvents = try ProcessEventMonitor(pid: options.pid)
#if MEMORY_LIFECYCLE_TEST_HOOKS
    if let ready = options.registrationReady,
       let release = options.registrationRelease {
        try Data().write(to: ready, options: .withoutOverwriting)
        try waitForFile(release, failure: "test registration handshake timed out")
    }
#endif
    let canonicalState = try readProcessState(pid: options.pid)
    try validateMemory(canonicalState)
    let canonicalIdentity = canonicalState.identity
    let fileManager = FileManager.default
    let outputDirectory = options.output.deletingLastPathComponent()
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    guard !fileManager.fileExists(atPath: options.output.path) else {
        throw MeasurementError(
            message: "output already exists; choose a fresh path: \(options.output.path)"
        )
    }
    let temporaryOutput = outputDirectory.appendingPathComponent(
        ".\(options.output.lastPathComponent).\(UUID().uuidString).tmp"
    )
    guard fileManager.createFile(atPath: temporaryOutput.path, contents: nil) else {
        throw MeasurementError(message: "cannot create temporary output at \(temporaryOutput.path)")
    }

    var publishCompleted = false
    defer {
        if !publishCompleted {
            try? fileManager.removeItem(at: temporaryOutput)
        }
    }

    let handle: FileHandle
    do {
        handle = try FileHandle(forWritingTo: temporaryOutput)
    } catch {
        throw MeasurementError(message: "cannot open temporary output: \(error.localizedDescription)")
    }
    var closeNeeded = true
    defer {
        if closeNeeded {
            try? handle.close()
        }
    }

    let start = ProcessInfo.processInfo.systemUptime
    let intervalSeconds = Double(options.intervalMilliseconds) / 1000.0
    var scheduledElapsed: TimeInterval = 0
    var sampleCount = 0

    while scheduledElapsed <= options.seconds + 0.000_001 {
        let wait = start + scheduledElapsed - ProcessInfo.processInfo.systemUptime
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, timestamp - start)
        try processEvents.check()
        let state = try readProcessState(pid: options.pid)
        guard state.identity == canonicalIdentity else {
            throw MeasurementError(
                message: "process identity changed during sampling; discard this run"
            )
        }
        try validateMemory(state)
        let windows = try visibleWindowCount(for: options.pid)
        let line = try jsonLine(
            state: state,
            visibleWindowCount: windows,
            observer: observer,
            timestamp: timestamp,
            elapsed: elapsed
        )
        do {
            try handle.write(contentsOf: line)
            try handle.write(contentsOf: Data([0x0a]))
        } catch {
            throw MeasurementError(
                message: "cannot write JSONL sample: \(error.localizedDescription)"
            )
        }
        sampleCount += 1
        scheduledElapsed += intervalSeconds
    }

    do {
        try handle.synchronize()
        try handle.close()
        closeNeeded = false
    } catch {
        throw MeasurementError(message: "cannot flush JSONL output: \(error.localizedDescription)")
    }

#if MEMORY_LIFECYCLE_TEST_HOOKS
    try runTestHandshake(
        ready: options.beforeFinalBoundaryReady,
        release: options.beforeFinalBoundaryRelease,
        timeoutFailure: "test before-final-boundary handshake timed out"
    )
#endif
    // This identity read plus event query is the accepted measurement boundary.
    try verifyIdentity(canonicalIdentity, pid: options.pid)
    try processEvents.check()
    guard publishExclusively(from: temporaryOutput, to: options.output) == 0 else {
        let code = errno
        throw MeasurementError(
            message: "cannot publish JSONL output: \(posixMessage("renameatx_np", code: code))"
        )
    }
    publishCompleted = true
#if MEMORY_LIFECYCLE_TEST_HOOKS
    try runTestHandshake(
        ready: options.afterPublicationReady,
        release: options.afterPublicationRelease,
        timeoutFailure: "test after-publication handshake timed out"
    )
#endif
    return sampleCount
}

private func main() throws {
    let options: Options
    do {
        options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    } catch let error as UsageError {
        throw error
    }

    let count = try writeAtomically(options: options)
    print("samples=\(count) output=\(options.output.path)")
}

do {
    try main()
} catch let error as UsageError {
    FileHandle.standardError.write(Data("usage error: \(error.message)\n\(usageText)\n".utf8))
    exit(64)
} catch let error as MeasurementError {
    FileHandle.standardError.write(Data("memory lifecycle measurement failed: \(error.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(
        Data("memory lifecycle measurement failed: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
