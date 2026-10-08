import Foundation

/// Builds the bounded, non-identifying app context sent in a heartbeat.
enum TelemetryAppMetadata {
    static var currentArchitecture: String? {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        nil
        #endif
    }

    static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func snapshot(
        appVersion: String?,
        build: String?,
        osVersion: String,
        preferredLanguages: [String],
        appLanguage: AppLanguage,
        appIconPlacement: AppIconPlacement
    ) -> TelemetryContext? {
        guard let appVersion else { return nil }
        let normalizedVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVersion.isEmpty else { return nil }

        return TelemetryContext(
            appVersion: normalizedVersion,
            build: build?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            osName: "macOS",
            osVersion: osVersion,
            architecture: currentArchitecture,
            distribution: "github",
            osLanguage: TelemetryLanguageTag.osLanguageTag(preferred: preferredLanguages),
            appLanguage: appLanguage.rawValue,
            appIconPlacement: appIconPlacement
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
