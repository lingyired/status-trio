import AppKit
import Combine
import SwiftUI
import os

private struct UncheckedSendableNSEvent: @unchecked Sendable {
    let event: NSEvent
}

private struct StatusBarAccessibilityKey: Equatable {
    let snapshot: StatusSnapshot
    let language: AppLanguage
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let popoverToggleLockoutInterval: TimeInterval = 0.25
    static let popoverContentReleaseDelay: TimeInterval = 5

    /// Draws the monochrome template base the menu bar hands to the system.
    typealias MenuBarBaseRenderer = @MainActor (
        _ scene: IconSceneState,
        _ size: Double,
        _ scale: CGFloat,
        _ appearance: NSAppearance
    ) -> NSImage?

    /// Draws the custom-colour overlay. `phase` is `nil` for the resting overlay
    /// and the clock's phase while the charging effect animates.
    typealias MenuBarOverlayRenderer = @MainActor (
        _ scene: IconSceneState,
        _ size: Double,
        _ scale: CGFloat,
        _ appearance: NSAppearance,
        _ phase: ChargingEffectPhase?
    ) -> CGImage?

    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let panelActions: StatusPanelActions
    private let panelViewModel: StatusPanelViewModel
    private let iconPresentation: IconPresentationViewModel
    private let localization: Localization
    private let renderMenuBarBase: MenuBarBaseRenderer
    private let renderMenuBarOverlay: MenuBarOverlayRenderer
    private let accessibilityValueDidChange: @MainActor (String) -> Void
    private let popoverContentReleaseSleeper: @Sendable (Duration) async throws -> Void
    private let activatesApplicationForPopover: @MainActor () -> Void
    let chargingEffectClock: ChargingEffectClock
    private var iconPresentationCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    /// The single accessibility update waiting on the main actor, so a burst of
    /// emissions cannot queue one stale update per value.
    private var accessibilityUpdateTask: Task<Void, Never>?
    private var chargingEffectCancellable: AnyCancellable?
    private var chargingEffectPreferenceCancellable: AnyCancellable?
    private var currentChargingEffectPhase: ChargingEffectPhase?
    private var isMenuBarChargingEffectEnabled: Bool
    private var screenParametersCancellable: AnyCancellable?
    private var refreshIntervalCancellable: AnyCancellable?
    private let openSettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []
    private var renderCache = StatusBarRenderCache()
    private let chargingFrameCache = StatusBarChargingFrameCache()
    private let animationLayerPresenter = StatusBarAnimationLayerPresenter()
    private let renderCoalescer = IconRenderCoalescer()
    /// The template base currently on the status item, kept so a custom-raster
    /// fallback can put the re-tintable image back.
    private var staticBase: NSImage?
    /// The key of a raster drawn while the button had no window yet, so
    /// a guessed backing scale is rasterized once instead of on every call.
    private var provisionalStaticKey: StatusBarRenderKey?
    /// The resting chromatic overlay for the current static key, rendered on
    /// demand instead of on every clock tick.
    private var staticOverlay: CGImage?
    private var staticOverlayIsPending = false
    private var baseIsCustomRaster = false
    private(set) var renderCounters = RenderCounters()
    var cachedChargingFrameCount: Int { chargingFrameCache.frameCount }
    var hasLayerBackedAnimation: Bool { animationLayerPresenter.isInstalled }
    var presentedImageForTesting: NSImage? { statusItem.button?.image }
    var animationLayerContentsUpdateCount: Int { animationLayerPresenter.contentsUpdateCount }
    var animationLayerGeometryUpdateCount: Int { animationLayerPresenter.geometryUpdateCount }
    var sublayerCountForTesting: Int { statusItem.button?.layer?.sublayers?.count ?? 0 }
    var cachedChargingFrameRebuildCount: Int { chargingFrameCache.rebuildCount }
    var rasterizedChargingFrameCount: Int { chargingFrameCache.rasterizedFrameCount }
    var popoverForTesting: NSPopover { popover }
    var popoverAnchorWindowForTesting: NSWindow? { popoverAnchorWindow }
    var panelForTesting: StatusPanelViewModel { panelViewModel }
    /// Invokes once when the controller clears a present
    /// `contentViewController`. This marks the end of popover content ownership;
    /// it does not mean the old hosting object has deallocated. Task 4 must
    /// treat it as a candidate boundary and still inspect visible owners.
    var onPopoverContentReleased: (@MainActor () -> Void)?
    var popoverContentReleaseTaskForTesting: Task<Void, Never>? {
        popoverContentReleaseTask
    }
    var didPresentStaticContent: (@MainActor () -> Void)?

    /// What the menu-bar path did, so a test can show that a steady 20-Hz tick
    /// neither re-rasterizes the static content nor reassigns
    /// `NSStatusBarButton.image`.
    struct RenderCounters: Equatable {
        /// Times the static base and its resting overlay were rebuilt.
        var staticPresentations = 0
        /// Times the template base renderer ran.
        var templateBaseRasters = 0
        /// Chromatic rasters the static and burst paths requested. The steady
        /// frames are counted by `StatusBarChargingFrameCache`.
        var overlayRasters = 0
        /// Frame or overlay images handed to the animation layer.
        var framesPresented = 0
        /// Assignments to `NSStatusBarButton.image`, including fallbacks.
        var buttonImageAssignments = 0
        /// Times the non-template fallback raster replaced the template base.
        var fallbackRasters = 0
    }
    private var isStatusItemVisible: Bool
    /// The status item is the charging animation's surface; whoever owns the
    /// placement decision is told when it changes so the clock can stop.
    var visibilityDidChange: (@MainActor () -> Void)?
    var isMenuBarVisible: Bool { isStatusItemVisible }
    private var accessibilityKey: StatusBarAccessibilityKey?
    private var latestIconOutput: IconPresentationOutput
    private var popoverDismissMonitor: Any?
    private var volumeScrollMonitor: Any?
    private let volumeScrollAdjustment = PopupVolumeScrollAdjustment()
    private var volumeScrollSession = PopupVolumeScrollSession()
    private let popoverScrollTargets = PopoverScrollTargets()
    private var popoverAnchorWindow: NSWindow?
    private var popoverToggleGate = PopoverToggleGate(
        lockout: StatusBarController.popoverToggleLockoutInterval
    )
    private var popoverContentReleaseTask: Task<Void, Never>?
    private var popoverContentGeneration: UInt64 = 0
    private var isPopoverClosing = false
    private var popoverWindowFocusCancellables: Set<AnyCancellable> = []
    private var applicationFocusCancellables: Set<AnyCancellable> = []
    private let inputSourceController: InputSourceController
    private let updaterManager: UpdateStateFacade
    private let helper: PrivilegedHelperFacade
    var platformServicesForTesting: (updater: UpdateStateFacade, helper: PrivilegedHelperFacade) {
        (updaterManager, helper)
    }
    var distributionCapabilityPolicyForTesting: DistributionCapabilityPolicy {
        capabilityPolicy
    }
    var panelCapabilityPolicyForTesting: DistributionCapabilityPolicy {
        panelActions.distributionCapabilityPolicyForTesting
    }
    private let capabilityPolicy: DistributionCapabilityPolicy
    /// How a presentation resolves the appearance it rasterizes in.
    ///
    /// Production reads the button's effective appearance. A test pins it: the
    /// status item's effective appearance only settles once AppKit installs the
    /// item into the menu bar, so a fixture that counts rasters would otherwise
    /// see an unrelated second presentation each time that install lands (#133).
    private let appearanceProvider: (@MainActor () -> NSAppearance)?

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        iconPresentation: IconPresentationViewModel,
        localization: Localization,
        isVisible: Bool = true,
        openSettings: @escaping () -> Void,
        quitAction: @escaping () -> Void,
        chargingEffectClock: ChargingEffectClock = ChargingEffectClock(),
        accessibilityValueDidChange: @escaping @MainActor (String) -> Void = { _ in },
        panelUpdateScheduler: (any PanelPresentationUpdateScheduling)? = nil,
        popoverContentReleaseSleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        activatesApplicationForPopover: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        renderMenuBarBase: @escaping MenuBarBaseRenderer = { scene, size, scale, appearance in
            StatusIconRenderer.menuBarTemplateBase(
                scene: scene,
                size: CGFloat(size),
                scale: scale,
                appearance: appearance
            )
        },
        renderMenuBarOverlay: @escaping MenuBarOverlayRenderer = { scene, size, scale, appearance, phase in
            StatusIconRenderer.menuBarChromaticImage(
                scene: scene,
                size: CGFloat(size),
                scale: scale,
                appearance: appearance,
                phase: phase
            )
        },
        inputSourceController: InputSourceController? = nil,
        updaterManager: UpdateStateFacade = UpdateStateFacade(service: SystemManagedUpdateService()),
        helper: PrivilegedHelperFacade = PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault,
        appearanceProvider: (@MainActor () -> NSAppearance)? = nil
    ) {
        self.appearanceProvider = appearanceProvider
        self.store = store
        self.settings = settings
        let resolvedInputSourceController = inputSourceController ?? InputSourceController()
        self.inputSourceController = resolvedInputSourceController
        self.updaterManager = updaterManager
        self.helper = helper
        self.capabilityPolicy = capabilityPolicy
        let panelActions = StatusPanelActions(
            store: store,
            settings: settings,
            inputSourceController: resolvedInputSourceController,
            capabilityPolicy: capabilityPolicy
        )
        self.panelActions = panelActions
        let resolvedPanelUpdateScheduler: any PanelPresentationUpdateScheduling
        if let panelUpdateScheduler {
            resolvedPanelUpdateScheduler = panelUpdateScheduler
        } else {
            resolvedPanelUpdateScheduler = StatusBarPanelUpdateScheduler()
        }
        self.panelViewModel = StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: panelActions,
            updateScheduler: resolvedPanelUpdateScheduler,
            inputSourceController: resolvedInputSourceController,
            capabilityPolicy: capabilityPolicy
        )
        self.iconPresentation = iconPresentation
        self.localization = localization
        self.renderMenuBarBase = renderMenuBarBase
        self.renderMenuBarOverlay = renderMenuBarOverlay
        self.accessibilityValueDidChange = accessibilityValueDidChange
        self.popoverContentReleaseSleeper = popoverContentReleaseSleeper
        self.activatesApplicationForPopover = activatesApplicationForPopover
        self.chargingEffectClock = chargingEffectClock
        self.openSettings = openSettings
        self.quitAction = quitAction
        self.isStatusItemVisible = isVisible
        self.isMenuBarChargingEffectEnabled = settings.showsMenuBarChargingEffect
        self.latestIconOutput = iconPresentation.output
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.isVisible = isVisible
        configureButton()
        configurePopover()
        observeApplicationFocusChanges()
        observeAppearanceChanges()
        scheduleInitialRender()

        iconPresentationCancellable = iconPresentation.$output
            .removeDuplicates()
            .sink { [weak self] output in
                guard let self else { return }
                latestIconOutput = output
                renderCoalescer.submit { [weak self] in
                    self?.renderLatestScene()
                }
            }

        chargingEffectCancellable = chargingEffectClock.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.renderAnimationPhase(phase)
            }

        chargingEffectPreferenceCancellable = settings.$showsMenuBarChargingEffect
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                isMenuBarChargingEffectEnabled = isEnabled
                renderLatestScene()
            }

        accessibilityCancellable = Publishers.CombineLatest(
            store.$snapshot,
            localization.$resolvedLanguage
        )
        .sink { [weak self] _, _ in
            self?.scheduleAccessibilityUpdate()
        }

        refreshIntervalCancellable = settings.$refreshIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.store.setRefreshInterval(.seconds(Int(seconds.rounded())))
            }

        screenParametersCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.renderLatestScene()
        }
    }

    static func clickKind(eventType: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> ClickKind? {
        if eventType == .rightMouseUp || modifiers.contains(.control) {
            return .right
        }
        if eventType == .leftMouseUp {
            return .left
        }
        return nil
    }

    func setVisible(_ isVisible: Bool) {
        guard isStatusItemVisible != isVisible else { return }
        isStatusItemVisible = isVisible

        if isVisible {
            statusItem.isVisible = true
            resetStaticPresentation()
            renderLatestScene()
        } else {
            clearAnimationPresentation()
            popover.performClose(nil)
            store.setPopoverVisible(false)
            panelViewModel.stop()
            if !popover.isShown {
                releasePopoverContentIfPresent()
            }
            statusItem.isVisible = false
        }
        visibilityDidChange?()
    }

    func refreshCurrentPresentation() {
        renderLatestScene()
    }

    func flushPendingPresentationForTesting() {
        renderCoalescer.flushPending()
    }

    func resetPopoverToggleGateForTesting() {
        popoverToggleGate = PopoverToggleGate(
            lockout: Self.popoverToggleLockoutInterval
        )
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeAppearanceChanges() {
        guard let button = statusItem.button else { return }
        appearanceObservations.append(button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.renderLatestScene()
            }
        })
    }

    private func scheduleInitialRender() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.renderLatestScene()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard
            let event = NSApp.currentEvent,
            let click = Self.clickKind(eventType: event.type, modifiers: event.modifierFlags)
        else { return }

        switch click {
        case .left:
            togglePopover()
        case .right:
            popover.performClose(nil)
            showMenu()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
    }

    private func installPopoverContentIfNeeded() {
        guard popover.contentViewController == nil else { return }
        let rootView = LocalizedRootView(localization: localization) {
            StatusPopoverView(
                panel: panelViewModel,
                helper: helper,
                capabilityPolicy: capabilityPolicy,
                scrollTargets: popoverScrollTargets,
                requestWiFiNameAccess: { self.handleRequestWiFiNameAccess() },
                requestBluetoothAuthorization: { self.handleRequestBluetoothAuthorization() },
                openBatterySettings: { self.handleOpenBatterySettings() },
                openWiFiSettings: { self.handleOpenWiFiSettings() },
                openNetworkSettings: { self.handleOpenNetworkSettings() },
                openSharingSettings: { self.handleOpenSharingSettings() },
                openLocationSettings: { self.handleOpenLocationSettings() },
                openBluetoothSettings: { self.handleOpenBluetoothSettings() },
                openBluetoothPermissionSettings: { self.handleOpenBluetoothPermissionSettings() },
                openSettings: { self.handleOpenSettings() },
                openSoundSettings: { self.handleOpenSoundSettings() },
                openSoundInputSettings: { self.handleOpenSoundInputSettings() },
                openKeyboardSettings: { self.handleOpenKeyboardSettings() },
                quit: quitAction
            )
        }
        // Task 2's start() refreshes synchronously from the store before the
        // first SwiftUI layout pass, so a reused hosting controller cannot show
        // the values it had when the popover last closed.
        panelViewModel.start()
        let hostingController = NSHostingController(rootView: rootView)
        if #available(macOS 14.0, *) {
            // The Ventura hosting pass can recurse while AppKit installs the
            // popover content. Leave sizing to the popover's measured content
            // there, and keep preferred sizing on the newer path.
            hostingController.sizingOptions = [.preferredContentSize]
        }
        popover.contentViewController = hostingController
    }

    private func togglePopover() {
        guard popoverToggleGate.shouldAccept(at: Date()) else { return }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            presentPopover(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    /// Shortcut activation uses the same open/close contract as the status item.
    func openPopoverFromShortcut() {
        switch StatusPanelShortcutPresentationPolicy.action(
            isPopoverShown: popover.isShown,
            isPopoverClosing: isPopoverClosing
        ) {
        case .close:
            closePopover()
        case .ignore:
            break
        case .open:
            presentPopoverFromShortcut()
        }
    }

    /// Shows the same popover for a Dock icon click, above the clicked icon.
    func togglePopover(anchoredAtScreenPoint point: NSPoint) {
        guard popoverToggleGate.shouldAccept(at: Date()) else { return }
        if popover.isShown {
            closePopover()
            return
        }

        let anchor = dockAnchor(at: point)
        presentPopover(
            relativeTo: anchor.view.bounds,
            of: anchor.view,
            preferredEdge: anchor.preferredEdge,
            // A real Dock tile click already activated this app before the
            // reopen callback. Re-activating can restore the existing Settings
            // window ahead of the transient popover.
            activatesApplication: false
        )
    }

    private func presentPopoverFromShortcut() {
        let menuBarAnchor = visibleMenuBarAnchor()
        let screens = NSScreen.screens.map {
            StatusPanelShortcutScreen(
                frame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        }
        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: menuBarAnchor?.screenRect,
            isMenuBarVisible: menuBarAnchor != nil,
            pointerLocation: NSEvent.mouseLocation,
            screens: screens
        )

        if case .menuBar = anchor, let menuBarAnchor {
            presentPopover(
                relativeTo: menuBarAnchor.button.bounds,
                of: menuBarAnchor.button,
                preferredEdge: .minY
            )
            return
        }
        guard case let .fallback(origin, preferredEdge) = anchor else { return }
        let anchorView = popoverAnchorView(at: origin)
        presentPopover(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: preferredEdge
        )
    }

    private func visibleMenuBarAnchor() -> (
        button: NSStatusBarButton,
        screenRect: NSRect
    )? {
        guard isStatusItemVisible,
              let button = statusItem.button,
              let window = button.window else {
            return nil
        }
        let windowRect = button.convert(button.bounds, to: nil)
        return (button, window.convertToScreen(windowRect))
    }

    private func presentPopover(
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge,
        activatesApplication: Bool = true
    ) {
        cancelPopoverContentRelease()
        store.setPopoverVisible(true)
        installPopoverContentIfNeeded()
        // An unretained hosting controller is installed above; a retained one
        // still has a stopped panel, so every open restores current state.
        panelViewModel.start()
        // One bounded refresh per open covers a lost distributed notification
        // without any polling while the popover is closed.
        refreshInputSourceIfNeeded()
        if activatesApplication {
            // A transient popover shown while the app is still inactive can be
            // dismissed again straight away. Status-item clicks come from the
            // system menu bar process, so the modern activate() can be ignored
            // by the user-activation policy.
            activatesApplicationForPopover()
        }
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        // The popover's backing window only exists once it has been shown, and
        // without a Spaces behavior it stays on this app's desktop Space while
        // another app is full-screen.
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.enableDisplayOnFullScreenSpaces()
        installPopoverWindowFocusObservers(popoverWindow)
        popoverWindow?.makeKey()
        dockActivationLogger.notice(
            """
            Popover presented shown=\(self.popover.isShown) \
            key=\(popoverWindow?.isKeyWindow ?? false) \
            applicationActivation=\(activatesApplication ? "forced" : "skipped", privacy: .public) \
            \(dockActivationFocusSnapshot(window: popoverWindow), privacy: .public)
            """
        )
        installPopoverDismissMonitor()
        installVolumeScrollMonitor()
    }

    private func observeApplicationFocusChanges() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                dockActivationLogger.notice(
                    """
                    Application became active popoverShown=\(self.popover.isShown) \
                    \(dockActivationFocusSnapshot(window: self.popover.contentViewController?.view.window), privacy: .public)
                    """
                )
            }
            .store(in: &applicationFocusCancellables)

        center.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                dockActivationLogger.notice(
                    """
                    Application resigned active popoverShown=\(self.popover.isShown) \
                    \(dockActivationFocusSnapshot(window: self.popover.contentViewController?.view.window), privacy: .public)
                    """
                )
            }
            .store(in: &applicationFocusCancellables)
    }

    private func installPopoverWindowFocusObservers(_ window: NSWindow?) {
        popoverWindowFocusCancellables.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default

        center.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                dockActivationLogger.notice(
                    """
                    Popover window became key popoverVisible=\(self.store.isPopoverVisible) \
                    \(dockActivationFocusSnapshot(window: window), privacy: .public)
                    """
                )
            }
            .store(in: &popoverWindowFocusCancellables)

        center.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                dockActivationLogger.notice(
                    """
                    Popover window resigned key popoverVisible=\(self.store.isPopoverVisible) \
                    \(dockActivationFocusSnapshot(window: window), privacy: .public)
                    """
                )
            }
            .store(in: &popoverWindowFocusCancellables)
    }

    private func closePopover() {
        guard !isPopoverClosing else { return }
        isPopoverClosing = true
        popover.performClose(nil)
    }

    /// The Dock icon has no public frame, but the click happens on the icon, so
    /// a tiny invisible window at the click point anchors the popover there.
    private func dockAnchor(at point: NSPoint) -> (view: NSView, preferredEdge: NSRectEdge) {
        let anchor = DockPopoverAnchor.make(
            clickPoint: point,
            tileSize: NSApplication.shared.dockTile.size,
            placement: dockPlacement(at: point)
        )
        return (
            popoverAnchorView(at: anchor.origin),
            anchor.preferredEdge
        )
    }

    private func popoverAnchorView(at origin: NSPoint) -> NSView {
        let window: NSWindow
        if let popoverAnchorWindow {
            window = popoverAnchorWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            popoverAnchorWindow = window
        }

        window.setFrameOrigin(origin)
        window.orderFront(nil)
        return window.contentView ?? window.contentViewController?.view ?? NSView()
    }

    private func releasePopoverAnchorWindow() {
        guard let popoverAnchorWindow else { return }
        popoverAnchorWindow.orderOut(nil)
        popoverAnchorWindow.close()
        self.popoverAnchorWindow = nil
    }

    private func dockPlacement(at point: NSPoint) -> DockPlacement {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else { return .bottom }
        return DockPlacement.resolve(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    private func removePopoverDismissMonitor() {
        guard let popoverDismissMonitor else { return }
        NSEvent.removeMonitor(popoverDismissMonitor)
        self.popoverDismissMonitor = nil
    }

    private func installVolumeScrollMonitor() {
        removeVolumeScrollMonitor()
        volumeScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local event monitors run on the main thread. Keep the non-Sendable
            // event inside this synchronous callback while hopping isolation.
            let boxedEvent = UncheckedSendableNSEvent(event: event)
            let shouldConsume = MainActor.assumeIsolated {
                self?.shouldConsumeVolumeScrollWheel(boxedEvent.event) ?? false
            }
            return shouldConsume ? nil : event
        }
    }

    private func removeVolumeScrollMonitor() {
        guard let volumeScrollMonitor else { return }
        NSEvent.removeMonitor(volumeScrollMonitor)
        self.volumeScrollMonitor = nil
        resetVolumeScrollSession()
    }

    private func shouldConsumeVolumeScrollWheel(_ event: NSEvent) -> Bool {
        guard event.window === popover.contentViewController?.view.window,
              settings.popupScrollAdjustsVolume,
              store.isVolumeControlAvailable,
              !isPointerOverScrollView(event),
              isPointerInsideVolumeScrollArea(event) else {
            return false
        }
        guard event.momentumPhase.isEmpty else { return true }

        guard let currentScalar = volumeScrollSession.scalar(
            at: event.timestamp,
            fallback: store.popupSnapshot.volume.scalar
        ) else {
            return false
        }
        let delta = volumeScrollAdjustment.volumeDelta(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            usesNaturalScrolling: settings.popupVolumeNaturalScrolling
        )
        guard let delta else { return true }

        let nextScalar = volumeScrollSession.applying(
            delta: delta,
            to: currentScalar
        )
        if volumeScrollSession.shouldUnmute(
            isMuted: store.popupSnapshot.volume.isMuted,
            isIncreasing: delta > 0
        ) {
            store.toggleMute()
        }
        store.setVolume(nextScalar)
        return true
    }

    /// Scroll targeting only narrows the gesture area; the whole panel stays
    /// valid when the preference is left at its default.
    private func isPointerInsideVolumeScrollArea(_ event: NSEvent) -> Bool {
        guard settings.popupVolumeScrollScope == .volumeControl else { return true }
        return popoverScrollTargets.containsVolumeControl(
            at: event.locationInWindow,
            in: event.window
        )
    }

    private func isPointerOverScrollView(_ event: NSEvent) -> Bool {
        guard let rootView = popover.contentViewController?.view else { return false }
        let point = rootView.convert(event.locationInWindow, from: nil)
        var view = rootView.hitTest(point)
        while let currentView = view {
            if currentView is NSScrollView {
                return true
            }
            view = currentView.superview
        }
        return false
    }

    private func resetVolumeScrollSession() {
        volumeScrollSession.reset()
    }

    func popoverDidClose(_ notification: Notification) {
        let popoverWindow = popover.contentViewController?.view.window
        dockActivationLogger.notice(
            """
            Popover closed appActive=\(NSApp.isActive) \
            \(dockActivationFocusSnapshot(window: popoverWindow), privacy: .public)
            """
        )
        popoverWindowFocusCancellables.removeAll()
        isPopoverClosing = false
        removePopoverDismissMonitor()
        removeVolumeScrollMonitor()
        releasePopoverAnchorWindow()
        // Read this before closing the popover: a detail panel keeps its own
        // SwiftUI state, so reusing the built content would reopen on that
        // panel. The battery page also clears its collector on disappear, so
        // the flag has to be sampled while the panel is still open.
        let hadOpenDetails = store.hasOpenPopoverPanel
        store.setPopoverVisible(false)
        store.closePopoverDetails()
        // Listening to store publishers is not free and none of their values can
        // be drawn while the popover is closed. Stop here rather than waiting for
        // the five-second hosting retention window.
        panelViewModel.stop()
        if hadOpenDetails {
            invalidatePopoverContentReleaseTask()
            releasePopoverContentIfPresent()
        } else {
            schedulePopoverContentRelease()
        }
    }

    /// Keeping the built content for a while makes rapid reopen cheap; releasing
    /// it later keeps idle memory low.
    private func schedulePopoverContentRelease() {
        cancelPopoverContentRelease()
        let delay = Self.popoverContentReleaseDelay
        popoverContentGeneration &+= 1
        let generation = popoverContentGeneration
        let sleeper = popoverContentReleaseSleeper
        popoverContentReleaseTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(.seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  popoverContentGeneration == generation,
                  !popover.isShown else {
                return
            }
            popoverContentReleaseTask = nil
            releasePopoverContentIfPresent()
        }
    }

    func trimForMemoryPressure() {
        chargingFrameCache.trimForMemoryPressure()
        guard !popover.isShown else { return }
        releasePopoverAnchorWindow()
        releasePopoverContentIfPresent()
    }

    private func cancelPopoverContentRelease() {
        invalidatePopoverContentReleaseTask()
    }

    private func invalidatePopoverContentReleaseTask() {
        popoverContentGeneration &+= 1
        popoverContentReleaseTask?.cancel()
        popoverContentReleaseTask = nil
    }

    /// The only teardown entry point. Releasing Task 2's inactive presentation
    /// state is idempotent and runs even when another owner already cleared
    /// `contentViewController`; only that presence transition ends content
    /// ownership and invokes the callback.
    private func releasePopoverContentIfPresent() {
        invalidatePopoverContentReleaseTask()
        let endedContentOwnership = popover.contentViewController != nil
        if endedContentOwnership {
            popover.contentViewController = nil
        }
        panelViewModel.stop()
        panelViewModel.releaseInactivePresentationState()
        if endedContentOwnership {
            onPopoverContentReleased?()
        }
    }

    /// The backing scale a menu-bar raster should be drawn at, plus whether
    /// that scale is the real one.
    struct BackingScaleResolution: Equatable {
        let scale: CGFloat
        let isFinal: Bool
    }

    /// Resolves the raster scale from the window the button actually lives in.
    ///
    /// `NSStatusBarButton` has no window until AppKit places the item on a menu
    /// bar, so the first presentation of a freshly shown item can only guess.
    /// The guess is the main screen's scale, which is wrong on a secondary
    /// display; `isFinal == false` tells the caller not to cache it, so the next
    /// presentation re-rasterizes at the window's own scale. No timer and no
    /// screen observer: correction rides on whichever presentation comes next.
    static func resolveBackingScale(
        windowScale: CGFloat?,
        mainScreenScale: CGFloat?
    ) -> BackingScaleResolution {
        if let windowScale, windowScale > 0, windowScale.isFinite {
            return BackingScaleResolution(scale: windowScale, isFinal: true)
        }
        if let mainScreenScale, mainScreenScale > 0, mainScreenScale.isFinite {
            return BackingScaleResolution(scale: mainScreenScale, isFinal: false)
        }
        return BackingScaleResolution(scale: 1, isFinal: false)
    }

    /// Everything one menu-bar presentation needs. The static key deliberately
    /// carries no animation phase, so a 20-Hz tick can never invalidate the
    /// template base.
    private struct PresentationContext {
        let button: NSStatusBarButton
        let scene: IconSceneState
        let iconSize: CGFloat
        let backingScale: CGFloat
        let appearance: NSAppearance
        let staticKey: StatusBarRenderKey
    }

    /// The one presentation entry point, for both a scene change and a clock
    /// tick. The static half runs only when the phase-free key changed; the
    /// overlay half runs per call and is a no-op for a repeated frame.
    private func presentMenuBar(phase: ChargingEffectPhase?) {
        guard isStatusItemVisible, let button = statusItem.button else { return }

        let scene = (latestIconOutput.menuBarTestScene ?? latestIconOutput.scene)
            .withChargingEffectEnabled(isMenuBarChargingEffectEnabled)
        let iconSize = latestIconOutput.menuBarSize
        guard iconSize.isFinite, iconSize > 0 else { return }
        let effectivePhase = isMenuBarChargingEffectEnabled ? phase : nil

        let scaleResolution = Self.resolveBackingScale(
            windowScale: button.window?.backingScaleFactor,
            mainScreenScale: NSScreen.main?.backingScaleFactor
        )
        let backingScale = scaleResolution.scale
        let appearance = appearanceProvider?() ?? button.effectiveAppearance
        let staticKey = StatusBarRenderKey(
            scene: scene,
            iconSize: iconSize,
            backingScale: backingScale,
            appearanceName: appearance.name.rawValue,
            phase: nil
        )

        if renderCache.needsRender(staticKey), provisionalStaticKey != staticKey {
            guard let base = staticBaseImage(
                scene: scene,
                iconSize: iconSize,
                backingScale: backingScale,
                appearance: appearance
            ) else {
                // Keep the icon that is already on screen; the next scene or
                // tick retries the same key because the cache stays invalid.
                return
            }
            // The button always carries the monochrome template image, so the
            // system keeps re-tinting it for the Space that is on top — including
            // while a Space switch is being dragged (#112).
            button.image = base
            renderCounters.buttonImageAssignments += 1
            staticBase = base
            staticOverlay = nil
            staticOverlayIsPending = true
            baseIsCustomRaster = false
            if scaleResolution.isFinal {
                renderCache.recordSuccessfulRender(staticKey)
                provisionalStaticKey = nil
            } else {
                // Drawn from a main-screen guess. Remember it so this key is not
                // rasterized twice, but keep it out of the cache: the next
                // presentation with a real window scale builds a different key
                // and therefore draws again, at the scale the button really has.
                provisionalStaticKey = staticKey
            }
            renderCounters.staticPresentations += 1
            didPresentStaticContent?()
        }

        // A fallback raster replaced the template base; put the re-tintable image
        // back as soon as the overlay can be drawn in the layer again.
        if baseIsCustomRaster, let staticBase {
            button.image = staticBase
            renderCounters.buttonImageAssignments += 1
            baseIsCustomRaster = false
        }

        let context = PresentationContext(
            button: button,
            scene: scene,
            iconSize: CGFloat(iconSize),
            backingScale: backingScale,
            appearance: appearance,
            staticKey: staticKey
        )

        guard let effectivePhase else {
            presentStaticOverlay(in: context)
            return
        }
        presentAnimationPhase(effectivePhase, in: context)
    }

    /// The template base. `nil` means the whole static presentation is left as
    /// it is, so a transient rasterization failure cannot blank the icon.
    private func staticBaseImage(
        scene: IconSceneState,
        iconSize: Double,
        backingScale: CGFloat,
        appearance: NSAppearance
    ) -> NSImage? {
        renderCounters.templateBaseRasters += 1
        // `nil` keeps the icon that is already on screen: a later state change
        // retries the same key because the render cache stays invalid.
        return renderMenuBarBase(scene, iconSize, backingScale, appearance)
    }

    /// The resting overlay: the scene's status colours at their idle values.
    /// Rendered on demand so an animating 20-Hz tick never rasterizes it, and
    /// kept for as long as the static key is on screen.
    private func presentStaticOverlay(in context: PresentationContext) {
        if staticOverlayIsPending {
            staticOverlay = renderMenuBarOverlay(
                context.scene,
                Double(context.iconSize),
                context.backingScale,
                context.appearance,
                nil
            )
            renderCounters.overlayRasters += 1
            // A failed raster stays pending so the next presentation retries it
            // instead of leaving the icon on the custom fallback forever.
            staticOverlayIsPending = staticOverlay == nil
        }

        if let staticOverlay {
            presentOverlayFrame(staticOverlay, in: context)
            // Steady frames belong to a phase that is no longer playing.
            chargingFrameCache.reset()
            return
        }

        guard !context.scene.chromaticRegions.isEmpty else {
            // A monochrome scene draws entirely in the template base.
            clearAnimationPresentation()
            return
        }
        installFallbackRaster(phase: nil, in: context)
    }

    /// A burst draws one overlay per tick; a steady tick reuses the frame set the
    /// cache built once for this icon state.
    private func presentAnimationPhase(
        _ phase: ChargingEffectPhase,
        in context: PresentationContext
    ) {
        guard !context.scene.chromaticRegions.isEmpty else {
            // Nothing in this scene can animate — the template base is the whole
            // icon — so there is no frame worth producing.
            clearAnimationPresentation()
            return
        }
        switch phase.kind {
        case .steady:
            let frame = chargingFrameCache.image(
                for: phase,
                key: context.staticKey,
                backingScale: context.backingScale,
                renderFrame: { framePhase in
                    renderMenuBarOverlay(
                        context.scene,
                        Double(context.iconSize),
                        context.backingScale,
                        context.appearance,
                        framePhase
                    )
                }
            )
            guard let frame else {
                installFallbackRaster(phase: phase, in: context)
                return
            }
            presentOverlayFrame(frame, in: context)
        case .burst:
            guard let overlay = renderMenuBarOverlay(
                context.scene,
                Double(context.iconSize),
                context.backingScale,
                context.appearance,
                phase
            ) else {
                installFallbackRaster(phase: phase, in: context)
                return
            }
            renderCounters.overlayRasters += 1
            presentOverlayFrame(overlay, in: context)
        }
    }

    private func clearAnimationPresentation() {
        chargingFrameCache.reset()
        animationLayerPresenter.clear()
    }

    private func resetStaticPresentation() {
        renderCache = StatusBarRenderCache()
        staticBase = nil
        provisionalStaticKey = nil
        staticOverlay = nil
        staticOverlayIsPending = false
        baseIsCustomRaster = false
    }

    /// Draws the chromatic overlay in a layer above the button's template image.
    private func presentOverlayFrame(
        _ image: CGImage,
        in context: PresentationContext
    ) {
        guard animationLayerPresenter.display(
            image,
            in: context.button,
            contentSize: CGSize(width: context.iconSize, height: context.iconSize),
            backingScale: context.backingScale
        ) != nil else {
            animationLayerPresenter.clear()
            return
        }
        renderCounters.framesPresented += 1
    }

    /// No overlay frame could be produced at all. One custom raster keeps the
    /// status colours visible even though the system can no longer re-tint it;
    /// the next successful tick restores the template base.
    private func installFallbackRaster(
        phase: ChargingEffectPhase?,
        in context: PresentationContext
    ) {
        animationLayerPresenter.clear()
        guard let image = StatusIconRenderer.image(
            scene: context.scene,
            size: context.iconSize,
            scale: context.backingScale,
            appearance: context.appearance,
            phase: phase
        ) else {
            return
        }
        context.button.image = image
        baseIsCustomRaster = true
        renderCounters.buttonImageAssignments += 1
        renderCounters.fallbackRasters += 1
    }

    /// Clock-driven frames bypass the status/setting coalescer; the menu-bar key
    /// includes every phase so the 20-fps stream cannot be deduplicated as static.
    private func renderAnimationPhase(_ phase: ChargingEffectPhase?) {
        currentChargingEffectPhase = phase
        presentMenuBar(phase: phase)
    }

    /// The status, the appearance, and the window's effective appearance all feed
    /// one cached render, so the newest state wins over a redraw that is still
    /// waiting out the coalescing interval.
    private func renderLatestScene() {
        presentMenuBar(phase: currentChargingEffectPhase)
    }

    /// Applies the newest status to the button's accessibility element.
    ///
    /// Both upstreams can emit several values in one turn. One in-flight task
    /// that reads the state when it runs keeps the element in step with the
    /// newest truth; queueing a task per emission instead would let each one
    /// apply the snapshot it captured, and the last to run would be the
    /// authority regardless of which value was newest.
    private func scheduleAccessibilityUpdate() {
        guard accessibilityUpdateTask == nil else { return }
        accessibilityUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            accessibilityUpdateTask = nil
            updateAccessibility(
                snapshot: store.snapshot,
                language: localization.resolvedLanguage
            )
        }
    }

    private func updateAccessibility(snapshot: StatusSnapshot, language: AppLanguage) {
        let key = StatusBarAccessibilityKey(snapshot: snapshot, language: language)
        guard key != accessibilityKey else { return }
        accessibilityKey = key
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(AccessibilityPresentation.statusItemLabel)
        let value = AccessibilityPresentation.statusItemValue(snapshot, localization: localization)
        button.setAccessibilityValue(value)
        accessibilityValueDidChange(value)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @objc private func handleOpenSettings() {
        popover.performClose(nil)
        openSettings()
    }

    @objc private func handleCheckForUpdates() {
        popover.performClose(nil)
        updaterManager.checkForUpdates()
    }

    @objc private func handleRequestWiFiNameAccess() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        if store.requestWiFiNameAccess() == .openLocationSettings {
            Self.openSystemSettings(Self.locationSettingsURLs)
        }
    }

    @objc private func handleRequestBluetoothAuthorization() {
        NSApp.activate(ignoringOtherApps: true)
        store.requestBluetoothAuthorization()
    }

    @objc private func handleOpenBatterySettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.batterySettingsURLs)
    }

    @objc private func handleOpenWiFiSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.wifiSettingsURLs)
    }

    /// Where the wired row's gear goes. The Network pane lists every service and
    /// is where a cable's own settings live; sending a wired user to the Wi-Fi
    /// pane would show them a radio that is not carrying the connection.
    @objc private func handleOpenNetworkSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.networkSettingsURLs)
    }

    @objc private func handleOpenLocationSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.locationSettingsURLs)
    }

    /// Where the wired row's Internet Sharing action goes. Status Trio does not
    /// toggle Internet Sharing itself — that needs an undocumented write to
    /// `com.apple.nat.plist` and the NetworkSharing daemon — so it opens the
    /// Sharing pane, where the switch lives.
    @objc private func handleOpenSharingSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.sharingSettingsURLs)
    }

    @objc private func handleOpenSoundSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.soundOutputSettingsURLs)
    }

    private func handleOpenSoundInputSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.soundInputSettingsURLs)
    }

    private func handleOpenKeyboardSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.keyboardSettingsURLs)
    }

    private func refreshInputSourceIfNeeded() {
        guard settings.connectionCenterSource == .inputSource
            || settings.enabledPopupSections.contains(.inputSource) else { return }
        inputSourceController.refresh()
    }

    private func handleOpenBluetoothSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.bluetoothSettingsURLs)
    }

    /// Where a refused Bluetooth grant is given back. This is not the pane the
    /// gear opens: that one turns the radio on and off, while a refusal lives in
    /// Privacy & Security. The store owns the route so Settings and the popover
    /// share one destination.
    private func handleOpenBluetoothPermissionSettings() {
        popover.performClose(nil)
        store.openBluetoothPermissionSettings()
    }

    static let batterySettingsURLs = [
        "x-apple.systempreferences:com.apple.Battery-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.battery"
    ]
    .compactMap(URL.init(string:))

    /// The Wi-Fi pane is what this button promises, and it has its own Settings
    /// extension on every macOS version the app supports. Routing through the
    /// Network pane instead lands on the wrong list: that pane shows services
    /// (Wi-Fi, Ethernet, VPNs) rather than networks, and its `?Wi-Fi` anchor
    /// does not select the Wi-Fi section on macOS 15.
    ///
    /// Do not reintroduce an OS-version branch here. A `majorVersion >= 27`
    /// guard shipped in 1.2.0 and 1.3.0 and sent macOS 15 through 26 to the
    /// Network pane; the pane identifier is not version-specific, because the
    /// extension bundle that declares it dates from macOS 14
    /// (`BuildMachineOSBuild 23A344017` in `Wi-Fi.appex`).
    ///
    /// The first route decides the destination. System Settings launches even
    /// for an unknown pane identifier and `open` reports success — verified on
    /// macOS 27 with a nonexistent identifier — so the later entries only cover
    /// the URL scheme itself failing to open, not a missing pane.
    static let wifiSettingsURLs = [
        "x-apple.systempreferences:com.apple.wifi-settings-extension",
        "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
        "x-apple.systempreferences:com.apple.preference.network?Wi-Fi"
    ]
    .compactMap(URL.init(string:))

    static let networkSettingsURLs = [
        "x-apple.systempreferences:com.apple.Network-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.network"
    ]
    .compactMap(URL.init(string:))

    /// The Sharing pane is where Internet Sharing lives. Its own Settings
    /// extension declares `com.apple.Sharing-Settings.extension` (legacy bundle
    /// id `com.apple.preferences.sharing`), so the first route goes straight
    /// there rather than through General or Network.
    static let sharingSettingsURLs = [
        "x-apple.systempreferences:com.apple.Sharing-Settings.extension",
        "x-apple.systempreferences:com.apple.preferences.sharing"
    ]
    .compactMap(URL.init(string:))

    static let bluetoothSettingsURLs = [
        "x-apple.systempreferences:com.apple.BluetoothSettings",
        "x-apple.systempreferences:com.apple.preference.bluetooth"
    ]
    .compactMap(URL.init(string:))

    /// The Keyboard pane owns the input-source list this section manages, so
    /// its own Settings extension identifier comes first. Verified by the pane
    /// the URL actually loads (`pgrep -fl ExtensionKit/Extensions`), not by
    /// `open`'s exit status.
    static let keyboardSettingsURLs = [
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.keyboard"
    ]
    .compactMap(URL.init(string:))

    static let locationSettingsURLs = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    ]
    .compactMap(URL.init(string:))

    static let soundOutputSettingsURLs = [
        "x-apple.systempreferences:com.apple.Sound-Settings.extension?output",
        "x-apple.systempreferences:com.apple.preference.sound?output"
    ]
    .compactMap(URL.init(string:))

    static let soundInputSettingsURLs = [
        "x-apple.systempreferences:com.apple.Sound-Settings.extension?input",
        "x-apple.systempreferences:com.apple.preference.sound?input"
    ]
    .compactMap(URL.init(string:))

    private static func openSystemSettings(_ urls: [URL]) {
        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    private func showMenu() {
        let menu = StatusMenuBuilder.makeMenu(
            version: Self.appVersion,
            settingsTarget: self,
            settingsAction: #selector(handleOpenSettings),
            localization: localization,
            updateTarget: updaterManager.canCheckForUpdates ? self : nil,
            updateAction: updaterManager.canCheckForUpdates
                ? #selector(handleCheckForUpdates)
                : nil
        )
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 4),
            in: button
        )
    }
}

@MainActor
private final class StatusBarPanelUpdateScheduler: PanelPresentationUpdateScheduling {
    func schedule(_ update: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            update()
        }
    }
}
