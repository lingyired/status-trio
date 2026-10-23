import AppKit
import Combine

@MainActor
protocol DockTilePresenting: AnyObject {
    var contentView: NSView? { get set }
    /// The tile's size in points, which follows the Dock's icon-size setting.
    var size: CGSize { get }
    func display()
}

extension NSDockTile: DockTilePresenting {}

@MainActor
protocol DockChargingAnimationPresenting: AnyObject {
    var isInstalled: Bool { get }
    func present(
        phase: ChargingEffectPhase,
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> Bool
    func restoreStaticIcon()
    func clear()
    func trimForMemoryPressure()
}

extension DockChargingAnimationPresenting {
    func restoreStaticIcon() {
        clear()
    }

    func trimForMemoryPressure() {}
}

/// Owns the Dock tile's animated `contentView` and drives it from the shared
/// charging clock.
///
/// Every steady frame is a lookup in `DockChargingFrameCache`; the static base
/// is built once per scene, theme and tile size. A tick that resolves to the
/// frame already on screen is a no-op, including `dockTile.display()`.
@MainActor
final class DockChargingAnimationPresenter: DockChargingAnimationPresenting {
    typealias BaseRenderer = @MainActor (
        _ scene: IconSceneState,
        _ backgroundStyle: DockIconBackgroundStyle,
        _ pixelLength: Int
    ) -> CGImage?
    typealias EffectRenderer = @MainActor (
        _ scene: IconSceneState,
        _ phase: ChargingEffectPhase,
        _ backgroundStyle: DockIconBackgroundStyle,
        _ pixelLength: Int
    ) -> CGImage?
    typealias EffectRectProvider = @MainActor (
        _ scene: IconSceneState,
        _ pixelLength: Int
    ) -> CGRect?

    /// What the tile last presented, for tests and for the no-op fast path.
    struct PresentedState: Equatable {
        let baseKey: DockIconRenderKey
        let overlayFrameKey: OverlayFrameKey?
    }

    struct OverlayFrameKey: Equatable {
        let baseKey: DockIconRenderKey
        let effectKey: DockChargingEffectKey
        let kind: ChargingEffectPhase.Kind
        let step: Int
        let stepsPerCycle: Int
        let heartbeatMultiplier: Double
    }

    private let dockTile: any DockTilePresenting
    private let rootView = DockChargingContentView()
    private let frameCache = DockChargingFrameCache()
    private let renderBase: BaseRenderer
    private let renderEffect: EffectRenderer
    private let effectRect: EffectRectProvider
    private let installsContentView: Bool
    private let displayScale: @MainActor () -> CGFloat

    private var tileContentSize: CGSize = .zero
    private var baseImage: CGImage?
    private var baseKey: DockIconRenderKey?
    private var failedBaseKey: DockIconRenderKey?
    private var baseEffectKey: DockChargingEffectKey?
    private var failedBaseEffectKey: DockChargingEffectKey?
    private var overlayFrameKey: OverlayFrameKey?
    private var isPresenting = false
    private var installed = false

    /// A tick that changes a bitmap and asks the Dock to display it. A repeated
    /// phase or a frame-cache hit must not move these.
    private(set) var displayCount = 0
    private(set) var rasterRequestCount = 0

    init(
        dockTile: any DockTilePresenting = NSApplication.shared.dockTile,
        renderBase: @escaping BaseRenderer = { scene, backgroundStyle, pixelLength in
            DockIconRenderer.animationBaseImage(
                scene: scene,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength
            )
        },
        renderEffect: @escaping EffectRenderer = { scene, phase, backgroundStyle, pixelLength in
            DockIconRenderer.chargingEffectImage(
                scene: scene,
                phase: phase,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength
            )
        },
        effectRect: @escaping EffectRectProvider = { scene, pixelLength in
            DockIconRenderer.chargingEffectRect(scene: scene, pixelLength: pixelLength)
        },
        installsContentView: Bool = true,
        displayScale: @escaping @MainActor () -> CGFloat = {
            NSScreen.main?.backingScaleFactor ?? 2
        }
    ) {
        self.dockTile = dockTile
        self.renderBase = renderBase
        self.renderEffect = renderEffect
        self.effectRect = effectRect
        self.installsContentView = installsContentView
        self.displayScale = displayScale
    }

    /// The dock tile's own pixel size, quantized so a magnification sweep
    /// cannot churn the base and frame rasters, and bounded by the requested
    /// length so a nonsense tile size cannot allocate a huge raster.
    static func resolvedPixelLength(
        requested: Int,
        tileSize: CGSize,
        displayScale: CGFloat
    ) -> Int {
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 2
        let measured = tileSize.width.isFinite && tileSize.width > 0
            ? tileSize.width * scale
            : CGFloat(requested)
        let bucket: CGFloat = 64
        let bounded = min(CGFloat(requested), max(measured, bucket))
        let quantized = Int((bounded / bucket).rounded()) * Int(bucket)
        return min(max(quantized, Int(bucket)), requested)
    }

    var isInstalled: Bool { isPresenting }
    var presentedState: PresentedState? {
        guard let baseKey else { return nil }
        return PresentedState(baseKey: baseKey, overlayFrameKey: overlayFrameKey)
    }
    var cachedFrameCount: Int { frameCache.frameCount }
    var cachedVariantCount: Int { frameCache.variantCount }
    var cachedFrameRebuildCount: Int { frameCache.rebuildCount }
    var rasterizedFrameCount: Int { frameCache.rasterizedFrameCount }
    var cachedResidentByteCount: Int { frameCache.residentByteCount }
    var contentDrawCountForTesting: Int { rootView.drawCount }
    var contentSizeForTesting: CGSize { tileContentSize }

    /// Presents one clock phase.
    ///
    /// Returns `false` when no frame could be produced, which is the caller's
    /// cue to fall back to the static `applicationIconImage` path.
    @discardableResult
    func present(
        phase: ChargingEffectPhase,
        scene: IconSceneState,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int
    ) -> Bool {
        let resolvedLength = Self.resolvedPixelLength(
            requested: pixelLength,
            tileSize: dockTile.size,
            displayScale: displayScale()
        )
        let key = DockIconRenderKey(
            scene: scene,
            backgroundStyle: backgroundStyle,
            pixelLength: resolvedLength
        )
        if failedBaseKey == key, failedBaseEffectKey == DockChargingEffectKey(key) { return false }

        guard ensureBase(key: key, scene: scene) else { return false }

        let frameKey = OverlayFrameKey(
            baseKey: key,
            effectKey: DockChargingEffectKey(key),
            kind: phase.kind,
            step: phase.step,
            stepsPerCycle: phase.stepsPerCycle,
            heartbeatMultiplier: phase.heartbeatMultiplier
        )
        guard frameKey != overlayFrameKey else { return true }

        let image: CGImage?
        switch phase.kind {
        case .steady:
            image = frameCache.image(
                for: phase,
                key: key,
                renderFrame: { framePhase in
                    renderEffect(scene, framePhase, key.backgroundStyle, key.pixelLength)
                }
            )
        case .burst:
            rasterRequestCount += 1
            image = renderEffect(scene, phase, key.backgroundStyle, key.pixelLength)
        }
        guard let image else { return false }

        let unitRect = unitRect(
            for: effectRect(scene, key.pixelLength),
            pixelLength: key.pixelLength
        )
        guard unitRect.width > 0, unitRect.height > 0 else {
            // A scene without a charging ring has nothing the Dock layer can
            // draw; fall back rather than drawing the effect raster at zero size.
            return false
        }
        rootView.overlayImage = image
        rootView.overlayUnitRect = unitRect
        overlayFrameKey = frameKey
        isPresenting = true
        presentIfInstalled()
        return true
    }

    /// Removes the custom content view and lets the static Dock icon return.
    func clear() {
        baseImage = nil
        baseKey = nil
        failedBaseKey = nil
        baseEffectKey = nil
        failedBaseEffectKey = nil
        overlayFrameKey = nil
        isPresenting = false
        rootView.baseImage = nil
        rootView.overlayImage = nil
        frameCache.reset()
        detachPresentedContentView()
    }

    /// Replaces the animated tile with the static Dock image while retaining
    /// reusable rasters and failure suppression for the next clock phase.
    func restoreStaticIcon() {
        // The overlay image stays attached to rootView, but re-presenting the
        // same phase must install it again instead of taking the lookup fast path.
        overlayFrameKey = nil
        isPresenting = false
        detachPresentedContentView()
    }

    private func detachPresentedContentView() {
        if installed {
            dockTile.contentView = nil
            dockTile.display()
            installed = false
        }
    }

    private func ensureBase(key: DockIconRenderKey, scene: IconSceneState) -> Bool {
        let effectKey = DockChargingEffectKey(key)
        if baseKey == key, baseEffectKey == effectKey, baseImage != nil { return true }
        if failedBaseKey == key, failedBaseEffectKey == effectKey { return false }

        rasterRequestCount += 1
        guard let image = renderBase(scene, key.backgroundStyle, key.pixelLength) else {
            failedBaseKey = key
            failedBaseEffectKey = effectKey
            // Do not composite a new overlay against the old scene's base.
            // The caller restores the static icon; a new identity retries.
            return false
        }

        baseImage = image
        baseKey = key
        baseEffectKey = effectKey
        failedBaseKey = nil
        failedBaseEffectKey = nil
        rootView.baseImage = image
        rootView.overlayImage = nil
        overlayFrameKey = nil

        // The Dock scales a content view to its own tile, so the rasters are
        // pixel-length based; the view only has to cover the tile's design box.
        tileContentSize = CGSize(
            width: CGFloat(key.pixelLength) / DockIconRenderer.scale,
            height: CGFloat(key.pixelLength) / DockIconRenderer.scale
        )
        rootView.frame = CGRect(origin: .zero, size: tileContentSize)
        rootView.autoresizingMask = [.width, .height]
        return true
    }

    func trimForMemoryPressure() {
        frameCache.trimForMemoryPressure()
    }

    private func installIfNeeded() {
        guard installsContentView, !installed else { return }
        dockTile.contentView = rootView
        installed = true
    }

    private func presentIfInstalled() {
        guard installsContentView else { return }
        installIfNeeded()
        rootView.needsDisplay = true
        dockTile.display()
        displayCount += 1
    }

    private func unitRect(for rect: CGRect?, pixelLength: Int) -> CGRect {
        guard let rect, pixelLength > 0 else { return .zero }
        let length = CGFloat(pixelLength)
        return CGRect(
            x: rect.minX / length,
            y: rect.minY / length,
            width: rect.width / length,
            height: rect.height / length
        )
    }
}
