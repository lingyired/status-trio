import AppKit
import XCTest
@testable import StatusTrioCore

/// The panel's row icons: an input source's own file has to survive as a single
/// flat mark, because the panel draws it in the row's text colour on a panel
/// that can be dark.
@MainActor
final class InputSourceIconMaskTests: XCTestCase {
    /// The WeChat input method ships exactly this shape: a filled dark badge
    /// with a light mark inside it. Tinting its alpha would fill the badge and
    /// lose the mark, so the mask has to knock the mark out.
    func testFilledBadgeKeepsTheMarkInsideItAsAKnockout() throws {
        let icon = makeIcon { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 12, y: 12, width: 8, height: 8))
        }

        let mask = try XCTUnwrap(InputSourceIconMask.make(from: icon))
        let pixels = try rasterize(mask)

        XCTAssertTrue(mask.isTemplate, "the panel tints the mask, so it must be a template")
        XCTAssertEqual(mask.size, icon.size)

        let badge = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 16, y: 4), of: mask))
        XCTAssertGreaterThan(badge.alpha, 200, "the badge itself has to become the mark")
        XCTAssertEqual(badge.red, badge.alpha, "the mask is white; the tint comes from the row")
        XCTAssertEqual(badge.green, badge.alpha)
        XCTAssertEqual(badge.blue, badge.alpha)

        let mark = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 16, y: 16), of: mask))
        XCTAssertLessThan(mark.alpha, 40, "the light mark inside the badge stays a hole")
    }

    /// The shipped Pinyin icon is dark art on transparency. Its ink has to keep
    /// the glyph and drop the empty background.
    func testDarkGlyphOnTransparencyKeepsTheGlyph() throws {
        let icon = makeIcon { context in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 12, y: 12, width: 8, height: 8))
        }

        let mask = try XCTUnwrap(InputSourceIconMask.make(from: icon))
        let pixels = try rasterize(mask)

        let glyph = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 16, y: 16), of: mask))
        XCTAssertGreaterThan(glyph.alpha, 200)

        let background = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 2, y: 2), of: mask))
        XCTAssertLessThan(background.alpha, 10)
    }

    /// A light logo on transparency reads as ink too: the icon's own average
    /// tone decides which direction the mask measures, so this cannot silently
    /// blank such an icon.
    func testLightGlyphOnTransparencyStaysReadable() throws {
        let icon = makeIcon { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 12, y: 12, width: 8, height: 8))
        }

        let mask = try XCTUnwrap(InputSourceIconMask.make(from: icon))
        let pixels = try rasterize(mask)

        let glyph = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 16, y: 16), of: mask))
        XCTAssertGreaterThan(glyph.alpha, 200)

        let background = try XCTUnwrap(pixel(in: pixels, at: CGPoint(x: 2, y: 2), of: mask))
        XCTAssertLessThan(background.alpha, 10)
    }

    func testFullyTransparentIconHasNoMask() {
        let icon = makeIcon { _ in }

        XCTAssertNil(InputSourceIconMask.make(from: icon))
    }

    // MARK: - Fixtures

    private func makeIcon(
        size: NSSize = NSSize(width: 32, height: 32),
        draw: @escaping (CGContext) -> Void
    ) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(context)
            return true
        }
    }

    private func rasterize(_ image: NSImage) throws -> PixelBuffer {
        var rect = CGRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try PixelBuffer(image: cgImage)
    }

    private func pixel(
        in buffer: PixelBuffer,
        at point: CGPoint,
        of image: NSImage
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let scale = CGFloat(buffer.width) / image.size.width
        let x = Int(point.x * scale)
        let y = Int(point.y * scale)
        guard x >= 0, x < buffer.width, y >= 0, y < buffer.height else { return nil }
        return buffer.rgba(x: x, y: y)
    }
}
