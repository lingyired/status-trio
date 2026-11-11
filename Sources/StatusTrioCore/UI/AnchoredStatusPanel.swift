import AppKit
import Combine
import QuartzCore
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

    /// Set for the Debug background-testing route so the panel stays visible
    /// while another application remains active. The controller owns this
    /// value and leaves it false for normal interaction.
    var disablesDismissOnResignForTesting: Bool = false

    /// Consulted by the focus-loss observers (`didResignActive` and another app
    /// activating). Returning `true` defers the close for this notification so
    /// a click on the status item is left to the item's own toggle instead of
    /// closing on mouse-down and reopening on mouse-up (issue #224 follow-up).
    /// The controller wires it to the current pointer and mouse-button state;
    /// `nil` keeps the native "always dismiss on focus loss" behaviour.
    var shouldDeferDismissalOnFocusLoss: (() -> Bool)?

    /// Set only for the Debug background-testing route. A visible nonactivating
    /// panel can still become key when AppKit orders it in; refusing key status
    /// keeps application activation and keyboard focus with the user's app.
    var disablesKeyWindowForTesting: Bool = false {
        didSet {
            becomesKeyOnlyIfNeeded = disablesKeyWindowForTesting
        }
    }

    /// The normal status panel orders itself in regardless of the active app.
    /// Background tests use a normal front order so an active app's windows can
    /// remain above it.
    var avoidsOrderFrontRegardlessForTesting: Bool = false

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
    /// Lock the actual selected side for this presentation. Intermediate layout
    /// heights cannot flip it; only a placement-environment change renews it.
    private var lockedResizeAnchor: StatusPanelAnchor?
    private var lockedResizeFrame: NSRect?
    private var lockedResizeEdge: NSRectEdge?
    /// The clamped vertical travel bounds for the current placement, refreshed
    /// by `lockResizePlacement` so an animated resize can translate the panel
    /// instead of growing off screen (#321).
    private var verticalPlacementBounds: ClosedRange<CGFloat>?
#if DEBUG
    /// Number of window frame writes since the last reset. Issue #259 uses it in
    /// the convergence regression and in the live diagnostic; release builds
    /// omit it.
    private(set) var frameWriteCount = 0

    func resetFrameWriteCount() {
        frameWriteCount = 0
    }

    /// The window follows measured layout; it has no separate animation or pin.
    var resizeDiagnostics: StatusPanelResizeDiagnostics {
        StatusPanelResizeDiagnostics(
            windowHeight: frame.height,
            anchoredEdgeY: lockedResizeEdge == .maxY ? frame.minY : frame.maxY,
            targetHeight: layoutMetrics.contentHeight ?? frame.height,
            presentedHeight: frame.height,
            frameWriteCount: frameWriteCount
        )
    }
#endif
    /// Coalesces the three things that can change the window's frame: a content
    /// measurement, the window's own resize, and a screen / Dock / Space change
    /// (issue #259). Each one is applied once, on a later main-actor turn.
    private let layoutUpdateScheduler: StatusPanelLayoutUpdateScheduler
    private lazy var layoutCoordinator = StatusPanelLayoutCoordinator(
        scheduler: layoutUpdateScheduler,
        applyContentSize: { [weak self] size in self?.applyContentSize(size) },
        reposition: { [weak self] in self?.repositionPlacementOnly() },
        remeasure: { [weak self] in self?.remeasureContent() }
    )
    /// Set while content is installed; asks the hosting controller to report its
    /// size again after the height budget changed.
    private var invalidateContentMeasurement: (() -> Void)?
    /// The hosting controller currently installed as the panel's content.
    private weak var contentHost: NSViewController?

    /// Whether `host` is the content currently installed.
    func isCurrentContentHost(_ host: NSViewController) -> Bool {
        contentHost === host
    }

    init(layoutUpdateScheduler: StatusPanelLayoutUpdateScheduler? = nil) {
        self.layoutUpdateScheduler = layoutUpdateScheduler
            ?? StatusPanelLayoutUpdateScheduler { operation in
                Task { @MainActor in operation() }
            }
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
    override var canBecomeKey: Bool { !disablesKeyWindowForTesting }
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
        backgroundStyle: PanelBackgroundStyle,
        measurementID: UUID? = nil
    ) {
        layoutMetrics.attachWindow(measurementID: measurementID) { [weak self] height in
            guard let self else { return }
            self.requestContentSize(NSSize(width: 330, height: height))
        }
        contentHost = hostingController
        hostingController.onLayout = { [weak self, weak hostingController] size in
            guard let self, let hostingController else { return }
            // A replaced host can still finish a delayed layout pass. Only the
            // content that is installed now may drive the window (issue #259).
            guard self.isCurrentContentHost(hostingController) else { return }
            self.requestContentSize(NSSize(width: size.width, height: self.layoutMetrics.contentHeight ?? size.height))
        }
        invalidateContentMeasurement = { [weak hostingController] in
            guard let hostingController else { return }
            hostingController.invalidateSizeMeasurement()
            // Clearing the cache alone does not schedule a layout pass, so the
            // host would never report again. Drive the pass here: the re-measure
            // must produce a fresh measurement, not silently do nothing.
            hostingController.view.needsLayout = true
            hostingController.view.layoutSubtreeIfNeeded()
        }
        layoutCoordinator.invalidate()
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
        layoutMetrics.setPresented(true)
        if avoidsOrderFrontRegardlessForTesting {
            orderFront(nil)
        } else {
            orderFrontRegardless()
        }
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
        layoutMetrics.setPresented(false)
        pendingReveal = false
        lockedResizeAnchor = nil
        lockedResizeFrame = nil
        lockedResizeEdge = nil
        layoutCoordinator.invalidate()
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
        var size = content.intrinsicContentSize
        size.height = layoutMetrics.contentHeight ?? size.height
        guard size.width > 0, size.height > 0 else { return }
        applyContentFrame(cappedContentSize(size))
    }

    private func applyContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let capped = cappedContentSize(size)
        let scale = max(backingScaleFactor, 1)
        let rounded = NSSize(width: ceil(capped.width * scale) / scale, height: ceil(capped.height * scale) / scale)
        applyContentFrame(rounded)
    }

    /// Writes the window frame for a measured content size, or does nothing when
    /// the window already sits at the frame that size produces. The write is not
    /// displayed synchronously: forcing a display here re-enters layout while a
    /// layout pass is still running (issue #259).
    private func applyContentFrame(_ contentSize: NSSize) {
        // Content already presents its intermediate disclosure height. Starting
        // another window animation here would put layout and chrome on different
        // clocks. Apply only the latest coalesced measurement, once per pixel.
        if isVisible, !pendingReveal, lockedResizeFrame == nil {
            lockResizePlacement()
        }
        let capped = cappedContentSize(contentSize)
        let scale = max(backingScaleFactor, 1)
        let size = NSSize(width: ceil(capped.width * scale) / scale,
                          height: ceil(capped.height * scale) / scale)
        let target = placementFrame(for: size)
        guard target != frame else { return }
        setFrame(target, display: false)
#if DEBUG
        frameWriteCount += 1
#endif
        invalidateShadow()
    }

    /// The placed frame for a presented height during an animated resize. The
    /// anchor is the one locked when the animation began, so intermediate
    /// heights cannot flip the panel to the other side of the menu bar / Dock.
    private func placementFrameForPresentedHeight(_ height: CGFloat) -> NSRect {
        if let locked = lockedResizeFrame {
            // Lock the edge of the actual selected placement, including flips
            // and screen clamping, rather than rerunning preferredEdge.
            let y: CGFloat
            switch lockedResizeEdge {
            case .maxY: y = locked.minY
            case .minX, .maxX: y = clampedVerticalOrigin(centered: locked.midY, for: height)
            default: y = locked.maxY - height
            }
            return NSRect(x: locked.minX, y: y,
                          width: locked.width, height: height)
        }
        let width = frame.width
        let size = NSSize(width: width, height: height)
        if let anchor = lockedResizeAnchor ?? currentAnchor() {
            return StatusPanelPlacement.frame(
                contentSize: size,
                anchor: anchor,
                screens: NSScreen.screens.map { StatusPanelScreen($0) },
                dockInset: dockInset
            )
        }
        return NSRect(origin: frame.origin, size: size)
    }

    /// The clamped y-origin that keeps a side-Dock panel vertically on screen
    /// for a given presented height. The panel grows from a fixed x-anchor and
    /// translates vertically instead of being compressed; the horizontal side
    /// and the upper/lower travel bounds come from `verticalPlacementBounds` so
    /// the panel never leaves the screen or overlaps the revealed Dock (#321).
    private func clampedVerticalOrigin(centered center: CGFloat, for height: CGFloat) -> CGFloat {
        guard let bounds = verticalPlacementBounds else {
            return center - height / 2
        }
        return StatusPanelPlacement.clampedVerticalOrigin(
            center: center,
            height: height,
            bounds: bounds
        )
    }

    /// Keep the side already visible to the user, including an initial flip.
    /// If the expanded page would need the other side's larger budget, scroll
    /// on the selected side instead of flipping or growing off screen.
    private func lockResizePlacement() {
        lockedResizeAnchor = currentAnchor()
        lockedResizeFrame = frame
        switch lockedResizeAnchor?.preferredEdge {
        case .minX, .maxX: lockedResizeEdge = .minX
        default:
            lockedResizeEdge = frame.midY > (lockedResizeAnchor?.screenRect.midY ?? frame.maxY) ? .maxY : .minY
        }
        guard let screen = screen else { return }
        // Re-derive the budget from the current geometry every time. Never
        // inherit an old, smaller value with `min`, which permanently stuck a
        // small budget once one resize happened to lock it small (#321).
        // The vertical travel bounds span the whole screen for side Docks so
        // the panel grows to its content height and translates instead of being
        // squeezed around the click point (#321).
        let bounds = StatusPanelPlacement.verticalTravelBounds(
            visibleFrame: screen.visibleFrame,
            dockInset: dockInset
        )
        let available: CGFloat
        switch lockedResizeEdge {
        case .maxY: available = bounds.upperBound - frame.minY
        case .minX, .maxX: available = bounds.upperBound - bounds.lowerBound
        default: available = frame.maxY - bounds.lowerBound
        }
        layoutMetrics.update(maximumPanelHeight: max(1, available))
        verticalPlacementBounds = bounds
    }

    // MARK: - Layout scheduling

    /// Receives the content's measured size. The coordinator applies the latest
    /// measurement on a later main-actor turn instead of resizing during the
    /// layout pass that produced it (issue #259).
    private func requestContentSize(_ size: NSSize) {
        guard isVisible, size.width > 0, size.height > 0 else { return }
        layoutCoordinator.requestContentSize(size)
    }

    private func handleWindowResize() {
        guard isVisible, lockedResizeFrame == nil else { return }
        layoutCoordinator.windowDidResize()
    }

    private func handlePlacementEnvironmentChange() {
        guard isVisible else { return }
        lockedResizeAnchor = nil
        lockedResizeFrame = nil
        lockedResizeEdge = nil
        updateLayoutMetrics()
        // Move to the new anchor before locking a side again. Otherwise the old
        // on-screen frame could be mistaken for a flipped placement at the new
        // anchor while a fresh content measurement is still queued.
        repositionPlacementOnly()
        lockResizePlacement()
        layoutCoordinator.placementEnvironmentChanged()
    }

    /// Asks the content to measure itself again after the height budget changed.
    /// Safe to call from a coordinator turn; never from inside `viewDidLayout`.
    private func remeasureContent() {
        guard isVisible else { return }
        invalidateContentMeasurement?()
        guard let content = contentViewController else { return }
        content.view.needsLayout = true
        content.view.layoutSubtreeIfNeeded()
    }

    /// Re-places the window for its current size. A resize notification only
    /// corrects the anchored edge; it must not replay an older content size
    /// (issue #259).
    private func repositionPlacementOnly() {
        guard isVisible else { return }
        let target = placementFrame(for: cappedContentSize(frame.size))
        guard target != frame else { return }
        setFrame(target, display: false)
#if DEBUG
        frameWriteCount += 1
#endif
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
        if let locked = lockedResizeFrame, locked.width == contentSize.width {
            return placementFrameForPresentedHeight(contentSize.height)
        }
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
                self?.handlePlacementEnvironmentChange()
            }
            .store(in: &showCancellables)
        // A Space change can move the anchor to a screen with a different
        // usable frame even when the screen parameters themselves do not change.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handlePlacementEnvironmentChange()
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
                self?.handleWindowResize()
            }
            .store(in: &showCancellables)
        // The panel is a non-activating NSPanel and usually owns keyboard
        // focus while the user stays in another app, so it dismisses itself
        // when the user switches away. The Debug background-test route stays
        // open while the user's foreground app is unchanged, so it omits the
        // focus-loss pair.
        if !disablesDismissOnResignForTesting {
            center.publisher(for: NSApplication.didResignActiveNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.dismissForFocusLossIfNeeded()
                }
                .store(in: &showCancellables)
            // A nonactivating panel can own keyboard focus while another app stays
            // active. Cmd-Tab then switches that app, without a Status Trio resign
            // notification. Observe the workspace as well while the panel is open.
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] notification in
                    guard
                        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication,
                        app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    else { return }
                    self?.dismissForFocusLossIfNeeded()
                }
                .store(in: &showCancellables)
        }
    }

    /// Closes the panel for a focus-loss notification unless the controller says
    /// this loss is a click on the status item, which the item's own mouse-up
    /// toggle will handle (issue #224 follow-up).
    private func dismissForFocusLossIfNeeded() {
        guard isVisible else { return }
        if shouldDeferDismissalOnFocusLoss?() == true { return }
        performClose(nil)
    }

    private func removeShowObservers() {
        showCancellables.removeAll()
    }
}

// MARK: - Layout coordinator

/// Owns the three sources that can change the panel window's frame and merges
/// them into a single main-actor turn (issue #259): a content measurement, the
/// window's own resize, and a screen / Dock / Space change.
///
/// The distinction matters. A resize notification must only re-place the window
/// for the size it already has — replaying an older content measurement there
/// is what kept the window and the layout pass updating each other. A content
/// measurement may resize the window. A placement-environment change drops
/// measurements taken against the old budget and asks the content to measure
/// again.
@MainActor
final class StatusPanelLayoutCoordinator {
    private let scheduler: StatusPanelLayoutUpdateScheduler
    private let applyContentSize: (NSSize) -> Void
    private let reposition: () -> Void
    private let remeasure: () -> Void

    private var pendingContentSize: NSSize?
    private var needsRemeasure = false

    init(
        scheduler: StatusPanelLayoutUpdateScheduler,
        applyContentSize: @escaping (NSSize) -> Void,
        reposition: @escaping () -> Void,
        remeasure: @escaping () -> Void
    ) {
        self.scheduler = scheduler
        self.applyContentSize = applyContentSize
        self.reposition = reposition
        self.remeasure = remeasure
    }

    func requestContentSize(_ size: NSSize) {
        pendingContentSize = size
        enqueueFlush()
    }

    func windowDidResize() {
        enqueueFlush()
    }

    func placementEnvironmentChanged() {
        needsRemeasure = true
        enqueueFlush()
    }

    func invalidate() {
        pendingContentSize = nil
        needsRemeasure = false
        scheduler.invalidate()
    }

    /// Runs one merged pass. `internal` so the coalescing behaviour is testable
    /// without a window; production reaches it through the scheduler.
    func flush() {
        if needsRemeasure {
            needsRemeasure = false
            // A measurement taken before the budget changed no longer describes
            // the available space, so it must not decide the new frame.
            pendingContentSize = nil
            remeasure()
            // `remeasure` drives a layout pass, so the fresh measurement usually
            // arrives synchronously. Apply it in this turn: waiting for another
            // one would drop a real update whenever the environment change did
            // not actually alter the budget.
            if let size = pendingContentSize {
                pendingContentSize = nil
                applyContentSize(size)
                return
            }
            reposition()
            return
        }
        if let size = pendingContentSize {
            pendingContentSize = nil
            applyContentSize(size)
            return
        }
        // A bare resize only re-places the window; it never replays content.
        reposition()
    }

    private func enqueueFlush() {
        scheduler.enqueue { [weak self] in
            self?.flush()
        }
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

    /// Drops the remembered measurement so the next layout pass reports again,
    /// even when the content's own ideal size did not change. Used after the
    /// panel's height budget changed (issue #259).
    func invalidateSizeMeasurement() {
        lastReportedSize = .zero
    }

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
        guard size.width > 0, size.height > 0 else { return }
        // Compare with a display-pixel tolerance: a re-layout that differs only
        // by a fraction of a physical pixel is the same presented size. Without
        // it a sub-point wobble republishes on every pass and fights the window
        // animation. A real change of a pixel still gets through.
        let scale = max(view.window?.backingScaleFactor ?? 1, 1)
        let tolerance = 1.0 / scale
        let unchanged = abs(size.width - lastReportedSize.width) < tolerance
            && abs(size.height - lastReportedSize.height) < tolerance
        guard !unchanged else { return }
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
        let container: NSView
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            // The hosting view now lives inside a plain container inside the
            // glass; match that container, not the glass view itself, so any
            // glass content insets cannot clip the content's top edge.
            container = hostingController.view.superview ?? glass
        } else {
            container = view
        }
        // Always fill the actual window. A final-height pin would move the
        // content before the measured disclosure and window have reached it.
        hostingController.view.frame = container.bounds
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
