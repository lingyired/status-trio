import Foundation

/// One rail in the provisional power info bar.
enum PowerInfoBarKind: String, Equatable, Hashable, Sendable {
    case input
    case battery
    case system

    var title: LocalizationKey {
        switch self {
        case .input: return .powerInfoBarInput
        case .battery: return .powerInfoBarBattery
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

    var isEmpty: Bool { items.isEmpty }
}
