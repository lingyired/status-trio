import Foundation

/// How the two Apple Pinyin input sources draw their middle marker.
///
/// #297 replaced their shared system image with an explicit 简/繁 marker. This
/// setting makes that opt-in and lets the user pick a single 中 instead:
///
/// - `.systemIcon` (default): leave the source's own system image alone, so the
///   behaviour is the same as before #297. Nothing is overridden.
/// - `.script`: draw 简 for Simplified and 繁 for Traditional Pinyin.
/// - `.zhong`: draw 中 for both.
///
/// The choice only affects the two Apple Pinyin IDs in
/// `InputSourceDescriptor.systemIconOverrideIDs`; every other input source,
/// third-party IMEs included, keeps its own icon and label.
enum InputSourceMarkerStyle: String, CaseIterable, Identifiable, Sendable {
    case systemIcon
    case script
    case zhong

    var id: Self { self }

    /// Whether this style replaces the Apple Pinyin system image with a text
    /// marker at all.
    var drawsTextMarker: Bool { self != .systemIcon }

    /// Localized name shown in the Settings picker.
    var titleKey: LocalizationKey {
        switch self {
        case .systemIcon: .settingsInputSourceMarkerSystemIcon
        case .script: .settingsInputSourceMarkerScript
        case .zhong: .settingsInputSourceMarkerZhong
        }
    }
}
