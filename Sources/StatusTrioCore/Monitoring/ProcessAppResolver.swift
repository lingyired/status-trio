import Foundation

/// Maps a process onto the application that owns it.
///
/// The order is deliberate: the responsibility PID is the strongest signal for
/// helpers and XPC children; an exact PID match covers the app's own process;
/// the bundle path is a last resort for processes whose owner app is not in the
/// running-application table. A failed lookup never collapses processes into a
/// shared fallback bucket.
enum ProcessAppResolver {
    static func resolve(_ metadata: ProcessMetadata,
                        applications: [ProcessApplication],
                        parentMetadata: ((Int32) -> ProcessMetadata?)? = nil) -> ProcessAppResolution {
        let byPID = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        if let responsiblePID = metadata.responsiblePID,
           responsiblePID > 0,
           responsiblePID != metadata.identity.pid,
           let app = byPID[responsiblePID] {
            return resolution(for: app)
        }
        if let app = byPID[metadata.identity.pid] {
            return resolution(for: app)
        }
        if let bundlePath = owningApplicationPath(for: metadata.executablePath) {
            if let app = applications.first(where: { canonicalPath($0.path) == bundlePath }) {
                return resolution(for: app)
            }
            return ProcessAppResolution(
                identity: .application(path: bundlePath),
                name: applicationName(fromBundlePath: bundlePath),
                applicationPath: bundlePath
            )
        }
        if let parentMetadata {
            var parent = metadata.parentPID
            var seen: Set<Int32> = []
            for _ in 0..<4 {
                guard let pid = parent, pid > 0, seen.insert(pid).inserted,
                      let parentInfo = parentMetadata(pid),
                      parentInfo.identity.startedAt != nil else { break }
                if let app = byPID[pid] {
                    return resolution(for: app)
                }
                if let bundlePath = owningApplicationPath(for: parentInfo.executablePath),
                   let app = applications.first(where: { canonicalPath($0.path) == bundlePath }) {
                    return resolution(for: app)
                }
                parent = parentInfo.parentPID
            }
        }
        return ProcessAppResolution(identity: .process(metadata.identity),
                                    name: metadata.name,
                                    applicationPath: nil)
    }

    private static func resolution(for app: ProcessApplication) -> ProcessAppResolution {
        let path = canonicalPath(app.path)
        return ProcessAppResolution(identity: .application(path: path),
                                    name: app.name,
                                    applicationPath: path)
    }

    /// Standardizes a path without resolving symlinks, so two launch paths that
    /// name the same bundle still compare equal.
    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// The outermost `.app` bundle containing an executable path. Nested
    /// Helper.app bundles must collapse into the outer app, so the first
    /// `.app/` component wins, not the longest one.
    static func owningApplicationPath(for executablePath: String?) -> String? {
        guard let executablePath, !executablePath.isEmpty else { return nil }
        let lowercased = executablePath.lowercased()
        guard let range = lowercased.range(of: ".app/") else {
            if lowercased.hasSuffix(".app") { return canonicalPath(executablePath) }
            return nil
        }
        let end = lowercased.index(range.lowerBound, offsetBy: 4)
        return canonicalPath(String(executablePath[..<end]))
    }

    static func applicationName(fromBundlePath path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
