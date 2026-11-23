import AppKit

/// Maps an on-screen preview size to the pixel length its raster needs.
///
/// Preview tiles are drawn at 30-128 pt, so at 2x they need 60-256 px. The Dock's
/// 512 px raster is ~1 MiB, and rendering it for a 30 pt tile is the allocation
/// this type exists to prevent. Sizes are quantized up into 4 px buckets so a
/// fractional layout size cannot churn the cache with a new raster per frame.
enum DockIconPreviewMetrics {
    static let deviceScale: CGFloat = 2
    /// Covers the 128 pt designer tile at 2x while keeping a runaway call site
    /// below the real Dock raster length.
    static let maximumPixelLength = 256
    private static let bucket = 4

    static func pixelLength(forPointSize pointSize: CGFloat) -> Int {
        let requested = (max(1, pointSize) * deviceScale).rounded(.up)
        let clamped = min(requested, CGFloat(maximumPixelLength))
        return Int((clamped / CGFloat(bucket)).rounded(.up)) * bucket
    }
}

/// Keeps the rasters that in-app previews draw, so re-evaluating a SwiftUI body
/// costs a dictionary lookup instead of a full Core Graphics render.
///
/// Storage is the same `DockIconImageCache` the real Dock path uses, keyed by
/// `DockIconRenderKey` — which now carries the pixel length, so a preview can
/// never be served the Dock's bitmap.
@MainActor
final class DockIconPreviewCache {
    typealias RenderObserver = @MainActor (Int) -> Void

    static let shared = DockIconPreviewCache()
    static let defaultLimit = 32
    static let defaultMaximumResidentBytes = 2 * 1024 * 1024

    private let images: DockIconImageCache
    /// Optional test instrumentation. The shared production cache has no
    /// observer and keeps no render history.
    private let renderObserver: RenderObserver?

    init(
        limit: Int = DockIconPreviewCache.defaultLimit,
        maximumResidentBytes: Int = DockIconPreviewCache.defaultMaximumResidentBytes,
        onRender: RenderObserver? = nil
    ) {
        images = DockIconImageCache(
            limit: limit,
            maximumResidentBytes: maximumResidentBytes
        )
        renderObserver = onRender
    }

    var entryCount: Int { images.entryCount }
    var residentByteCount: Int { images.residentByteCount }

    func image(for key: DockIconRenderKey, render: () -> NSImage?) -> NSImage? {
        if let cached = images.image(for: key) { return cached }

        renderObserver?(key.pixelLength)

        guard let image = render() else { return nil }
        images.store(image, for: key)
        return image
    }

    func reset() {
        images.reset()
    }
}
