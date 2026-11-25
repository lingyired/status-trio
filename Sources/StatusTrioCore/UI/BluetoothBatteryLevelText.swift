import AppKit
import SwiftUI

/// Draws a device's level pieces as one run of text.
///
/// A `Text` and a `Text(Image(systemName:))` concatenate into a single `Text`, so
/// a row keeps one line, one font and one truncation behaviour while one piece
/// of it is a glyph. Both surfaces that show a level — the device rows and the
/// popover's summary line — go through here, so the charging case cannot be a
/// glyph on one and a word on the other.
enum BluetoothBatteryLevelText {
    /// The pieces as one drawable run, in the order they were built.
    static func drawn(
        _ segments: [BluetoothBatterySegment],
        symbolImage: (String) -> NSImage? = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    ) -> Text {
        segments.reduce(Text(verbatim: "")) { run, segment in
            switch segment {
            case .text(let value):
                return run + Text(verbatim: value)
            case .symbol(let name, let label):
                // A symbol Apple drops in a later release must not take the
                // meaning with it: the label stands in for the glyph, the way
                // the row's other icon lookups fall back rather than draw blank.
                guard let image = symbolImage(name) else {
                    return run + Text(verbatim: label)
                }
                // The charging mark is decoration, not a digit, and the battery
                // glyph is wider than tall: a fixed 11pt symbol image keeps its
                // own aspect (no square stretch) and its own size, because the
                // row's outer `.font(...)` cannot shrink a `Text(Image)` run.
                if name == BluetoothBatteryLevel.chargingSymbolName {
                    let small = image.withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    ) ?? image
                    if small.size.height > 0 {
                        small.size = NSSize(
                            width: 11 * (small.size.width / small.size.height),
                            height: 11
                        )
                    }
                    return run + Text(Image(nsImage: small))
                }
                return run + Text(Image(systemName: name))
            }
        }
    }
}
