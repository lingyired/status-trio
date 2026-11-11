import Foundation

enum SettingsTransferError: Error, Equatable {
    case malformedFile
    case unsupportedVersion(Int)
    case fileTooLarge
    case noPendingImport
    case backupFailed
    case undoUnavailable
}

/// Deliberately not a dump of UserDefaults: the two dictionaries are allowlisted
/// by their respective catalogs before any value reaches a live setter.
struct SettingsTransferDocument: Codable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumFileSize = 2 * 1024 * 1024

    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let preferences: [String: SettingsTransferValue]
    let devices: [String: SettingsTransferValue]?
    private(set) var unknownFields: [String] = []

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, exportedAt, appVersion, preferences, devices
    }

    init(
        appVersion: String,
        exportedAt: Date = Date(),
        preferences: [String: SettingsTransferValue],
        devices: [String: SettingsTransferValue]? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.preferences = preferences
        self.devices = devices
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw SettingsTransferError.fileTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileSize else { throw SettingsTransferError.fileTooLarge }
        do {
            let decoder = JSONDecoder()
            // Inspect the envelope first so newer versions are rejected even if
            // their payload no longer matches this build's schema.
            let raw = try decoder.decode([String: SettingsTransferValue].self, from: data)
            guard case .number(let version) = raw["schemaVersion"],
                  version.isFinite, let integerVersion = Int(exactly: version)
            else { throw SettingsTransferError.malformedFile }
            guard integerVersion == currentSchemaVersion else {
                throw SettingsTransferError.unsupportedVersion(integerVersion)
            }
            decoder.dateDecodingStrategy = .iso8601
            var document = try decoder.decode(Self.self, from: data)
            guard !document.appVersion.isEmpty, document.appVersion.count <= 128 else {
                throw SettingsTransferError.malformedFile
            }
            let knownKeys = Set(CodingKeys.allCases.map { $0.rawValue })
            document.unknownFields = raw.keys.filter { !knownKeys.contains($0) }.sorted()
            return document
        } catch let error as SettingsTransferError {
            throw error
        } catch {
            throw SettingsTransferError.malformedFile
        }
    }
}
