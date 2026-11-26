import Foundation

/// Semantic data type of a user-visible setting.
///
/// Deliberately broader than the primitive storage type so the registry can
/// describe colours, collections, device/plugin references and structured
/// blobs without flattening them into `String`. The cases mirror the plan's
/// supported types; `enumeration` is used for a closed set with a raw value.
enum SettingsValueType: String, Codable, CaseIterable, Sendable {
    case boolean
    case integer
    case number
    case string
    case enumeration
    case color
    case nullable
    case object
    case map
    case set
    case orderedList
    case taggedUnion
    case deviceReference
    case pluginReference
}

/// Inclusive numeric range for `integer`/`number` settings.
struct SettingsNumericRange: Codable, Equatable, Sendable {
    var min: Double
    var max: Double

    func contains(_ value: Double) -> Bool {
        value >= min && value <= max
    }
}
