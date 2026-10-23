import AppKit
import CoreGraphics
import ImageIO
import Foundation
import XCTest
@testable import StatusTrioCore

/// Icon files for the input-source rendering tests.
///
/// Input sources hand their icon over as a file (`kTISPropertyIconImageURL`), so
/// the fixtures are real files on disk: the renderer caches the decode by URL,
/// and an in-memory image would skip that path.
enum InputSourceIconFixtures {
    enum Background {
        case transparent
        case opaque
    }

    /// Writes a PNG whose inked area sits deliberately off the bitmap's centre,
    /// so a box-centred draw and an ink-centred draw land in different places.
    /// A symmetric fixture could pass while the layout is wrong.
    static func writeIcon(
        pixelWidth: Int,
        pixelHeight: Int,
        inkRect: CGRect,
        background: Background = .transparent,
        inkColor: CGColor = CGColor(gray: 1, alpha: 1),
        at destination: URL? = nil
    ) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if background == .opaque {
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        context.setFillColor(inkColor)
        context.fill(inkRect)

        let cgImage = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        )
        let url = destination ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-input-source-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    /// Writes a deliberately over-resolution raster so the decoder has to use
    /// ImageIO's thumbnail path instead of materialising a 64 MiB bitmap.
    static func writePNG(
        pixelWidth: Int,
        pixelHeight: Int,
        inkRect: CGRect,
        background: Background = .transparent,
        inkColor: CGColor = CGColor(gray: 1, alpha: 1)
    ) throws -> URL {
        try writeIcon(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            inkRect: inkRect,
            background: background,
            inkColor: inkColor
        )
    }

    /// A PNG containing one small bitmap. ImageIO applies the orientation during
    /// thumbnail creation so the normalised image has the displayed dimensions.
    static func writeRotatedIcon(
        pixelWidth: Int,
        pixelHeight: Int,
        inkRect: CGRect
    ) throws -> URL {
        let url = try writeIcon(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            inkRect: inkRect
        )
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
              ) else {
            throw FixtureError.cannotWriteImage
        }
        var metadata = properties
        metadata[kCGImagePropertyOrientation] = 6
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.cannotWriteImage
        }
        return url
    }

    /// Writes a TIFF with independent 32 px and 96 px representations. The
    /// decoder must choose one bounded representation rather than keeping both.
    static func writeMultiRepresentationTIFF() throws -> URL {
        let small = try rasterImage(
            pixelWidth: 32,
            pixelHeight: 32,
            inkRect: CGRect(x: 4, y: 4, width: 8, height: 8)
        )
        let large = try rasterImage(
            pixelWidth: 96,
            pixelHeight: 96,
            inkRect: CGRect(x: 24, y: 12, width: 40, height: 60)
        )
        let data = try XCTUnwrap(NSBitmapImageRep.representationOfImageReps(
            in: [small, large],
            using: .tiff,
            properties: [:]
        ))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-multi-\(UUID().uuidString).tiff")
        try data.write(to: url)
        return url
    }

    /// ICNS is a multi-representation container used by application icons.
    static func writeICNSIcon() throws -> URL {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        let representations: [(pixels: Int, scale: Int)] = [
            (16, 1),
            (16, 2),
            (32, 1),
            (32, 2),
            (128, 1),
            (128, 2),
            (256, 1),
            (256, 2),
            (512, 1),
            (512, 2)
        ]
        for representation in representations {
            let size = representation.pixels
            let scale = representation.scale
            let image = try rasterImage(
                pixelWidth: size * scale,
                pixelHeight: size * scale,
                inkRect: CGRect(
                    x: CGFloat(size * scale) * 0.25,
                    y: CGFloat(size * scale) * 0.125,
                    width: CGFloat(size * scale) * 0.5,
                    height: CGFloat(size * scale) * 0.7
                )
            )
            let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 1 ? "" : "@\(scale)x").png"))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-\(UUID().uuidString).icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["--convert", "icns", "--output", url.path, iconset.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureError.cannotWriteImage
        }
        return url
    }

    static func writeCorruptIcon() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-corrupt-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: url)
        return url
    }

    /// The same fixture as a PDF page, which is what real input sources ship
    /// (`/Library/Input Methods/…/menu_icon.pdf`). A PDF has no pixels of its
    /// own, so this is the case that proves the ink measurement rasterises a
    /// vector icon at a usable resolution.
    static func writePDFIcon(
        pointWidth: CGFloat,
        pointHeight: CGFloat,
        inkRect: CGRect
    ) throws -> URL {
        var mediaBox = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(inkRect)
        context.endPDFPage()
        context.closePDF()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-input-source-\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return url
    }

    /// A 16 pt PDF with the same vector traits as real input-source icons:
    /// an ICCBased colour space and an even-odd path that knocks a transparent
    /// hole out of a filled circle. At 512 px the ring must cover most of the
    /// bitmap, not just the page's original 16 px square.
    static func writeEvenOddPDFIcon() throws -> URL {
        var mediaBox = CGRect(x: 0, y: 0, width: 16, height: 16)
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addEllipse(in: CGRect(x: 1, y: 1, width: 14, height: 14))
        context.addEllipse(in: CGRect(x: 5, y: 5, width: 6, height: 6))
        context.fillPath(using: .evenOdd)
        context.endPDFPage()
        context.closePDF()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-even-odd-\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return url
    }

    /// A valid portrait PDF after `/Rotate 90`: its 200x100 crop box displays
    /// as 100x200. The left half of the unrotated page becomes the top half.
    static func writeRotatedPDFIcon() throws -> URL {
        let bytes = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [3 0 R] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate 90 /Resources << >> /Contents 4 0 R >>
        endobj
        4 0 obj
        << /Length 25 >>
        stream
        1 0 0 rg 0 0 50 100 re f
        endstream
        endobj
        xref
        0 5
        0000000000 65535 f\u{20}
        0000000009 00000 n\u{20}
        0000000058 00000 n\u{20}
        0000000115 00000 n\u{20}
        0000000230 00000 n\u{20}
        trailer
        << /Size 5 /Root 1 0 R >>
        startxref
        304
        %%EOF

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-rotated-\(UUID().uuidString).pdf")
        try Data(bytes.utf8).write(to: url)
        return url
    }

    static func writePNGWithPointSize(
        pixelWidth: Int,
        pixelHeight: Int,
        pointWidth: CGFloat,
        pointHeight: CGFloat,
        inkRect: CGRect
    ) throws -> URL {
        let sourceURL = try writeIcon(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            inkRect: inkRect
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let outputURL = Optional(
                  FileManager.default.temporaryDirectory
                      .appendingPathComponent("status-trio-point-size-\(UUID().uuidString).png")
              ),
              let destination = CGImageDestinationCreateWithURL(
                  outputURL as CFURL,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw FixtureError.cannotWriteImage
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: (Double(pixelWidth) * 72 / Double(pointWidth)).rounded(),
            kCGImagePropertyDPIHeight: (Double(pixelHeight) * 72 / Double(pointHeight)).rounded()
        ]
        CGImageDestinationAddImageFromSource(destination, imageSource, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.cannotWriteImage
        }
        return outputURL
    }

    private enum FixtureError: Error {
        case cannotWriteImage
    }

    private static func rasterImage(
        pixelWidth: Int,
        pixelHeight: Int,
        inkRect: CGRect
    ) throws -> NSBitmapImageRep {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(inkRect)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
    }
}

extension PixelBuffer {
    /// Edge-to-edge midpoint of the opaque ink in the icon's own scene units,
    /// independent of how much faint anti-aliasing each platform includes.
    func horizontalAlphaMidpoint(size: CGFloat, scale: CGFloat) -> CGFloat? {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        var minX = width
        var maxX = -1
        for y in 0..<height {
            for x in 0..<width where rgba(x: x, y: y).alpha > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard minX <= maxX else { return nil }
        return (CGFloat(minX) + CGFloat(maxX) + 1) / 2 / pixelsPerSVGUnit
    }

    /// Ink bounds inside `rect` (scene units), returned in scene units with the
    /// renderer's top-down y. Lets a test measure one mark without the pixels of
    /// a neighbour it is compared against.
    func alphaBounds(
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat,
        minimumAlpha: UInt8 = 0
    ) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)? {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * pixelsPerSVGUnit).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * pixelsPerSVGUnit).rounded(.up)))
        let minY = max(0, Int((rect.minY * pixelsPerSVGUnit).rounded(.down)))
        let maxY = min(height, Int((rect.maxY * pixelsPerSVGUnit).rounded(.up)))
        guard minX < maxX, minY < maxY else { return nil }

        var left = maxX, right = -1, top = maxY, bottom = -1
        for y in minY..<maxY {
            for x in minX..<maxX where rgba(x: x, y: y).alpha > minimumAlpha {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return (
            CGFloat(left) / pixelsPerSVGUnit,
            CGFloat(top) / pixelsPerSVGUnit,
            CGFloat(right + 1) / pixelsPerSVGUnit,
            CGFloat(bottom + 1) / pixelsPerSVGUnit
        )
    }
}
