import Foundation

/// Local JSON packages are a Direct-build feature.
///
/// This branch has no verified App Store entitlement or build pipeline for
/// durable folder access, so a sandboxed process neither advertises the external
/// entry nor resolves any configured path. Hiding the feature is deliberate: a
/// bare path is not a usable authorization in a sandbox, and resolving a
/// security-scoped bookmark without a matching `stopAccessing…` call would leak
/// the access the app never releases.
enum LocalIconPluginAccess {
    static let sandboxEnvironmentKey = "APP_SANDBOX_CONTAINER_ID"

    static var isSandboxed: Bool {
        isSandboxed(environment: ProcessInfo.processInfo.environment)
    }

    static func isSandboxed(environment: [String: String]) -> Bool {
        environment[sandboxEnvironmentKey] != nil
    }

    /// The external package entry is compiled in only for Direct builds.
    static func entryIsAvailable(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !isSandboxed(environment: environment)
    }

    /// Direct builds read the explicitly enabled paths. A sandboxed build resolves
    /// nothing, including when paths were persisted by a Direct build running
    /// against the same preferences.
    static func resolvedDirectories(
        paths: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        guard entryIsAvailable(environment: environment) else { return [] }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
