import CoreGraphics
import Foundation

enum ChargingEffectPalette {
    static let minimumContrastRatio = 1.8
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()

    static func automaticHighlight(for fillColor: CGColor) -> CGColor {
        guard let base = components(of: fillColor) else {
            return CGColor(gray: 1, alpha: fillColor.alpha)
        }

        let white = RGB(red: 1, green: 1, blue: 1, alpha: base.alpha)
        if contrastRatio(between: base, and: white) >= minimumContrastRatio {
            return contrastingMix(from: base, toward: white)
        }

        let black = RGB(red: 0, green: 0, blue: 0, alpha: base.alpha)
        if contrastRatio(between: base, and: black) >= minimumContrastRatio {
            return contrastingMix(from: base, toward: black)
        }

        let destination = contrastRatio(between: base, and: white)
            >= contrastRatio(between: base, and: black)
            ? white
            : black
        return contrastingMix(from: base, toward: destination)
    }

    static func chargingBoltHighlight(
        for fillColor: CGColor,
        using automaticHighlight: CGColor
    ) -> CGColor {
        guard let base = components(of: fillColor) else { return fillColor }
        guard let highlighted = components(of: automaticHighlight),
              relativeLuminance(highlighted) > relativeLuminance(base) else {
            return blend(fillColor, with: CGColor(gray: 1, alpha: fillColor.alpha), amount: 0.35)
        }
        return automaticHighlight
    }

    static func blend(_ first: CGColor, with second: CGColor, amount: Double) -> CGColor {
        guard let firstRGB = components(of: first), let secondRGB = components(of: second) else {
            return amount >= 0.5 ? second : first
        }
        let result = mix(firstRGB, secondRGB, amount: min(1, max(0, amount)))
        return makeColor(result)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private static func components(of color: CGColor) -> RGB? {
        guard let converted = color.converted(
            to: sRGBColorSpace,
            intent: .defaultIntent,
            options: nil
        ), let values = converted.components, values.count >= 3 else {
            return nil
        }
        return RGB(
            red: min(1, max(0, Double(values[0]))),
            green: min(1, max(0, Double(values[1]))),
            blue: min(1, max(0, Double(values[2]))),
            alpha: values.count >= 4 ? min(1, max(0, Double(values[3]))) : 1
        )
    }

    private static func contrastingMix(from base: RGB, toward destination: RGB) -> CGColor {
        var low = 0.0
        var high = 1.0
        for _ in 0..<32 {
            let midpoint = (low + high) / 2
            let mixed = mix(base, destination, amount: midpoint)
            if contrastRatio(between: base, and: mixed) >= minimumContrastRatio {
                high = midpoint
            } else {
                low = midpoint
            }
        }
        let result = mix(base, destination, amount: high)
        return makeColor(result)
    }

    private static func makeColor(_ color: RGB) -> CGColor {
        let values: [CGFloat] = [
            CGFloat(color.red),
            CGFloat(color.green),
            CGFloat(color.blue),
            CGFloat(color.alpha)
        ]
        return CGColor(colorSpace: sRGBColorSpace, components: values)
            ?? CGColor(gray: 1, alpha: 1)
    }

    private static func mix(_ start: RGB, _ end: RGB, amount: Double) -> RGB {
        RGB(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount,
            alpha: start.alpha + (end.alpha - start.alpha) * amount
        )
    }

    private static func contrastRatio(between first: RGB, and second: RGB) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func relativeLuminance(_ color: RGB) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(color.red)
            + 0.7152 * linearize(color.green)
            + 0.0722 * linearize(color.blue)
    }
}
