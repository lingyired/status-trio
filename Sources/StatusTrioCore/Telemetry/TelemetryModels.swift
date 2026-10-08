import Foundation

struct TelemetryContext: Sendable {
    let appVersion: String
    let build: String?
    let osName: String?
    let osVersion: String?
    let architecture: String?
    let distribution: String?
    let osLanguage: String?
    let appLanguage: String?
    let appIconPlacement: AppIconPlacement?

    init(appVersion: String, build: String?, osName: String?, osVersion: String?,
         architecture: String?, distribution: String?, osLanguage: String?,
         appLanguage: String?, appIconPlacement: AppIconPlacement?) {
        self.appVersion = appVersion
        self.build = build
        self.osName = osName
        self.osVersion = Self.majorMinorVersion(osVersion)
        self.architecture = architecture
        self.distribution = distribution
        self.osLanguage = osLanguage
        self.appLanguage = appLanguage
        self.appIconPlacement = appIconPlacement
    }

    private static func majorMinorVersion(_ version: String?) -> String? {
        guard let version, !version.isEmpty else { return nil }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }
}

struct TelemetryAttributes: Encodable, Sendable {
    let appIconPlacement: String?
    enum CodingKeys: String, CodingKey { case appIconPlacement = "app_icon_placement" }
}

struct TelemetryHeartbeat: Encodable, Sendable {
    let schemaVersion: Int
    let appID: String
    let installID: String
    let appVersion: String
    let build: String?
    let osName: String?
    let osVersion: String?
    let architecture: String?
    let distribution: String?
    let osLanguage: String?
    let appLanguage: String?
    let attributes: TelemetryAttributes?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appID = "app_id"
        case installID = "install_id"
        case appVersion = "app_version"
        case build
        case osName = "os_name"
        case osVersion = "os_version"
        case architecture = "arch"
        case distribution
        case osLanguage = "os_language"
        case appLanguage = "app_language"
        case attributes
    }

    init(installID: String, context: TelemetryContext, configuration: TelemetryConfiguration) {
        schemaVersion = configuration.schemaVersion
        appID = configuration.appID
        self.installID = installID
        appVersion = context.appVersion
        build = context.build
        osName = context.osName
        osVersion = context.osVersion
        architecture = context.architecture
        distribution = context.distribution
        osLanguage = TelemetryLanguageTag.normalize(context.osLanguage)
        appLanguage = TelemetryLanguageTag.normalize(context.appLanguage)
        if let placement = context.appIconPlacement {
            attributes = TelemetryAttributes(appIconPlacement: placement.rawValue)
        } else {
            attributes = nil
        }
    }
}
