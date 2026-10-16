import AppKit

/// Reduces one input source's icon file to a single-colour mark.
///
/// The status panel draws every row icon in the row's own text colour. Two
/// shapes have to end up readable without their original palette: a logo that
/// is a filled badge with a light mark inside it (the WeChat input method ships
/// a black disc with a white glyph), and ordinary dark line art on a
/// transparent background (the system's own Pinyin icon). Using the file's
/// alpha alone turns the badge into a solid blob and loses the mark inside it,
/// so the mask keeps the icon's *ink*: the pixels that stand out from the tone
/// the icon is drawn on. The icon's own average tone decides which direction
/// that is, so a light-on-dark logo keeps working too.
enum InputSourceIconMask {
    /// Rasterises `image` and rewrites every pixel as white with the ink it
    /// carries as its alpha, preserving the original point size.
    static func make(from image: NSImage, pixelScale: CGFloat = 4) -> NSImage? {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              pixelScale.isFinite, pixelScale > 0 else {
            return nil
        }

        let width = Int((size.width * pixelScale).rounded())
        let height = Int((size.height * pixelScale).rounded())
        guard width > 0, height > 0, width <= 1024, height <= 1024 else { return nil }

        var source = [UInt8](repeating: 0, count: width * height * 4)
        guard let sourceContext = CGContext(
            data: &source,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // The context is measured in pixels; the icon keeps drawing in points.
        sourceContext.scaleBy(x: pixelScale, y: pixelScale)
        let graphics = NSGraphicsContext(cgContext: sourceContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(
            in: CGRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var weightedLuminance = 0.0
        var coverage = 0.0
        for index in stride(from: 0, to: source.count, by: 4) {
            let alpha = Double(source[index + 3]) / 255
            guard alpha > 0.02 else { continue }
            weightedLuminance += luminance(ofPremultipliedPixelAt: index, in: source) * alpha
            coverage += alpha
        }
        guard coverage > 0 else { return nil }
        let inkIsDark = weightedLuminance / coverage < 0.5

        var mask = [UInt8](repeating: 0, count: source.count)
        for index in stride(from: 0, to: source.count, by: 4) {
            let alpha = Double(source[index + 3]) / 255
            guard alpha > 0.001 else { continue }
            let tone = inkIsDark
                ? 1 - luminance(ofPremultipliedPixelAt: index, in: source)
                : luminance(ofPremultipliedPixelAt: index, in: source)
            let value = UInt8(min(255, max(0, (alpha * tone * 255).rounded())))
            mask[index] = value
            mask[index + 1] = value
            mask[index + 2] = value
            mask[index + 3] = value
        }

        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let masked = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        let result = NSImage(cgImage: masked, size: size)
        result.isTemplate = true
        return result
    }

    /// The luminance of one premultiplied RGBA pixel, in 0...1.
    private static func luminance(ofPremultipliedPixelAt index: Int, in bytes: [UInt8]) -> Double {
        let alpha = Double(bytes[index + 3]) / 255
        guard alpha > 0 else { return 0 }
        let red = Double(bytes[index]) / 255 / alpha
        let green = Double(bytes[index + 1]) / 255 / alpha
        let blue = Double(bytes[index + 2]) / 255 / alpha
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
