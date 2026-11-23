import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsTransferLocalizationTests: XCTestCase {
    private let keys = [
        "title", "description", "exclusions",
        "export", "import", "previewTitle", "previewDescription", "preferenceCount",
        "source", "warnings", "warningCount", "confirm", "cancel", "undo", "backup",
        "exported", "imported", "undone", "errorTitle", "error.malformedFile",
        "error.unsupportedVersion", "error.fileTooLarge", "error.noPendingImport",
        "error.backupFailed", "error.undoUnavailable", "error.fileAccess", "done"
    ].map { "settings.transfer.\($0)" }

    func testWarningRowsAreLimitedToFirstFiftyAndKeepOriginalOrder() {
        let warnings = (0..<75).map { "document.future\($0)" }
        let rows = SettingsTransferView.visibleWarnings(warnings)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(rows.first, "document.future0")
        XCTAssertEqual(rows.last, "document.future49")
        XCTAssertTrue(SettingsTransferView.visibleWarnings([]).isEmpty)
        XCTAssertEqual(SettingsTransferView.visibleWarnings(["document.foo"]), ["document.foo"])
    }

    func testWarningRowsBoundUntrustedFieldNameLength() throws {
        let name = "document." + String(repeating: "x", count: 10_000)
        let row = try XCTUnwrap(SettingsTransferView.visibleWarnings([name]).first)
        XCTAssertLessThanOrEqual(row.count, 257)
        XCTAssertTrue(row.hasPrefix("document."))
        XCTAssertTrue(row.hasSuffix("…"))
        let combiningMarks = "document.x" + String(repeating: "\u{0301}", count: 10_000)
        let bounded = try XCTUnwrap(SettingsTransferView.visibleWarnings([combiningMarks]).first)
        XCTAssertLessThanOrEqual(bounded.utf8.count, 1_027)
        XCTAssertTrue(bounded.hasSuffix("…"))
    }

    func testRecreatedTransferPaneUsesInjectedSessionsPreviewAndUndo() throws {
        let name = "SettingsTransferPaneLifetimeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let backupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: backupDirectory)
        }
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let session = SettingsTransferSession(
            store: store, localization: localization, backupDirectory: backupDirectory
        )
        store.iconSize = 22
        let data = try SettingsTransferDocument(
            appVersion: "1.9.5", preferences: ["iconSize": .number(32)]
        ).encoded()
        _ = try session.stageImport(data)
        let firstPane = SettingsTransferView(
            session: session, localization: localization
        )
        XCTAssertNotNil(firstPane.session.preview)
        XCTAssertEqual(store.iconSize, 22)
        _ = try firstPane.session.applyImport()
        let returnedPane = SettingsTransferView(
            session: session, localization: localization
        )
        XCTAssertTrue(returnedPane.session.canUndo)
        XCTAssertEqual(returnedPane.session.lastBackupURL, session.lastBackupURL)
        try returnedPane.session.undoImport()
        XCTAssertEqual(store.iconSize, 22)
    }

    func testTransferErrorsHaveLocalizedActionableMessages() {
        let suite = "SettingsTransferLocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let cases: [(SettingsTransferError, String)] = [
            (.malformedFile, "This is not a valid settings file."),
            (.unsupportedVersion(99), "Settings file version 99 is not supported."),
            (.fileTooLarge, "Choose a settings file no larger than 2 MB."),
            (.noPendingImport, "Choose a settings file and review it before importing."),
            (.backupFailed, "The backup could not be saved. No settings were changed."),
            (.undoUnavailable, "No import is available to undo.")
        ]
        for (error, expected) in cases {
            XCTAssertEqual(SettingsTransferView.errorMessage(error, localization: localization), expected)
        }
        XCTAssertEqual(
            SettingsTransferView.errorMessage(CocoaError(.fileReadNoPermission), localization: localization),
            "The file could not be read or saved. Check its location and permissions."
        )
    }

    func testFileReaderRejectsOversizedFileBeforeStaging() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 2 * 1024 * 1024 + 1).write(to: url)
        XCTAssertThrowsError(try SettingsTransferView.readImportData(from: url)) { error in
            XCTAssertEqual(error as? SettingsTransferError, .fileTooLarge)
        }
    }

    func testFileReaderPassesSmallFileWithoutChangingItsBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("{\"schemaVersion\":1}".utf8)
        try data.write(to: url)
        XCTAssertEqual(try SettingsTransferView.readImportData(from: url), data)
    }

    func testEveryShippedLanguageContainsTransferStringsInRealResourceBundle() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(value, key, "\(language.rawValue) is missing \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    func testEveryLanguagePreservesCountAndMetadataFormatArguments() throws {
        let formats = [
            "preferenceCount": ["%d"],
            "warningCount": ["%d"],
            "source": ["%@", "%@"],
            "error.unsupportedVersion": ["%d"]
        ]
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            for (suffix, arguments) in formats {
                let key = "settings.transfer.\(suffix)"
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                for argument in Set(arguments) {
                    XCTAssertEqual(
                        value.components(separatedBy: argument).count - 1,
                        arguments.filter { $0 == argument }.count,
                        "\(language.rawValue): \(key) must preserve \(arguments)"
                    )
                }
            }
        }
    }
}
