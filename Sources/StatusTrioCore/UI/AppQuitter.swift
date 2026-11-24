import AppKit
import Darwin

/// One running application as snapshot for quit-target resolution. A plain
/// value instead of `NSRunningApplication` so the resolution logic is testable
/// without a live process table.
struct RunningAppInfo: Equatable, Sendable {
    let pid: pid_t
    let path: String?
    let bundleIdentifier: String?
    let terminated: Bool
}

/// A single force-quit action: a display name plus the PIDs to SIGKILL. The
/// current app is always excluded while the target is built.
struct ForceQuitTarget: Equatable, Sendable {
    let displayName: String
    let pids: [pid_t]
    /// Start time captured when the row was resolved, keyed by PID. The
    /// confirmation dialog can sit open while the app exits, so every signal
    /// re-checks this to avoid killing a process that reused the PID.
    var startedAt: [pid_t: UInt64] = [:]
}

/// Resolves list rows to running processes and force-quits them, following the
/// Stats popup behaviour (kill -9). This needs no extra permission: a same-user
/// GUI app dies on SIGKILL; another user's, root's, or a SIP-protected process
/// simply fails and the caller reports "couldn't quit".
@MainActor
enum AppQuitter {
    static var currentPID: pid_t { ProcessInfo.processInfo.processIdentifier }
    static var ownBundleIdentifier: String? { Bundle.main.bundleIdentifier }

    /// Snapshot of the applications `NSWorkspace` currently knows about.
    static func currentRunningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(pid: $0.processIdentifier,
                           path: $0.bundleURL?.path,
                           bundleIdentifier: $0.bundleIdentifier,
                           terminated: $0.isTerminated)
        }
    }

    /// A top-app row's force-quit target, or nil only when the target is unsafe
    /// (Status Trio itself) or gone (the app no longer runs / the PID was
    /// reused). Any live process PID is a valid target, like Stats; a failed
    /// SIGKILL is reported by the caller rather than hidden here.
    static func target(for row: TopAppRow,
                       running: [RunningAppInfo],
                       startTime: (Int32) -> UInt64? = { SystemProcessMetadataReader.startTime(for: $0) },
                       selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                       selfBundleID: String? = Bundle.main.bundleIdentifier) -> ForceQuitTarget? {
        switch row.id {
        case .application(let path):
            return target(forApplicationPath: path, name: row.name,
                          running: running, startTime: startTime,
                          selfPID: selfPID, selfBundleID: selfBundleID)
        case .process(let identity):
            return target(forProcess: identity, name: row.name,
                          running: running, startTime: startTime, selfPID: selfPID)
        }
    }

    /// A battery high-energy app's force-quit target. `id` is the bundle path.
    static func target(forApplicationPath path: String,
                       name: String,
                       running: [RunningAppInfo],
                       startTime: (Int32) -> UInt64? = { SystemProcessMetadataReader.startTime(for: $0) },
                       selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                       selfBundleID: String? = Bundle.main.bundleIdentifier) -> ForceQuitTarget? {
        let canonical = canonicalPath(path)
        let rowBundleID = Bundle(path: path)?.bundleIdentifier
        if let selfBundleID, let rowBundleID, rowBundleID == selfBundleID { return nil }

        func isQuittable(_ app: RunningAppInfo) -> Bool {
            guard !app.terminated, app.pid != selfPID else { return false }
            if let selfBundleID, app.bundleIdentifier == selfBundleID { return false }
            return true
        }
        var pids = running
            .filter { app in
                guard isQuittable(app), let appPath = app.path else { return false }
                return canonicalPath(appPath) == canonical
            }
            .map(\.pid)

        // The row's bundle path may not be the running copy (e.g. a CrossOver
        // bottle resolves to /Applications/CrossOver.app while the running app
        // is "CrossOver Preview.app"). Fall back to the bundle identifier so the
        // app is still selectable.
        if pids.isEmpty, let rowBundleID {
            pids = running
                .filter { isQuittable($0) && $0.bundleIdentifier == rowBundleID }
                .map(\.pid)
        }

        // A row can also group helper processes whose executable lives inside
        // the app bundle but which are not NSWorkspace applications (CrossOver's
        // wine processes). Kill them too, otherwise "quit" leaves them running
        // and the app's usage keeps showing in the list.
        pids.append(contentsOf: pidsWithExecutableUnder(bundlePath: path, selfPID: selfPID))

        // Capture every incarnation now: an app can relaunch and reuse a PID
        // before the user confirms, so the signal path verifies these again.
        var identities: [pid_t: UInt64] = [:]
        let verified = Array(Set(pids)).sorted().filter { pid in
            guard let started = startTime(pid) else { return false }
            identities[pid] = started
            return true
        }
        return verified.isEmpty
            ? nil
            : ForceQuitTarget(displayName: name, pids: verified, startedAt: identities)
    }

    /// Same-user processes whose executable path sits inside `bundlePath`.
    private static func pidsWithExecutableUnder(bundlePath: String, selfPID: pid_t) -> [pid_t] {
        let canonicalBundle = canonicalPath(bundlePath)
        let prefix = canonicalBundle.hasSuffix("/") ? canonicalBundle : canonicalBundle + "/"
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = min(Int(bytes) / MemoryLayout<pid_t>.stride + 64, 16_384)
        var buffer = [pid_t](repeating: 0, count: capacity)
        let returned = buffer.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        let count = max(0, min(Int(returned) / MemoryLayout<pid_t>.stride, capacity))
        var result: [pid_t] = []
        for pid in buffer.prefix(count) where pid > 0 && pid != selfPID {
            var pathBuffer = [CChar](repeating: 0, count: 4_096)
            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            let executable = String(decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if canonicalPath(executable).hasPrefix(prefix) { result.append(pid) }
        }
        return result
    }

    private static func target(forProcess identity: ProcessIdentity,
                               name: String,
                               running: [RunningAppInfo],
                               startTime: (Int32) -> UInt64?,
                               selfPID: pid_t) -> ForceQuitTarget? {
        // Any live PID with a verifiable start time can be force-quit, like
        // Stats. System/root processes will fail the SIGKILL and report a
        // message rather than being silently hidden.
        guard identity.pid > 0, identity.pid != selfPID else { return nil }
        // Without a recorded start time there is no way to tell the sampled
        // process from a later one that reused its PID, so refuse the target.
        guard let expected = identity.startedAt,
              let actual = startTime(identity.pid),
              actual == expected else { return nil }
        return ForceQuitTarget(
            displayName: name,
            pids: [identity.pid],
            startedAt: [identity.pid: expected]
        )
    }

    /// SIGKILLs every PID in the target after re-checking its identity.
    /// Returns true only when every signal was delivered (or the process was
    /// already gone) *and* every PID still belonged to the captured process.
    /// A mismatched or unreadable identity skips its signal and fails the batch,
    /// so a relaunched app is never killed by a stale confirmation. Never
    /// touches Status Trio.
    @discardableResult
    static func forceQuit(_ target: ForceQuitTarget,
                          terminate: (pid_t) -> Bool = { pid in
                              if Darwin.kill(pid, SIGKILL) == 0 { return true }
                              return errno == ESRCH
                          },
                          startTime: (Int32) -> UInt64? = { SystemProcessMetadataReader.startTime(for: $0) },
                          selfPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        var allSucceeded = true
        for pid in target.pids where pid != selfPID {
            guard let expected = target.startedAt[pid],
                  let actual = startTime(pid),
                  actual == expected else {
                allSucceeded = false
                continue
            }
            if !terminate(pid) { allSucceeded = false }
        }
        return allSucceeded
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
