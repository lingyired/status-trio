import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// 解码次数: an input source keeps the same icon URL while it is selected, and
/// the menu bar's drawing handler runs on every display pass, so each URL has to
/// be decoded once and only once.
final class IconImageDecodeCacheTests: XCTestCase {
    func testEachURLIsDecodedOnce() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = URL(fileURLWithPath: "/tmp/status-trio-decode-once.png")
        let image = NSImage(size: NSSize(width: 16, height: 16))
        var loads = 0

        for _ in 0..<3 {
            let loaded = cache.image(for: url) { _ in
                loads += 1
                return image
            }
            XCTAssertTrue(loaded === image)
        }

        XCTAssertEqual(loads, 1)
    }

    /// The panel's monochrome version is derived from the file just once per
    /// URL: the mask is a second entry beside the decoded image, not a second
    /// read, so deleting the file after the first row render must not change
    /// what the next render draws.
    func testPanelMaskIsDerivedOncePerFile() throws {
        IconImageDecodeCache.shared.reset()
        defer { IconImageDecodeCache.shared.reset() }
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 32,
            pixelHeight: 32,
            inkRect: CGRect(x: 8, y: 8, width: 16, height: 16)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try XCTUnwrap(cache.monochromeInputSourceIcon(for: url))
        try FileManager.default.removeItem(at: url)
        let second = try XCTUnwrap(cache.monochromeInputSourceIcon(for: url))

        XCTAssertTrue(first === second)
    }

    func testDifferentURLsAreDecodedSeparately() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        var loadedURLs: [URL] = []

        for index in 0..<3 {
            let url = URL(fileURLWithPath: "/tmp/status-trio-source-\(index).png")
            _ = cache.image(for: url) { url in
                loadedURLs.append(url)
                return NSImage(size: NSSize(width: 16, height: 16))
            }
        }

        XCTAssertEqual(loadedURLs.count, 3)
    }

    /// A source whose file cannot be read must not poison the cache with a nil:
    /// the file can appear later, and the fallback is decided per render.
    func testFailedLoadIsNotCached() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = URL(fileURLWithPath: "/tmp/status-trio-missing.png")
        var loads = 0

        for _ in 0..<2 {
            XCTAssertNil(cache.image(for: url) { _ in
                loads += 1
                return nil
            })
        }

        XCTAssertEqual(loads, 2)
    }

    func testCacheIsBoundedByItsOldestEntries() {
        let cache = IconImageDecodeCache(maximumEntries: 2)
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/status-trio-bounded-\($0).png") }
        var loads = 0
        let load: (URL) -> NSImage? = { _ in
            loads += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }

        for url in urls {
            _ = cache.image(for: url, load: load)
        }
        XCTAssertEqual(loads, 3)

        // The most recent entry is still cached...
        _ = cache.image(for: urls[2], load: load)
        XCTAssertEqual(loads, 3)

        // ...while the evicted one is decoded again.
        _ = cache.image(for: urls[0], load: load)
        XCTAssertEqual(loads, 4)
    }

    func testDecodedAndMaskEntriesShareEntryAndByteBudget() throws {
        let cache = IconImageDecodeCache(
            maximumEntries: 2,
            maximumResidentBytes: 600_000
        )
        let urls = try (0..<3).map { _ in
            try InputSourceIconFixtures.writePNG(
                pixelWidth: 256,
                pixelHeight: 256,
                inkRect: CGRect(x: 64, y: 64, width: 128, height: 128)
            )
        }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        for url in urls {
            XCTAssertNotNil(cache.decodedImage(for: url))
            XCTAssertNotNil(cache.monochromeInputSourceIcon(for: url))
            XCTAssertLessThanOrEqual(cache.entryCount, 2)
            XCTAssertLessThanOrEqual(cache.residentByteCount, 600_000)
        }
    }

    func testOversizedImageIsReturnedButNotRetained() {
        let cache = IconImageDecodeCache(
            maximumEntries: 4,
            maximumResidentBytes: 1
        )
        let url = URL(fileURLWithPath: "/tmp/status-trio-oversized.png")
        var loads = 0
        let image = bitmapImage(pixelLength: 2)

        XCTAssertNotNil(cache.image(for: url) { _ in
            loads += 1
            return image
        })
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.residentByteCount, 0)

        XCTAssertNotNil(cache.image(for: url) { _ in
            loads += 1
            return image
        })
        XCTAssertEqual(loads, 2)
    }

    func testResetClearsEntriesAndBytes() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = URL(fileURLWithPath: "/tmp/status-trio-reset.png")
        XCTAssertNotNil(cache.image(for: url) { _ in bitmapImage(pixelLength: 16) })
        XCTAssertGreaterThan(cache.residentByteCount, 0)

        cache.reset()

        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.residentByteCount, 0)
    }

    func testLoadBeginningBeforeResetReturnsButDoesNotEnterNewEpoch() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = URL(fileURLWithPath: "/tmp/status-trio-epoch.png")
        var loads = 0

        let beforeReset = cache.image(for: url) { _ in
            loads += 1
            cache.reset()
            return self.bitmapImage(pixelLength: 16)
        }
        XCTAssertNotNil(beforeReset)
        XCTAssertEqual(cache.entryCount, 0)

        XCTAssertNotNil(cache.image(for: url) { _ in
            loads += 1
            return self.bitmapImage(pixelLength: 16)
        })
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(cache.entryCount, 1)
    }

    /// The renderer reads through the same cache the panel rows use, so a second
    /// render of an unchanged source never touches the file system.
    func testSharedCacheServesTheRendererWithoutTouchingDisk() throws {
        IconImageDecodeCache.shared.reset()
        defer { IconImageDecodeCache.shared.reset() }
        let url = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 64,
            pixelHeight: 64,
            inkRect: CGRect(x: 36, y: 20, width: 20, height: 24)
        )
        XCTAssertNotNil(IconImageDecodeCache.shared.decodedImage(for: url))

        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.removeItem(at: url)

        XCTAssertNotNil(IconImageDecodeCache.shared.decodedImage(for: url))
    }

    func testImageAtCustomSizeIsCachedAtThatKey() {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = URL(fileURLWithPath: "/tmp/status-trio-sized.png")
        var loads = 0
        let load: (URL) -> NSImage? = { _ in
            loads += 1
            return self.bitmapImage(pixelLength: 60)
        }

        _ = cache.image(for: url, maximumPixelLength: 60, load: load)
        _ = cache.image(for: url, maximumPixelLength: 60, load: load)
        XCTAssertEqual(loads, 1)

        _ = cache.image(for: url, maximumPixelLength: 120, load: load)
        XCTAssertEqual(loads, 2)
    }

    func testMaskAndDecodedGeometryMatchForWideTransparentImage() throws {
        let cache = IconImageDecodeCache(maximumEntries: 4)
        let url = try InputSourceIconFixtures.writePNG(
            pixelWidth: 512,
            pixelHeight: 128,
            inkRect: CGRect(x: 400, y: 32, width: 64, height: 64),
            inkColor: CGColor(gray: 0, alpha: 1)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try XCTUnwrap(cache.decodedImage(for: url))
        let mask = try XCTUnwrap(cache.monochromeInputSourceIcon(for: url))

        XCTAssertEqual(decoded.size.width / decoded.size.height, 4, accuracy: 0.001)
        XCTAssertEqual(mask.size, decoded.size)
        XCTAssertEqual(mask.representations.count, 1)
        XCTAssertLessThanOrEqual(mask.representations[0].pixelsWide, 128)
        XCTAssertLessThanOrEqual(mask.representations[0].pixelsHigh, 128)
    }

    func testUnknownMixedRepresentationIsNotRetained() {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmapRepresentation(pixelLength: 32))
        image.addRepresentation(UnknownImageRepresentation())
        let cache = IconImageDecodeCache(maximumEntries: 4)

        XCTAssertNotNil(cache.image(for: URL(fileURLWithPath: "/tmp/status-trio-mixed.png")) { _ in
            image
        })
        XCTAssertEqual(cache.entryCount, 0)
        XCTAssertEqual(cache.residentByteCount, 0)
    }

    func testPlanarImageAccountsForEveryPlane() {
        let image = planarBitmapImage(pixelWidth: 64, pixelHeight: 64)
        let bitmap = image.representations.first as! NSBitmapImageRep
        let expectedBytes = bitmap.bytesPerPlane * bitmap.numberOfPlanes
        XCTAssertTrue(bitmap.isPlanar)
        XCTAssertEqual(bitmap.numberOfPlanes, 4)
        XCTAssertGreaterThan(expectedBytes, bitmap.bytesPerRow * bitmap.pixelsHigh)

        let cache = IconImageDecodeCache(
            maximumEntries: 4,
            maximumResidentBytes: expectedBytes
        )
        XCTAssertNotNil(cache.image(
            for: URL(fileURLWithPath: "/tmp/status-trio-planar.png")
        ) { _ in image })

        XCTAssertEqual(cache.entryCount, 1)
        XCTAssertEqual(cache.residentByteCount, expectedBytes)
    }

    private func bitmapImage(pixelLength: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: pixelLength, height: pixelLength))
        image.addRepresentation(bitmapRepresentation(pixelLength: pixelLength))
        return image
    }

    private func bitmapRepresentation(pixelLength: Int) -> NSBitmapImageRep {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelLength,
            pixelsHigh: pixelLength,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelLength * 4,
            bitsPerPixel: 32
        )!
        representation.size = NSSize(width: pixelLength, height: pixelLength)
        return representation
    }

    private func planarBitmapImage(pixelWidth: Int, pixelHeight: Int) -> NSImage {
        let pixelCount = pixelWidth * pixelHeight
        let red = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let green = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let blue = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let alpha = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        red.initialize(repeating: 0, count: pixelCount)
        green.initialize(repeating: 0, count: pixelCount)
        blue.initialize(repeating: 0, count: pixelCount)
        alpha.initialize(repeating: 255, count: pixelCount)
        defer {
            red.deinitialize(count: pixelCount)
            green.deinitialize(count: pixelCount)
            blue.deinitialize(count: pixelCount)
            alpha.deinitialize(count: pixelCount)
            red.deallocate()
            green.deallocate()
            blue.deallocate()
            alpha.deallocate()
        }
        let planes = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: 4)
        planes.initialize(from: [red, green, blue, alpha], count: 4)
        defer {
            planes.deinitialize(count: 4)
            planes.deallocate()
        }
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: planes,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: true,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
        image.addRepresentation(representation)
        return image
    }
}

private final class UnknownImageRepresentation: NSImageRep {}
