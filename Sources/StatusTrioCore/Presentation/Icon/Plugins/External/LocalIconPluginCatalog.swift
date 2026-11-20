import Foundation

struct LocalIconPluginPackage: Equatable, Sendable {
    let directory: URL
    let manifest: LocalIconPluginManifest

    var pluginID: String { manifest.pluginID }
}

enum LocalIconPluginCatalogRejection: Equatable, Sendable {
    case directoryUnreadable(URL)
    case directoryIsSymlink(URL)
    case manifest(URL, LocalIconPluginManifestError)
    case duplicatePluginID(String, URL)

    var directory: URL {
        switch self {
        case let .directoryUnreadable(url), let .directoryIsSymlink(url), let .manifest(url, _):
            return url
        case let .duplicatePluginID(_, url):
            return url
        }
    }
}

/// The enabled external packages visible to the icon registry.
///
/// A plugin ID installed by more than one enabled directory is ambiguous, so
/// all packages with that ID are removed rather than picking a winner. Unknown
/// package contents never reach the registry.
struct LocalIconPluginCatalog: Equatable, Sendable {
    private(set) var packages: [LocalIconPluginPackage] = []
    private(set) var rejections: [LocalIconPluginCatalogRejection] = []

    init(packages: [LocalIconPluginPackage] = [],
         rejections: [LocalIconPluginCatalogRejection] = []) {
        self.packages = packages
        self.rejections = rejections
    }

    static func load(directories: [URL]) async -> Self {
        guard !directories.isEmpty else { return .init() }
        let loaded = await withTaskGroup(of: (URL, Result<LocalIconPluginManifest, LocalIconPluginManifestError>).self) {
            group in
            for directory in directories {
                group.addTask {
                    (directory, Self.loadManifest(at: directory))
                }
            }
            var results: [(URL, Result<LocalIconPluginManifest, LocalIconPluginManifestError>)] = []
            for await result in group { results.append(result) }
            return results
        }
        return assemble(loaded)
    }

    private static func loadManifest(
        at directory: URL
    ) -> Result<LocalIconPluginManifest, LocalIconPluginManifestError> {
        var isDirectory: ObjCBool = false
        let path = directory.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.unreadable)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
            return .failure(.notRegularFile)
        }
        do {
            return .success(try LocalIconPluginManifestLoader.load(directory: directory))
        } catch let error as LocalIconPluginManifestError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
    }

    private static func assemble(
        _ loaded: [(URL, Result<LocalIconPluginManifest, LocalIconPluginManifestError>)]
    ) -> Self {
        var candidates: [(URL, LocalIconPluginManifest)] = []
        var rejections: [LocalIconPluginCatalogRejection] = []
        for (directory, result) in loaded.sorted(by: { $0.0.path < $1.0.path }) {
            switch result {
            case let .success(manifest):
                candidates.append((directory, manifest))
            case let .failure(error):
                rejections.append(.manifest(directory, error))
            }
        }
        let counts = Dictionary(grouping: candidates, by: { $0.1.pluginID })
            .mapValues(\.count)
        var packages: [LocalIconPluginPackage] = []
        for (directory, manifest) in candidates {
            guard counts[manifest.pluginID] == 1 else {
                let rejection = LocalIconPluginCatalogRejection.duplicatePluginID(
                    manifest.pluginID, directory)
                if !rejections.contains(rejection) {
                    rejections.append(rejection)
                }
                continue
            }
            packages.append(LocalIconPluginPackage(directory: directory, manifest: manifest))
        }
        return Self(
            packages: packages.sorted { $0.pluginID < $1.pluginID },
            rejections: rejections
        )
    }
}
