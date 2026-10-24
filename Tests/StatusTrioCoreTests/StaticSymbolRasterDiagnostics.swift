import AppKit
import CryptoKit
import Foundation

@MainActor
func staticSymbolRasterBaselineFingerprint() -> String? {
    guard let size = staticFingerprintSymbol()?.size else { return nil }
    switch (ProcessInfo.processInfo.operatingSystemVersion.majorVersion, size.width, size.height) {
    case (26, 50, 47):
        return "9dcba3184f0953f8c173cc2f846977f01b84510a8505166bd6a8048f44d8fd97"
    case (26, 50, 46):
        return "a89b29044ab04205b8c1c12265bc5ad6e22f8384832436ca48a2d3934f17aaa9"
    case (27, 50, 47):
        return "e08ab4aebc69b650e667fb2aa5a2647f9efade4a7941dbd19061134192280cbc"
    case (27, 51, 46):
        return "377721331486253656c666fdc02ca98650f5d4421d623a54f388fd8389da339e"
    default:
        return nil
    }
}

@MainActor
private func staticFingerprintSymbol() -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 38, weight: .semibold)
        .applying(.init(hierarchicalColor: NSColor(cgColor: CGColor(gray: 1, alpha: 1))!))
    return NSImage(
        systemSymbolName: "wifi.slash", variableValue: 1, accessibilityDescription: nil
    )?.withSymbolConfiguration(config)
}

@MainActor
func printStaticSymbolRasterDiagnostics() {
    for (label, cacheMode) in [("default", NSImage.CacheMode.default), ("never", .never)] {
        guard let image = staticFingerprintSymbol() else { continue }
        image.cacheMode = cacheMode
        let size = image.size
        let measure = CGContext(
            data: nil, width: Int(ceil(size.width * 6)), height: Int(ceil(size.height * 6)),
            bitsPerComponent: 8, bytesPerRow: Int(ceil(size.width * 6)) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        measure.scaleBy(x: 6, y: 6)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: measure, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let data = measure.data!.assumingMemoryBound(to: UInt8.self)
        var minX = measure.width
        var maxX = -1
        var minY = measure.height
        var maxY = -1
        for y in 0..<measure.height {
            for x in 0..<measure.width where data[y * measure.bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        let offset = CGFloat(minX + maxX + 1) / 12 - size.width / 2
        let context = CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: 40)
        context.scaleBy(x: 1.0 / 3, y: -1.0 / 3)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(
            x: 59.5 - size.width / 2 - offset, y: -(64 + size.height / 2),
            width: size.width, height: size.height
        ))
        NSGraphicsContext.restoreGraphicsState()
        let bytes = Data(bytes: context.data!, count: 6_400)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        print(
            "SYMBOL_RASTER_DIAGNOSTIC mode=\(label) size=\(size) offset=\(offset)"
                + " measureBounds=\([minX, minY, maxX, maxY])"
                + " pixels=40x40 sha256=\(hash) rgbaBase64=\(bytes.base64EncodedString())"
        )
    }
}
