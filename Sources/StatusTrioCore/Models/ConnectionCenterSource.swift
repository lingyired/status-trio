import Foundation

/// What the status icon's centre slot draws from.
///
/// `batteryPercentage` and `power` replace the former standalone
/// `showsBatteryPercentageInConnectionSlot` switch, so the user can only pick
/// one middle-slot content instead of combining mutually exclusive toggles.
enum ConnectionCenterSource: String, CaseIterable, Identifiable, Sendable {
    /// The shipped behaviour: battery percentage, Bluetooth replacement, then
    /// Ethernet / Wi-Fi. Existing users stay on this path pixel for pixel.
    case automatic
    /// The currently selected macOS input source, falling back to the
    /// automatic decision whenever a source cannot be read or drawn.
    case inputSource
    /// The battery percentage, only on Macs that have a battery. A Mac without
    /// one falls back to the automatic decision rather than inventing a level.
    case batteryPercentage
    /// The live whole-machine power reading. Falls back to the battery
    /// percentage on a battery Mac when the sensor is unreadable, and to a
    /// neutral placeholder on a Mac with no battery.
    case power

    var id: Self { self }

    /// True when this choice needs the shared power sampler kept alive.
    var needsPowerSampling: Bool { self == .power }
}
