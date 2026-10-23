import AppKit

/// Measurement-only switch between the two Dock presentation approaches.
///
/// Kind `.tile` is the shipped approach: a `dockTile.contentView` that draws a
/// static base plus a cropped effect raster (plan 方案 A). Kind
/// `.applicationIcon` is the A/B prototype: whole-tile frames pushed through
/// `applicationIconImage` (plan 方案 B). The prototype is reachable only from a
/// development bundle, so a shipped build always animates through the tile's
/// content view. Results live in
/// `docs/performance/dock-charging-cpu-optimization.md`.
enum DockChargingAnimationRendererMode {
    static let environmentKey = "STATUS_TRIO_DOCK_ANIMATION_RENDERER"
    static let applicationIcon = "applicationIcon"

    static func usesApplicationIconFrames(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        ChargingEffectTestMode.isAvailable(bundleIdentifier: bundleIdentifier)
            && environment[environmentKey] == applicationIcon
    }
}

/// The A/B prototype: every tick swaps the Dock icon's `applicationIconImage`
/// for a cached whole-tile frame.
///
/// It shares the one `ChargingEffectClock` and the same frame cache discipline
/// as the tile presenter, so a paired measurement isolates the presentation
/// cost: assigning a 512-px `NSImage` 20 times a second and letting the Dock
/// scale it, against redrawing a small effect raster inside the tile view.
@MainActor
final class DockApplicationIconChargingPresenter: DockChargingAnimationPresenting {
    typealias TileRenderer = @MainActor (
        _ scene: IconSceneState,
        _ phase: ChargingEffectPhase,
        _ backgroundStyle: DockIconBackgroundStyle,
        _ pixelLength: Int
    ) -> NSImage?

    private struct VariantKey: Equatable {
        let renderKey: DockIconRenderKey
        let heartbeatMultiplier: Double
    }

    private struct FrameSet {
        let key: VariantKey
        let pixelLength: Int
        let frames: [NSImage]

        /// Raw RGBA pixels, which is what the A/B comparison reports.
        var byteCount: Int { frames.count * pixelLength * pixelLength * 4 }
    }

    private struct FrameKey: Equatable {
        let variant: VariantKey
        let kind: ChargingEffectPhase.Kind
        let step: Int
        let stepsPerCycle: Int
    }

    static let steadyFrameCount = DockChargingFrameCache.steadyFrameCount
    static let maximumVariants = 2

    private let application: any ApplicationDockIconApplying
    private let renderTile: TileRenderer
    private var variants: [FrameSet] = []
    private var lastFrameKey: FrameKey?
    private var failedKey: VariantKey?

    /// Cumulative counters: a repeated phase must not move them.
    private(set) var assignmentCount = 0
    private(set) var rasterizedFrameCount = 0

    init(
        application: any ApplicationDockIconApplying = NSApplication.shared,
        renderTile: @escaping TileRenderer = { scene, phase, backgroundStyle, pixelLength in
            guard let image = DockIconRenderer.tileImage(
                scene: scene,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength,
                phase: phase
            ) else { return nil }
            let logicalLength = CGFloat(pixelLength) / DockIconRenderer.scale
            let representation = NSBitmapImageRep(cgImage: image)
            representation.size = NSSize(width: logicalLength, height: logicalLength)
            let frame = NSImage(size: NSSize(width: logicalLength, height: logicalLength))
            frame.addRepresentation(representation)
            frame.isTemplate = false
            return frame
        }
    ) {
        self.application = application
        self.renderTile = renderTile
    }

    var isInstalled: Bool { lastFrameKey != nil }
    var cachedVariantCount: Int { variants.count }
    var cachedResidentByteCount: Int { variants.reduce(0) { $0 + $1.byteCount } }

    @discardableResult
    func present(
        phase: ChargingEffectPhase,
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> Bool {
        let variant = VariantKey(
            renderKey: DockIconRenderKey(
                scene: scene,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength
            ),
            heartbeatMultiplier: phase.heartbeatMultiplier
        )
        let key = FrameKey(
            variant: variant,
            kind: phase.kind,
            step: phase.step,
            stepsPerCycle: phase.stepsPerCycle
        )
        guard key != lastFrameKey else { return true }

        let frames: [NSImage]
        switch phase.kind {
        case .steady:
            guard let cached = steadyFrames(for: variant, phase: phase, scene: scene) else {
                return false
            }
            frames = cached
        case .burst:
            guard let frame = renderTile(scene, phase, backgroundStyle, pixelLength) else {
                return false
            }
            lastFrameKey = key
            application.setApplicationIconImage(frame)
            assignmentCount += 1
            return true
        }

        lastFrameKey = key
        application.setApplicationIconImage(frames[phase.step])
        assignmentCount += 1
        return true
    }

    func clear() {
        // The static icon comes back through `AppIconController`, which owns the
        // Dock's visuals whenever the animation is not presenting.
        lastFrameKey = nil
        variants.removeAll()
        failedKey = nil
    }

    func restoreStaticIcon() {
        // AppIconController installs the current static image after this call.
        // Keep the expensive frame sets and the failed variant's suppression.
        lastFrameKey = nil
    }

    func trimForMemoryPressure() {
        if variants.count > 1 { variants.removeLast(variants.count - 1) }
    }

    private func steadyFrames(
        for variant: VariantKey,
        phase: ChargingEffectPhase,
        scene: IconSceneState
    ) -> [NSImage]? {
        guard phase.stepsPerCycle == Self.steadyFrameCount,
              (0..<Self.steadyFrameCount).contains(phase.step),
              failedKey != variant
        else { return nil }

        if let index = variants.firstIndex(where: { $0.key == variant }) {
            let cached = variants.remove(at: index)
            variants.insert(cached, at: 0)
            return cached.frames
        }

        var frames: [NSImage] = []
        frames.reserveCapacity(Self.steadyFrameCount)
        for step in 0..<Self.steadyFrameCount {
            let framePhase = ChargingEffectPhase(
                step: step,
                stepsPerCycle: Self.steadyFrameCount,
                kind: .steady,
                heartbeatMultiplier: phase.heartbeatMultiplier
            )
            guard let frame = renderTile(
                scene,
                framePhase,
                variant.renderKey.backgroundStyle,
                variant.renderKey.pixelLength
            ) else {
                failedKey = variant
                return nil
            }
            frames.append(frame)
        }

        variants.insert(
            FrameSet(
                key: variant,
                pixelLength: variant.renderKey.pixelLength,
                frames: frames
            ),
            at: 0
        )
        rasterizedFrameCount += frames.count
        while variants.count > Self.maximumVariants {
            variants.removeLast()
        }
        return frames
    }
}
