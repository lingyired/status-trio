import AppKit
import Combine
import SwiftUI

/// The status panel window.
///
/// Issue #186 removes the arrow that `NSPopover` draws. AppKit has no public API
/// to hide it, so the panel is now a borderless `NSPanel` that reproduces the
/// popover's behaviour itself:
///
/// - native Liquid Glass on macOS 26+ (`NSGlassEffectView`), the pre-Tahoe
///   `NSVisualEffectView` material on macOS 13–25, and a solid fill when the
///   user has Reduce Transparency on;
/// - anchored placement with the same edge semantics, gap, screen clamping and
///   flip-to-the-other-side fallback as `NSPopover`;
/// - outside-click dismissal, Escape, app deactivation and the status item's
///   own toggle all close it.
///
/// The panel keeps `NSWindow.contentViewController` as its content owner so the
/// controller's five-second retention contract still applies unchanged.
@MainActor
final class AnchoredStatusPanel: NSPanel {
    static let didCloseNotification = Notification.Name(
        "StatusTrioAnchoredStatusPanelDidClose"
    )
    static let cornerRadius: CGFloat = 16

    /// Called once for every close, on the main actor, after the panel is off
    /// screen. Replaces `NSPopoverDelegate.popoverDidClose(_:)`.
    var onClose: (() -> Void)?

    private var anchor: StatusPanelAnchor?
    private var anchorView: NSView?
    private var anchorRectInView: NSRect = .zero
    private var preferredEdge: NSRectEdge = .minY
    /// Clearance reserved for an auto-hidden Dock on the anchored edge (#229).
    private var dockInset = DockReveal.noInset
    private var showCancellables: Set<AnyCancellable> = []

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
    }

    /// A borderless, non-activating panel is only key when it says so.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isShown: Bool { isVisible }

    // MARK: - Content

    /// Wraps the SwiftUI hosting controller in the panel's glass background and
    /// keeps the window sized to the content's intrinsic size.
    ///
    /// Sizing is driven by `StatusPanelHostingController.viewDidLayout`, not by
    /// the wrapper's own layout pass: the hosting view is the thing whose
    /// intrinsic size changes when a row expands.
    func installContent<Content: View>(_ hostingController: StatusPanelHostingController<Content>) {
        hostingController.onLayout = { [weak self] size in
            self?.applyContentSize(size)
        }
        let controller = StatusPanelContentViewController(hostingController: hostingController)
        contentViewController = controller
    }

    // MARK: - Presentation

    func show(
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge,
        dockInset: NSEdgeInsets = DockReveal.noInset
    ) {
        anchorView = view
        anchorRectInView = rect
        self.preferredEdge = preferredEdge
        self.dockInset = dockInset
        anchor = StatusPanelAnchor(
            screenRect: Self.screenRect(for: rect, in: view),
            preferredEdge: preferredEdge
        )
        installShowObservers()

        if let content = contentViewController as? StatusPanelContentViewController {
            let size = content.intrinsicContentSize
            if size.width > 0, size.height > 0 {
                setFrame(placementFrame(for: size), display: false)
            }
        }
        orderFrontRegardless()
        invalidateShadow()
    }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func close() {
        // A hidden window has nothing to tear down; callers rely on `isShown`
        // before they act on a close.
        guard isVisible else { return }
        removeShowObservers()
        super.close()
        NotificationCenter.default.post(name: Self.didCloseNotification, object: self)
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    // MARK: - Placement

    private func applyContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(frame.width - rounded.width) >= 0.5 || abs(frame.height - rounded.height) >= 0.5
        else { return }
        setFrame(placementFrame(for: rounded), display: true)
        invalidateShadow()
    }

    private func reposition() {
        guard isVisible else { return }
        let target = placementFrame(for: frame.size)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }

    private func placementFrame(for contentSize: NSSize) -> NSRect {
        guard let currentAnchor = currentAnchor() else {
            return NSRect(origin: frame.origin, size: contentSize)
        }
        return StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: currentAnchor,
            screens: NSScreen.screens.map { StatusPanelScreen($0) },
            dockInset: dockInset
        )
    }

    private func currentAnchor() -> StatusPanelAnchor? {
        if let anchorView, let window = anchorView.window {
            let rectInWindow = anchorView.convert(anchorRectInView, to: nil)
            return StatusPanelAnchor(
                screenRect: window.convertToScreen(rectInWindow),
                preferredEdge: preferredEdge
            )
        }
        return anchor
    }

    private static func screenRect(for rect: NSRect, in view: NSView) -> NSRect {
        guard let window = view.window else { return view.convert(rect, to: nil) }
        return window.convertToScreen(view.convert(rect, to: nil))
    }

    // MARK: - Lifecycle observers

    private func installShowObservers() {
        removeShowObservers()
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &showCancellables)
        // The window's content view controller drives the window's height from
        // the hosting view's preferred size. When that size grows after
        // presentation AppKit resizes the window while keeping the top-left
        // corner fixed, so a Dock-anchored panel would grow *downwards* past
        // the screen edge and cover the Dock (issue #229). Re-run placement on
        // every resize so the anchored edge stays put and the panel grows away
        // from the Dock instead.
        center.publisher(for: NSWindow.didResizeNotification, object: self)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &showCancellables)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.performClose(nil)
            }
            .store(in: &showCancellables)
    }

    private func removeShowObservers() {
        showCancellables.removeAll()
    }
}

// MARK: - Content view controller

/// A hosting controller that reports the SwiftUI content's ideal size whenever
/// it lays out. It is the panel's sizing signal for expanding rows and detail
/// pages, and it replaces the layout feedback `NSPopover` used to provide.
@MainActor
final class StatusPanelHostingController<Content: View>: NSHostingController<Content> {
    var onLayout: ((NSSize) -> Void)?
    private var lastReportedSize: NSSize = .zero

    override func viewDidLayout() {
        super.viewDidLayout()
        // Ask for the ideal size at the panel width with an unbounded height.
        // `view.fittingSize` can echo the hosting view's current (possibly
        // stale) bounds while a route transition is still settling; a stale
        // report would leave the panel at the detail page's height after going
        // back, clipping the taller summary at the top.
        let width = view.bounds.width > 0 ? view.bounds.width : view.fittingSize.width
        let proposed = NSSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        let measured = sizeThatFits(in: proposed)
        let size = measured.width > 0 && measured.height > 0 ? measured : view.fittingSize
        guard size.width > 0, size.height > 0, size != lastReportedSize else { return }
        lastReportedSize = size
        onLayout?(size)
    }
}

/// Hosts the SwiftUI content inside the panel's background.
@MainActor
final class StatusPanelContentViewController: NSViewController {
    let hostingController: NSViewController

    private var backgroundView: NSView?

    init(hostingController: NSViewController) {
        self.hostingController = hostingController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        // Clip at the window's root as well as at the glass surface. The
        // glass rounds its own material; it does not round its ancestor's
        // backing layer or rectangular descendant drawing outside the curve.
        container.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        container.layer?.masksToBounds = true
        view = container

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if #available(macOS 26.0, *), !reduceTransparency {
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.style = .regular
            glass.cornerRadius = AnchoredStatusPanel.cornerRadius
            glass.autoresizingMask = [.width, .height]
            // Keep the SwiftUI hosting view one plain container away from
            // `NSGlassEffectView.contentView`. Assigning the hosting view
            // directly lets the glass view treat the hosting view's intrinsic
            // content size as its own and resize/reposition the panel window
            // whenever a detail page changes the content height (#183
            // follow-up).
            let glassContent = NSView(frame: glass.bounds)
            glassContent.autoresizingMask = [.width, .height]
            hostingController.view.frame = glassContent.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            glassContent.addSubview(hostingController.view)
            glass.contentView = glassContent
            container.addSubview(glass)
            backgroundView = glass
        } else {
            let background: NSView
            if reduceTransparency {
                let solid = NSView(frame: container.bounds)
                solid.wantsLayer = true
                solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
                solid.layer?.masksToBounds = true
                background = solid
            } else {
                let effect = NSVisualEffectView(frame: container.bounds)
                effect.material = .popover
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.wantsLayer = true
                effect.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
                effect.layer?.masksToBounds = true
                background = effect
            }
            background.autoresizingMask = [.width, .height]
            container.addSubview(background)
            backgroundView = background

            hostingController.view.frame = container.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            container.addSubview(hostingController.view)
        }

        addChild(hostingController)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            // The hosting view now lives inside a plain container inside the
            // glass; match that container, not the glass view itself, so any
            // glass content insets cannot clip the content's top edge.
            hostingController.view.frame = hostingController.view.superview?.bounds
                ?? glass.bounds
        } else {
            hostingController.view.frame = view.bounds
        }
    }

    var intrinsicContentSize: NSSize {
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            return fitting
        }
        return hostingController.preferredContentSize
    }
}
