import AppKit

/// Reads the geometry SwiftUI actually rendered for a summary row's controls.
@MainActor
struct SummaryActionAlignmentProbe {
    let bitmap: NSBitmapImageRep
    let scale: CGFloat

    init?(_ hosting: NSView, pixelScale: CGFloat? = nil) {
        let image: NSBitmapImageRep?
        if let pixelScale {
            image = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((hosting.bounds.width * pixelScale).rounded(.up)),
                pixelsHigh: Int((hosting.bounds.height * pixelScale).rounded(.up)),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            image?.size = hosting.bounds.size
        } else {
            image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        }
        guard let bitmap = image else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        self.bitmap = bitmap
        scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
    }

    func trailingGlyphRects(
        count: Int,
        minimumX: CGFloat = 0,
        maxX: CGFloat? = nil
    ) -> [CGRect] {
        let minimumPixelX = max(0, Int((minimumX * scale).rounded(.down)))
        let maximumPixelX = min(
            bitmap.pixelsWide,
            maxX.map { Int(($0 * scale).rounded(.up)) } ?? bitmap.pixelsWide
        )
        let blankGap = max(1, Int((3 * scale).rounded()))
        guard minimumPixelX < maximumPixelX else { return [] }
        var hasInk = Array(repeating: false, count: maximumPixelX)
        for x in minimumPixelX..<maximumPixelX {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let luminance = 0.299 * color.redComponent
                    + 0.587 * color.greenComponent
                    + 0.114 * color.blueComponent
                if luminance < 0.9 {
                    hasInk[x] = true
                    break
                }
            }
        }

        var groups: [Range<Int>] = []
        var start: Int?
        var lastInk = minimumPixelX
        for x in minimumPixelX..<maximumPixelX {
            if hasInk[x] {
                if start == nil {
                    start = x
                }
                lastInk = x
            } else if let groupStart = start, x - lastInk > blankGap {
                groups.append(groupStart..<lastInk + 1)
                start = nil
            }
        }
        if let start {
            groups.append(start..<lastInk + 1)
        }

        return groups.suffix(count).map { group in
            CGRect(
                x: CGFloat(group.lowerBound) / scale,
                y: 0,
                width: CGFloat(group.count) / scale,
                height: CGFloat(bitmap.pixelsHigh) / scale
            )
        }
    }

    func glyphCenterY(in rect: CGRect) -> CGFloat? {
        inkBounds(in: rect).map(\.midY)
    }

    func glyphCenterY(from minX: CGFloat, to maxX: CGFloat) -> CGFloat? {
        let rect = CGRect(x: minX, y: 0, width: maxX - minX, height: CGFloat(bitmap.pixelsHigh) / scale)
        return inkBounds(in: rect).map(\.midY)
    }

    func controlRowCenterY(
        excluding excludedRects: [CGRect]
    ) -> CGFloat? {
        let actionRows = excludedRects.map { inkBounds(in: $0) }.compactMap { $0 }
        guard let actionTop = actionRows.map(\.minY).min(),
              let actionBottom = actionRows.map(\.maxY).max() else {
            return nil
        }
        let lowerY = max(0, Int(((actionTop - 12) * scale).rounded(.down)))
        let upperY = min(
            bitmap.pixelsHigh - 1,
            Int(((actionBottom + 12) * scale).rounded(.up))
        )
        guard lowerY <= upperY else { return nil }

        var minPixelY = upperY
        var maxPixelY = lowerY
        var found = false
        for x in 0..<bitmap.pixelsWide {
            let xPoint = (CGFloat(x) + 0.5) / scale
            guard !excludedRects.contains(where: { $0.minX <= xPoint && xPoint <= $0.maxX }) else {
                continue
            }
            for y in lowerY...upperY {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let luminance = 0.299 * color.redComponent
                    + 0.587 * color.greenComponent
                    + 0.114 * color.blueComponent
                guard luminance < 0.9 else { continue }
                found = true
                minPixelY = min(minPixelY, y)
                maxPixelY = max(maxPixelY, y)
            }
        }
        guard found else { return nil }
        return CGFloat(minPixelY + maxPixelY + 1) / (2 * scale)
    }

    private func inkBounds(in rect: CGRect) -> CGRect? {
        let lowerX = max(0, Int((rect.minX * scale).rounded(.down)))
        let upperX = min(bitmap.pixelsWide - 1, Int((rect.maxX * scale).rounded(.up)))
        let lowerY = max(0, Int((rect.minY * scale).rounded(.down)))
        let upperY = min(bitmap.pixelsHigh - 1, Int((rect.maxY * scale).rounded(.up)))
        guard lowerX <= upperX, lowerY <= upperY else { return nil }

        var minPixelX = upperX
        var maxPixelX = lowerX
        var minPixelY = upperY
        var maxPixelY = lowerY
        var found = false
        for x in lowerX...upperX {
            for y in lowerY...upperY {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let luminance = 0.299 * color.redComponent
                    + 0.587 * color.greenComponent
                    + 0.114 * color.blueComponent
                guard luminance < 0.9 else { continue }
                found = true
                minPixelX = min(minPixelX, x)
                maxPixelX = max(maxPixelX, x)
                minPixelY = min(minPixelY, y)
                maxPixelY = max(maxPixelY, y)
            }
        }
        guard found else { return nil }
        return CGRect(
            x: CGFloat(minPixelX) / scale,
            y: CGFloat(minPixelY) / scale,
            width: CGFloat(maxPixelX - minPixelX) / scale,
            height: CGFloat(maxPixelY - minPixelY) / scale
        )
    }
}
