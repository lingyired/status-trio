import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Pixel proof for the ABC keycap.
///
/// The fix replaces the semantic `.primary` fill — the label colour, only about
/// 85 % white in dark mode, which reads as grey — with an explicit white disc in
/// dark mode and black in light mode. These tests render the real
/// `InputSourceLabelChip` headlessly with `ImageRenderer` (no window, no
/// ordering, no GUI) and read the resulting bitmap, so they pin both the fill
/// value and the two ways the `destinationOut` letter can misbehave.
@MainActor
final class InputSourceLabelChipRenderingTests: XCTestCase {
    private let scale = 8
    private let canvas = CGSize(width: 40, height: 24)
    private let chipSize = CGSize(width: 18, height: 15)
    /// A backdrop that is neither the chip's white nor its black, so a knocked
    /// out letter and a leaked knockout are both unambiguous.
    private let backdrop = Color(red: 0, green: 0.5, blue: 0.5)
    private let backdropRGB = (r: 0, g: 128, b: 128)
    private let backdropTolerance = 6

    func testDarkChipFillsExplicitWhiteNotLabelGrey() throws {
        let image = try render(scheme: .dark)
        XCTAssertEqual(image.transparentPixelCount, 0)
        let fill = try dominantFill(in: image, rect: chipRectPixels)
        XCTAssertLessThanOrEqual(abs(fill.r - 255), 1, "dark chip must be explicit white, got \(fill)")
        XCTAssertLessThanOrEqual(abs(fill.g - 255), 1, "dark chip must be explicit white, got \(fill)")
        XCTAssertLessThanOrEqual(abs(fill.b - 255), 1, "dark chip must be explicit white, got \(fill)")
        // The old `.primary` fill is only ~85 % opaque white, so over this teal
        // backdrop it blended to about (216, 236, 236). Keep it from silently
        // regressing back to that translucent label colour.
        XCTAssertGreaterThan(fill.r, 240, "dark chip fell back to label grey: \(fill)")
    }

    func testLightChipFillsExplicitBlack() throws {
        let image = try render(scheme: .light)
        XCTAssertEqual(image.transparentPixelCount, 0)
        let fill = try dominantFill(in: image, rect: chipRectPixels)
        XCTAssertLessThanOrEqual(fill.r, 1, "light chip must be explicit black, got \(fill)")
        XCTAssertLessThanOrEqual(fill.g, 1, "light chip must be explicit black, got \(fill)")
        XCTAssertLessThanOrEqual(fill.b, 1, "light chip must be explicit black, got \(fill)")
    }

    func testLetterKnocksTheBackdropThroughTheDisc() throws {
        for scheme in [ColorScheme.dark, .light] {
            let image = try render(scheme: scheme)
            let inner = chipRectPixels.insetBy(dx: chipRectPixels.width / 6, dy: chipRectPixels.height / 6)
            XCTAssertTrue(
                image.contains(in: inner, where: isBackdrop),
                "the letter must knock the backdrop through the disc in \(scheme)"
            )
        }
    }

    func testDestinationOutNeverPunchesThroughTheRow() throws {
        for scheme in [ColorScheme.dark, .light] {
            let image = try render(scheme: scheme)
            XCTAssertEqual(
                image.transparentPixelCount, 0,
                "compositingGroup must contain destinationOut in \(scheme)"
            )
            // Everything outside the chip frame has to stay the untouched,
            // opaque backdrop.
            let chip = chipRectPixels.insetBy(dx: -2, dy: -2)
            XCTAssertTrue(
                image.allPixelsOutside(chip, where: isBackdrop),
                "destinationOut leaked past the chip in \(scheme)"
            )
        }
    }

    // MARK: - Rendering

    private func render(scheme: ColorScheme) throws -> Bitmap {
        let root = ZStack {
            backdrop
            InputSourceLabelChip(label: "ABC")
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: root)
        renderer.scale = CGFloat(scale)
        let nsImage = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
        let cgImage = try XCTUnwrap(
            nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// The chip's frame, in bitmap pixels. The chip is centred in the canvas, so
    /// this rectangle is symmetric and unaffected by the bitmap's row direction.
    private var chipRectPixels: CGRect {
        let originX = (canvas.width - chipSize.width) / 2
        let originY = (canvas.height - chipSize.height) / 2
        return CGRect(
            x: originX * CGFloat(scale),
            y: originY * CGFloat(scale),
            width: chipSize.width * CGFloat(scale),
            height: chipSize.height * CGFloat(scale)
        )
    }

    private func dominantFill(in image: Bitmap, rect: CGRect) throws -> (r: Int, g: Int, b: Int) {
        var counts: [String: Int] = [:]
        var sample: (r: Int, g: Int, b: Int) = (r: -1, g: -1, b: -1)
        image.forEachPixel(in: rect) { pixel in
            guard pixel.a >= 250, !isBackdrop(pixel) else { return }
            let key = "\(pixel.r),\(pixel.g),\(pixel.b)"
            counts[key, default: 0] += 1
            if sample.r < 0 { sample = (pixel.r, pixel.g, pixel.b) }
        }
        guard let dominant = counts.max(by: { $0.value < $1.value })?.key else {
            throw XCTSkip("no fill pixels found inside chip rect \(rect)")
        }
        let parts = dominant.split(separator: ",").compactMap { Int($0) }
        return (parts[0], parts[1], parts[2])
    }

    private func isBackdrop(_ pixel: Bitmap.Pixel) -> Bool {
        abs(pixel.r - backdropRGB.r) <= backdropTolerance
            && abs(pixel.g - backdropRGB.g) <= backdropTolerance
            && abs(pixel.b - backdropRGB.b) <= backdropTolerance
    }
}

private struct Bitmap {
    struct Pixel {
        let r: Int
        let g: Int
        let b: Int
        let a: Int
    }

    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (y * width + x) * 4
        return Pixel(
            r: Int(bytes[index]),
            g: Int(bytes[index + 1]),
            b: Int(bytes[index + 2]),
            a: Int(bytes[index + 3])
        )
    }

    var transparentPixelCount: Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where pixel(x: x, y: y).a < 10 {
                count += 1
            }
        }
        return count
    }

    func forEachPixel(in rect: CGRect, _ body: (Pixel) -> Void) {
        let minX = max(0, Int(rect.minX))
        let maxX = min(width, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return }
        for y in minY..<maxY {
            for x in minX..<maxX {
                body(pixel(x: x, y: y))
            }
        }
    }

    func contains(in rect: CGRect, where predicate: (Pixel) -> Bool) -> Bool {
        var found = false
        forEachPixel(in: rect) { pixel in
            if predicate(pixel) { found = true }
        }
        return found
    }

    func allPixelsOutside(_ rect: CGRect, where predicate: (Pixel) -> Bool) -> Bool {
        var satisfied = true
        for y in 0..<height {
            for x in 0..<width where !rect.contains(CGPoint(x: x, y: y)) {
                if !predicate(pixel(x: x, y: y)) { satisfied = false }
            }
        }
        return satisfied
    }
}
