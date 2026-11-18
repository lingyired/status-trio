import AppKit

/// Issue #355: the geometry and timing of "show the status panel when the
/// pointer rests on the menu-bar icon, hide it when it leaves".
///
/// Kept as a pure value type so the dwell bounds and the enter/exit decisions
/// are tested without a live status item. The controller owns the actual
/// delayed transitions; nothing here polls or retains a timer.
struct PopoverHoverPresentation: Equatable {
    /// The pointer must dwell this long before the panel appears, so merely
    /// crossing the menu bar does not flash it. The issue pins 0.3–0.5 s.
    static let showDelay: TimeInterval = 0.35
    /// Leaving the icon and panel is delayed too, so crossing the small gap
    /// between them (or briefly clipping a corner) keeps the panel open.
    static let hideDelay: TimeInterval = 0.30
    /// Extra slack around the icon and panel frames that still counts as the
    /// hover area. It only widens the *keep-open* decision; it never opens the
    /// panel.
    static let bridgeInset: CGFloat = 8

    /// The status item button's rectangle in screen coordinates, when visible.
    let statusItemFrame: NSRect?
    /// Frames of every panel the presentation currently shows.
    var panelFrames: [NSRect] = []

    func containsStatusItem(_ point: NSPoint) -> Bool {
        guard let statusItemFrame else { return false }
        return Self.containsInclusive(statusItemFrame, point)
    }

    func containsPanel(_ point: NSPoint) -> Bool {
        panelFrames.contains { Self.containsInclusive($0, point) }
    }

    /// The icon, any panel, or the thin bridge between them. A pointer anywhere
    /// in this area must not trigger the delayed close.
    func isWithinHoverArea(_ point: NSPoint) -> Bool {
        if containsStatusItem(point) || containsPanel(point) {
            return true
        }
        if let statusItemFrame,
           Self.containsInclusive(statusItemFrame.insetBy(dx: -Self.bridgeInset, dy: -Self.bridgeInset), point) {
            return true
        }
        return panelFrames.contains {
            Self.containsInclusive($0.insetBy(dx: -Self.bridgeInset, dy: -Self.bridgeInset), point)
        }
    }

    /// Covers the right and top edges, which `NSRect.contains(_:)` excludes.
    private static func containsInclusive(_ rect: NSRect, _ point: NSPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
}

/// Pure bookkeeping for the two delayed hover transitions.
///
/// A new transition supersedes the pending one, so a pointer that leaves and
/// re-enters within the dwell window cannot leave a stale close behind. The
/// controller owns the actual sleeps; it captures the token returned by
/// `begin(_:)` and only acts when `consume(_:)` still recognises it.
struct PopoverHoverIntent: Equatable {
    enum Transition: Equatable {
        case show
        case hide
    }

    private(set) var pending: Transition?
    private var token = 0

    /// Starts a transition and returns the token its timer must present when it
    /// fires. Starting any transition cancels the previous one.
    mutating func begin(_ transition: Transition) -> Int {
        token &+= 1
        pending = transition
        return token
    }

    /// Cancels the pending transition, if any. Returns true when something was
    /// cancelled so the caller can drop its task.
    @discardableResult
    mutating func cancel() -> Bool {
        guard pending != nil else { return false }
        pending = nil
        token &+= 1
        return true
    }

    /// Whether a timer that captured `candidate` may still act. A successful
    /// match also clears the pending state so a duplicate fire is inert.
    mutating func consume(_ candidate: Int) -> Bool {
        guard pending != nil, candidate == token else { return false }
        pending = nil
        token &+= 1
        return true
    }
}

/// Receives AppKit tracking-area events and forwards them as plain closures, so
/// the status item and each panel can share one hover handler without owning a
/// view subclass. The tracking area references this object unretained, so the
/// controller must keep it alive for as long as the area is installed.
@MainActor
final class PopoverHoverTracking: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    private(set) weak var view: NSView?
    private var area: NSTrackingArea?

    init(view: NSView) {
        self.view = view
        super.init()

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        self.area = area
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PopoverHoverTracking does not support NSCoding")
    }

    func invalidate() {
        if let area, let view {
            view.removeTrackingArea(area)
        }
        area = nil
        view = nil
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}
