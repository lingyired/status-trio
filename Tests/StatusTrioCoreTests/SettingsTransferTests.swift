import Foundation
import Combine
import Testing
@testable import StatusTrioCore

struct SettingsTransferValueTests {
    @Test func distinguishesBooleansFromNumbersAndPreservesNestedJSON() throws {
        let data = Data(#"{"enabled":true,"size":24,"unset":null,"list":["one",false]}"#.utf8)
        let value = try JSONDecoder().decode(SettingsTransferValue.self, from: data)
        #expect(value == .object([
            "enabled": .bool(true), "size": .number(24), "unset": .null,
            "list": .array([.string("one"), .bool(false)])
        ]))
        #expect(try JSONDecoder().decode(SettingsTransferValue.self, from: JSONEncoder().encode(value)) == value)
    }
}

struct SettingsTransferDocumentTests {
    @Test func roundTripHasReadableVersionedMetadata() throws {
        let document = SettingsTransferDocument(
            appVersion: "1.9.5", exportedAt: Date(timeIntervalSince1970: 0),
            preferences: ["iconSize": .number(30)]
        )
        let data = try document.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("1970-01-01T00:00:00Z"))
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(try SettingsTransferDocument.decode(data).preferences["iconSize"] == .number(30))
    }

    @Test(arguments: [0, 2, 999]) func refusesUnsupportedVersions(_ version: Int) throws {
        let data = Data("{\"schemaVersion\":\(version),\"appVersion\":\"new\",\"exportedAt\":\"2026-11-11T00:00:00Z\",\"preferences\":{}}".utf8)
        #expect(throws: SettingsTransferError.unsupportedVersion(version)) {
            try SettingsTransferDocument.decode(data)
        }
    }

    @Test(arguments: ["{", "[]", "{}", #"{"schemaVersion":true}"#,
                      #"{"schemaVersion":1,"appVersion":"1","exportedAt":"bad","preferences":{}}"#])
    func rejectsMalformedDocuments(_ text: String) {
        #expect(throws: SettingsTransferError.malformedFile) {
            try SettingsTransferDocument.decode(Data(text.utf8))
        }
    }

    @Test func rejectsOversizedInputBeforeDecoding() {
        #expect(throws: SettingsTransferError.fileTooLarge) {
            try SettingsTransferDocument.decode(Data(repeating: 32, count: 2 * 1024 * 1024 + 1))
        }
    }
}

@MainActor
struct SettingsTransferSessionTests {
    private func fixture() throws -> (SettingsStore, Localization, URL, UserDefaults, String) {
        let name = "SettingsTransferSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (store, localization, directory, defaults, name)
    }

    @Test func stagesWithoutMutationThenBacksUpAppliesAndUndoesPublishedState() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.iconSize = 22
        store.batteryCriticalThreshold = 17
        localization.setPreference(.language(.english))
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let data = try SettingsTransferDocument(appVersion: "1.9.5", preferences: [
            "iconSize": .number(32), "language": .string("zh-Hans"),
            "futurePreference": .bool(true), "sharesAnonymousAnalytics": .bool(true),
            "statusPanelShortcut": .object([:])
        ]).encoded()
        var publishedSizes: [Double] = []
        let observation = store.$iconSize.dropFirst().sink { publishedSizes.append($0) }
        let preview = try session.stageImport(data)
        #expect(store.iconSize == 22)
        #expect(localization.preference == .language(.english))
        #expect(preview.warnings.count == 3)
        let backupURL = try session.applyImport()
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backup = try SettingsTransferDocument.decode(Data(contentsOf: backupURL))
        #expect(backup.preferences["iconSize"] == .number(22))
        #expect(backup.preferences["language"] == .string("en"))
        #expect(store.iconSize == 32)
        #expect(store.batteryCriticalThreshold == 17)
        #expect(localization.preference == .language(.simplifiedChinese))
        #expect(!store.sharesAnonymousAnalytics)
        #expect(store.statusPanelShortcut == nil)
        #expect(publishedSizes == [32])
        #expect(session.canUndo)
        try session.undoImport()
        #expect(store.iconSize == 22)
        #expect(localization.preference == .language(.english))
        #expect(!session.canUndo)
        #expect(publishedSizes == [32, 22])
        withExtendedLifetime(observation) {}
    }

    @Test func damagedImportClearsStalePreviewAndDoesNotChangeSettings() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.iconSize = 26
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        _ = try session.stageImport(SettingsTransferDocument(appVersion: "1", preferences: ["iconSize": .number(34)]).encoded())
        #expect(throws: SettingsTransferError.malformedFile) { try session.stageImport(Data("oops".utf8)) }
        #expect(session.preview == nil)
        #expect(throws: SettingsTransferError.noPendingImport) { try session.applyImport() }
        #expect(store.iconSize == 26)
        #expect(!session.canUndo)
    }

    @Test func backupFailureLeavesSettingsAndLanguageUntouched() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        try Data("not a directory".utf8).write(to: directory)
        store.iconSize = 26
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        _ = try session.stageImport(SettingsTransferDocument(appVersion: "1", preferences: ["iconSize": .number(34)]).encoded())
        #expect(throws: SettingsTransferError.backupFailed) { try session.applyImport() }
        #expect(store.iconSize == 26)
        #expect(!session.canUndo)
        #expect(session.lastBackupURL == nil)
    }

    @Test func invalidLanguageFallsBackToSystemWithWarningOnlyAfterConfirmation() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        localization.setPreference(.language(.english))
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let preview = try session.stageImport(SettingsTransferDocument(appVersion: "1", preferences: ["language": .number(1)]).encoded())
        #expect(preview.warnings == ["language"])
        #expect(localization.preference == .language(.english))
        _ = try session.applyImport()
        #expect(localization.preference == .system)
    }

    @Test func wheelStepRoundTripsAndMissingKeyKeepsCurrentValue() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.popupScrollWheelStepPercent = 2.5
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let data = try session.exportData()
        #expect(try SettingsTransferDocument.decode(data).preferences["popupScrollWheelStepPercent"] == .number(2.5))
        store.popupScrollWheelStepPercent = 10
        _ = try session.stageImport(data)
        #expect(store.popupScrollWheelStepPercent == 10)
        _ = try session.applyImport()
        #expect(store.popupScrollWheelStepPercent == 2.5)
        #expect(SettingsStore(defaults: defaults).popupScrollWheelStepPercent == 2.5)
        _ = try session.stageImport(SettingsTransferDocument(appVersion: "old", preferences: [:]).encoded())
        _ = try session.applyImport()
        #expect(store.popupScrollWheelStepPercent == 2.5)
        _ = try session.stageImport(SettingsTransferDocument(appVersion: "bad", preferences: ["popupScrollWheelStepPercent": .number(30)]).encoded())
        _ = try session.applyImport()
        #expect(store.popupScrollWheelStepPercent == 10)
    }

    @Test func backupCanBeImportedByANewSession() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.iconSize = 28
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        _ = try session.stageImport(SettingsTransferDocument(appVersion: "1", preferences: ["iconSize": .number(34)]).encoded())
        let url = try session.applyImport()
        let next = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        _ = try next.stageImport(Data(contentsOf: url))
        _ = try next.applyImport()
        #expect(store.iconSize == 28)
    }

    @Test func backupIncludesPendingSliderValuesAndUndoRestoresPreferences() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        store.setIconSizeFromSlider(28)
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let data = try SettingsTransferDocument(appVersion: "1", preferences: ["iconSize": .number(34)]).encoded()
        _ = try session.stageImport(data)
        let backup = try session.applyImport()
        #expect(try SettingsTransferDocument.decode(Data(contentsOf: backup)).preferences["iconSize"] == .number(28))
        #expect(defaults.double(forKey: SettingsStore.iconSizeDefaultsKey) == 34)
        try session.undoImport()
        #expect(store.iconSize == 28)
        #expect(defaults.double(forKey: SettingsStore.iconSizeDefaultsKey) == 28)
    }

    @Test func warnsAboutUnknownEnvelopeFieldsAndCancellationDoesNotCreateBackup() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        let data = Data(#"{"schemaVersion":1,"appVersion":"1","exportedAt":"2026-11-11T00:00:00Z","preferences":{},"future":true}"#.utf8)
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let preview = try session.stageImport(data)
        #expect(preview.warnings == ["document.future"])
        session.cancelImport()
        #expect(session.preview == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func exportOmitsPrivatePreferences() throws {
        let (store, localization, directory, defaults, name) = try fixture()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("never-export", forKey: "unrelatedSecret")
        let session = SettingsTransferSession(store: store, localization: localization, backupDirectory: directory)
        let data = try session.exportData()
        let document = try SettingsTransferDocument.decode(data)
        #expect(document.preferences["language"] == .string("system"))
        #expect(document.preferences["iconSize"] == .number(24))
        #expect(!String(decoding: data, as: UTF8.self).contains("never-export"))
    }
}
