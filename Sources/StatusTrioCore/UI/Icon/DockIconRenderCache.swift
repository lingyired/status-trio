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
            footer: scene.footer
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
    private var images: [DockIconRenderKey: NSImage] = [:]
    private var order: [DockIconRenderKey] = []

    init(limit: Int = 12) {
        self.limit = max(1, limit)
    }

    func image(for key: DockIconRenderKey) -> NSImage? {
        guard let image = images[key] else { return nil }
        touch(key)
        return image
    }

    func store(_ image: NSImage, for key: DockIconRenderKey) {
        images[key] = image
        touch(key)

        while order.count > limit {
            let oldest = order.removeFirst()
            images[oldest] = nil
        }
    }

    func reset() {
        images.removeAll()
        order.removeAll()
    }

    private func touch(_ key: DockIconRenderKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
