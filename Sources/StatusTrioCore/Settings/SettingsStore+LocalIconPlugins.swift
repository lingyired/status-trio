import Foundation

extension SettingsStore {
    /// Whether this build exposes local JSON packages in settings and at runtime.
    var isLocalIconPluginEntryAvailable: Bool {
        LocalIconPluginAccess.entryIsAvailable()
    }

    @discardableResult
    func addLocalIconPluginDirectory(_ url: URL) -> Bool {
        guard isLocalIconPluginEntryAvailable else { return false }
        let path = url.path
        guard !localIconPluginDirectories.contains(path) else { return true }
        localIconPluginDirectories.append(path)
        return true
    }

    func removeLocalIconPluginDirectory(_ url: URL) {
        localIconPluginDirectories.removeAll { $0 == url.path }
    }

    /// Resolves saved directories only when local packages are available.
    func resolvedLocalIconPluginDirectories() -> [URL] {
        LocalIconPluginAccess.resolvedDirectories(paths: localIconPluginDirectories)
    }
}
