import AppKit
import CoreGraphics
import Foundation

struct FocusTargetIdentity: Equatable {
    let pid: Int32
    let path: String?
    let launchedAt: Date?
}

struct FocusTargetCoverage {
    enum Observation: Equatable {
        case waiting
        case bound
        case tracking
        case ended(String)
    }

    let expectedPID: Int32?
    private(set) var identity: FocusTargetIdentity?
    private(set) var failure: String?
    private(set) var boundAt: Double?

    mutating func observe(_ candidates: [FocusTargetIdentity], elapsed: Double) -> Observation {
        if let failure { return .ended(failure) }
        guard candidates.count <= 1 else { return end("multiple-targets") }
        guard let candidate = candidates.first else {
            return identity == nil ? .waiting : end("target-disappeared")
        }
        guard candidate.path != nil, candidate.launchedAt != nil else {
            return end("target-identity-unavailable")
        }
        if let expectedPID, candidate.pid != expectedPID { return end("unexpected-pid") }
        if let identity {
            return candidate == identity ? .tracking : end("target-identity-changed")
        }
        identity = candidate
        boundAt = elapsed
        return .bound
    }

    private mutating func end(_ reason: String) -> Observation {
        failure = reason
        return .ended(reason)
    }
}

#if !FOCUS_COVERAGE_TESTS
// Standalone, read-only diagnostics. Never linked into the app.
let arguments = Array(CommandLine.arguments.dropFirst())
guard [2, 4].contains(arguments.count),
      arguments[0].hasPrefix("com.lingsmbp.StatusTrio.dev."),
      let duration = Double(arguments[1]),
      duration.isFinite, duration > 0, duration <= 120,
      arguments.count == 2 || (arguments[2] == "--pid" && (Int32(arguments[3]) ?? 0) > 0) else {
    FileHandle.standardError.write(Data(
        "Usage: swift scripts/measure-ui-focus.swift <dev-bundle-id> <seconds: 0...120> [--pid <pid>]\n".utf8
    ))
    exit(2)
}

let bundleID = arguments[0]
let expectedPID = arguments.count == 4 ? Int32(arguments[3]) : nil
var coverage = FocusTargetCoverage(expectedPID: expectedPID)
let interval = 0.025
var started = ProcessInfo.processInfo.systemUptime
var samples = 0
var sampleTransitions = 0
var activationEvents = 0
var previousPID: pid_t?
var maximumSampleGap = 0.0
var lastSample = started

func emit(_ record: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func elapsed() -> Double {
    ProcessInfo.processInfo.systemUptime - started
}

emit([
    "type": "start",
    "date": ISO8601DateFormatter().string(from: Date()),
    "bundleID": bundleID,
    "expectedPID": expectedPID ?? 0,
    "durationSeconds": duration,
    "intervalSeconds": interval,
    "mainDisplayID": CGMainDisplayID(),
    "screens": NSScreen.screens.map { screen -> [String: Any] in
        [
            "displayID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber)?.uint32Value ?? 0,
            "frame": NSStringFromRect(screen.frame),
            "visibleFrame": NSStringFromRect(screen.visibleFrame),
            "scale": screen.backingScaleFactor
        ]
    }
])
let center = NSWorkspace.shared.notificationCenter
let observer = center.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication else { return }
    activationEvents += 1
    emit([
        "type": "activation",
        "elapsed": elapsed(),
        "pid": app.processIdentifier,
        "bundleID": app.bundleIdentifier ?? ""
    ])
}

while elapsed() < duration {
    let now = ProcessInfo.processInfo.systemUptime
    maximumSampleGap = max(maximumSampleGap, now - lastSample)
    lastSample = now
    let foreground = NSWorkspace.shared.frontmostApplication
    let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    let observation = coverage.observe(target.map {
        FocusTargetIdentity(
            pid: $0.processIdentifier,
            path: $0.bundleURL?.resolvingSymlinksInPath().path,
            launchedAt: $0.launchDate
        )
    }, elapsed: elapsed())
    if case .ended(let reason) = observation {
        emit(["type": "coverage-ended", "elapsed": elapsed(), "reason": reason])
        break
    }
    if case .bound = observation, let identity = coverage.identity {
        emit([
            "type": "target-bound", "elapsed": elapsed(),
            "pid": identity.pid, "path": identity.path ?? "",
            "launchedAt": identity.launchedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        ])
    }
    let foregroundPID = foreground?.processIdentifier ?? 0
    if let previousPID, previousPID != foregroundPID {
        sampleTransitions += 1
    }
    previousPID = foregroundPID
    samples += 1
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
        as? [[String: Any]] ?? []
    let targetPIDs = Set(target.map(\.processIdentifier))
    emit([
        "type": "sample",
        "elapsed": elapsed(),
        "targetBound": coverage.identity != nil,
        "foregroundPID": foregroundPID,
        "foregroundBundleID": foreground?.bundleIdentifier ?? "",
        "targets": target.map { app -> [String: Any] in
            [
                "pid": app.processIdentifier,
                "active": app.isActive,
                "activationPolicy": app.activationPolicy.rawValue
            ]
        },
        "windows": windows.compactMap { window -> [String: Any]? in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  targetPIDs.contains(pid) else { return nil }
            return [
                "number": window[kCGWindowNumber as String] ?? 0,
                "layer": window[kCGWindowLayer as String] ?? 0,
                "bounds": window[kCGWindowBounds as String] ?? [:]
            ]
        }
    ])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: interval))
}
center.removeObserver(observer)
emit([
    "type": "summary",
    "elapsed": elapsed(),
    "samples": samples,
    "sampleTransitions": sampleTransitions,
    "activationEvents": activationEvents,
    "targetPID": coverage.identity?.pid ?? 0,
    "targetBoundAtSeconds": coverage.boundAt ?? -1,
    "targetCoverageComplete": coverage.identity != nil && coverage.failure == nil,
    "coverageEndReason": coverage.failure ?? (coverage.identity == nil ? "target-never-observed" : "deadline"),
    "unmeasured": ["keyboard-routing", "pointer", "clipboard", "spaces"],
    "maximumSampleGapSeconds": maximumSampleGap
])
if coverage.identity == nil || coverage.failure != nil { exit(1) }
#endif
