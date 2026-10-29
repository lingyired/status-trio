import AppKit

/// Keeps monochrome primitives system-tintable without making the status
/// button's colored CALayer part of a template-image compositing group.
@MainActor
final class StatusBarTemplateImagePresenter {
    private var imageView: NSImageView?

    func display(_ image: NSImage, in host: NSView, contentSize: CGSize) {
        if imageView?.superview !== host {
            clear()
            let view = StatusBarTemplateImageView()
            view.imageScaling = .scaleNone
            view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            view.setAccessibilityElement(false)
            host.addSubview(view)
            imageView = view
        }
        imageView?.image = image
        imageView?.frame = NSRect(
            x: host.bounds.midX - contentSize.width / 2,
            y: host.bounds.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    func clear() {
        imageView?.removeFromSuperview()
        imageView = nil
    }
}

private final class StatusBarTemplateImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
