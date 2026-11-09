import AppKit
import SwiftUI

/// Marker for an AppKit control that handles the scroll wheel itself. The panel
/// wheel monitor leaves the event for such a view instead of turning it into a
/// panel-wide volume change.
@MainActor
protocol ScrollWheelHandlingView: AnyObject {}

extension NSView {
    /// True when this view or any ancestor handles the scroll wheel itself.
    @MainActor
    var handlesScrollWheelItself: Bool {
        var current: NSView? = self
        while let view = current {
            if view is ScrollWheelHandlingView { return true }
            current = view.superview
        }
        return false
    }
}

/// What a registered panel slider adjusts when the wheel rolls over it.
@MainActor
enum PanelLevelScrollTarget: Equatable {
    case volume
    case brightness(displayID: String)
    case audioInput
}

/// Keeps a registry of the panel's level sliders (volume, per-display
/// brightness, audio input) so the popover scroll monitor can tell which one
/// (if any) is under the pointer and route the wheel accordingly.
///
/// Regions are read from real `NSView` frames instead of SwiftUI geometry, so
/// they always match the window coordinates carried by the scroll event.
@MainActor
final class PopoverScrollTargets {
    /// Holds the slider view weakly: the registry must never keep a dismantled
    /// SwiftUI-hosted view alive.
    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private struct Entry {
        let holder: WeakView
        let target: PanelLevelScrollTarget
    }

    private var entries: [Entry] = []

    func register(_ view: NSView, as target: PanelLevelScrollTarget) {
        pruneDeadEntries()
        entries.removeAll { $0.holder.view === view }
        entries.append(Entry(holder: WeakView(view), target: target))
    }

    func unregister(_ view: NSView) {
        entries.removeAll { $0.holder.view === view }
        pruneDeadEntries()
    }

    /// The top-most registered slider whose window-space frame contains
    /// `point`, or nil when the pointer is not over any registered slider.
    func target(at point: NSPoint, in window: NSWindow?) -> PanelLevelScrollTarget? {
        guard let window else { return nil }
        // Iterate in reverse registration order (later = on top) so the most
        // recently placed slider wins when markers overlap.
        for entry in entries.reversed() {
            guard let view = entry.holder.view, view.window === window else { continue }
            let frameInWindow = view.convert(view.bounds, to: nil)
            if frameInWindow.contains(point) {
                return entry.target
            }
        }
        return nil
    }

    private func pruneDeadEntries() {
        entries.removeAll { $0.holder.view == nil }
    }
}

/// Marks a SwiftUI region as a scroll target that adjusts a specific panel
/// level (volume, a display's brightness, or the audio input).
struct LevelSliderScrollTarget: NSViewRepresentable {
    let targets: PopoverScrollTargets
    var target: PanelLevelScrollTarget = .volume

    func makeNSView(context: Context) -> ScrollTargetView {
        let view = ScrollTargetView()
        view.targets = targets
        targets.register(view, as: target)
        return view
    }

    func updateNSView(_ nsView: ScrollTargetView, context: Context) {
        nsView.targets = targets
        targets.register(nsView, as: target)
    }

    static func dismantleNSView(_ nsView: ScrollTargetView, coordinator: ()) {
        nsView.targets?.unregister(nsView)
    }
}

/// Kept for source compatibility with the existing volume view call site.
struct VolumeControlScrollTarget: NSViewRepresentable {
    let targets: PopoverScrollTargets

    func makeNSView(context: Context) -> ScrollTargetView {
        let view = ScrollTargetView()
        view.targets = targets
        targets.register(view, as: .volume)
        return view
    }

    func updateNSView(_ nsView: ScrollTargetView, context: Context) {
        nsView.targets = targets
        targets.register(nsView, as: .volume)
    }

    static func dismantleNSView(_ nsView: ScrollTargetView, coordinator: ()) {
        nsView.targets?.unregister(nsView)
    }
}

/// A transparent marker view: it reports its frame but never takes clicks,
/// so the slider underneath stays fully interactive.
final class ScrollTargetView: NSView {
    weak var targets: PopoverScrollTargets?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}