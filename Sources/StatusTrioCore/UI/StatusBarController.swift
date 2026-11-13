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
final class StatusBarController: NSObject {
    static let popoverToggleLockoutInterval: TimeInterval = 0.25
    /// Bounds the "this close came from the current click's mouse-down" record
    /// so a later opening click is not suppressed. Kept short: a same-click
    /// mouse-up follows its mouse-down within the physical press.
    static let popoverReopenSuppressionInterval: TimeInterval = 0.35
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
    private let popover = AnchoredStatusPanel()
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let panelActions: StatusPanelActions
    /// Retained so the right-click quick action can reuse the same
    /// charge-to-full start/cancel path the panel button uses.
    private let chargeToFullNow: ChargeToFullNowController?
    private let panelViewModel: StatusPanelViewModel
    private let iconPresentation: IconPresentationViewModel
    private let localization: Localization
    private let renderMenuBarBase: MenuBarBaseRenderer
    private let renderMenuBarOverlay: MenuBarOverlayRenderer
    private let accessibilityValueDidChange: @MainActor (String) -> Void
    private let popoverContentReleaseSleeper: @Sendable (Duration) async throws -> Void
    private let activatesApplicationForPopover: @MainActor () -> Void
    /// Whether the app currently runs as a regular app (Dock icon, its own
    /// windows on a desktop Space). See `presentPopover` for why a forced
    /// activation is withheld in that state.
    private let isApplicationRegular: @MainActor () -> Bool
    private let backgroundUITesting: BackgroundUITestingConfiguration
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
    private var powerDemandCancellable: AnyCancellable?
    private var panelBackgroundCancellable: AnyCancellable?
    private let openSettings: () -> Void
    /// Opens Status Trio's own Settings window on the Battery tab.
    private let openAppBatterySettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []
    private var renderCache = StatusBarRenderCache()
    private let chargingFrameCache = StatusBarChargingFrameCache()
    private let animationLayerPresenter = StatusBarAnimationLayerPresenter()
    private let templateImagePresenter = StatusBarTemplateImagePresenter()
    #if DEBUG
    private let alignmentDiagnostics = StatusBarAlignmentDiagnostics()
    #endif
    private let renderCoalescer = IconRenderCoalescer()
    /// The template base and button footprint, kept so a custom-raster fallback
    /// can restore the independent template presentation.
    private var staticBase: NSImage?
    private var staticButtonImage: NSImage?
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
    var popoverForTesting: AnchoredStatusPanel { popover }
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
    private var volumeScrollAdjustment = PopupVolumeScrollAdjustment()
    private var volumeScrollSession = PopupVolumeScrollSession()
    private var brightnessScrollSession = PopupLevelScrollSession()
    private var audioInputScrollSession = PopupLevelScrollSession()
    private let popoverScrollTargets = PopoverScrollTargets()
    private var popoverAnchorWindow: NSWindow?
    private var popoverToggleGate = PopoverToggleGate(
        lockout: StatusBarController.popoverToggleLockoutInterval
    )
    private var reopenSuppression = PopoverReopenSuppression(
        window: StatusBarController.popoverReopenSuppressionInterval
    )
    private var popoverContentReleaseTask: Task<Void, Never>?
    private var popoverContentGeneration: UInt64 = 0
    private var isPopoverClosing = false
    private var popoverWindowFocusCancellables: Set<AnyCancellable> = []
    private var applicationFocusCancellables: Set<AnyCancellable> = []
    /// Observes other app windows coming to the front so the panel closes when
    /// the user clicks a real window such as Settings (issue #267).
    private var appWindowFrontmostCancellables: Set<AnyCancellable> = []
    private let inputSourceController: InputSourceController
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
        openAppBatterySettings: @escaping () -> Void = {},
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
        isApplicationRegular: @escaping @MainActor () -> Bool = {
            NSApplication.shared.activationPolicy() == .regular
        },
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
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
        chargeToFullNow: ChargeToFullNowController? = nil,
        appearanceProvider: (@MainActor () -> NSAppearance)? = nil
    ) {
        self.appearanceProvider = appearanceProvider
        self.store = store
        self.settings = settings
        self.chargeToFullNow = chargeToFullNow
        let resolvedInputSourceController = inputSourceController ?? InputSourceController()
        self.inputSourceController = resolvedInputSourceController
        let panelActions = StatusPanelActions(
            store: store,
            settings: settings,
            inputSourceController: resolvedInputSourceController,
            chargeToFullNow: chargeToFullNow
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
            chargeToFullNow: chargeToFullNow
        )
        self.iconPresentation = iconPresentation
        self.localization = localization
        self.renderMenuBarBase = renderMenuBarBase
        self.renderMenuBarOverlay = renderMenuBarOverlay
        self.accessibilityValueDidChange = accessibilityValueDidChange
        self.popoverContentReleaseSleeper = popoverContentReleaseSleeper
        self.activatesApplicationForPopover = activatesApplicationForPopover
        self.isApplicationRegular = isApplicationRegular
        self.backgroundUITesting = backgroundUITesting
        self.chargingEffectClock = chargingEffectClock
        self.openSettings = openSettings
        self.openAppBatterySettings = openAppBatterySettings
        self.quitAction = quitAction
        self.isStatusItemVisible = isVisible
        self.isMenuBarChargingEffectEnabled = settings.showsMenuBarChargingEffect
        self.latestIconOutput = iconPresentation.output
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.isVisible = isVisible
        configureButton()
        #if DEBUG
        alignmentDiagnostics?.didChange = { [weak self] in
            self?.renderLatestScene()
        }
        #endif
        configurePopover()
        observeApplicationFocusChanges()
        observeAppWindowFrontmostChanges()
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

        // #255: the effective cadence depends on the two per-power-source
        // settings and the deduplicated power source. Mapping the snapshot to a
        // single Bool first means an unrelated snapshot update (battery percent,
        // Wi-Fi, volume) never rebuilds the wait.
        refreshIntervalCancellable = Publishers.CombineLatest3(
            settings.$refreshIntervalOnBatterySeconds,
            settings.$refreshIntervalOnPowerSeconds,
            store.$snapshot
                .map { Self.effectivePluggedIn(battery: $0.battery) }
                .removeDuplicates()
        )
        .map { batterySeconds, powerSeconds, pluggedIn in
            pluggedIn
                ? Duration.seconds(Int(powerSeconds.rounded()))
                : Duration.seconds(Int(batterySeconds.rounded()))
        }
        .removeDuplicates()
        .sink { [weak self] interval in
            self?.store.setRefreshInterval(interval)
        }

        // The icon is the surface that keeps wanting watts while the panel is
        // closed. Its demand keeps the shared sampler at the idle cadence; the
        // panel and details page add their own faster demands.
        powerDemandCancellable = settings.$connectionCenterSource
            .removeDuplicates()
            .sink { [weak self] source in
                guard let self else { return }
                if source.needsPowerSampling {
                    self.store.powerSampling.begin(.icon)
                } else {
                    self.store.powerSampling.end(.icon)
                }
            }

        // The panel may already be open when the user changes the background
        // style; swap it in place rather than waiting for the next reopen.
        panelBackgroundCancellable = settings.$panelBackgroundStyle
            .removeDuplicates()
            .sink { [weak self] style in
                self?.popover.applyBackgroundStyle(style)
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

    /// Whether the effective refresh cadence should use the wall-power value.
    ///
    /// #255: a Mac with no battery has no battery mode, so it is treated as
    /// plugged in. Charging state is deliberately ignored — an unplugged Mac
    /// that happens to report charging must still use the battery cadence.
    static func effectivePluggedIn(battery: BatteryStatus) -> Bool {
        !battery.isPresent || battery.isConnectedToPower
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
            // The colored presentation's non-template footprint is transparent.
            // Keep a readable template behind it while hidden so a failed first
            // raster after re-showing cannot leave an invisible status item.
            if let staticBase,
               let button = statusItem.button,
               button.image === staticButtonImage,
               button.image !== staticBase {
                button.image = staticBase
                renderCounters.buttonImageAssignments += 1
            }
            templateImagePresenter.clear()
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
            performRightClickAction()
        }
    }

    /// Resolve which custom quick action is possible right now. Each flag comes
    /// from the owning subsystem; the router falls back to the context menu for
    /// anything unavailable so the right-click never silently does nothing.
    private var quickActionAvailability: MenuBarQuickActionAvailability {
        MenuBarQuickActionAvailability(
            lowPowerMode: settings.controlsLowPowerMode && PrivilegedHelperManager.shared.isReady,
            chargeToFullNow: chargeToFullNow?.isSettingAvailable ?? false,
            mute: store.liveVolume.canMute,
            wifi: store.snapshot.wifi.state != .unavailable
        )
    }

    /// Route a right-click to the configured quick action (#209). The default
    /// `.contextMenu` keeps the historical `showMenu()` path unchanged.
    private func performRightClickAction() {
        let outcome = MenuBarRightClickRouter.outcome(
            for: settings.menuBarRightClickAction,
            availability: quickActionAvailability
        )
        switch outcome {
        case .showContextMenu:
            showMenu()
        case .toggleLowPowerMode:
            store.lowPowerMode.setLowPowerMode(!store.lowPowerMode.isLowPowerMode)
        case .toggleChargeToFullNow:
            if chargeToFullNow?.performQuickToggle(battery: store.snapshot.battery) != true {
                showMenu()
            }
        case .toggleMute:
            store.toggleMute()
        case .toggleWiFi:
            store.toggleWiFiPower()
        case .refreshStatus:
            store.refreshAll()
        case .openWiFiSettings:
            handleOpenWiFiSettings()
        case .openBluetoothSettings:
            handleOpenBluetoothSettings()
        case .openBatterySettings:
            handleOpenBatterySettings()
        case .openSoundSettings:
            handleOpenSoundSettings()
        }
    }

    private func configurePopover() {
        // The panel replaces NSPopover (issue #186); close teardown runs through
        // the panel's own callback instead of NSPopoverDelegate.
        popover.onClose = { [weak self] in
            self?.handlePanelDidClose()
        }
        // Issue #224 follow-up: while the app is active (regular mode), the
        // panel's focus-loss observers would close it on the status-item
        // mouse-down and the item's mouse-up toggle would reopen it. Defer that
        // close when the pointer is pressing the item so the toggle owns the
        // click; a genuine focus loss (no button pressed) still dismisses.
        popover.shouldDeferDismissalOnFocusLoss = { [weak self] in
            guard let self else { return false }
            let policy = PopoverDismissalPolicy(
                statusItemFrame: self.statusItemButtonScreenFrame()
            )
            return !policy.shouldDismissOnFocusLoss(
                at: NSEvent.mouseLocation,
                isMouseButtonDown: NSEvent.pressedMouseButtons != 0
            )
        }
    }

    private func installPopoverContentIfNeeded() {
        guard popover.contentViewController == nil else { return }
        let measurementID = UUID()
        let rootView = LocalizedRootView(localization: localization) {
            StatusPopoverView(
                panel: panelViewModel,
                scrollTargets: popoverScrollTargets,
                layoutMetrics: popover.layoutMetrics,
                requestWiFiNameAccess: { self.handleRequestWiFiNameAccess() },
                requestBluetoothAuthorization: { self.handleRequestBluetoothAuthorization() },
                openBatterySettings: { self.handleOpenBatterySettings() },
                openAppBatterySettings: { self.handleOpenAppBatterySettings() },
                openWiFiSettings: { self.handleOpenWiFiSettings() },
                openNetworkSettings: { self.handleOpenNetworkSettings() },
                openSharingSettings: { self.handleOpenSharingSettings() },
                openLocationSettings: { self.handleOpenLocationSettings() },
                openBluetoothSettings: { self.handleOpenBluetoothSettings() },
                openBluetoothPermissionSettings: { self.handleOpenBluetoothPermissionSettings() },
                openSettings: { self.handleOpenSettings() },
                openSoundSettings: { self.handleOpenSoundSettings() },
                openSoundInputSettings: { self.handleOpenSoundInputSettings() },
                openDisplaySettings: { self.handleOpenDisplaySettings() },
                openKeyboardSettings: { self.handleOpenKeyboardSettings() },
                quit: quitAction,
                dismissPanel: { [weak self] in self?.closePopover() },
                contentMeasurementID: measurementID
            )
        }
        let hostingController = StatusPanelHostingController(rootView: rootView)
        // StatusPanelLayoutMetrics owns the panel height; preferred sizing here
        // would add a second owner and can reset the measured window frame.
        popover.installContent(hostingController,
                               backgroundStyle: settings.panelBackgroundStyle,
                               measurementID: measurementID)
    }

    func togglePopover() {
        // Issue #224 follow-up 2: if this same click's mouse-down already closed
        // the panel (the outside-click monitor, or a focus-loss close while the
        // button was held), the click intended to close — never reopen on the
        // following mouse-up.
        if !popover.isShown, reopenSuppression.shouldSuppressReopen(at: Date()) {
            return
        }
        guard popoverToggleGate.shouldAccept(at: Date()) else { return }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            // The panel is nonactivating and becomes key on its own. Forcing
            // activation here lets the next status-item press deactivate and
            // close it before mouse-up, which would reopen it (#224).
            presentPopover(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY,
                activatesApplication: false
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
            activatesApplication: false,
            dockInset: anchor.dockInset
        )
    }

    /// Presents the panel on the Debug background-testing route. The anchor is
    /// derived from the requested display instead of the pointer, the panel is
    /// not made key, and focus-loss dismissal stays disabled while it is open.
    func presentStatusPanelForBackgroundTesting() {
        guard backgroundUITesting.isEnabled, backgroundUITesting.opensStatusPanel else {
            return
        }
        presentPopoverFromShortcut(
            pointerLocation: backgroundTestingPointerLocation(),
            activatesApplication: false,
            makesKeyWindow: false,
            prefersMenuBarAnchor: false
        )
    }

    private func backgroundTestingPointerLocation() -> NSPoint {
        let screens = NSScreen.screens
        let mainDisplayID = CGMainDisplayID()
        let target: NSScreen?
        switch backgroundUITesting.display {
        case .secondary:
            target = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber)?.uint32Value != mainDisplayID
            } ?? screens.first
        case .automatic:
            target = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber)?.uint32Value == mainDisplayID
            } ?? screens.first
        }
        guard let target else { return NSEvent.mouseLocation }
        return NSPoint(x: target.frame.midX, y: target.frame.midY)
    }

    private func presentPopoverFromShortcut(
        pointerLocation: NSPoint = NSEvent.mouseLocation,
        activatesApplication: Bool = true,
        makesKeyWindow: Bool = true,
        prefersMenuBarAnchor: Bool = true
    ) {
        let menuBarAnchor = prefersMenuBarAnchor ? visibleMenuBarAnchor() : nil
        let screens = NSScreen.screens.map {
            StatusPanelShortcutScreen(
                frame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        }
        let anchor = StatusPanelShortcutPresentationPolicy.anchor(
            menuBarRect: menuBarAnchor?.screenRect,
            isMenuBarVisible: menuBarAnchor != nil,
            pointerLocation: pointerLocation,
            screens: screens
        )

        if case .menuBar = anchor, let menuBarAnchor {
            presentPopover(
                relativeTo: menuBarAnchor.button.bounds,
                of: menuBarAnchor.button,
                preferredEdge: .minY,
                activatesApplication: activatesApplication,
                makesKeyWindow: makesKeyWindow
            )
            return
        }
        guard case let .fallback(origin, preferredEdge) = anchor else { return }
        let anchorView = popoverAnchorView(at: origin)
        presentPopover(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: preferredEdge,
            activatesApplication: activatesApplication,
            makesKeyWindow: makesKeyWindow
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
        activatesApplication: Bool = true,
        makesKeyWindow: Bool = true,
        dockInset: NSEdgeInsets = DockReveal.noInset
    ) {
        cancelPopoverContentRelease()
        // A fresh presentation is not the tail of a mouse-down dismissal.
        reopenSuppression.reset()
        store.setPopoverVisible(true)
        // A retained route is lightweight. Re-enter its detail source before
        // installing or laying out content so the first frame uses fresh data.
        panelViewModel.start()
        panelViewModel.prepareForPresentation()
        installPopoverContentIfNeeded()
        // One bounded refresh per open covers a lost distributed notification
        // without any polling while the popover is closed.
        refreshInputSourceIfNeeded()
        // Only force-activate when the app is not already regular. A regular
        // app owns a Dock tile and real windows on a desktop Space (the Settings
        // or first-run window). Activating such an app from another app's
        // full-screen Space makes macOS restore that window, which switches away
        // from the full-screen Space; the app resigns active right after the
        // panel is presented and the panel dismisses itself (#183). The panel is
        // a non-activating NSPanel, so it still shows over the full-screen Space
        // and becomes key without activating the app. The Dock click path skips
        // activation for the same reason.
        let forcesApplicationActivation =
            activatesApplication && !isApplicationRegular()
        if forcesApplicationActivation {
            // A transient popover shown while the app is still inactive can be
            // dismissed again straight away. Status-item clicks come from the
            // system menu bar process, so the modern activate() can be ignored
            // by the user-activation policy.
            activatesApplicationForPopover()
        }
        // The background route must also survive the panel's own focus-loss
        // observers before the window is ordered in.
        let isBackgroundStatusPanel =
            backgroundUITesting.isEnabled && backgroundUITesting.opensStatusPanel
        popover.disablesDismissOnResignForTesting = isBackgroundStatusPanel || settings.keepsPanelOpenWhenOpeningSettings
        popover.disablesKeyWindowForTesting = isBackgroundStatusPanel
        popover.avoidsOrderFrontRegardlessForTesting = isBackgroundStatusPanel
        if isBackgroundStatusPanel {
            // Borderless, status-level NSPanels are skipped by some CU window
            // enumerators. Give the Debug test instance a standard AX window
            // identity and a normal window level so its existing controls stay
            // addressable. Release and normal presentation keep their defaults.
            popover.setAccessibilitySubrole(.standardWindow)
            popover.setAccessibilityTitle("Status Panel")
            popover.level = .normal
            popover.isFloatingPanel = false
            popover.collectionBehavior = [.ignoresCycle]
        }
        popover.show(
            relativeTo: rect,
            of: view,
            preferredEdge: preferredEdge,
            dockInset: dockInset
        )
        // The popover's backing window only exists once it has been shown, and
        // without a Spaces behavior it stays on this app's desktop Space while
        // another app is full-screen.
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.enableDisplayOnFullScreenSpaces()
        installPopoverWindowFocusObservers(popoverWindow)
        if makesKeyWindow {
            popoverWindow?.makeKey()
            // Do not focus the first row on open. With keyboard navigation enabled,
            // AppKit's initial key view drew a blue focus ring on the battery row
            // before the user touched the keyboard. Clearing the first responder
            // keeps Tab working: the window still hands the first Tab to the key
            // view loop, so the panel stays fully keyboard operable.
            popoverWindow?.makeFirstResponder(nil)
        }
        dockActivationLogger.notice(
            """
            Popover presented shown=\(self.popover.isShown) \
            key=\(popoverWindow?.isKeyWindow ?? false) \
            applicationActivation=\(forcesApplicationActivation ? "forced" : (activatesApplication ? "withheld-regular" : "skipped"), privacy: .public) \
            \(dockActivationFocusSnapshot(window: popoverWindow), privacy: .public)
            """
        )
        // A background test instance must not close on the user's global clicks
        // or consume their scroll wheel.
        if !(backgroundUITesting.isEnabled && backgroundUITesting.opensStatusPanel) {
            installPopoverDismissMonitor()
            installVolumeScrollMonitor()
        }
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

    /// The panel is a non-activating borderless `NSPanel`, so clicking another of
    /// this app's windows (the Settings window that was already key before the
    /// panel opened) never reaches `addGlobalMonitorForEvents`, which only sees
    /// events outside the app. Without this, the panel stays on top of Settings
    /// (issue #267). An `NSPopover` would close by itself here because it tracks
    /// its own window; a custom panel must react to the key/main handoff.
    private func observeAppWindowFrontmostChanges() {
        let center = NotificationCenter.default
        let policy = PanelFocusDismissPolicy()
        // AppKit posts these window notifications synchronously on the main
        // thread. Handle them synchronously so a run-loop hop cannot deliver a
        // stale key change after the panel has re-keyed itself and close it
        // spuriously (e.g. when app activation keys Settings just before the
        // panel is ordered in).
        let handle: (Notification) -> Void = { [weak self] notification in
            MainActor.assumeIsolated {
                self?.dismissPanelIfExternalWindowCameForward(notification, policy: policy)
            }
        }
        center.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink(receiveValue: handle)
            .store(in: &appWindowFrontmostCancellables)
        center.publisher(for: NSWindow.didBecomeMainNotification)
            .sink(receiveValue: handle)
            .store(in: &appWindowFrontmostCancellables)
    }

    /// Closes the panel when a real, independent window (Settings) is brought to
    /// the front. This mirrors the app's existing close paths so focus falls on
    /// the clicked window without activating the app or stealing focus.
    private func dismissPanelIfExternalWindowCameForward(
        _ notification: Notification,
        policy: PanelFocusDismissPolicy
    ) {
        guard popover.isShown, !isPopoverClosing,
              // The Debug background-testing route intentionally keeps the panel
              // up while the user works; it must not be closed by a focus change.
              !popover.disablesDismissOnResignForTesting,
              let candidateWindow = notification.object as? NSWindow else { return }
        let panelWindow = popover.contentViewController?.view.window
        let candidate = PanelFocusDismissPolicy.FocusedWindow(
            isPanel: candidateWindow === panelWindow,
            isVisible: candidateWindow.isVisible,
            level: candidateWindow.level,
            hasSheetParent: candidateWindow.sheetParent != nil,
            hasParent: candidateWindow.parent != nil
        )
        guard policy.shouldDismiss(for: candidate) else { return }
        popover.performClose(nil)
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
        // The panel's close is synchronous. If it was already off screen the
        // panel intentionally posts no close callback, so never leave the gate
        // stuck closed for the next shortcut/toggle.
        if !popover.isShown {
            isPopoverClosing = false
        }
    }

    /// The Dock icon has no public frame, but the click happens on the icon, so
    /// a tiny invisible window at the click point anchors the popover there.
    private func dockAnchor(at point: NSPoint) -> (
        view: NSView,
        preferredEdge: NSRectEdge,
        dockInset: NSEdgeInsets
    ) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        // A collapsed Dock no longer shrinks visibleFrame, so resolve() cannot
        // tell its orientation; fall back to the pointer's nearest edge first.
        let placement = screen.map {
            DockReveal.collapsedPlacement(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame,
                pointer: point
            ) ?? DockPlacement.resolve(screenFrame: $0.frame, visibleFrame: $0.visibleFrame)
        } ?? .bottom
        let anchor = DockPopoverAnchor.make(
            clickPoint: point,
            tileSize: NSApplication.shared.dockTile.size,
            placement: placement
        )
        // Leave room for the revealed Dock so the panel cannot overlap it when
        // the Dock is set to auto-hide (#229). A visible Dock needs no inset.
        let dockInset = screen.map {
            DockReveal.inset(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame,
                pointer: point
            )
        } ?? DockReveal.noInset
        // Attach the panel to the Dock's inner edge rather than to the click
        // point plus half a tile. The tile-based raise made the gap grow with
        // where on the icon the click landed and with the tile size, leaving the
        // panel noticeably far from the Dock (#229 follow-up).
        var origin = anchor.origin
        if let screen {
            let edge = DockReveal.dockEdge(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                placement: placement
            )
            switch placement {
            case .bottom:
                origin.y = edge
            case .left, .right:
                origin.x = edge
            }
        }
        return (
            popoverAnchorView(at: origin),
            anchor.preferredEdge,
            dockInset
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

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Read the pointer synchronously: the event is non-Sendable and the
            // pointer may move before the main-actor hop runs.
            let clickLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self else { return }
                let policy = PopoverDismissalPolicy(
                    statusItemFrame: self.statusItemButtonScreenFrame()
                )
                // A click on the status item is the item's own toggle, not an
                // outside click. Dismissing here would close on mouse-down and
                // the item's mouse-up toggle would reopen it (issue #224).
                guard policy.shouldDismiss(at: clickLocation) else { return }
                // Even when the geometry check cannot recognise the item (some
                // multi-display / OS setups), remember that this mouse-down
                // closed the panel so the same click's mouse-up will not reopen
                // it (issue #224 follow-up 2).
                self.reopenSuppression.recordClose(at: Date(), mouseButtonDown: true)
                self.popover.performClose(nil)
            }
        }
    }

    /// The status item button's rectangle in screen coordinates, when the item
    /// is visible. Used to tell a click on the item (its own toggle) from an
    /// outside click that should dismiss the panel (issue #224).
    private func statusItemButtonScreenFrame() -> NSRect? {
        guard isStatusItemVisible,
              let button = statusItem.button,
              let window = button.window else {
            return nil
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
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
        guard event.window === popover.contentViewController?.view.window else { return false }

        let point = event.locationInWindow
        let window = event.window

        // 1. The registered slider directly under the pointer owns the wheel,
        //    before any scroll view or the panel-wide fallback (issue #256).
        if let target = popoverScrollTargets.target(at: point, in: window) {
            return consumeScroll(target: target, event: event)
        }

        // 1b. A control that handles the wheel itself (e.g. the compact Adaptive
        //     strength bar) keeps the event, so the panel-wide volume fallback
        //     never turns its scroll into a volume change.
        if let hit = window?.contentView?.hitTest(point), hit.handlesScrollWheelItself {
            return false
        }

        // 2. A scrollable scroll view under the pointer owns the wheel.
        if isPointerOverScrollableScrollView(event) { return false }

        // 3. Opt-in summary-page fallback to the output volume. Sliders were
        //    handled above; detail pages never change volume (issue #324).
        guard PanelScrollVolumeFallback.allows(
            panelScrollEnabled: settings.popupPanelScrollAdjustsVolume,
            route: panelViewModel.route,
            isVolumeControlAvailable: store.isVolumeControlAvailable,
            canAdjustVolume: panelViewModel.volume.canAdjust
        ) else {
            return false
        }
        return consumeVolume(event: event)
    }

    /// Routes a wheel event to the slider directly under the pointer.
    private func consumeScroll(
        target: PanelLevelScrollTarget,
        event: NSEvent
    ) -> Bool {
        switch target {
        case .volume:
            guard store.isVolumeControlAvailable, panelViewModel.volume.canAdjust else {
                return true // consume so the wheel does not scroll underneath
            }
            return consumeVolume(event: event)
        case .brightness(let displayID):
            // Sliders own the wheel wherever they are; the scope setting only
            // decides whether empty panel areas also adjust the output volume.
            return consumeBrightness(displayID: displayID, event: event)
        case .audioInput:
            return consumeAudioInput(event: event)
        }
    }

    private func consumeAudioInput(event: NSEvent) -> Bool {
        let inputState = panelViewModel.audioInput
        guard inputState.canAdjust, let fallback = inputState.scalar else {
            return true // registered but not adjustable: consume, do not change volume
        }
        guard event.momentumPhase.isEmpty else { return true }

        guard let currentScalar = audioInputScrollSession.scalar(
            at: event.timestamp,
            displayID: "audio-input",
            fallback: fallback
        ) else { return false }
        let delta = volumeScrollAdjustment.levelDelta(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            timestamp: event.timestamp,
            target: .audioInput,
            settings: settings
        )
        guard let delta else { return true }

        let nextScalar = audioInputScrollSession.applying(delta: delta, to: currentScalar)
        store.setInputScalar(nextScalar)
        return true
    }

    private func consumeBrightness(displayID: String, event: NSEvent) -> Bool {
        guard let row = panelViewModel.brightness.rows.first(where: { $0.id == displayID }),
              row.canAdjust,
              let fallback = row.scalar else {
            return true // registered but not adjustable: consume, do not change volume
        }
        guard event.momentumPhase.isEmpty else { return true }

        guard let currentScalar = brightnessScrollSession.scalar(
            at: event.timestamp,
            displayID: displayID,
            fallback: fallback
        ) else { return false }
        let delta = volumeScrollAdjustment.levelDelta(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            timestamp: event.timestamp,
            target: .brightness(displayID: displayID),
            settings: settings
        )
        guard let delta else { return true }

        let nextScalar = brightnessScrollSession.applying(delta: delta, to: currentScalar)
        store.setBrightness(nextScalar, forDisplayID: displayID)
        return true
    }

    private func consumeVolume(event: NSEvent) -> Bool {
        let volumeState = panelViewModel.volume
        guard event.window === popover.contentViewController?.view.window,
              store.isVolumeControlAvailable,
              volumeState.canAdjust else {
            return false
        }
        guard event.momentumPhase.isEmpty else { return true }

        guard let currentScalar = volumeScrollSession.scalar(
            at: event.timestamp,
            identity: volumeState.interactionIdentity,
            fallback: volumeState.scalar
        ) else {
            return false
        }
        let delta = volumeScrollAdjustment.levelDelta(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            timestamp: event.timestamp,
            target: .volume,
            settings: settings
        )
        guard let delta else { return true }

        let nextScalar = volumeScrollSession.applying(
            delta: delta,
            to: currentScalar
        )
        // Publish this wheel step on the current runloop instead of waiting for
        // the drag coalescer, so the row tracks the wheel without a visible lag.
        panelViewModel.beginWheelVolumeAdjustment()
        if volumeScrollSession.shouldUnmute(
            in: volumeState,
            isIncreasing: delta > 0
        ) {
            store.toggleMute()
        }
        store.setVolume(nextScalar)
        panelViewModel.endWheelVolumeAdjustment()
        return true
    }

    /// Whether the pointer sits over a scroll view that can actually scroll
    /// right now.
    ///
    /// The panel's own outer scroll view (#237) is always present, but a
    /// scroll view with nothing to scroll must not
    /// swallow the wheel: on a short panel the wheel still adjusts the volume
    /// (issue #22), exactly as it did before the panel could scroll.
    private func isPointerOverScrollableScrollView(_ event: NSEvent) -> Bool {
        guard let rootView = popover.contentViewController?.view else { return false }
        return PanelScrollHitTesting.pointerIsOverScrollableScrollView(
            at: rootView.convert(event.locationInWindow, from: nil),
            in: rootView
        )
    }

    private func resetVolumeScrollSession() {
        volumeScrollSession.reset()
        brightnessScrollSession.reset()
        audioInputScrollSession.reset()
    }

    private func handlePanelDidClose() {
        // A close while a mouse button is held is a mouse-down dismissal (the
        // outside-click monitor or a focus-loss close during the press). The
        // same click's mouse-up must not reopen the panel (issue #224 follow-up
        // 2). The item's own toggle closes on mouse-up, so it is not recorded.
        reopenSuppression.recordClose(
            at: Date(),
            mouseButtonDown: NSEvent.pressedMouseButtons != 0
        )
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
        if backgroundUITesting.isEnabled && backgroundUITesting.opensStatusPanel {
            popover.level = .statusBar
            popover.isFloatingPanel = true
            popover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
        releasePopoverAnchorWindow()
        // The route survives as a few bytes, but detail views and collectors do
        // not. Sample both owners before closing deactivates the collectors.
        let hadOpenDetails = panelViewModel.isShowingDetailPage
            || store.hasOpenPopoverPanel
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

        var scene = (latestIconOutput.menuBarTestScene ?? latestIconOutput.scene)
            .withChargingEffectEnabled(isMenuBarChargingEffectEnabled)
        var iconSize = latestIconOutput.menuBarSize
        var effectivePhase = isMenuBarChargingEffectEnabled ? phase : nil
        var forcesSplitPresentation = false
        #if DEBUG
        if let request = alignmentDiagnostics?.request {
            scene = request.scene
            iconSize = request.size
            effectivePhase = request.animated ? ChargingEffectPhase(step: request.phaseStep, stepsPerCycle: 40, kind: .steady) : nil
            forcesSplitPresentation = true
        }
        #endif
        guard iconSize.isFinite, iconSize > 0 else { return }

        let scaleResolution = Self.resolveBackingScale(
            windowScale: button.window?.backingScaleFactor,
            mainScreenScale: NSScreen.main?.backingScaleFactor
        )
        let backingScale = scaleResolution.scale
        let appearance = appearanceProvider?() ?? button.effectiveAppearance
        #if DEBUG
        if let diagnostics = alignmentDiagnostics {
            // One deferred observation per explicit fixture request/presentation;
            // wait for AppKit's image-driven button resize, without polling.
            DispatchQueue.main.async { [weak self, weak button] in
                guard let self, let button else { return }
                diagnostics.write(button: button, scale: backingScale, size: iconSize,
                                  overlayFrame: self.animationLayerPresenter.frameForDiagnostics,
                                  statusItemLength: self.statusItem.length,
                                  overlayContentsScale: self.animationLayerPresenter.contentsScaleForDiagnostics)
            }
        }
        #endif
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
            let buttonImage: NSImage
            if scene.chromaticRegions.isEmpty && !forcesSplitPresentation {
                buttonImage = base
            } else {
                guard let placeholder = StatusIconRenderer.transparentMenuBarImage(
                    size: CGFloat(iconSize), scale: backingScale
                ) else { return }
                buttonImage = placeholder
            }
            presentBase(base, buttonImage: buttonImage, in: button)
            staticBase = base
            staticButtonImage = buttonImage
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

    private func presentBase(
        _ base: NSImage,
        buttonImage: NSImage,
        in button: NSStatusBarButton
    ) {
        button.image = buttonImage
        renderCounters.buttonImageAssignments += 1
        if buttonImage === base {
            templateImagePresenter.clear()
        } else {
            // A non-template footprint lets the colored layer inherit inactive
            // display styling. The separate template still re-tints live (#112).
            templateImagePresenter.display(base, in: button, contentSize: buttonImage.size)
        }
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
        templateImagePresenter.clear()
        staticBase = nil
        staticButtonImage = nil
        provisionalStaticKey = nil
        staticOverlay = nil
        staticOverlayIsPending = false
        baseIsCustomRaster = false
    }

    /// Draws the chromatic overlay above the independent template primitives.
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
        // Restore the independent template and button footprint only after a
        // usable overlay exists. Persistent raster failures stay on the single
        // fallback raster instead of recreating this view on every tick.
        if baseIsCustomRaster, let staticBase, let staticButtonImage {
            presentBase(staticBase, buttonImage: staticButtonImage, in: context.button)
            baseIsCustomRaster = false
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
            phase: phase,
            supersample: 2
        ) else {
            return
        }
        templateImagePresenter.clear()
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
        if settings.keepsPanelOpenWhenOpeningSettings {
            // Keep the panel alive across the key/main handoff to Settings.
            popover.disablesDismissOnResignForTesting = true
        } else {
            popover.performClose(nil)
        }
        openSettings()
    }

    @objc private func handleCheckForUpdates() {
        popover.performClose(nil)
        UpdaterManager.shared.checkForUpdates()
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

    @objc private func handleOpenAppBatterySettings() {
        popover.performClose(nil)
        openAppBatterySettings()
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

    private func handleOpenDisplaySettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.displaySettingsURLs)
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

    /// The Displays pane owns brightness for built-in and external monitors.
    /// Keep the legacy identifier as a fallback for older System Settings
    /// builds; the extension route decides the destination.
    static let displaySettingsURLs = [
        "x-apple.systempreferences:com.apple.Displays-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.displays"
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

    static let locationSettingsURLs = SystemStatusStore.locationSettingsURLs

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

    /// Pops the right-click context menu below the status item (#302).
    ///
    /// The anchor is the button's local bounds, but those bounds can be briefly
    /// wrong during status-item/menu-bar lifecycle churn, which is what pushed
    /// the menu away from the icon every so often. Validate the same screen rect
    /// the panel path uses and, when it is unusable, retry on the next run-loop
    /// turn instead of popping at the stale position.
    private func showMenu(attempt: Int = 0) {
        let screens = NSScreen.screens.map {
            StatusPanelShortcutScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let decision = StatusMenuPresentationPolicy.decision(
            menuBarRect: visibleMenuBarAnchor()?.screenRect,
            isStatusItemVisible: isStatusItemVisible,
            screens: screens,
            attempt: attempt
        )
        guard decision == .present else {
            DispatchQueue.main.async { [weak self] in
                self?.showMenu(attempt: attempt + 1)
            }
            return
        }

        let menu = StatusMenuBuilder.makeMenu(
            version: Self.appVersion,
            settingsTarget: self,
            settingsAction: #selector(handleOpenSettings),
            localization: localization,
            updateTarget: self,
            updateAction: #selector(handleCheckForUpdates)
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
