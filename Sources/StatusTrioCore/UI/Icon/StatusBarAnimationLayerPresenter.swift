import AppKit
import QuartzCore

/// Presents steady animation frames through a single layer attached to the
/// status-bar button, avoiding an `NSStatusBarButton.image` assignment per tick.
@MainActor
final class StatusBarAnimationLayerPresenter {
    enum DisplayResult: Equatable {
        case installed
        case updated
        /// The layer already shows this image at this geometry, so the 20-Hz
        /// tick did not write anything to the layer.
        case unchanged
    }

    private weak var hostView: NSView?
    private var contentsLayer: CALayer?
    private var shouldRestoreLayerBacking = false

    /// What this presenter last wrote to the layer. AppKit derives `frame` from
    /// position, bounds, and anchor point, so the requested values are cached
    /// here rather than read back and compared with floating-point equality.
    private var presentedFrame: CGRect?
    private var presentedBackingScale: CGFloat?
    private var presentedImage: CGImage?

    /// Counters for the charging-animation CPU work; a steady tick must leave
    /// `contentsUpdateCount` unchanged.
    private(set) var contentsUpdateCount = 0
    private(set) var geometryUpdateCount = 0

    func display(
        _ image: CGImage,
        in view: NSView,
        contentSize: CGSize,
        backingScale: CGFloat
    ) -> DisplayResult? {
        guard backingScale.isFinite, backingScale > 0,
              contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0
        else { return nil }

        if hostView !== view || contentsLayer == nil {
            clear()
            let restoreLayerBacking = !view.wantsLayer
            view.wantsLayer = true
            guard let parentLayer = view.layer else {
                if restoreLayerBacking { view.wantsLayer = false }
                return nil
            }

            let layer = CALayer()
            layer.contentsGravity = .resize
            // The ring fill must cover its monochrome track, including when
            // AppKit reorders the template image view's backing layer.
            layer.zPosition = 1
            layer.actions = [
                "bounds": NSNull(),
                "contents": NSNull(),
                "position": NSNull()
            ]
            parentLayer.addSublayer(layer)
            contentsLayer = layer
            hostView = view
            shouldRestoreLayerBacking = restoreLayerBacking
            _ = update(
                layer,
                image: image,
                view: view,
                contentSize: contentSize,
                backingScale: backingScale
            )
            return .installed
        }

        guard let contentsLayer else { return nil }
        return update(
            contentsLayer,
            image: image,
            view: view,
            contentSize: contentSize,
            backingScale: backingScale
        ) ? .updated : .unchanged
    }

    var isInstalled: Bool { contentsLayer != nil }

    func clear() {
        let previousHostView = hostView
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentsLayer?.removeFromSuperlayer()
        CATransaction.commit()
        contentsLayer = nil
        hostView = nil
        presentedFrame = nil
        presentedBackingScale = nil
        presentedImage = nil

        if shouldRestoreLayerBacking {
            previousHostView?.wantsLayer = false
        }
        shouldRestoreLayerBacking = false
    }

    private func update(
        _ layer: CALayer,
        image: CGImage,
        view: NSView,
        contentSize: CGSize,
        backingScale: CGFloat
    ) -> Bool {
        // The status item centres its image in the button, so anchor the overlay
        // to the same centre. Using the icon's own size instead of the button's
        // bounds keeps the two aligned even before AppKit has resized the item.
        let bounds = view.bounds
        let frame = CGRect(
            x: bounds.midX - contentSize.width / 2,
            y: bounds.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        let frameChanged = presentedFrame != frame
        let scaleChanged = presentedBackingScale != backingScale
        let contentsChanged = presentedImage.map { $0 !== image } ?? true
        guard frameChanged || scaleChanged || contentsChanged else { return false }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frameChanged {
            layer.frame = frame
            geometryUpdateCount += 1
        }
        if scaleChanged {
            layer.contentsScale = backingScale
            geometryUpdateCount += 1
        }
        if contentsChanged {
            layer.contents = image
            contentsUpdateCount += 1
        }
        CATransaction.commit()
        presentedFrame = frame
        presentedBackingScale = backingScale
        presentedImage = image
        return true
    }
}
