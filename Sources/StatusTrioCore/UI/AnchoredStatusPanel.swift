import AppKit
import Combine
import SwiftUI

/// The status panel window.
///
/// Issue #186 removes the arrow that `NSPopover` draws. AppKit has no public API
/// to hide it, so the panel is now a borderless `NSPanel` that reproduces the
/// popover's behaviour itself:
///
/// - a user-selectable background (issue #233): native Liquid Glass on
///   macOS 26+ (`NSGlassEffectView`), the pre-Tahoe `NSVisualEffectView`
///   material, or an opaque fill that follows light / dark. Reduce
///   Transparency always forces the opaque fill;
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

    /// Height budget shared with the SwiftUI content. The window and the
    /// content must agree on it so overflowing content scrolls instead of
    /// growing the window past the screen (#237).
    let layoutMetrics = StatusPanelLayoutMetrics()

    private var anchor: StatusPanelAnchor?
    private var anchorView: NSView?
    private var anchorRectInView: NSRect = .zero
    private var preferredEdge: NSRectEdge = .minY
    /// Clearance reserved for an auto-hidden Dock on the anchored edge (#229).
    private var dockInset = DockReveal.noInset
    private var showCancellables: Set<AnyCancellable> = []
    /// Set by `show` between ordering the window in transparent and revealing it
    /// once the first layout has settled, so a size correction never flashes.
    private var pendingReveal = false
    /// The last size the content reported at its natural height, before the
    /// screen cap was applied (#237).
    private var lastContentSize: NSSize = .zero

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
    func installContent<Content: View>(
        _ hostingController: StatusPanelHostingController<Content>,
        backgroundStyle: PanelBackgroundStyle
    ) {
        hostingController.onLayout = { [weak self] size in
            self?.applyContentSize(size)
        }
        let controller = StatusPanelContentViewController(
            hostingController: hostingController,
            backgroundStyle: backgroundStyle
        )
        contentViewController = controller
    }

    /// Swaps the panel background in place when the setting changes. No-op when
    /// no content is installed yet; the next `installContent` uses the current
    /// style.
    func applyBackgroundStyle(_ style: PanelBackgroundStyle) {
        (contentViewController as? StatusPanelContentViewController)?
            .applyBackgroundStyle(style)
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
        // Publish the height cap before the content loads so the first layout
        // already measures against it; otherwise the first frame would be the
        // full, off-screen height (#237).
        updateLayoutMetrics()
        installShowObservers()

        if let content = contentViewController as? StatusPanelContentViewController {
            // Touching `view` loads it; macOS 13 has no `loadViewIfNeeded`.
            _ = content.view
            content.view.layoutSubtreeIfNeeded()
            applyInitialContentSize()
        }
        // Order the window in already sized but fully transparent. The first
        // layout pass after this can still correct the content size; doing it
        // while invisible and then fading the panel in hides the jump that read
        // as a flash on open.
        alphaValue = 0
        orderFrontRegardless()
        invalidateShadow()
        pendingReveal = true
        DispatchQueue.main.async { [weak self] in
            self?.revealAfterSettling()
        }
    }

    /// Runs one runloop turn after `show`, lays the content out once more, applies
    /// any corrected size while still transparent, and fades the panel in. A
    /// single, short fade reads as the panel simply appearing, rather than a
    /// window that lands at one height and then snaps to another.
    private func revealAfterSettling() {
        guard isVisible, pendingReveal else {
            pendingReveal = false
            return
        }
        pendingReveal = false
        contentViewController?.view.layoutSubtreeIfNeeded()
        applyInitialContentSize()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 1
        }
    }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func close() {
        // A hidden window has nothing to tear down; callers rely on `isShown`
        // before they act on a close.
        guard isVisible else { return }
        pendingReveal = false
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

    /// Sizes the window from the content's current natural measurement, capped
    /// to the screen budget, without a display pass (#237).
    private func applyInitialContentSize() {
        guard let content = contentViewController as? StatusPanelContentViewController else {
            return
        }
        let size = content.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        lastContentSize = size
        setFrame(placementFrame(for: cappedContentSize(size)), display: false)
    }

    private func applyContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        // Keep the content's own height. When the screen budget grows again,
        // the panel can return to it instead of staying at the old cap.
        lastContentSize = size
        let capped = cappedContentSize(size)
        let rounded = NSSize(width: ceil(capped.width), height: ceil(capped.height))
        guard abs(frame.width - rounded.width) >= 0.5 || abs(frame.height - rounded.height) >= 0.5
        else { return }
        setFrame(placementFrame(for: rounded), display: true)
        invalidateShadow()
    }

    /// Limits a measured content height to the current screen budget (#237).
    ///
    /// The SwiftUI page deliberately reports its natural height even when it
    /// is scrolling inside the capped window. Capping belongs here, at the
    /// window, so a short page can still be shorter than the budget and hug
    /// its content instead of growing to the cap.
    private func cappedContentSize(_ size: NSSize) -> NSSize {
        guard let maximumHeight = layoutMetrics.maximumPanelHeight else { return size }
        return NSSize(width: size.width, height: min(size.height, maximumHeight))
    }

    private func reposition() {
        guard isVisible else { return }
        updateLayoutMetrics()
        // A screen, Space or Dock change can move the cap without changing the
        // page. Re-apply the last natural content size so the window shrinks
        // back into the new budget (or grows back into a roomier one).
        if lastContentSize.width > 0, lastContentSize.height > 0 {
            applyContentSize(lastContentSize)
        }
        let target = placementFrame(for: frame.size)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }

    /// Recomputes how tall the panel may get and hands the number to the
    /// SwiftUI content. Called when the panel opens and whenever the screen,
    /// Dock, menu bar or Space geometry changes while it is open (#237).
    ///
    /// The published value only changes when the number actually changes, so
    /// a resize notification triggered by our own `setFrame` cannot start a
    /// layout/publish loop.
    private func updateLayoutMetrics() {
        guard let currentAnchor = currentAnchor() else { return }
        layoutMetrics.update(
            maximumPanelHeight: StatusPanelPlacement.maximumPanelHeight(
                anchor: currentAnchor,
                screens: NSScreen.screens.map { StatusPanelScreen($0) },
                dockInset: dockInset
            )
        )
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
        // Covers display changes, menu bar geometry and Dock show/hide (all of
        // which move the usable frame and therefore the height budget).
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &showCancellables)
        // A Space change can move the anchor to a screen with a different
        // usable frame even when the screen parameters themselves do not change.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
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
        // A nonactivating panel can own keyboard focus while another app stays
        // active. Cmd-Tab then switches that app, without a Status Trio resign
        // notification. Observe the workspace as well while the panel is open.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, self.isVisible,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else { return }
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

/// Solid fill used when the panel renders opaque — either the user picked
/// `.solid`, or macOS "Reduce Transparency" is on (issues #233 / #234).
///
/// `NSColor.windowBackgroundColor` is a dynamic color. Resolving `.cgColor`
/// once, at `loadView()` time, freezes whatever appearance happened to be
/// current then (often a dark menu-bar/SwiftUI drawing context) and never
/// follows the panel's own `effectiveAppearance` afterwards — a light-mode
/// panel then paints a black background behind dark text. Resolving inside
/// `updateLayer()` under `effectiveAppearance` keeps it correct on first show,
/// and `viewDidChangeEffectiveAppearance()` repaints when the system or the
/// screen appearance changes, so the fill follows light / dark automatically.
@MainActor
final class SolidPanelBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Hosts the SwiftUI content inside the panel's background.
@MainActor
final class StatusPanelContentViewController: NSViewController {
    let hostingController: NSViewController

    /// The user's chosen style. The effective style can differ when Reduce
    /// Transparency forces a solid fill.
    private(set) var backgroundStyle: PanelBackgroundStyle
    /// Injectable so tests can exercise the non-solid paths on a machine that
    /// has Reduce Transparency turned on.
    private let isReduceTransparencyEnabled: () -> Bool
    private var backgroundView: NSView?

    init(
        hostingController: NSViewController,
        backgroundStyle: PanelBackgroundStyle,
        isReduceTransparencyEnabled: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    ) {
        self.hostingController = hostingController
        self.backgroundStyle = backgroundStyle
        self.isReduceTransparencyEnabled = isReduceTransparencyEnabled
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

        addChild(hostingController)
        installBackground(in: container)
    }

    /// Swaps the background without rebuilding the window or re-creating the
    /// SwiftUI content. Called when the setting changes while the panel exists.
    func applyBackgroundStyle(_ style: PanelBackgroundStyle) {
        guard style != backgroundStyle else { return }
        backgroundStyle = style
        guard isViewLoaded else { return }
        installBackground(in: view)
    }

    /// Reduce Transparency keeps the panel opaque for accessibility; it wins
    /// over the user's choice and forces the solid fill.
    private var effectiveBackgroundStyle: PanelBackgroundStyle {
        PanelBackgroundStyle.renderStyle(
            for: backgroundStyle,
            reduceTransparency: isReduceTransparencyEnabled()
        )
    }

    private func installBackground(in container: NSView) {
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        hostingController.view.removeFromSuperview()

        let background = makeBackgroundView(in: container)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        backgroundView = background

        // The glass path already embedded the hosting view in its own plain
        // container; every other path hosts the content directly above the
        // background in `container`.
        if hostingController.view.superview == nil {
            hostingController.view.frame = container.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            container.addSubview(hostingController.view)
        }
    }

    private func makeBackgroundView(in container: NSView) -> NSView {
        switch effectiveBackgroundStyle {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: container.bounds)
                glass.style = .regular
                glass.cornerRadius = AnchoredStatusPanel.cornerRadius
                // Keep the SwiftUI hosting view one plain container away from
                // `NSGlassEffectView.contentView`. Assigning the hosting view
                // directly lets the glass view treat the hosting view's
                // intrinsic content size as its own and resize/reposition the
                // panel window whenever a detail page changes the content
                // height (#183 follow-up).
                let glassContent = NSView(frame: glass.bounds)
                glassContent.autoresizingMask = [.width, .height]
                hostingController.view.frame = glassContent.bounds
                hostingController.view.autoresizingMask = [.width, .height]
                glassContent.addSubview(hostingController.view)
                glass.contentView = glassContent
                return glass
            }
            // Older systems cannot render Liquid Glass; `.resolved` normally
            // prevents this, but fall back to the classic material if a direct
            // caller still asks for it.
            return makeClassicMaterialBackground(in: container)
        case .classicMaterial:
            return makeClassicMaterialBackground(in: container)
        case .solid:
            let solid = SolidPanelBackgroundView(frame: container.bounds)
            solid.wantsLayer = true
            solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
            solid.layer?.masksToBounds = true
            return solid
        }
    }

    private func makeClassicMaterialBackground(in container: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        effect.layer?.masksToBounds = true
        return effect
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
