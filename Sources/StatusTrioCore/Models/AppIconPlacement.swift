import Foundation

/// The only user preference currently permitted in telemetry attributes.
/// Keep this allowlist narrow: changing it requires an explicit privacy review.
enum AppIconPlacement: String, CaseIterable, Identifiable, Sendable {
    case menuBar
    case dock
    case both

    var id: Self { self }

    var showsMenuBarIcon: Bool {
        self != .dock
    }

    var showsDockIcon: Bool {
        self != .menuBar
    }
}
