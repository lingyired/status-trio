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

            HStack(spacing: 8) {
                Button {
                    beginExport()
                } label: {
                    Label(localization.string(.settingsTransferExport), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    isImporting = true
                } label: {
                    Label(localization.string(.settingsTransferImport), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)
            .disabled(session.preview != nil || isImporting || isExporting)

            if let preview = session.preview {
                SettingsDivider()
                importPreview(preview)
            }

            if let failure {
                SettingsDivider()
                statusRow(failure, symbol: "exclamationmark.triangle.fill", tint: .red)
            } else if let message, session.preview == nil {
                SettingsDivider()
                statusRow(localization.string(message), symbol: "checkmark.circle.fill", tint: .green)
            }

            if let backup = session.lastBackupURL {
                SettingsDivider()
                backupRow(backup)
            }

            SettingsHintRow(text: localization.string(.settingsTransferExclusions))
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

    private func statusRow(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 10)
    }

    private func backupRow(_ backup: URL) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(localization.string(.settingsTransferBackup))
                    .font(.system(size: 12, weight: .semibold))
                Text(backup.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(localization.string(.settingsTransferUndo)) {
                undoImport()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!session.canUndo || session.preview != nil || isImporting || isExporting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }

    private func importPreview(_ preview: SettingsTransferPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(localization.string(.settingsTransferPreviewTitle), systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
            Text(localization.string(.settingsTransferPreviewDescription))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(localization.format(.settingsTransferPreferenceCount, preview.preferenceCount))
                Text(localization.format(
                    .settingsTransferSource,
                    preview.appVersion,
                    preview.exportedAt.formatted(
                        .dateTime.year().month().day().hour().minute().locale(localization.resolvedLanguage.locale)
                    )
                ))
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))

            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(localization.string(.settingsTransferWarnings))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(localization.format(.settingsTransferWarningCount, preview.warnings.count))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(Self.visibleWarnings(preview.warnings).enumerated()), id: \.offset) { _, warning in
                                Text(verbatim: warning)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }

            Divider()
                .opacity(0.4)

            HStack(spacing: 8) {
                Button(localization.string(.settingsTransferConfirm)) {
                    applyImport()
                }
                .buttonStyle(.borderedProminent)

                Button(localization.string(.settingsTransferCancel)) {
                    session.cancelImport()
                    failure = nil
                    message = nil
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
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
