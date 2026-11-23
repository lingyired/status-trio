import SwiftUI

/// Ink for the "connected" marker in the Wi-Fi network list.
///
/// The marker is a semantic state, not a themed control, so it uses a fixed
/// green instead of the accent colour: a pale accent can fall below 3:1 on the
/// light panel (issue #227). Light appearance gets the deeper green; dark
/// appearance gets the brighter one, because the panel is much darker there.
enum WiFiConnectedMarkerPalette {
    struct Ink {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }
    }

    static let light = Ink(red: 30 / 255, green: 142 / 255, blue: 62 / 255)
    static let dark = Ink(red: 48 / 255, green: 209 / 255, blue: 88 / 255)

    static func resolved(dark: Bool) -> Ink {
        dark ? self.dark : light
    }
}
