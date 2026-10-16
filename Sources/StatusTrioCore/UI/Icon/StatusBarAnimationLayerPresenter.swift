import AppKit
import QuartzCore

/// Presents steady animation frames through a single layer attached to the
/// status-bar button, avoiding an `NSStatusBarButton.image` assignment per tick.
@MainActor
final class StatusBarAnimationLayerPresenter {
    enum DisplayResult: Equatable {
        case installed
        case updated
    }

    private weak var hostView: NSView?
    private var contentsLayer: CALayer?
    private var shouldRestoreLayerBacking = false

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
            layer.actions = [
                "bounds": NSNull(),
                "contents": NSNull(),
                "position": NSNull()
            ]
            parentLayer.addSublayer(layer)
            contentsLayer = layer
            hostView = view
            shouldRestoreLayerBacking = restoreLayerBacking
            update(layer, image: image, view: view, contentSize: contentSize, backingScale: backingScale)
            return .installed
        }

        guard let contentsLayer else { return nil }
        update(contentsLayer, image: image, view: view, contentSize: contentSize, backingScale: backingScale)
        return .updated
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
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The status item centres its image in the button, so anchor the overlay
        // to the same centre. Using the icon's own size instead of the button's
        // bounds keeps the two aligned even before AppKit has resized the item.
        let bounds = view.bounds
        layer.frame = CGRect(
            x: bounds.midX - contentSize.width / 2,
            y: bounds.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        layer.contentsScale = backingScale
        layer.contents = image
        CATransaction.commit()
    }
}
