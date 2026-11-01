import AppKit

/// Identifies only the scene and Dock inputs that affect its raster.
struct DockIconRenderKey: Hashable {
    let scene: IconSceneState
    let backgroundStyle: DockIconBackgroundStyle
    let pixelLength: Int

    private var staticScene: IconSceneState {
        guard let ring = scene.outerRing, ring.effect != nil else { return scene }
        return IconSceneState(
            outerRing: OuterRingState(
                segments: ring.segments,
                gap: ring.gap,
                accessory: ring.accessory,
                effect: nil,
                strokeScale: ring.strokeScale
            ),
            center: scene.center,
            footer: scene.footer,
            statusColors: scene.statusColors
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.staticScene == rhs.staticScene
            && lhs.backgroundStyle == rhs.backgroundStyle
            && lhs.pixelLength == rhs.pixelLength
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(staticScene)
        hasher.combine(backgroundStyle)
        hasher.combine(pixelLength)
    }
}

struct DockIconRenderCache {
    private(set) var successfulKey: DockIconRenderKey?

    func needsRender(_ key: DockIconRenderKey) -> Bool {
        key != successfulKey
    }

    mutating func recordSuccessfulRender(_ key: DockIconRenderKey) {
        successfulKey = key
    }

    mutating func reset() {
        successfulKey = nil
    }
}

/// Keeps recent successfully rendered images so recurring scenes reuse a raster.
@MainActor
final class DockIconImageCache {
    private let limit: Int
    private let maximumResidentBytes: Int
    private var entries: [DockIconRenderKey: Entry] = [:]
    private var order: [DockIconRenderKey] = []
    private var residentBytes = 0

    var entryCount: Int { entries.count }
    var residentByteCount: Int { residentBytes }

    init(limit: Int = 4, maximumResidentBytes: Int = 4 * 1024 * 1024) {
        self.limit = max(1, limit)
        self.maximumResidentBytes = max(0, maximumResidentBytes)
    }

    func image(for key: DockIconRenderKey) -> NSImage? {
        guard let image = entries[key]?.image else { return nil }
        touch(key)
        return image
    }

    func store(_ image: NSImage, for key: DockIconRenderKey) {
        remove(key)

        guard let imageBytes = residentByteCount(of: image),
              imageBytes <= maximumResidentBytes else { return }

        while !order.isEmpty,
              order.count >= limit || residentBytes + imageBytes > maximumResidentBytes {
            removeOldest()
        }

        entries[key] = Entry(image: image, byteCount: imageBytes)
        order.append(key)
        residentBytes += imageBytes
    }

    func reset() {
        entries.removeAll()
        order.removeAll()
        residentBytes = 0
    }

    private func touch(_ key: DockIconRenderKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func remove(_ key: DockIconRenderKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        residentBytes -= entry.byteCount
        order.removeAll { $0 == key }
    }

    private func removeOldest() {
        guard !order.isEmpty else { return }
        let oldest = order[0]
        remove(oldest)
    }

    private func residentByteCount(of image: NSImage) -> Int? {
        // A rep-free image has no decoded raster to account for. Once an image
        // carries storage, only a concrete bitmap has a byte contract we can
        // enforce without estimating another representation's hidden buffers.
        guard !image.representations.isEmpty else { return 0 }

        var total = 0
        for representation in image.representations {
            guard let bitmap = representation as? NSBitmapImageRep else {
                return nil
            }
            let planeCount = max(1, bitmap.numberOfPlanes)
            let bytesPerPlane = bitmap.isPlanar
                ? max(0, bitmap.bytesPerPlane)
                : max(0, bitmap.bytesPerRow) * max(0, bitmap.pixelsHigh)
            total += planeCount * bytesPerPlane
        }
        return total
    }

    private struct Entry {
        let image: NSImage
        let byteCount: Int
    }
}
