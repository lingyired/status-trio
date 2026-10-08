import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRenderKeyPixelLengthTests {
    private var placeholderScene: IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            configuration: .standard
        )
    }

    @Test func defaultsToTheDockRasterLength() {
        let key = DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )

        #expect(key.pixelLength == DockIconRenderer.pixelSize)
    }

    @Test func distinguishesTheSameStateAtAPreviewLength() {
        let dock = DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )
        let preview = DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: 112
        )

        #expect(dock != preview)
        #expect(preview.pixelLength == 112)
    }

    @Test func keepsTheDockDeduplicationBehaviour() {
        var cache = DockIconRenderCache()
        let dock = DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )
        let preview = DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: 112
        )

        let firstDockRender = cache.needsRender(dock)
        cache.recordSuccessfulRender(dock)
        let duplicateDockRender = cache.needsRender(dock)
        let firstPreviewRender = cache.needsRender(preview)
        cache.recordSuccessfulRender(preview)
        let duplicatePreviewRender = cache.needsRender(preview)

        #expect(firstDockRender)
        #expect(duplicateDockRender == false)
        #expect(firstPreviewRender)
        #expect(duplicatePreviewRender == false)
    }
}

@MainActor
struct DockIconPreviewMetricsTests {
    @Test func pixelLengthCoversEveryPreviewSizeInTheApp() {
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 30) == 60)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 44) == 88)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 56) == 112)
    }

    @Test func quantizesFractionalSizesUpIntoFourPixelBuckets() {
        let lengths = [30.0, 30.2, 30.6, 30.9, 31.0].map {
            DockIconPreviewMetrics.pixelLength(forPointSize: $0)
        }

        #expect(lengths == [60, 64, 64, 64, 64])
    }

    @Test func clampsAnAbsurdPointSize() {
        #expect(DockIconPreviewMetrics.maximumPixelLength == 128)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 0) == 4)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 10_000) == 128)
        #expect(
            DockIconPreviewMetrics.pixelLength(forPointSize: 10_000)
                < DockIconRenderer.pixelSize
        )
    }
}

@MainActor
struct DockIconPreviewCacheTests {
    @Test func reusesOneRasterForARepeatedKey() {
        var observedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 4) {
            observedLengths.append($0)
        }
        let key = previewKey(pixelLength: 112)
        var renders = 0

        let first = cache.image(for: key) {
            renders += 1
            return NSImage(size: NSSize(width: 56, height: 56))
        }
        let second = cache.image(for: key) {
            renders += 1
            return NSImage(size: NSSize(width: 56, height: 56))
        }

        #expect(renders == 1)
        #expect(observedLengths == [112])
        #expect(first === second)
    }

    @Test func rendersAgainWhenOnlyThePixelLengthChanges() {
        var observedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 4) {
            observedLengths.append($0)
        }
        var renders = 0

        for pixelLength in [112, 60] {
            _ = cache.image(for: previewKey(pixelLength: pixelLength)) {
                renders += 1
                return NSImage(size: NSSize(width: 8, height: 8))
            }
        }

        #expect(renders == 2)
        #expect(observedLengths == [112, 60])
    }

    @Test func evictsTheOldestRasterWhenFull() {
        let cache = DockIconPreviewCache(limit: 2)
        var renders = 0

        for pixelLength in [60, 88, 112, 60] {
            _ = cache.image(for: previewKey(pixelLength: pixelLength)) {
                renders += 1
                return NSImage(size: NSSize(width: 8, height: 8))
            }
        }

        #expect(renders == 4, "The first raster must have been evicted before it was asked for again.")
    }

    @Test func resetDropsEveryRaster() {
        var renders = 0
        let cache = DockIconPreviewCache(limit: 2) {
            _ in renders += 1
        }
        let key = previewKey(pixelLength: 60)

        _ = cache.image(for: key) {
            NSImage(size: NSSize(width: 8, height: 8))
        }
        cache.reset()
        _ = cache.image(for: key) {
            NSImage(size: NSSize(width: 8, height: 8))
        }

        #expect(renders == 2, "The raster must be rendered again after reset.")
    }

    @Test func aFailedRenderIsCountedButNotCached() {
        var observedLengths: [Int] = []
        let cache = DockIconPreviewCache(limit: 2) {
            observedLengths.append($0)
        }

        let image = cache.image(for: previewKey(pixelLength: 60)) { nil as NSImage? }

        #expect(image == nil)
        #expect(observedLengths == [60])
    }

    @Test func theCachePathReproducesTheDockRasterByteForByte() throws {
        let cache = DockIconPreviewCache(limit: 2)
        let status = MenuBarStatus.placeholder
        let key = previewKey(pixelLength: DockIconRenderer.pixelSize)
        let dock = try #require(renderDockFixture(
                status: status))
        let throughTheCache = try #require(
            cache.image(for: key) {
                renderDockFixture(
                status: status,
                    pixelLength: DockIconRenderer.pixelSize
                )
            }
        )
        let dockPixels = try pixels(of: dock)
        let cachedPixels = try pixels(of: throughTheCache)

        #expect(dockPixels.bytes == cachedPixels.bytes)
    }

    private var placeholderScene: IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            configuration: .standard
        )
    }

    private func previewKey(pixelLength: Int) -> DockIconRenderKey {
        DockIconRenderKey(
            scene: placeholderScene,
            backgroundStyle: .dark,
            pixelLength: pixelLength
        )
    }

    private func pixels(of image: NSImage) throws -> PixelBuffer {
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }
}
