import Darwin
import Foundation

/// Root-helper recovery record. This is separate from app preferences and the
/// native PowerUI session. An interrupted transaction retains its intended raw
/// values; a readback is never substituted for physical behavior validation.
struct LegacyChargeLimitJournal: Codable, Equatable, Sendable {
    enum Backend: String, Codable, Sendable {
        case intelBCLM
        case silicon
        /// macOS 15.7+/26 firmware charge limit: bfD0 (upper %), bfE0 (lower %),
        /// bfF0 (enable flag). The firmware enforces the limit; the app only
        /// sets/clears it.
        case firmwareLimit
    }
    var backend: Backend
    var hardwareModel: String
    /// OS build (`kern.osversion`) when the record was written. A journal from
    /// a different firmware/OS build is not trusted to describe this machine.
    /// Optional so a record written by an earlier development build still
    /// decodes; a present-but-different value is rejected.
    var osBuild: String? = nil
    var requestedLimit: Int
    var originalRaw: [String: Data]
    var lastWrittenRaw: [String: Data]
    var isTemporarilyOverridden = false
    var pendingRaw: [String: Data]? = nil
}

protocol LegacyChargeLimitJournaling: AnyObject {
    func load() throws -> LegacyChargeLimitJournal?
    func save(_ journal: LegacyChargeLimitJournal) throws
    func clear() throws
}

/// Atomic, bounded and permission-checked persistence. A failed save throws
/// before the coordinator can issue a hardware write. Existing corrupt or
/// unsafe records are errors, not "no session".
final class FileLegacyChargeLimitJournal: LegacyChargeLimitJournaling {
    private let directory: URL
    private let url: URL
    private let expectedOwner: uid_t
    private static let maxBytes = 16_384

    enum StoreError: Error {
        case unsafeDirectory
        case unsafeFile
        case io(Int32)
        case oversized
    }

    init(directory: URL, expectedOwner: uid_t = 0) {
        self.directory = directory
        self.url = directory.appendingPathComponent("legacy-charge-limit-journal.json")
        self.expectedOwner = expectedOwner
    }

    func load() throws -> LegacyChargeLimitJournal? {
        guard try validateDirectory(create: false) else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw StoreError.io(errno)
        }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == expectedOwner, (info.st_mode & 0o077) == 0,
              info.st_nlink == 1 else { throw StoreError.unsafeFile }
        guard info.st_size >= 0, info.st_size <= Self.maxBytes else { throw StoreError.oversized }
        let data = try file.readToEnd() ?? Data()
        guard data.count <= Self.maxBytes else { throw StoreError.oversized }
        return try JSONDecoder().decode(LegacyChargeLimitJournal.self, from: data)
    }

    func save(_ journal: LegacyChargeLimitJournal) throws {
        _ = try validateDirectory(create: true)
        let data = try JSONEncoder().encode(journal)
        guard data.count <= Self.maxBytes else { throw StoreError.oversized }
        let temporary = directory.appendingPathComponent(".legacy-charge-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw StoreError.io(errno) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try file.write(contentsOf: data)
            try file.synchronize()
            try file.close()
            guard rename(temporary.path, url.path) == 0 else { throw StoreError.io(errno) }
            try syncDirectory()
        } catch {
            // The exact temporary path was created exclusively above under the
            // validated directory; cleanup never follows a caller-supplied path.
            _ = unlink(temporary.path)
            throw error
        }
    }

    func clear() throws {
        guard try validateDirectory(create: false) else { return }
        guard unlink(url.path) == 0 || errno == ENOENT else { throw StoreError.io(errno) }
        try syncDirectory()
    }

    private func validateDirectory(create: Bool) throws -> Bool {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw StoreError.io(errno) }
            guard create else { return false }
            // Parent exists in production (/Library/Application Support); do
            // not recursively create or follow a user-controlled ancestor.
            guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else {
                throw StoreError.io(errno)
            }
            guard lstat(directory.path, &info) == 0 else { throw StoreError.io(errno) }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == expectedOwner,
              (info.st_mode & 0o022) == 0 else { throw StoreError.unsafeDirectory }
        return true
    }

    private func syncDirectory() throws {
        let fd = open(directory.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw StoreError.io(errno) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw StoreError.io(errno) }
    }
}
