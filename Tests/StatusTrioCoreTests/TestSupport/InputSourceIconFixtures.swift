import AppKit
import CoreGraphics
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
        background: Background = .transparent
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
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(inkRect)

        let cgImage = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-input-source-\(UUID().uuidString).png")
        try png.write(to: url)
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
