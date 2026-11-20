import Foundation

extension SettingsStore {
    /// The external package entry is a Direct-build feature. A sandboxed build
    /// hides it entirely until a verified App Store authorization pipeline
    /// exists; it must not resolve bare paths or bookmarks as a stand-in.
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

    /// Resolves the enabled directories for the current build. Direct builds use
    /// the persisted paths; sandboxed builds resolve nothing.
    func resolvedLocalIconPluginDirectories() -> [URL] {
        LocalIconPluginAccess.resolvedDirectories(paths: localIconPluginDirectories)
    }
}
