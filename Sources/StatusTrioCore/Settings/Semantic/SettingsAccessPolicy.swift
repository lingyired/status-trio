import Foundation

/// Who may read or write a setting, and whether it carries risk.
///
/// Everything not explicitly granted stays denied. New settings default to
/// UI-only access; a caller must opt into development-profile, transfer or
/// external access deliberately.
struct SettingsAccessPolicy: Codable, Equatable, Sendable {
    /// May the ordinary in-app Settings UI read and edit this setting?
    var uiAccessible: Bool = true
    /// May a development test profile set this value on launch?
    var developmentProfile: Bool = false
    /// May this setting travel in the settings export/import document?
    var transferable: Bool = false
    /// May a future external (Agent/CLI) reader read this value?
    var externalRead: Bool = false
    /// May a future external (Agent/CLI) writer change this value?
    var externalWrite: Bool = false
    /// Does applying a change require explicit user confirmation?
    var requiresConfirmation: Bool = false
    /// Does the value contain sensitive information (device ids, paths, consent)?
    var containsSensitiveInfo: Bool = false
    /// Does changing it trigger a real system side effect (helper, login item, power)?
    var systemSideEffect: Bool = false

    /// Conservative default for ordinary, UI-only preferences.
    static let uiOnly = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: false,
        transferable: false,
        externalRead: false,
        externalWrite: false,
        requiresConfirmation: false,
        containsSensitiveInfo: false,
        systemSideEffect: false
    )

    /// Safe to read externally and safe to set from a development profile,
    /// but not externally writable.
    static let profileSafe = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: true,
        transferable: false,
        externalRead: true,
        externalWrite: false
    )

    /// An ordinary preference that is also part of the settings transfer catalog.
    static let transferable = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: true,
        transferable: true,
        externalRead: true,
        externalWrite: false
    )

    /// Restricted: never auto-modified, requires confirmation, may be sensitive.
    static let restricted = SettingsAccessPolicy(
        uiAccessible: true,
        developmentProfile: false,
        transferable: false,
        externalRead: false,
        externalWrite: false,
        requiresConfirmation: true,
        containsSensitiveInfo: true,
        systemSideEffect: true
    )
}

/// Performance / data-collection impact of enabling a setting or feature.
struct SettingsPerformanceImpact: Codable, Equatable, Sendable {
    enum Activation: String, Codable, Sendable {
        case none
        case onDemand
        case periodic
        case continuous
        case onLaunch
    }

    /// Named monitoring resources this touches, e.g. `temperatureSampling`.
    var resources: [String] = []
    var activation: Activation = .none

    static let none = SettingsPerformanceImpact()
}

/// One selectable option of an `enumeration` (or `map`/`set`) setting.
struct SettingsOptionDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var description: String? = nil
    var value: SettingsTransferValue
}

/// A mutation a feature (or an `onChange` rule) applies to a preference.
struct SettingsMutationDescriptor: Codable, Equatable, Sendable {
    enum Operation: String, Codable, CaseIterable, Sendable {
        case set
        case add
        case remove
        case merge
        case move
        case reset
    }

    /// Target preference id.
    var id: String
    var operation: Operation
    /// Payload; `reset` and some `remove` operations may omit it.
    var value: SettingsTransferValue? = nil
}
