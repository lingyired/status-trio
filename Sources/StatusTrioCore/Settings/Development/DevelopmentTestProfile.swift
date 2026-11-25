import Foundation

/// How a development test profile is applied.
///
/// Only `onLaunch` is implemented in this phase; `firstLaunch` and `manual` are
/// reserved by the protocol so a future lifecycle manager can adopt them without
/// changing the file format.
enum SettingsProfileApplyMode: String, Codable, CaseIterable, Sendable {
    case onLaunch
    case firstLaunch
    case manual
}

/// A per-worktree development testing profile (`.dev-profile.json`).
///
/// It declares the minimal conditions a build needs to start in a testable
/// state: features to enable, exact preference overrides, and collection
/// mutations. It deliberately does not describe arbitrary store writes.
struct DevelopmentTestProfile: Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var features: [String]
    var preferences: [String: SettingsTransferValue]
    var mutations: [SettingsMutationDescriptor]
    var applyMode: SettingsProfileApplyMode

    init(
        schemaVersion: Int = DevelopmentTestProfile.currentSchemaVersion,
        features: [String] = [],
        preferences: [String: SettingsTransferValue] = [:],
        mutations: [SettingsMutationDescriptor] = [],
        applyMode: SettingsProfileApplyMode = .onLaunch
    ) {
        self.schemaVersion = schemaVersion
        self.features = features
        self.preferences = preferences
        self.mutations = mutations
        self.applyMode = applyMode
    }
}

extension DevelopmentTestProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, features, preferences, mutations, applyMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
        preferences = try container.decodeIfPresent([String: SettingsTransferValue].self, forKey: .preferences) ?? [:]
        mutations = try container.decodeIfPresent([SettingsMutationDescriptor].self, forKey: .mutations) ?? []
        applyMode = try container.decodeIfPresent(SettingsProfileApplyMode.self, forKey: .applyMode) ?? .onLaunch
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(features, forKey: .features)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(mutations, forKey: .mutations)
        try container.encode(applyMode, forKey: .applyMode)
    }
}

/// A structural problem in a development profile.
struct DevelopmentProfileIssue: Equatable, Sendable, CustomStringConvertible {
    enum Kind: String, Sendable {
        case unsupportedSchemaVersion
        case unknownFeature
        case unknownPreference
        case unknownMutationTarget
        case preferenceNotAllowedInProfile
    }

    var kind: Kind
    var detail: String

    var description: String { "[\(kind.rawValue)] \(detail)" }
}

enum DevelopmentProfileValidator {
    /// Validate a profile against the registry: schema version, resolvable ids,
    /// and the development-profile access policy (restricted/system settings may
    /// never be auto-applied by a profile).
    static func validate(_ profile: DevelopmentTestProfile, against registry: SettingsSemanticRegistry) -> [DevelopmentProfileIssue] {
        var issues: [DevelopmentProfileIssue] = []
        if profile.schemaVersion < 1 || profile.schemaVersion > DevelopmentTestProfile.currentSchemaVersion {
            issues.append(.init(kind: .unsupportedSchemaVersion, detail: "schemaVersion \(profile.schemaVersion) 不受支持"))
        }
        for feature in profile.features where registry.feature(feature) == nil {
            issues.append(.init(kind: .unknownFeature, detail: "未知功能：\(feature)"))
        }
        for id in profile.preferences.keys.sorted() {
            guard let descriptor = registry.preference(id) else {
                issues.append(.init(kind: .unknownPreference, detail: "未知设置：\(id)"))
                continue
            }
            if descriptor.accessPolicy?.developmentProfile != true {
                issues.append(.init(kind: .preferenceNotAllowedInProfile, detail: "开发 Profile 不允许设置：\(id)"))
            }
        }
        for mutation in profile.mutations {
            guard let descriptor = registry.preference(mutation.id) else {
                issues.append(.init(kind: .unknownMutationTarget, detail: "未知变更目标：\(mutation.id)"))
                continue
            }
            if descriptor.accessPolicy?.developmentProfile != true {
                issues.append(.init(kind: .preferenceNotAllowedInProfile, detail: "开发 Profile 不允许设置：\(mutation.id)"))
            }
        }
        return issues
    }
}

enum DevelopmentProfileLoader {
    static let environmentVariable = "STATUS_TRIO_DEV_PROFILE"
    static let bundleResourceName = "dev-profile"

    static func load(from url: URL) throws -> DevelopmentTestProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DevelopmentTestProfile.self, from: data)
    }

    /// Resolve the profile location: `STATUS_TRIO_DEV_PROFILE` first, then a
    /// `dev-profile.json` bundle resource written by the build script.
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> URL? {
        if let path = environment[environmentVariable], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return bundle.url(forResource: bundleResourceName, withExtension: "json")
    }
}
