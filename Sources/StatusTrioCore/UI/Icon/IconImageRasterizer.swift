import AppKit
import CoreGraphics
import ImageIO

/// Reads an icon file into one bounded bitmap representation.
///
/// Input-source and audio-device icons can be multi-representation ICNS or
/// TIFF files, or a large PNG. NSImage keeps every representation it read, so
/// the decode cache cannot account for, or bound, what is resident. ImageIO can
/// produce a transformed thumbnail without materialising the full-size source.
enum IconImageRasterizer {
    static func image(at url: URL, maximumPixelLength: Int) -> NSImage? {
        guard maximumPixelLength > 0 else { return nil }
        if usesPDFDocumentPath(type: nil, url: url) {
            return pdfImage(at: url, maximumPixelLength: maximumPixelLength)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let type = CGImageSourceGetType(source) as String?
        if usesPDFDocumentPath(type: type, url: url) {
            return pdfImage(at: url, maximumPixelLength: maximumPixelLength)
        }

        let index = bestRasterIndex(
            in: source,
            maximumPixelLength: maximumPixelLength
        )
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any]
        let selectedPixelLength = pixelLength(from: properties) ?? maximumPixelLength
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(
                maximumPixelLength,
                selectedPixelLength
            ),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        // ImageIO's thumbnail max applies within the selected representation.
        // Selection prefers the smallest representation large enough to serve
        // the request, then falls back to the largest one when all are smaller.
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            index,
            options as CFDictionary
        ) else {
            return nil
        }

        let pointSize = logicalPointSize(properties: properties, cgImage: cgImage)
        return makeImage(from: cgImage, pointSize: pointSize)
    }

    private static func bestRasterIndex(
        in source: CGImageSource,
        maximumPixelLength: Int
    ) -> Int {
        let count = CGImageSourceGetCount(source)
        var largestIndex = 0
        var largestLength = 0
        var smallestSufficientIndex: Int?
        var smallestSufficientLength = Int.max
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let length = max(width, height)
            guard length > 0 else { continue }
            if length > largestLength {
                largestIndex = index
                largestLength = length
            }
            if length >= maximumPixelLength,
               length < smallestSufficientLength {
                smallestSufficientIndex = index
                smallestSufficientLength = length
            }
        }
        if let smallestSufficientIndex {
            return smallestSufficientIndex
        }
        return largestIndex
    }

    private static func pdfImage(at url: URL, maximumPixelLength: Int) -> NSImage? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else {
            return nil
        }
        let cropBox = page.getBoxRect(.cropBox)
        guard cropBox.width.isFinite, cropBox.height.isFinite,
              cropBox.width > 0, cropBox.height > 0 else {
            return nil
        }
        let rotation = (Int(page.rotationAngle) % 360 + 360) % 360
        let displayedPointSize = rotation == 90 || rotation == 270
            ? CGSize(width: cropBox.height, height: cropBox.width)
            : cropBox.size
        let scale = min(
            CGFloat(maximumPixelLength) / displayedPointSize.width,
            CGFloat(maximumPixelLength) / displayedPointSize.height
        )
        let width = max(1, Int((displayedPointSize.width * scale).rounded()))
        let height = max(1, Int((displayedPointSize.height * scale).rounded()))
        guard width <= maximumPixelLength,
              height <= maximumPixelLength,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        let logicalBounds = CGRect(
            x: 0,
            y: 0,
            width: displayedPointSize.width,
            height: displayedPointSize.height
        )
        let pageTransform = page.getDrawingTransform(
            .cropBox,
            rect: logicalBounds,
            rotate: 0,
            preserveAspectRatio: true
        )
        // CGPDFPage can clamp this transform at 1:1 instead of enlarging the
        // page. Apply the requested pixel scale explicitly so a 16 pt vector
        // icon still fills its bounded raster.
        context.scaleBy(x: scale, y: scale)
        context.concatenate(pageTransform)
        context.drawPDFPage(page)
        guard let cgImage = context.makeImage() else { return nil }
        return makeImage(from: cgImage, pointSize: displayedPointSize)
    }

    private static func usesPDFDocumentPath(type: String?, url: URL) -> Bool {
        type == "com.adobe.pdf"
            || type == "public.pdf"
            || type == "public.pdf-page"
            || url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
    }

    private static func logicalPointSize(
        properties: [CFString: Any]?,
        cgImage: CGImage
    ) -> CGSize {
        logicalPointSize(
            properties: properties,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height
        )
    }

    internal static func logicalPointSize(
        properties: [CFString: Any]?,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGSize {
        let dpiWidth = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiHeight = (properties?[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        let sourceWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
            ?? Double(imageWidth)
        let sourceHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
            ?? Double(imageHeight)
        var pointSize = CGSize(
            width: max(1, sourceWidth * 72 / max(1, dpiWidth)),
            height: max(1, sourceHeight * 72 / max(1, dpiHeight))
        )
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        if (5...8).contains(orientation) {
            pointSize = CGSize(width: pointSize.height, height: pointSize.width)
        }
        return pointSize
    }

    private static func pixelLength(from properties: [CFString: Any]?) -> Int? {
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let length = max(width, height)
        return length > 0 ? length : nil
    }

    private static func makeImage(from cgImage: CGImage, pointSize: CGSize) -> NSImage? {
        guard pointSize.width.isFinite, pointSize.height.isFinite,
              pointSize.width > 0, pointSize.height > 0 else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = pointSize
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        image.cacheMode = .never
        return image
    }
}
