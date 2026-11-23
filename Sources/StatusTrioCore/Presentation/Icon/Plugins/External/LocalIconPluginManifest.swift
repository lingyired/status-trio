import Foundation

enum LocalIconPluginSlot: String, Codable, CaseIterable, Sendable {
    case outerRing
    case center
    case footer

    var iconSlot: IconSlot {
        switch self {
        case .outerRing: .outerRing
        case .center: .center
        case .footer: .footer
        }
    }
}

enum LocalIconPluginKind: String, Codable, CaseIterable, Sendable {
    /// A short text reading for the centre slot (maximum 16 characters).
    case text
    /// A normalized finite number in `0...1` for the outer ring or footer.
    case fraction
}

enum LocalIconPluginManifestError: Error, Equatable {
    case unreadable
    case notRegularFile
    case tooLarge
    case invalidJSON
    case unsupportedSchemaVersion(Int)
    case invalidPluginID
    case builtinPrefix
    case emptyTitle
    case tooManyPresentations
    case duplicatePresentation(String)
    case invalidPresentationID(String)
    case invalidPresentation(String)
}

struct LocalIconPluginPresentation: Codable, Equatable, Sendable {
    let id: String
    let slot: LocalIconPluginSlot
    let kind: LocalIconPluginKind
}

struct LocalIconPluginManifest: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumPresentations = 16
    static let maximumIDLength = 128
    static let maximumTitleLength = 128
    static let maximumFileBytes = 16 * 1024

    let schemaVersion: Int
    let pluginID: String
    let title: String
    let presentations: [LocalIconPluginPresentation]

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw LocalIconPluginManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        guard LocalIconPluginManifest.isValidID(pluginID) else {
            throw LocalIconPluginManifestError.invalidPluginID
        }
        guard !pluginID.hasPrefix("builtin.") else {
            throw LocalIconPluginManifestError.builtinPrefix
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= Self.maximumTitleLength else {
            throw LocalIconPluginManifestError.emptyTitle
        }
        guard !presentations.isEmpty, presentations.count <= Self.maximumPresentations else {
            throw LocalIconPluginManifestError.tooManyPresentations
        }
        var seen = Set<String>()
        for presentation in presentations {
            guard LocalIconPluginManifest.isValidID(presentation.id) else {
                throw LocalIconPluginManifestError.invalidPresentationID(presentation.id)
            }
            guard seen.insert(presentation.id).inserted else {
                throw LocalIconPluginManifestError.duplicatePresentation(presentation.id)
            }
            switch (presentation.slot, presentation.kind) {
            case (.center, .text), (.outerRing, .fraction), (.footer, .fraction):
                continue
            default:
                throw LocalIconPluginManifestError.invalidPresentation(presentation.id)
            }
        }
    }

    /// External IDs are ASCII letters, digits, dot, underscore and hyphen.
    static func isValidID(_ id: String) -> Bool {
        guard (1...maximumIDLength).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 95:
                true
            default:
                false
            }
        }
    }
}

enum LocalIconPluginManifestLoader {
    static func load(directory: URL) throws -> LocalIconPluginManifest {
        let data = try LocalIconFileReader.readRegularFile(
            at: directory.appendingPathComponent("manifest.json", isDirectory: false),
            maximumBytes: LocalIconPluginManifest.maximumFileBytes
        )
        let manifest: LocalIconPluginManifest
        do {
            manifest = try JSONDecoder().decode(LocalIconPluginManifest.self, from: data)
        } catch {
            throw LocalIconPluginManifestError.invalidJSON
        }
        try manifest.validate()
        return manifest
    }
}

/// Reads only regular, non-symlink files and never trusts the size reported by
/// the directory listing. The file descriptor is opened with `O_NOFOLLOW` and
/// `O_NONBLOCK`, and a hard byte cap is enforced while reading.
///
/// `O_NONBLOCK` matters for a directory the user can write to: replacing the
/// fixed file with a FIFO would otherwise block `open(2)` forever before the
/// post-open `fstat` can reject the non-regular type.
enum LocalIconFileReader {
    static func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        let fd = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        return try readAll(fd: fd, maximumBytes: maximumBytes)
    }

    static func readRegularFile(at name: String, inDirectory directory: URL,
                                maximumBytes: Int) throws -> Data {
        let directoryFD = directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard directoryFD >= 0 else { throw LocalIconPluginManifestError.unreadable }
        defer { close(directoryFD) }
        let fd = name.withCString { name in
            openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        return try readAll(fd: fd, maximumBytes: maximumBytes)
    }

    private static func readAll(fd: Int32, maximumBytes: Int) throws -> Data {
        guard fd >= 0 else { throw LocalIconPluginManifestError.unreadable }
        defer { close(fd) }

        var status = stat()
        guard fstat(fd, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG else {
            throw LocalIconPluginManifestError.notRegularFile
        }
        guard status.st_size >= 0, status.st_size <= maximumBytes else {
            throw LocalIconPluginManifestError.tooLarge
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            if count == 0 { break }
            guard count > 0 else { throw LocalIconPluginManifestError.unreadable }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > maximumBytes { throw LocalIconPluginManifestError.tooLarge }
        }
        return data
    }
}
