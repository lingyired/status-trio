import Foundation

/// Gates the local JSON package preview at both the settings and runtime boundaries.
enum LocalIconPluginAccess {
    static let sandboxEnvironmentKey = "APP_SANDBOX_CONTAINER_ID"
    private static let packagesEnabled = false

    static func isSandboxed(environment: [String: String]) -> Bool {
        environment[sandboxEnvironmentKey] != nil
    }

    static func entryIsAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        enabled: Bool = packagesEnabled
    ) -> Bool {
        enabled && !isSandboxed(environment: environment)
    }

    static func resolvedDirectories(
        paths: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        enabled: Bool = packagesEnabled
    ) -> [URL] {
        guard entryIsAvailable(environment: environment, enabled: enabled) else { return [] }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
