import AppKit
import Combine
import SwiftUI

private struct UncheckedSendableNSEvent: @unchecked Sendable {
    let event: NSEvent
}

private struct StatusBarAccessibilityKey: Equatable {
    let status: MenuBarStatus
    let language: AppLanguage
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let iconSnapshotDebounceInterval: TimeInterval = 0.5
    static let popoverToggleLockoutInterval: TimeInterval = 0.25
    static let popoverContentReleaseDelay: TimeInterval = 60

    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let localization: Localization
    private let batteryActionLauncher = BatteryActionLauncher()
    let chargingEffectClock: ChargingEffectClock
    private var cancellable: AnyCancellable?
    private var localizationCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var chargingEffectCancellable: AnyCancellable?
    private var currentChargingEffectPhase: ChargingEffectPhase?
    private var testsChargingEffect: Bool
    private var chargingEffectTestCancellable: AnyCancellable?
    private var screenParametersCancellable: AnyCancellable?
    private var refreshIntervalCancellable: AnyCancellable?
    private let openSettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []
    private var renderCache = StatusBarRenderCache()
    private let chargingFrameCache = StatusBarChargingFrameCache()
    private let animationLayerPresenter = StatusBarAnimationLayerPresenter()
    private let renderCoalescer = IconRenderCoalescer()
    var cachedChargingFrameCount: Int { chargingFrameCache.frameCount }
    var hasLayerBackedAnimation: Bool { animationLayerPresenter.isInstalled }
    private var isStatusItemVisible: Bool
    private var accessibilityKey: StatusBarAccessibilityKey?
    private var popoverDismissMonitor: Any?
    private var volumeScrollMonitor: Any?
    private let volumeScrollAdjustment = PopupVolumeScrollAdjustment()
    private var volumeScrollSession = PopupVolumeScrollSession()
    private let popoverScrollTargets = PopoverScrollTargets()
    private var dockAnchorWindow: NSWindow?
    private var popoverToggleGate = PopoverToggleGate(
        lockout: StatusBarController.popoverToggleLockoutInterval
    )
    private var popoverContentRetention = PopoverContentRetention(
        releaseDelay: StatusBarController.popoverContentReleaseDelay
    )
    private var popoverContentReleaseTask: Task<Void, Never>?

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        isVisible: Bool = true,
        openSettings: @escaping () -> Void,
        quitAction: @escaping () -> Void,
        chargingEffectClock: ChargingEffectClock = ChargingEffectClock()
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.chargingEffectClock = chargingEffectClock
        self.openSettings = openSettings
        self.quitAction = quitAction
        self.isStatusItemVisible = isVisible
        self.testsChargingEffect = settings.testsChargingEffect
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.isVisible = isVisible
        configureButton()
        configurePopover()
        observeAppearanceChanges()
        scheduleInitialRender()

        cancellable = store.$snapshot
            .map { MenuBarStatus(snapshot: $0) }
            .removeDuplicates()
            .dropFirst()
            .debounce(
                for: .seconds(Self.iconSnapshotDebounceInterval),
                scheduler: RunLoop.main
            )
            .sink { [weak self] _ in
                self?.renderLatestSnapshot()
            }

        // One subscription carries every icon option. Adding a setting to
        // `SettingsStore.iconAppearancePublisher` is enough to reach the menu
        // bar; the scattered subscriptions this replaced could silently miss
        // one, and the icon then stayed stale until the next status poll.
        appearanceCancellable = settings.iconAppearancePublisher
            .dropFirst()
            .sink { [weak self] appearance in
                guard let self else { return }
                self.renderCoalescer.submit { [weak self] in
                    guard let self else { return }
                    self.render(
                        appearance,
                        status: MenuBarStatus(snapshot: self.store.snapshot),
                        phase: currentChargingEffectPhase
                    )
                }
            }

        chargingEffectCancellable = chargingEffectClock.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.renderAnimationPhase(phase)
            }

        chargingEffectTestCancellable = settings.$testsChargingEffect
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                testsChargingEffect = enabled
                renderLatestSnapshot()
            }

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderLatestSnapshot()
                }
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
            self?.renderLatestSnapshot()
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
            renderCache = StatusBarRenderCache()
            renderLatestSnapshot()
        } else {
            clearAnimationPresentation()
            popover.performClose(nil)
            store.setPopoverVisible(false)
            statusItem.isVisible = false
        }
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
                self?.renderLatestSnapshot()
            }
        })
    }

    private func scheduleInitialRender() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.renderLatestSnapshot()
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
                store: store,
                settings: settings,
                scrollTargets: popoverScrollTargets,
                requestWiFiNameAccess: { self.handleRequestWiFiNameAccess() },
                requestBluetoothAuthorization: { self.handleRequestBluetoothAuthorization() },
                openBatterySettings: { self.handleOpenBatterySettings() },
                openWiFiSettings: { self.handleOpenWiFiSettings() },
                openNetworkSettings: { self.handleOpenNetworkSettings() },
                openLocationSettings: { self.handleOpenLocationSettings() },
                openBluetoothSettings: { self.handleOpenBluetoothSettings() },
                openBluetoothPermissionSettings: { self.handleOpenBluetoothPermissionSettings() },
                openSettings: { self.handleOpenSettings() },
                openSoundSettings: { self.handleOpenSoundSettings() },
                quit: quitAction
            )
        }
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func togglePopover() {
        guard popoverToggleGate.shouldAccept(at: Date()) else { return }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            presentPopover(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    /// Shows the same popover for a Dock icon click, above the clicked icon.
    func togglePopover(anchoredAtScreenPoint point: NSPoint) {
        guard popoverToggleGate.shouldAccept(at: Date()) else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let anchor = dockAnchor(at: point)
        presentPopover(
            relativeTo: anchor.view.bounds,
            of: anchor.view,
            preferredEdge: anchor.preferredEdge
        )
    }

    private func presentPopover(
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge
    ) {
        cancelPopoverContentRelease()
        popoverContentRetention.markOpened()
        store.setPopoverVisible(true)
        installPopoverContentIfNeeded()
        // Activate first: a transient popover shown while the app is still
        // inactive can be dismissed again straight away.
        // Status-item clicks come from the system menu bar process, so the
        // modern activate() can be ignored by the user-activation policy.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        // The popover's backing window only exists once it has been shown, and
        // without a Spaces behavior it stays on this app's desktop Space while
        // another app is full-screen.
        popover.contentViewController?.view.window?.enableDisplayOnFullScreenSpaces()
        popover.contentViewController?.view.window?.makeKey()
        installPopoverDismissMonitor()
        installVolumeScrollMonitor()
    }

    /// The Dock icon has no public frame, but the click happens on the icon, so
    /// a tiny invisible window at the click point anchors the popover there.
    private func dockAnchor(at point: NSPoint) -> (view: NSView, preferredEdge: NSRectEdge) {
        let window: NSWindow
        if let dockAnchorWindow {
            window = dockAnchorWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            dockAnchorWindow = window
        }

        let anchor = DockPopoverAnchor.make(
            clickPoint: point,
            tileSize: NSApplication.shared.dockTile.size,
            placement: dockPlacement(at: point)
        )
        window.setFrameOrigin(anchor.origin)
        window.orderFront(nil)
        let view = window.contentView ?? window.contentViewController?.view ?? NSView()
        return (view, anchor.preferredEdge)
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
        removePopoverDismissMonitor()
        removeVolumeScrollMonitor()
        // Read this before closing the popover: a detail panel keeps its own
        // SwiftUI state, so reusing the built content would reopen on that
        // panel. The battery page also clears its collector on disappear, so
        // the flag has to be sampled while the panel is still open.
        let hadOpenDetails = store.hasOpenPopoverPanel
        store.setPopoverVisible(false)
        store.closePopoverDetails()
        if hadOpenDetails {
            cancelPopoverContentRelease()
            popover.contentViewController = nil
        } else {
            schedulePopoverContentRelease()
        }
    }

    /// Keeping the built content for a while makes rapid reopen cheap; releasing
    /// it later keeps idle memory low.
    private func schedulePopoverContentRelease() {
        cancelPopoverContentRelease()
        popoverContentRetention.markClosed(at: Date())
        let delay = Self.popoverContentReleaseDelay
        popoverContentReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard popoverContentRetention.shouldRelease(at: Date()), !popover.isShown else { return }
            popover.contentViewController = nil
            popoverContentReleaseTask = nil
        }
    }

    private func cancelPopoverContentRelease() {
        popoverContentReleaseTask?.cancel()
        popoverContentReleaseTask = nil
        popoverContentRetention.markOpened()
    }

    private func render(
        _ appearance: StatusIconAppearance,
        status: MenuBarStatus,
        phase: ChargingEffectPhase?
    ) {
        guard isStatusItemVisible, let button = statusItem.button else { return }

        let status = ChargingEffectTestMode.status(status, enabled: testsChargingEffect)

        if phase == nil {
            clearAnimationPresentation()
        }
        let backingScale =
            button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        let key = StatusBarRenderKey(
            status: status,
            iconSize: appearance.iconSize,
            options: appearance.batteryOptions,
            connectionOptions: appearance.connectionOptions,
            volumeOptions: appearance.volumeOptions,
            bluetoothAudioOptions: appearance.bluetoothAudioOptions,
            appearanceName: button.effectiveAppearance.name.rawValue,
            phase: phase
        )
        if let phase, phase.kind == .steady,
            chargingFrameCache.needsFrames(for: phase, key: key, backingScale: backingScale)
        {
            // A backing-scale change is not in the existing render key. Reset on
            // any frame-set rebuild so the current phase is displayed immediately.
            renderCache = StatusBarRenderCache()
        }
        guard renderCache.shouldRender(key) else { return }

        if let phase, phase.kind == .steady,
            let cachedImage = chargingFrameCache.image(
                for: phase,
                key: key,
                backingScale: backingScale,
                renderFrame: { framePhase in
                    StatusIconRenderer.preRenderedMenuBarImage(
                        menuBarStatus: status,
                        size: appearance.iconSize,
                        scale: backingScale,
                        appearance: button.effectiveAppearance,
                        phase: framePhase,
                        options: appearance.batteryOptions,
                        connectionOptions: appearance.connectionOptions,
                        volumeOptions: appearance.volumeOptions,
                        bluetoothAudioOptions: appearance.bluetoothAudioOptions
                    )
                }
            )
        {
            presentCachedAnimationFrame(
                cachedImage,
                button: button,
                iconSize: appearance.iconSize,
                backingScale: backingScale
            )
        } else {
            animationLayerPresenter.clear()
            button.image = StatusIconRenderer.image(
                menuBarStatus: status,
                size: appearance.iconSize,
                options: appearance.batteryOptions,
                connectionOptions: appearance.connectionOptions,
                volumeOptions: appearance.volumeOptions,
                bluetoothAudioOptions: appearance.bluetoothAudioOptions,
                phase: phase
            )
        }

        let nextAccessibilityKey = StatusBarAccessibilityKey(
            status: status,
            language: localization.resolvedLanguage
        )
        guard nextAccessibilityKey != accessibilityKey else { return }
        accessibilityKey = nextAccessibilityKey
        button.setAccessibilityLabel(StatusPresentation.statusItemAccessibilityLabel)
        button.setAccessibilityValue(
            StatusPresentation.statusItemAccessibilityValue(
                status,
                localization: localization
            )
        )
    }

    private func clearAnimationPresentation() {
        chargingFrameCache.reset()
        animationLayerPresenter.clear()
    }

    private func presentCachedAnimationFrame(
        _ image: NSImage,
        button: NSStatusBarButton,
        iconSize: CGFloat,
        backingScale: CGFloat
    ) {
        guard
            let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ),
            let result = animationLayerPresenter.display(
                cgImage,
                in: button,
                backingScale: backingScale
            )
        else {
            animationLayerPresenter.clear()
            button.image = image
            return
        }

        guard result == .installed else { return }
        guard
            let placeholder = StatusIconRenderer.transparentMenuBarImage(
                size: iconSize,
                scale: backingScale
            )
        else {
            animationLayerPresenter.clear()
            button.image = image
            return
        }
        button.image = placeholder
    }

    /// Clock-driven frames bypass the status/setting coalescer; the menu-bar key
    /// includes every phase so the 20-fps stream cannot be deduplicated as static.
    private func renderAnimationPhase(_ phase: ChargingEffectPhase?) {
        currentChargingEffectPhase = phase
        render(
            StatusIconAppearance(settings: settings),
            status: MenuBarStatus(snapshot: store.snapshot),
            phase: phase
        )
    }

    /// The status, the appearance, and the window's effective appearance all feed
    /// one cached render, so the newest state wins over a redraw that is still
    /// waiting out the coalescing interval.
    private func renderLatestSnapshot() {
        renderCoalescer.submit { [weak self] in
            guard let self else { return }
            self.render(
                StatusIconAppearance(settings: self.settings),
                status: MenuBarStatus(snapshot: self.store.snapshot),
                phase: self.currentChargingEffectPhase
            )
        }
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
        UpdaterManager.shared.checkForUpdates()
    }

    @objc private func handleRequestWiFiNameAccess() {
        popover.performClose(nil)
        NSApp.activate()
        if store.requestWiFiNameAccess() == .openLocationSettings {
            Self.openSystemSettings(Self.locationSettingsURLs)
        }
    }

    @objc private func handleRequestBluetoothAuthorization() {
        NSApp.activate()
        store.requestBluetoothAuthorization()
    }

    @objc private func handleOpenBatterySettings() {
        popover.performClose(nil)
        let target = settings.batteryActionTarget
        Task { @MainActor in
            await batteryActionLauncher.open(target: target) {
                Self.openSystemSettings(Self.batterySettingsURLs)
            }
        }
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

    @objc private func handleOpenSoundSettings() {
        popover.performClose(nil)
        Self.openSystemSoundSettings()
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

    static let bluetoothSettingsURLs = [
        "x-apple.systempreferences:com.apple.BluetoothSettings",
        "x-apple.systempreferences:com.apple.preference.bluetooth"
    ]
    .compactMap(URL.init(string:))

    static let locationSettingsURLs = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    ]
    .compactMap(URL.init(string:))

    private static func openSystemSoundSettings() {
        let soundSettingsURLs = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound"
        ]
        .compactMap(URL.init(string:))

        for url in soundSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }

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
