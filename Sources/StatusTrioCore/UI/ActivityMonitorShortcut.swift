import AppKit

/// Launches (or activates) the system Activity Monitor. This needs no extra
/// permission: it is a plain `NSWorkspace` open of an Apple app, no Apple
/// Events, no accessibility.
enum ActivityMonitorShortcut {
    /// The bundle identifier of the built-in Activity Monitor app.
    static let bundleIdentifier = "com.apple.ActivityMonitor"
    /// Where Activity Monitor lives on every supported macOS version. Used as a
    /// fallback in case the bundle-id lookup fails.
    static let applicationPath = "/System/Applications/Utilities/Activity Monitor.app"

    /// The URL to open: the installed bundle when resolvable, otherwise the
    /// standard Utilities path if it exists. Split out from `open` so the
    /// resolution can be tested without launching anything.
    static func applicationURL(
        bundleIdentifierLookup: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        if let url = bundleIdentifierLookup(bundleIdentifier) {
            return url
        }
        return fileExists(applicationPath) ? URL(fileURLWithPath: applicationPath) : nil
    }

    /// Opens Activity Monitor, activating an already-running copy. Returns
    /// false when no installed app could be found.
    @discardableResult
    static func open(workspace: NSWorkspace = .shared) -> Bool {
        guard let url = applicationURL(
            bundleIdentifierLookup: { workspace.urlForApplication(withBundleIdentifier: $0) }
        ) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
    }
}
