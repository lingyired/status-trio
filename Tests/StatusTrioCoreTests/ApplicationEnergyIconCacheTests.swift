import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class ApplicationEnergyIconCacheTests: XCTestCase {
    func testSuccessfulLoadIsReusedForTheSameBundlePath() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return Self.solidImage()
        }

        let first = cache.image(for: "/Applications/Browser.app")
        let second = cache.image(for: "/Applications/Browser.app")

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testFailedLoadIsNotCachedAndCanRecover() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return loads == 1 ? nil : Self.solidImage()
        }

        XCTAssertNil(cache.image(for: "/Applications/Browser.app"))
        XCTAssertEqual(cache.entryCount, 0)

        XCTAssertNotNil(cache.image(for: "/Applications/Browser.app"))
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(cache.entryCount, 1)
    }

    func testLeastRecentlyUsedEntryIsEvictedAtTheLimit() {
        var loads: [String: Int] = [:]
        let cache = ApplicationEnergyIconCache(maximumEntries: 2) { url in
            loads[url.path, default: 0] += 1
            return Self.solidImage()
        }

        _ = cache.image(for: "/Applications/A.app")
        _ = cache.image(for: "/Applications/B.app")
        _ = cache.image(for: "/Applications/A.app")
        _ = cache.image(for: "/Applications/C.app")
        XCTAssertEqual(cache.entryCount, 2)

        _ = cache.image(for: "/Applications/A.app")
        XCTAssertEqual(loads["/Applications/A.app"], 1, "A was touched before C was inserted")

        _ = cache.image(for: "/Applications/B.app")
        XCTAssertEqual(loads["/Applications/B.app"], 2, "B was the least recently used entry")
    }

    func testEmptyPathDoesNotCallTheLoader() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return Self.solidImage()
        }

        XCTAssertNil(cache.image(for: ""))
        XCTAssertEqual(loads, 0)
        XCTAssertEqual(cache.entryCount, 0)
    }

    func testRasterSizeIsPartOfTheCacheKey() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return Self.solidImage()
        }

        _ = cache.image(for: "/Applications/Browser.app", pixelLength: 16)
        _ = cache.image(for: "/Applications/Browser.app", pixelLength: 32)

        XCTAssertEqual(loads, 2)
        XCTAssertEqual(cache.entryCount, 2)
    }

    func testHighEnergyAppsViewUsesTheInjectedCache() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return Self.solidImage()
        }
        let ranking = ApplicationEnergyRanking(
            apps: [
                EnergyApplication(id: "/Applications/Browser.app", name: "Browser"),
                EnergyApplication(id: "/Applications/Editor.app", name: "Editor")
            ],
            basis: .cpuEnergy,
            phase: .ready
        )
        let localization = Localization(preferredLanguages: ["en"])
        let view = HighEnergyAppsView(ranking: ranking, iconCache: cache)
            .environmentObject(localization)
        let hosting = NSHostingView(rootView: view)

        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(loads, 2)

        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(loads, 2, "A body update must reuse the cached application icons")
    }

    func testHighEnergyAppsViewRendersFallbackWhenAnIconFailsToLoad() {
        var loads = 0
        let cache = ApplicationEnergyIconCache(maximumEntries: 8) { _ in
            loads += 1
            return nil
        }
        let ranking = ApplicationEnergyRanking(
            apps: [EnergyApplication(id: "/Applications/Missing.app", name: "Missing")],
            basis: .cpuEnergy,
            phase: .ready
        )
        let localization = Localization(preferredLanguages: ["en"])
        let view = HighEnergyAppsView(ranking: ranking, iconCache: cache)
            .environmentObject(localization)
        let hosting = NSHostingView(rootView: view)

        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(loads, 1)
        XCTAssertEqual(cache.entryCount, 0, "A failed icon must fall back without poisoning the cache")
    }

    private static func solidImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        return image
    }
}
