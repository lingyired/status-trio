import AppKit
import ImageIO
import XCTest
@testable import StatusTrioCore

final class IconImageRasterizerTests: XCTestCase {
    func testLargePNGIsBoundedToMaximumPixelLength() throws {
        let url = try InputSourceIconFixtures.writePNG(
            pixelWidth: 4096,
            pixelHeight: 2048,
            inkRect: CGRect(x: 3000, y: 200, width: 800, height: 1600)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 512))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(max(bitmap.pixelsWide, bitmap.pixelsHigh), 512)
        XCTAssertGreaterThan(bitmap.pixelsWide, bitmap.pixelsHigh)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.001)
    }

    func testWideTransparentImagePreservesWholeAspectRatio() throws {
        let url = try InputSourceIconFixtures.writePNG(
            pixelWidth: 1600,
            pixelHeight: 200,
            inkRect: CGRect(x: 1400, y: 50, width: 100, height: 100)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 128))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(bitmap.pixelsWide, 128)
        XCTAssertEqual(bitmap.pixelsHigh, 16)
        XCTAssertEqual(image.size.width / image.size.height, 8, accuracy: 0.001)
    }

    func testLowResolutionImageIsNotUpscaled() throws {
        let url = try InputSourceIconFixtures.writePNG(
            pixelWidth: 24,
            pixelHeight: 18,
            inkRect: CGRect(x: 4, y: 3, width: 8, height: 6)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 512))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(bitmap.pixelsWide, 24)
        XCTAssertEqual(bitmap.pixelsHigh, 18)
    }

    func testPDFUsesBoundedRasterAndKeepsAspectRatio() throws {
        let url = try InputSourceIconFixtures.writePDFIcon(
            pointWidth: 48,
            pointHeight: 24,
            inkRect: CGRect(x: 28, y: 4, width: 16, height: 16)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 96))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(bitmap.pixelsWide, 96)
        XCTAssertEqual(bitmap.pixelsHigh, 48)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.001)

        let pixels = try PixelBuffer(image: XCTUnwrap(bitmap.cgImage))
        var minimumAlpha = UInt8.max
        var maximumAlpha = UInt8.min
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let alpha = pixels.rgba(x: x, y: y).alpha
                minimumAlpha = min(minimumAlpha, alpha)
                maximumAlpha = max(maximumAlpha, alpha)
            }
        }
        XCTAssertLessThan(minimumAlpha, 10, "the PDF background must stay transparent")
        XCTAssertGreaterThan(maximumAlpha, 200, "the PDF ink must stay opaque")
    }

    func testPDFUpscalesEvenOddVectorArtToTheRequestedPixelBounds() throws {
        let url = try InputSourceIconFixtures.writeEvenOddPDFIcon()
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 512))
        let bitmap = try bitmap(of: image)
        let pixels = try PixelBuffer(image: XCTUnwrap(bitmap.cgImage))

        var visiblePixels = 0
        var minX = pixels.width
        var maxX = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgba(x: x, y: y).alpha > 10 {
                visiblePixels += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }

        XCTAssertEqual(bitmap.pixelsWide, 512)
        XCTAssertEqual(bitmap.pixelsHigh, 512)
        XCTAssertGreaterThan(
            visiblePixels,
            100_000,
            "the 16 pt page must be scaled across the requested 512 px bounds"
        )
        XCTAssertLessThanOrEqual(minX, 64, "the vector ink must reach the left side of the bitmap")
        XCTAssertGreaterThanOrEqual(maxX, 448, "the vector ink must reach the right side of the bitmap")
        XCTAssertLessThan(
            pixels.rgba(x: 256, y: 256).alpha,
            10,
            "the even-odd centre must stay transparent"
        )
        XCTAssertGreaterThan(
            pixels.rgba(x: 256, y: 100).alpha,
            200,
            "the scaled ring must keep opaque vector ink"
        )
    }

    func testRotatedPDFUsesDisplayedLogicalSizeAndInkOrientation() throws {
        let url = try InputSourceIconFixtures.writeRotatedPDFIcon()
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.cropBox), CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(page.rotationAngle, 90)

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 80))
        let bitmap = try bitmap(of: image)
        XCTAssertEqual(bitmap.pixelsWide, 40)
        XCTAssertEqual(bitmap.pixelsHigh, 80)
        XCTAssertEqual(image.size, CGSize(width: 100, height: 200))

        let pixels = try PixelBuffer(image: XCTUnwrap(bitmap.cgImage))
        let topAlpha = (0..<(pixels.height / 2)).reduce(0) { total, y in
            total + (0..<pixels.width).reduce(0) {
                $0 + Int(pixels.rgba(x: $1, y: y).alpha)
            }
        }
        let bottomAlpha = ((pixels.height / 2)..<pixels.height).reduce(0) { total, y in
            total + (0..<pixels.width).reduce(0) {
                $0 + Int(pixels.rgba(x: $1, y: y).alpha)
            }
        }
        XCTAssertGreaterThan(topAlpha, bottomAlpha * 10)
    }

    func testICNSProducesSingleBoundedBitmap() throws {
        let url = try InputSourceIconFixtures.writeICNSIcon()
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 64))

        XCTAssertEqual(image.representations.count, 1)
        XCTAssertTrue(image.representations.first is NSBitmapImageRep)
        XCTAssertLessThanOrEqual(max(image.representations[0].pixelsWide,
                                     image.representations[0].pixelsHigh), 64)
    }

    func testMultiRepresentationTIFFKeepsOnlyOneBoundedRepresentation() throws {
        let url = try InputSourceIconFixtures.writeMultiRepresentationTIFF()
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 64))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(image.representations.count, 1)
        XCTAssertEqual(max(bitmap.pixelsWide, bitmap.pixelsHigh), 64)
    }

    func testICNSChoosesSmallestRepresentationLargeEnoughForTheLimit() throws {
        let url = try InputSourceIconFixtures.writeICNSIcon()
        defer { try? FileManager.default.removeItem(at: url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return XCTFail("the ICNS fixture did not expose an ImageIO source")
        }
        let dimensions = (0..<CGImageSourceGetCount(source)).compactMap { index -> Int? in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any]
            return properties?[kCGImagePropertyPixelWidth] as? Int
        }
        XCTAssertTrue(dimensions.contains(32))
        XCTAssertTrue(dimensions.contains(128))
        XCTAssertTrue(dimensions.contains(256))
        XCTAssertTrue(dimensions.contains(512))

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 512))
        XCTAssertEqual(try bitmap(of: image).pixelsWide, 512)
    }

    func testPointSizeComesFromDPIAndUsesSingleBitmap() throws {
        let url = try InputSourceIconFixtures.writePNGWithPointSize(
            pixelWidth: 96,
            pixelHeight: 48,
            pointWidth: 48,
            pointHeight: 24,
            inkRect: CGRect(x: 60, y: 8, width: 24, height: 24)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 64))
        let bitmap = try bitmap(of: image)

        XCTAssertEqual(bitmap.pixelsWide, 64)
        XCTAssertEqual(bitmap.pixelsHigh, 32)
        XCTAssertEqual(image.size.width, 48, accuracy: 1)
        XCTAssertEqual(image.size.height, 24, accuracy: 1)
    }

    func testOrientationTransformIsAppliedConsistently() throws {
        let url = try InputSourceIconFixtures.writeRotatedIcon(
            pixelWidth: 64,
            pixelHeight: 32,
            inkRect: CGRect(x: 20, y: 4, width: 24, height: 24)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(IconImageRasterizer.image(at: url, maximumPixelLength: 64))
        let bitmap = try bitmap(of: image)

        XCTAssertGreaterThan(bitmap.pixelsHigh, bitmap.pixelsWide)
        XCTAssertGreaterThan(image.size.height, image.size.width)
    }

    func testCorruptAndMissingFilesReturnNil() throws {
        let corrupt = try InputSourceIconFixtures.writeCorruptIcon()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-missing-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.removeItem(at: missing)
        }

        XCTAssertNil(IconImageRasterizer.image(at: corrupt, maximumPixelLength: 512))
        XCTAssertNil(IconImageRasterizer.image(at: missing, maximumPixelLength: 512))
    }

    func testMaximumPixelLengthMustBePositive() throws {
        let url = try InputSourceIconFixtures.writePNG(
            pixelWidth: 16,
            pixelHeight: 16,
            inkRect: CGRect(x: 4, y: 4, width: 8, height: 8)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(IconImageRasterizer.image(at: url, maximumPixelLength: 0))
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(image.representations.count, 1)
        return representation
    }
}
