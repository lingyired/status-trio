import AppKit

/// Keeps the menu-bar icon rasters that in-app previews draw.
///
/// `StatusIconRenderer.image(...)` returns an `NSImage` whose *drawing handler*
/// re-runs the whole Core Graphics render — including SF Symbol vector-path
/// resolution — on every composite. A Settings preview observes the status
/// store, so any published value (a volume tick, a battery sample, a Wi-Fi
/// update) used to re-rasterize every preview card, and re-drawing the pane
/// did it again.
///
/// This cache stores an **eagerly rasterized** bitmap keyed by the same
/// `StatusBarRenderKey` the live menu-bar path uses, so re-evaluating a preview
/// body or re-drawing the pane costs a dictionary lookup and a blit instead of a
/// full render.
@MainActor
final class StatusIconPreviewCache {
    static let shared = StatusIconPreviewCache()
    static let defaultLimit = 24
    /// Previews are 20–56 pt, so a resident set stays small; the cap only guards
    /// against a runaway call site.
    static let defaultMaximumResidentBytes = 2 * 1024 * 1024

    private struct Entry {
        let image: NSImage
        let byteCount: Int
    }

    private let limit: Int
    private let maximumResidentBytes: Int
    private var entries: [StatusBarRenderKey: Entry] = [:]
    private var order: [StatusBarRenderKey] = []
    private var residentBytes = 0

    var entryCount: Int { entries.count }
    var residentByteCount: Int { residentBytes }

    init(
        limit: Int = StatusIconPreviewCache.defaultLimit,
        maximumResidentBytes: Int = StatusIconPreviewCache.defaultMaximumResidentBytes
    ) {
        self.limit = max(1, limit)
        self.maximumResidentBytes = max(0, maximumResidentBytes)
    }

    /// The single place a preview resolves its bitmap.
    ///
    /// Returns `nil` only when the scene cannot be rendered, matching
    /// `StatusIconRenderer.image`. A miss rasterizes once and stores the bitmap,
    /// so the caller's `Image(nsImage:)` draws a blit.
    func image(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance? = nil,
        phase: ChargingEffectPhase? = nil
    ) -> NSImage? {
        guard size.isFinite, size > 0, scale.isFinite, scale > 0 else { return nil }
        let key = StatusBarRenderKey(
            scene: scene,
            iconSize: Double(size),
            backingScale: Double(scale),
            appearanceName: (appearance ?? NSApp?.effectiveAppearance)?.name.rawValue ?? "",
            phase: phase
        )
        if let entry = entries[key] {
            touch(key)
            return entry.image
        }
        guard let image = Self.rasterize(
            scene: scene,
            size: size,
            scale: scale,
            appearance: appearance,
            phase: phase
        ) else {
            return nil
        }
        store(image, for: key)
        return image
    }

    func reset() {
        entries.removeAll()
        order.removeAll()
        residentBytes = 0
    }

    /// Renders the scene into an `NSBitmapImageRep` so later draws never re-enter
    /// the drawing handler that `StatusIconRenderer.image` would install.
    private static func rasterize(
        scene: IconSceneState,
        size: CGFloat,
        scale: CGFloat,
        appearance: NSAppearance?,
        phase: ChargingEffectPhase?
    ) -> NSImage? {
        let environment = StatusIconRenderer.renderEnvironment(
            size: size,
            scale: scale,
            appearance: appearance
        )
        guard let cgImage = StatusIconRenderer.render(
            scene: scene,
            environment: environment,
            phase: phase,
            regions: .all
        ) else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = NSSize(width: size, height: size)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(representation)
        return image
    }

    private func store(_ image: NSImage, for key: StatusBarRenderKey) {
        remove(key)
        let byteCount = image.preferredBitmapByteCount
        guard byteCount <= maximumResidentBytes else { return }
        while !order.isEmpty,
              order.count >= limit || residentBytes + byteCount > maximumResidentBytes {
            removeOldest()
        }
        entries[key] = Entry(image: image, byteCount: byteCount)
        order.append(key)
        residentBytes += byteCount
    }

    private func touch(_ key: StatusBarRenderKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func remove(_ key: StatusBarRenderKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        residentBytes -= entry.byteCount
        order.removeAll { $0 == key }
    }

    private func removeOldest() {
        guard let oldest = order.first else { return }
        remove(oldest)
    }
}

private extension NSImage {
    /// Bytes the bitmap representation holds, used to bound the cache.
    var preferredBitmapByteCount: Int {
        guard let representation = representations.first as? NSBitmapImageRep else { return 0 }
        return max(0, representation.bytesPerRow * representation.pixelsHigh)
    }
}
