import SwiftUI
import UniformTypeIdentifiers

/// File selection and confirmation only; the session owns validation, backup and mutation.
@MainActor
struct SettingsTransferView: View {
    @ObservedObject var localization: Localization
    @ObservedObject var session: SettingsTransferSession
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportFile: TransferJSONFile?
    @State private var message: LocalizationKey?
    @State private var failure: String?

    init(
        session: SettingsTransferSession,
        localization: Localization
    ) {
        self.session = session
        self.localization = localization
    }

    var body: some View {
        SettingsGroup(localization.string(.settingsTransferTitle)) {
            SettingsHintRow(text: localization.string(.settingsTransferDescription))

            SettingsDivider()
            HStack(spacing: 12) {
                Button(localization.string(.settingsTransferExport)) { beginExport() }
                Button(localization.string(.settingsTransferImport)) { isImporting = true }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)
            .disabled(session.preview != nil || isImporting || isExporting)

            SettingsHintRow(text: localization.string(.settingsTransferExclusions))

            if let preview = session.preview {
                SettingsDivider()
                importPreview(preview)
            }

            if let failure {
                VStack(alignment: .leading, spacing: 4) {
                    Label(localization.string(.settingsTransferErrorTitle), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(failure)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsMetrics.rowPaddingH)
            } else if let message, session.preview == nil {
                SettingsHintRow(text: localization.string(message))
            }

            if let backup = session.lastBackupURL {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(localization.string(.settingsTransferBackup))
                        .font(.system(size: 12, weight: .semibold))
                    Text(backup.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(localization.string(.settingsTransferUndo)) { undoImport() }
                        .controlSize(.small)
                        .disabled(!session.canUndo || session.preview != nil || isImporting || isExporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsMetrics.rowPaddingH)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            receiveImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: .json,
            defaultFilename: "Status-Trio-Settings.json"
        ) { result in
            switch result {
            case .success:
                failure = nil
                message = .settingsTransferExported
            case .failure(let error):
                report(error)
            }
            exportFile = nil
        }
    }

    private func importPreview(_ preview: SettingsTransferPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.string(.settingsTransferPreviewTitle))
                .font(.system(size: 13, weight: .semibold))
            Text(localization.string(.settingsTransferPreviewDescription))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(localization.format(.settingsTransferPreferenceCount, preview.preferenceCount))
            Text(localization.format(
                .settingsTransferSource,
                preview.appVersion,
                preview.exportedAt.formatted(
                    .dateTime.year().month().day().hour().minute().locale(localization.resolvedLanguage.locale)
                )
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if !preview.warnings.isEmpty {
                Text(localization.string(.settingsTransferWarnings))
                    .font(.system(size: 12, weight: .semibold))
                Text(localization.format(.settingsTransferWarningCount, preview.warnings.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(Self.visibleWarnings(preview.warnings).enumerated()), id: \.offset) { _, warning in
                            Text(verbatim: warning)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            HStack(spacing: 12) {
                Button(localization.string(.settingsTransferConfirm)) { applyImport() }
                    .buttonStyle(.borderedProminent)
                Button(localization.string(.settingsTransferCancel)) {
                    session.cancelImport()
                    failure = nil
                    message = nil
                }
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SettingsMetrics.rowPaddingH)
    }

    /// Unknown JSON field names are untrusted: bound both row count and per-row text.
    static func visibleWarnings(_ warnings: [String]) -> [String] {
        warnings.prefix(50).map { warning in
            let scalars = warning.unicodeScalars.prefix(257)
            let prefix = String(String.UnicodeScalarView(scalars.prefix(256)))
            return scalars.count > 256 ? prefix + "…" : prefix
        }
    }

    private func beginExport() {
        do {
            exportFile = TransferJSONFile(data: try session.exportData())
            isExporting = true
        } catch {
            report(error)
        }
    }

    private func receiveImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Self.readImportData(from: url)
            _ = try session.stageImport(data)
            // Preview is inline, not an alert: export success cannot replace confirmation.
            failure = nil
            message = nil
        } catch {
            report(error)
        }
    }

    static func readImportData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw SettingsTransferError.malformedFile
        }
        guard size <= SettingsTransferDocument.maximumFileSize else {
            throw SettingsTransferError.fileTooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= SettingsTransferDocument.maximumFileSize else {
            throw SettingsTransferError.fileTooLarge
        }
        return data
    }

    private func applyImport() {
        do {
            _ = try session.applyImport()
            failure = nil
            message = .settingsTransferImported
        } catch {
            report(error)
        }
    }

    private func undoImport() {
        do {
            try session.undoImport()
            failure = nil
            message = .settingsTransferUndone
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        let cocoa = error as NSError
        guard !(cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError) else { return }
        failure = Self.errorMessage(error, localization: localization)
        message = nil
    }

    static func errorMessage(_ error: Error, localization: Localization) -> String {
        guard let transfer = error as? SettingsTransferError else {
            return localization.string(.settingsTransferErrorFileAccess)
        }
        switch transfer {
        case .malformedFile: return localization.string(.settingsTransferErrorMalformedFile)
        case .unsupportedVersion(let version):
            return localization.format(.settingsTransferErrorUnsupportedVersion, version)
        case .fileTooLarge: return localization.string(.settingsTransferErrorFileTooLarge)
        case .noPendingImport: return localization.string(.settingsTransferErrorNoPendingImport)
        case .backupFailed: return localization.string(.settingsTransferErrorBackupFailed)
        case .undoUnavailable: return localization.string(.settingsTransferErrorUndoUnavailable)
        }
    }

    private struct TransferJSONFile: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }
        let data: Data

        init(data: Data) { self.data = data }
        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.data = data
        }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
}
