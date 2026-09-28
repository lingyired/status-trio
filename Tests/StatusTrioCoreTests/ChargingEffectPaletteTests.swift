import CoreGraphics
import Testing
@testable import StatusTrioCore

struct ChargingEffectPaletteTests {
    @Test func chargingBoltHighlightLightensEachStatusColorPalette() throws {
        let colors = [
            CGColor(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1),
            CGColor(red: 31.0 / 255, green: 143.0 / 255, blue: 61.0 / 255, alpha: 1),
            CGColor(red: 255.0 / 255, green: 59.0 / 255, blue: 48.0 / 255, alpha: 1),
            CGColor(red: 242.0 / 255, green: 185.0 / 255, blue: 0, alpha: 1),
            CGColor(red: 201.0 / 255, green: 151.0 / 255, blue: 0, alpha: 1)
        ]

        for color in colors {
            let highlight = ChargingEffectPalette.chargingBoltHighlight(
                for: color,
                using: ChargingEffectPalette.automaticHighlight(for: color)
            )
            #expect(try relativeLuminance(highlight) > relativeLuminance(color))
        }
    }

    @Test func automaticHighlightMaintainsContrastAcrossBatteryColorRoles() throws {
        let fills = [
            CGColor(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1),
            CGColor(red: 255.0 / 255, green: 59.0 / 255, blue: 48.0 / 255, alpha: 1),
            CGColor(red: 242.0 / 255, green: 185.0 / 255, blue: 0, alpha: 1),
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 1, alpha: 1)
        ]

        for fill in fills {
            let highlight = ChargingEffectPalette.automaticHighlight(for: fill)
            let ratio = try contrastRatio(highlight, fill)
            #expect(ratio >= 1.8 - 1e-6)
        }
    }

    @Test func whiteMonochromeFillUsesTheDarkFallbackDirection() throws {
        let white = CGColor(gray: 1, alpha: 1)
        let highlight = ChargingEffectPalette.automaticHighlight(for: white)
        let components = try rgb(highlight)

        #expect(components.red < 0.9)
        #expect(components.green < 0.9)
        #expect(components.blue < 0.9)
        let ratio = try contrastRatio(highlight, white)
        #expect(ratio >= 1.8 - 1e-6)
    }

    @Test func darkFillCanUseTheWhiteHighlightDirection() throws {
        let black = CGColor(gray: 0, alpha: 1)
        let highlight = ChargingEffectPalette.automaticHighlight(for: black)
        let components = try rgb(highlight)

        #expect(components.red > 0.2)
        #expect(components.green > 0.2)
        #expect(components.blue > 0.2)
        let ratio = try contrastRatio(highlight, black)
        #expect(ratio >= 1.8 - 1e-6)
    }

    private func contrastRatio(_ first: CGColor, _ second: CGColor) throws -> Double {
        let firstLuminance = try relativeLuminance(first)
        let secondLuminance = try relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: CGColor) throws -> Double {
        let values = try rgb(color)
        func linearize(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(values.red)
            + 0.7152 * linearize(values.green)
            + 0.0722 * linearize(values.blue)
    }

    private func rgb(_ color: CGColor) throws -> (red: Double, green: Double, blue: Double) {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try #require(color.converted(
            to: colorSpace,
            intent: .defaultIntent,
            options: nil
        ))
        let components = try #require(converted.components)
        #expect(components.count >= 3)
        return (
            Double(components[0]),
            Double(components[1]),
            Double(components[2])
        )
    }
}
