import AppKit

/// Routes a scroll-wheel event to the view under the pointer, but only when
/// that view can actually scroll (issue #237).
///
/// The status panel owns one stable outer scroll view. When its content fits,
/// the wheel still adjusts volume; only actual overflow takes the wheel for
/// scrolling. Keeping this decision separate from the controller makes both
/// cases testable with real AppKit views.
@MainActor
enum PanelScrollHitTesting {
    static func pointerIsOverScrollableScrollView(
        at pointInRootView: NSPoint,
        in rootView: NSView
    ) -> Bool {
        // NSView.hitTest takes a point in its superview's coordinate system.
        // Hosting views are flipped, while their window's container may not be.
        let hitTestPoint = rootView.superview.map {
            rootView.convert(pointInRootView, to: $0)
        } ?? pointInRootView
        var view = rootView.hitTest(hitTestPoint)
        while let currentView = view {
            if let scrollView = currentView as? NSScrollView,
               scrollView.hasVerticalOverflow {
                return true
            }
            view = currentView.superview
        }
        return false
    }
}

extension NSScrollView {
    /// True when the document is taller than the viewport, so a vertical wheel
    /// event can actually move it.
    var hasVerticalOverflow: Bool {
        guard let documentView else { return false }
        return documentView.frame.height - contentView.bounds.height > 0.5
    }
}
