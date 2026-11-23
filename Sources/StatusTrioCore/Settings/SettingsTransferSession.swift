import Combine
import Foundation

struct SettingsTransferPreview: Identifiable {
    let id = UUID()
    let preferenceCount: Int
    /// Technical field paths. The view explains their meaning in the selected
    /// language and bounds the displayed list rather than rendering arbitrary JSON.
    let warnings: [String]
    let appVersion: String
    let exportedAt: Date
    fileprivate let preferences: [String: SettingsTransferValue]
    fileprivate let language: LanguagePreference?
}

/// One settings-window session. Validation never mutates the store; confirmation
/// first writes a recoverable file, then uses the normal published setters.
@MainActor
final class SettingsTransferSession: ObservableObject {
    @Published private(set) var preview: SettingsTransferPreview?
    @Published private(set) var lastBackupURL: URL?
    @Published private(set) var canUndo = false

    private let store: SettingsStore
    private let localization: Localization
    private let backupDirectory: URL
    private var undoState: UndoState?

    private struct UndoState {
        let preferences: [String: SettingsTransferValue]
        let language: LanguagePreference
    }

    init(store: SettingsStore, localization: Localization, backupDirectory: URL? = nil) {
        self.store = store
        self.localization = localization
        self.backupDirectory = backupDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("StatusTrio/Settings Backups", isDirectory: true)
    }

    func exportData() throws -> Data {
        try document().encoded()
    }

    private func document() -> SettingsTransferDocument {
        var preferences = SettingsPreferenceCatalog.snapshot(store)
        preferences["language"] = .string(localization.preference.id)
        return SettingsTransferDocument(
            appVersion: AppMetadata.versionShortString,
            preferences: preferences
        )
    }

    @discardableResult
    func stageImport(_ data: Data) throws -> SettingsTransferPreview {
        // Failed attempts cannot leave an earlier file's confirmation live.
        preview = nil
        let document = try SettingsTransferDocument.decode(data)
        var fields = document.preferences
        let languageValue = fields.removeValue(forKey: "language")
        let prepared = SettingsPreferenceCatalog.prepare(fields)
        var warnings = document.unknownFields.map { "document.\($0)" } + prepared.warnings
        var language: LanguagePreference?
        if let languageValue {
            if case .string(let value) = languageValue, value == "system" {
                language = .system
            } else if case .string(let value) = languageValue,
                      let selected = AppLanguage(rawValue: value) {
                language = .language(selected)
            } else {
                language = .system
                warnings.append("language")
            }
        }
        let staged = SettingsTransferPreview(
            preferenceCount: prepared.values.count + (language == nil ? 0 : 1),
            warnings: warnings.sorted(),
            appVersion: document.appVersion,
            exportedAt: document.exportedAt,
            preferences: prepared.values,
            language: language
        )
        preview = staged
        return staged
    }

    func cancelImport() {
        preview = nil
    }

    @discardableResult
    func applyImport() throws -> URL {
        guard let staged = preview else { throw SettingsTransferError.noPendingImport }
        let previous = UndoState(
            preferences: SettingsPreferenceCatalog.snapshot(store),
            language: localization.preference
        )
        // Read live in-memory slider values into the backup, not potentially
        // stale coalesced defaults. No setter or persistent flush before success.
        let backupURL = backupDirectory.appendingPathComponent("StatusTrio-\(UUID().uuidString).json")
        do {
            let backup = try exportData()
            try FileManager.default.createDirectory(
                at: backupDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try backup.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } catch {
            throw SettingsTransferError.backupFailed
        }
        // A slider's delayed write must not later overwrite imported values.
        store.flushPendingPersists()
        SettingsPreferenceCatalog.apply(staged.preferences, to: store)
        if let language = staged.language { localization.setPreference(language) }
        undoState = previous
        lastBackupURL = backupURL
        canUndo = true
        preview = nil
        return backupURL
    }

    func undoImport() throws {
        guard let previous = undoState else { throw SettingsTransferError.undoUnavailable }
        store.flushPendingPersists()
        SettingsPreferenceCatalog.apply(previous.preferences, to: store)
        localization.setPreference(previous.language)
        undoState = nil
        canUndo = false
        preview = nil
    }
}
