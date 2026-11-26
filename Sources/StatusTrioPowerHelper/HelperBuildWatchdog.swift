import Foundation

/// Detects that the on-disk app bundle was replaced (updated) while this daemon
/// process is still running the previous binary.
///
/// Replacing an app does not restart an already-running `SMAppService` daemon:
/// the process keeps the old code in memory and a freshly launched app would
/// talk to a stale helper. This watchdog captures the app build the daemon was
/// started from; when a new connection arrives and the on-disk app build has
/// changed, the daemon exits itself. launchd then relaunches the binary at the
/// registered path — the freshly installed one — on the next connection.
final class HelperBuildWatchdog {
    private let startBuild: String?

    init() {
        startBuild = HelperBuildWatchdog.appBundleBuild()
    }

    /// True only when a start build was captured and the on-disk app build now
    /// differs. Unknown builds (e.g. a bare executable) never trigger a restart.
    func isStale() -> Bool {
        guard let startBuild,
              let current = HelperBuildWatchdog.appBundleBuild() else { return false }
        return startBuild != current
    }

    /// The `CFBundleVersion` of the `.app` bundle that contains this helper
    /// executable, read from disk at call time.
    static func appBundleBuild() -> String? {
        guard let bundleURL = appBundleURL() else { return nil }
        return Bundle(url: bundleURL)?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Walks up from the running executable to the enclosing `.app` bundle.
    static func appBundleURL() -> URL? {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        var url = executable.resolvingSymlinksInPath()
        while url.path != "/" && !url.path.isEmpty {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
