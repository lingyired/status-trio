import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

/// Issue #281: the two "open … settings" rows at the bottom of the battery
/// page each have to be a full-width target — the blank space to the right of
/// the text included — and each highlights only while its own row is hovered.
///
/// The row paints its hover highlight over the same rectangle it uses as its
/// hit shape, so the rendered highlight width is the clickable width. These are
/// offscreen `NSHostingView` captures: no window is ordered on screen.
@MainActor
struct BatterySettingsLinkTests {
    private static let width: CGFloat = 302

    private func render<V: View>(_ view: V) throws -> SummaryActionAlignmentProbe {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.appearance = NSAppearance(named: .aqua)
        var size = hosting.fittingSize
        size.width = Self.width
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return try #require(SummaryActionAlignmentProbe(hosting))
    }

    /// The horizontal extent of non-background ink in each equal-height band of
    /// the capture, in points.
    private func bandMaxX(_ probe: SummaryActionAlignmentProbe, bandCount: Int) throws -> [CGFloat] {
        let bitmap = probe.bitmap
        let scale = probe.scale
        let bandHeight = max(1, bitmap.pixelsHigh / bandCount)
        var result: [CGFloat] = []
        for band in 0..<bandCount {
            let startY = band * bandHeight
            let endY = band == bandCount - 1 ? bitmap.pixelsHigh : startY + bandHeight
            var maxX = -1
            for y in startY..<endY {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.1 else { continue }
                    let luminance = 0.299 * color.redComponent
                        + 0.587 * color.greenComponent
                        + 0.114 * color.blueComponent
                    if luminance < 0.985 { maxX = max(maxX, x) }
                }
            }
            #expect(maxX >= 0, "each band must render some ink")
            result.append(maxX < 0 ? 0 : CGFloat(maxX) / scale)
        }
        return result
    }

    @Test func hoveredRowReachesTheRightEdgeWhileIdleRowStaysAtItsLabel() throws {
        let content = VStack(spacing: 0) {
            BatterySettingsLinkRow("Open System Power Settings", isHovered: true) {}
            BatterySettingsLinkRow("Open App Battery Settings", isHovered: false) {}
        }
        .frame(width: Self.width)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let probe = try render(content)
        let bands = try bandMaxX(probe, bandCount: 2)

        #expect(bands[0] >= 0.95 * Self.width,
                "the hovered row's highlight must span the whole row, right blank included")
        #expect(bands[1] > 0.1 * Self.width,
                "the idle row still draws its label")
        #expect(bands[1] < 0.80 * Self.width,
                "the idle row must not paint a full-width highlight")
    }

    @Test func aSingleHoveredRowPaintsFullWidthAndAnIdleOneDoesNot() throws {
        func maxX(hovered: Bool) throws -> CGFloat {
            let content = BatterySettingsLinkRow("Open System Power Settings", isHovered: hovered) {}
                .frame(width: Self.width)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            return try bandMaxX(render(content), bandCount: 1)[0]
        }
        let hovered = try maxX(hovered: true)
        let idle = try maxX(hovered: false)
        #expect(hovered >= 0.95 * Self.width)
        #expect(idle < 0.80 * Self.width)
    }

    @Test func hoverHighlightAddsBreathingRoomAboveAndBelowTheLabel() throws {
        let content = BatterySettingsLinkRow("Open System Power Settings", isHovered: true) {}
            .frame(width: Self.width)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let probe = try render(content)
        let scale = probe.scale

        func isPainted(x: CGFloat, y: CGFloat) throws -> Bool {
            let color = try #require(probe.bitmap.colorAt(
                x: Int(x * scale), y: Int(y * scale)
            )?.usingColorSpace(.deviceRGB))
            let luminance = 0.299 * color.redComponent
                + 0.587 * color.greenComponent
                + 0.114 * color.blueComponent
            return luminance < 0.985
        }

        // The hover fill reaches the padding above and below the text line,
        // instead of hugging the glyphs' exact height.
        #expect(try isPainted(x: Self.width / 2, y: 1))
        #expect(try isPainted(x: Self.width / 2, y: CGFloat(probe.bitmap.pixelsHigh) / probe.scale - 2))
    }
}
