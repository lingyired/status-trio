import Foundation

/// What the battery arc's top gap shows while the Mac is connected to power but
/// not charging — a level-limited battery, or one already full (#195).
///
/// The charging case keeps the bolt regardless; this only decides the
/// connected-without-charging case so a user who reads the bolt as "power is
/// connected" and one who reads it as "currently charging" can both be served.
enum BatteryConnectedIndicator: String, CaseIterable, Identifiable, Sendable {
    /// The plug. This is the historical default and keeps the current look.
    case plug
    /// The lightning bolt, as if the Mac were charging.
    case bolt
    /// The percentage numerals, when the battery percentage is shown at all.
    case percentage

    var id: Self { self }
}
