import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct BatteryStatusColorBaselineTests {
    /// #188 / high contrast: the ink is opaque black on every light appearance
    /// and opaque white on every dark one, including the accessibility variants.
    /// Each expectation is written literally so the test does not re-derive the
    /// answer with the same `bestMatch` call the renderer uses.
    @Test func inkIsOpaqueAndMatchesEachAppearanceLiterally() throws {
        let cases: [(NSAppearance.Name, CGFloat, Bool)] = [
            (.aqua, 0, false),
            (.darkAqua, 1, true),
            (.accessibilityHighContrastAqua, 0, false),
            (.accessibilityHighContrastDarkAqua, 1, true)
        ]

        for (name, expectedRed, isDark) in cases {
            let appearance = try #require(NSAppearance(named: name))
            let environment = StatusIconRenderer.renderEnvironment(size: 20, scale: 2, appearance: appearance)
            let ink = try #require(NSColor(cgColor: environment.foreground)?.usingColorSpace(.deviceRGB))
            #expect(environment.foreground.alpha == 1)
            #expect(ink.redComponent == expectedRed, "\(name.rawValue)")
            #expect(ink.greenComponent == expectedRed, "\(name.rawValue)")
            #expect(ink.blueComponent == expectedRed, "\(name.rawValue)")

            let palette = try #require(environment.statusPalette)
            appearance.performAsCurrentDrawingAppearance {
                let green = NSColor.systemGreen.usingColorSpace(.deviceRGB)
                #expect(palette.charging == green?.cgColor, "\(name.rawValue)")
                #expect(palette.lowPower == NSColor.systemYellow.usingColorSpace(.deviceRGB)?.cgColor)
                #expect(palette.critical == NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor)
            }
            _ = isDark
        }
    }
}
