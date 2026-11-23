import AppKit
import Testing
@testable import StatusTrioCore

@Suite(.serialized)
@MainActor
struct StatusIconPreviewCacheTests {
    private func scene(volume: Double, color: IconColorRole = .primary) -> IconSceneState {
        IconSceneState(
            outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.62, color: .primary)],
                gap: .value,
                accessory: .text(IconTextState(text: "68", color: .primary, scale: 1)),
                strokeScale: 1.25
            ),
            center: .text(IconTextState(text: "Wi-Fi", color: .primary, scale: 0.6)),
            footer: .arc(ArcState(progress: volume, color: color, strokeScale: 1.25)),
            statusColors: .standard
        )
    }

    /// The whole point of the cache: re-evaluating a preview body must not
    /// rasterize the icon again.
    @Test func repeatedLookupsReuseTheRenderedImage() throws {
        let cache = StatusIconPreviewCache()
        let scenes = scene(volume: 0.5)

        let first = try #require(cache.image(scene: scenes, size: 28, scale: 2))
        let second = try #require(cache.image(scene: scenes, size: 28, scale: 2))

        #expect(first === second)
        #expect(cache.entryCount == 1)
    }

    /// A different scene is a different raster.
    @Test func aChangedVolumeRendersANewImage() throws {
        let cache = StatusIconPreviewCache()

        let quiet = try #require(cache.image(scene: scene(volume: 0.2), size: 28, scale: 2))
        let loud = try #require(cache.image(scene: scene(volume: 0.8), size: 28, scale: 2))

        #expect(quiet !== loud)
        #expect(cache.entryCount == 2)
    }

    /// The cached image must be an eagerly rasterized bitmap. A drawing-handler
    /// backed `NSImage` (what `StatusIconRenderer.image` returns) would re-run
    /// the whole render on every composite, which is the defect this fixes.
    @Test func cachedImageIsABitmapNotADrawingHandler() throws {
        let cache = StatusIconPreviewCache()
        let image = try #require(cache.image(scene: scene(volume: 0.5), size: 28, scale: 2))

        #expect(image.representations.contains { $0 is NSBitmapImageRep })
    }

    /// Size and appearance are part of the key, so a light/dark switch cannot be
    /// served the other appearance's bitmap.
    @Test func sizeAndAppearanceArePartOfTheKey() throws {
        let cache = StatusIconPreviewCache()
        let dark = NSAppearance(named: .darkAqua)
        let light = NSAppearance(named: .aqua)

        let small = try #require(
            cache.image(scene: scene(volume: 0.5), size: 20, scale: 2, appearance: dark)
        )
        let large = try #require(
            cache.image(scene: scene(volume: 0.5), size: 28, scale: 2, appearance: dark)
        )
        let lightImage = try #require(
            cache.image(scene: scene(volume: 0.5), size: 20, scale: 2, appearance: light)
        )

        #expect(small !== large)
        #expect(small !== lightImage)
        #expect(cache.entryCount == 3)
    }

    @Test func resetDropsEveryEntry() throws {
        let cache = StatusIconPreviewCache()
        _ = cache.image(scene: scene(volume: 0.5), size: 28, scale: 2)
        #expect(cache.entryCount == 1)

        cache.reset()

        #expect(cache.entryCount == 0)
        #expect(cache.residentByteCount == 0)
    }

    /// The cache is bounded, so a settings sweep cannot grow it without limit.
    @Test func theCacheEvictsBeyondItsLimit() throws {
        let cache = StatusIconPreviewCache(limit: 3)
        for step in 0..<6 {
            _ = cache.image(scene: scene(volume: Double(step) / 10), size: 28, scale: 2)
        }

        #expect(cache.entryCount <= 3)
    }

    /// An invalid size must not be stored; call sites fall back to an empty image.
    @Test func invalidSizesAreNotCached() {
        let cache = StatusIconPreviewCache()

        #expect(cache.image(scene: scene(volume: 0.5), size: 0, scale: 2) == nil)
        #expect(cache.image(scene: scene(volume: 0.5), size: 28, scale: 0) == nil)
        #expect(cache.entryCount == 0)
    }
}
