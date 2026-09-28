import AppKit
import Foundation

@MainActor
protocol BatteryWorkspace {
    func applicationURL(bundleIdentifier: String) -> URL?
    func fileExists(at url: URL) -> Bool
    func openURL(_ url: URL) -> Bool
    func openApplication(_ url: URL) async throws
}

@MainActor
struct SystemBatteryWorkspace: BatteryWorkspace {
    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func fileExists(at url: URL) -> Bool {
        guard Self.isApplicationBundleURL(url) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func openApplication(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func isApplicationBundleURL(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}

@MainActor
final class BatteryActionLauncher {
    private let workspace: any BatteryWorkspace
    private let definitions: [KnownBatteryAppDefinition]

    init(
        workspace: any BatteryWorkspace = SystemBatteryWorkspace(),
        definitions: [KnownBatteryAppDefinition] = KnownBatteryApps.all
    ) {
        self.workspace = workspace
        self.definitions = definitions
    }

    func isInstalled(_ definition: KnownBatteryAppDefinition) -> Bool {
        firstExistingApplicationURL(bundleIdentifiers: definition.bundleIdentifiers) != nil
    }

    static func validatedURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }

    func open(
        target: BatteryActionTarget,
        systemSettingsFallback: @escaping @MainActor () -> Void
    ) async {
        switch target {
        case .systemSettings:
            systemSettingsFallback()
        case .knownApp(let id):
            await openKnownApp(id, systemSettingsFallback: systemSettingsFallback)
        case .customApp(let application):
            let candidates = applicationCandidates(for: application)
            await openApplications(candidates, systemSettingsFallback: systemSettingsFallback)
        case .customURL(let raw):
            guard let url = Self.validatedURL(raw), workspace.openURL(url) else {
                systemSettingsFallback()
                return
            }
        }
    }

    private func openKnownApp(
        _ id: KnownBatteryAppID,
        systemSettingsFallback: @escaping @MainActor () -> Void
    ) async {
        guard let definition = definitions.first(where: { $0.id == id }),
              let applicationURL = firstExistingApplicationURL(
                bundleIdentifiers: definition.bundleIdentifiers
              ) else {
            systemSettingsFallback()
            return
        }

        if let deepLink = definition.deepLink, workspace.openURL(deepLink) {
            return
        }

        await openApplications([applicationURL], systemSettingsFallback: systemSettingsFallback)
    }

    private func applicationCandidates(for application: ExternalApplicationTarget) -> [URL] {
        var candidates: [URL] = []
        if let bundleIdentifier = usableBundleIdentifier(application.bundleIdentifier),
           let applicationURL = workspace.applicationURL(bundleIdentifier: bundleIdentifier),
           isExistingApplication(at: applicationURL) {
            candidates.append(applicationURL)
        }

        if let fallbackPath = usableApplicationPath(application.fallbackPath) {
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            if isExistingApplication(at: fallbackURL) {
                candidates.append(fallbackURL)
            }
        }

        var seenPaths: Set<String> = []
        return candidates.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    private func firstExistingApplicationURL(bundleIdentifiers: [String]) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            guard let identifier = usableBundleIdentifier(bundleIdentifier),
                  let url = workspace.applicationURL(bundleIdentifier: identifier),
                  isExistingApplication(at: url) else {
                continue
            }
            return url
        }
        return nil
    }

    private func isExistingApplication(at url: URL) -> Bool {
        url.isFileURL
            && url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            && workspace.fileExists(at: url)
    }

    private func usableBundleIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func usableApplicationPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func openApplications(
        _ candidates: [URL],
        systemSettingsFallback: @escaping @MainActor () -> Void
    ) async {
        var attemptedPaths: Set<String> = []
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard attemptedPaths.insert(path).inserted else { continue }
            do {
                try await workspace.openApplication(url)
                return
            } catch {
                continue
            }
        }
        systemSettingsFallback()
    }
}
