import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

/// #282: extending ribbons underneath translucent cards must not leave a
/// darker strip inside either card. Check actual pixels away from the labels
/// and rim rather than only checking that the path endpoints overlap.
@MainActor
struct PowerFlowOverlapRenderingTests {
    @Test(arguments: [false, true])
    func translucentCardsDoNotShowTheRibbonBehindThem(dark: Bool) throws {
        let state = BatteryPowerFlowState(
            input: .init(label: "Adapter", value: "100W", watts: 100, kind: .input),
            destinations: [
                .init(label: "System", value: "65W", watts: 65, kind: .system),
                .init(label: "Battery", value: "35W", watts: 35, kind: .charging)
            ]
        )
        let background = dark ? 0.16 : 0.95
        let view = BatteryPowerFlowView(state: state)
            .frame(width: 330, height: 110)
            .background(Color(red: background, green: background, blue: background))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 110)
        hosting.layoutSubtreeIfNeeded()
        let probe = try #require(SummaryActionAlignmentProbe(hosting))

        func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
            try #require(probe.bitmap.colorAt(
                x: Int((x * probe.scale).rounded()),
                y: Int((y * probe.scale).rounded())
            )?.usingColorSpace(.deviceRGB))
        }
        func sameFill(_ a: NSColor, _ b: NSColor) {
            #expect(abs(a.redComponent - b.redComponent) < 0.02)
            #expect(abs(a.greenComponent - b.greenComponent) < 0.02)
            #expect(abs(a.blueComponent - b.blueComponent) < 0.02)
        }

        // Both pixels are inside the card outline. One lies in the 6pt ribbon
        // overlap and the other is farther inside, away from glyphs and text.
        sameFill(try color(58, 20), try color(48, 20))
        sameFill(try color(239, 15), try color(260, 15))
        sameFill(try color(239, 85), try color(260, 85))

        // The exposed ribbon reaches the card's left rim, with no background
        // seam at the junction. The system branch is blue in both appearances.
        let junction = try color(235, 30)
        let clearBackground = try color(200, 109)
        #expect(junction.blueComponent > junction.redComponent + 0.05)
        #expect(abs(junction.redComponent - clearBackground.redComponent) > 0.05)
    }
}
