import Foundation

/// What a battery's top gap shows in a given power state (#315).
///
/// The settings surface offers one choice per state — on battery, charging, and
/// connected-without-charging — so each state can carry its own marker: the
/// level percentage, the lightning bolt, the plug, or nothing. This replaces the
/// older pairing of a "show percentage" toggle and a "charging indicator" toggle
/// plus a "connected without charging" choice, whose interactions were hard to
/// reason about.
enum BatteryTopMarker: String, CaseIterable, Identifiable, Sendable {
    /// The level percentage numerals.
    case percentage
    /// The lightning bolt.
    case bolt
    /// The plug.
    case plug
    /// Nothing: the top gap closes.
    case hidden

    var id: Self { self }

    /// On battery the Mac is not on power, so a bolt or plug would be a lie: only
    /// the percentage or nothing is offered.
    static let onBatteryOptions: [BatteryTopMarker] = [.percentage, .hidden]
    /// Charging and connected states can carry any of the four markers.
    static let onPowerOptions: [BatteryTopMarker] = [.percentage, .bolt, .plug, .hidden]
    /// A battery-less Mac only has a decorative plug or bolt, or nothing.
    static let noBatteryOptions: [BatteryTopMarker] = [.plug, .bolt, .hidden]
}
