import Foundation

/// One rail in the provisional power info bar.
///
/// The battery rail carries its power direction in the kind, because the same
/// positive magnitude means opposite things: current into the pack is charging,
/// current out of it is discharging. Keeping the direction here lets the title,
/// glyph and colour agree instead of a discharging pack still reading
/// "Battery charging".
enum PowerInfoBarKind: String, Equatable, Hashable, Sendable {
    case input
    case batteryCharging
    case batteryDischarging
    case batteryIdle
    case system

    var title: LocalizationKey {
        switch self {
        case .input: return .powerInfoBarInput
        case .batteryCharging: return .powerInfoBarBattery
        case .batteryDischarging: return .powerInfoBarDischarging
        case .batteryIdle: return .powerInfoBarNotCharging
        case .system: return .powerInfoBarSystem
        }
    }
}

/// One item in the provisional power info bar: a label and its own reading.
/// Items are independent rails; they are never added together to claim a
/// whole-machine total.
struct PowerInfoBarItem: Equatable, Hashable, Sendable, Identifiable {
    let kind: PowerInfoBarKind
    let value: String

    var id: String { kind.rawValue }
    var title: LocalizationKey { kind.title }
}

/// The power info bar under the panel's battery module. Missing or stale rails
/// are absent from `items`; the bar hides entirely when empty.
struct PowerInfoBarState: Equatable, Hashable, Sendable {
    let items: [PowerInfoBarItem]
    /// Rails to draw as grey skeletons while the first whole-machine read is
    /// still pending. Empty once the real `items` are available (or when there is
    /// nothing to reserve), so the bar's height does not jump when data arrives.
    var placeholderKinds: [PowerInfoBarKind] = []

    var isEmpty: Bool { items.isEmpty && placeholderKinds.isEmpty }
}
