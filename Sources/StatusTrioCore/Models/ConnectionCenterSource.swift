import Foundation

/// What the status icon's centre slot draws from.
enum ConnectionCenterSource: String, CaseIterable, Identifiable, Sendable {
    /// The shipped behaviour: battery percentage, Bluetooth replacement, then
    /// Ethernet / Wi-Fi. Existing users stay on this path pixel for pixel.
    case automatic
    /// The currently selected macOS input source, falling back to the
    /// automatic decision whenever a source cannot be read or drawn.
    case inputSource

    var id: Self { self }
}
