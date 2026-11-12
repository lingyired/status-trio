import Foundation

/// Where the in-app Wi-Fi join keeps the passphrases it was given. Everything
/// that touches disk goes through this protocol, so the file implementation can
/// be replaced (for example by the Keychain) without touching the join flow.
///
/// Implementations may do blocking I/O: callers invoke them from the CoreWLAN
/// worker queue, never from the main actor.
protocol WiFiPasswordStoring: Sendable {
    func password(for ssid: String) -> String?
    /// Returns false when the passphrase could not be persisted.
    @discardableResult
    func save(_ password: String, for ssid: String) -> Bool
    func remove(ssid: String)
    /// Forgets every saved password.
    func removeAll()
}

/// Stores passphrases in the current user's home directory at
/// `~/.status-trio/wifi-passwords.json`, as a product decision (the passphrases
/// are saved as plain text). The directory is created `0700` and the file
/// `0600`, so only the owning user can read it. The file is deliberately outside
/// UserDefaults and is never part of settings export/import.
final class FileWiFiPasswordStore: WiFiPasswordStoring, @unchecked Sendable {
    static let directoryName = ".status-trio"
    static let fileName = "wifi-passwords.json"

    static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private struct Document: Codable {
        var version = 1
        var networks: [String: String] = [:]
    }

    private let directoryURL: URL
    private let lock = NSLock()

    var fileURL: URL { directoryURL.appendingPathComponent(Self.fileName, isDirectory: false) }

    init(directoryURL: URL = FileWiFiPasswordStore.defaultDirectoryURL) {
        self.directoryURL = directoryURL
    }

    func password(for ssid: String) -> String? {
        lock.withLock { load().networks[ssid] }
    }

    @discardableResult
    func save(_ password: String, for ssid: String) -> Bool {
        lock.withLock {
            var document = load()
            document.networks[ssid] = password
            return write(document)
        }
    }

    func remove(ssid: String) {
        lock.withLock {
            var document = load()
            guard document.networks.removeValue(forKey: ssid) != nil else { return }
            _ = write(document)
        }
    }

    func removeAll() {
        lock.withLock {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// A missing or unreadable file is an empty store. The next save replaces it.
    private func load() -> Document {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            return Document()
        }
        return document
    }

    private func write(_ document: Document) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // The directory may already exist with looser permissions.
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            let data = try JSONEncoder().encode(document)
            // The 0700 directory keeps the temporary file private until the
            // 0600 mode below is applied to the replaced file.
            try data.write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }
}

/// The part of a join that decides which passphrase is used and what is
/// remembered afterwards. It is a pure function of the credential, the outcome
/// and the store, so it is tested without CoreWLAN.
enum WiFiJoinPasswordPolicy {
    enum Resolution: Equatable {
        /// Join with this passphrase (`nil` for an open network).
        case password(String?)
        /// A saved passphrase was asked for and none exists.
        case needsPassword
    }

    static func resolve(
        _ credential: WiFiJoinCredential,
        ssid: String,
        store: any WiFiPasswordStoring
    ) -> Resolution {
        switch credential {
        case .none:
            .password(nil)
        case .typed(let password):
            .password(password)
        case .stored:
            store.password(for: ssid).map { .password($0) } ?? .needsPassword
        }
    }

    /// A typed passphrase is saved only after the join succeeded, so a mistyped
    /// one is never kept. A saved passphrase the system refused is forgotten,
    /// so the next attempt asks again instead of repeating a refused value.
    static func record(
        _ outcome: WiFiJoinOutcome,
        credential: WiFiJoinCredential,
        ssid: String,
        store: any WiFiPasswordStoring
    ) {
        switch (outcome, credential) {
        case (.joined, .typed(let password)):
            store.save(password, for: ssid)
        case (.rejected, .stored):
            store.remove(ssid: ssid)
        default:
            break
        }
    }
}
