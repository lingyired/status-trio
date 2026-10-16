import AppKit
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

    /// The renderer reads through the same cache the panel rows use, so a second
    /// render of an unchanged source never touches the file system.
    func testSharedCacheServesTheRendererWithoutTouchingDisk() throws {
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
}
