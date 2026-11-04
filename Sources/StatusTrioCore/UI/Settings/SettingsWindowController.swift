import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let chargingEffectClock: ChargingEffectClock
    private let localization: Localization
    private let inputSourceController: InputSourceController
    private let globalShortcutController: GlobalShortcutController?
    private let chargeToFullNow: ChargeToFullNowController?
    private let activationPolicy: AppActivationPolicy
    private let showIconGuide: () -> Void
    private let backgroundUITesting: BackgroundUITestingConfiguration
    private let presentWindow: @MainActor (NSWindow, SettingsWindowPresentation) -> Void
    private var localizationCancellable: AnyCancellable?
    private var authorizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var previewVisibilityObserver: ((Bool) -> Void)?
    private var isPreviewWindowVisible = false
    /// Track the published initial state as well as subsequent updates, so a
    /// refresh of an already-known grant is not mistaken for a permission decision.
    private var lastBluetoothAuthorization: BluetoothAuthorizationStatus
    /// The sidebar tab a panel action asked for. Kept until `SettingsView`
    /// takes it, because the first presentation posts its notification before
    /// the SwiftUI view necessarily exists.
    private var pendingSection: SettingsView.Section?

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        showIconGuide: @escaping () -> Void,
        chargingEffectClock: ChargingEffectClock = ChargingEffectClock(),
        inputSourceController: InputSourceController? = nil,
        globalShortcutController: GlobalShortcutController? = nil,
        chargeToFullNow: ChargeToFullNowController? = nil,
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
        presentWindow: @escaping @MainActor (NSWindow, SettingsWindowPresentation) -> Void = {
            window, mode in mode.present(window)
        }
    ) {
        self.store = store
        self.statusStore = statusStore
        self.chargingEffectClock = chargingEffectClock
        self.localization = localization
        self.inputSourceController = inputSourceController ?? InputSourceController()
        self.globalShortcutController = globalShortcutController
        self.chargeToFullNow = chargeToFullNow
        self.activationPolicy = activationPolicy
        self.showIconGuide = showIconGuide
        self.backgroundUITesting = backgroundUITesting
        self.presentWindow = presentWindow
        self.lastBluetoothAuthorization = statusStore.bluetoothDevices.authorizationStatus
        super.init(window: nil)

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLocalization(language: language)
            }

        // A system Bluetooth permission prompt steals focus and can dismiss or
        // background this window. Once the user decides, bring Settings back so
        // they land where they were instead of hunting for the window.
        authorizationCancellable = statusStore.bluetoothDevices.$authorizationStatus
            .dropFirst()
            .sink { [weak self] status in
                guard let self else { return }
                let wasUndetermined = self.lastBluetoothAuthorization == .notDetermined
                self.lastBluetoothAuthorization = status
                if wasUndetermined, status != .notDetermined {
                    self.resurface()
                }
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startPreviewResourceObservation(_ observer: @escaping (Bool) -> Void) {
        guard previewVisibilityObserver == nil else { return }
        previewVisibilityObserver = observer
        observer(isPreviewWindowVisible)
    }

    func stopPreviewResourceObservation() {
        guard previewVisibilityObserver != nil else { return }
        previewVisibilityObserver = nil
    }

    func show() {
        show(section: nil)
    }

    /// Shows the window and, when requested, reveals one sidebar tab. The
    /// status panel uses this to open the app's own battery settings.
    func show(section: SettingsView.Section?) {
        if let section {
            pendingSection = section
        }
        dockActivationLogger.notice("Settings.show existing=\(self.window != nil)")
        let window = window ?? makeWindow()
        self.window = window
        statusStore.setSettingsVisible(true)
        applyLocalization()
        if !backgroundUITesting.isEnabled {
            enterActivationPolicyIfNeeded()
        } else {
            BackgroundUIWindowPlacement.position(window, display: backgroundUITesting.display)
        }
        // The user may have approved the power helper in System Settings since
        // the last look; refresh so the toggle and its approval note are current.
        PrivilegedHelperManager.shared.refresh()
        presentWindow(window, backgroundUITesting.isEnabled ? .background : .activating)
        if backgroundUITesting.isEnabled {
            let displayID = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber)?.uint32Value ?? 0
            dockActivationLogger.notice(
                """
                Settings.background requestedDisplay=\(self.backgroundUITesting.display.rawValue, privacy: .public) \
                displayID=\(displayID) \(dockActivationFocusSnapshot(window: window), privacy: .public)
                """
            )
        }
        setPreviewWindowVisible(true)
        if pendingSection != nil {
            NotificationCenter.default.post(name: .settingsSelectSection, object: nil)
        }
    }

    /// Called by `SettingsView` on appear and when the tab notification fires.
    func takePendingSection() -> SettingsView.Section? {
        defer { pendingSection = nil }
        return pendingSection
    }

    func windowWillClose(_ notification: Notification) {
        globalShortcutController?.endRecording()
        statusStore.setSettingsVisible(false)
        leaveActivationPolicyIfNeeded()
        setPreviewWindowVisible(false)
        window = nil
    }

    /// Re-fronts an existing Settings window after a system permission dialog.
    /// Reading Bluetooth authorization for the first popover also publishes a
    /// transition from `.notDetermined`; it must never create a Settings window
    /// or reopen one the user has closed.
    func resurface() {
        guard let window else { return }
        guard !backgroundUITesting.isEnabled else {
            dockActivationLogger.notice("Settings.resurface suppressed for background UI testing")
            return
        }
        // Opening the status panel can publish the first authorization read.
        // Settings must not steal that user interaction or dismiss its panel.
        guard !statusStore.isPopoverVisible else {
            dockActivationLogger.notice("Settings.resurface suppressed while status popover is visible")
            return
        }
        dockActivationLogger.notice("Settings.resurface existing=true")
        presentWindow(window, .activating)
        setPreviewWindowVisible(true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        dockActivationLogger.notice(
            """
            Settings became key popoverVisible=\(self.statusStore.isPopoverVisible) \
            \(dockActivationFocusSnapshot(window: self.window), privacy: .public)
            """
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        dockActivationLogger.notice(
            """
            Settings resigned key popoverVisible=\(self.statusStore.isPopoverVisible) \
            \(dockActivationFocusSnapshot(window: self.window), privacy: .public)
            """
        )
    }

    private func makeWindow() -> NSWindow {
        let contentSize = NSSize(width: SettingsView.width, height: SettingsView.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let rootView = LocalizedRootView(localization: localization) {
            SettingsView(
                store: store,
                statusStore: statusStore,
                localization: localization,
                inputSourceController: inputSourceController,
                globalShortcutController: globalShortcutController,
                chargeToFullNow: chargeToFullNow,
                onShowIconGuide: showIconGuide,
                consumePendingSection: { [weak self] in self?.takePendingSection() }
            )
            .environmentObject(chargingEffectClock)
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        if !backgroundUITesting.isEnabled {
            window.setFrameAutosaveName("SettingsWindow.Sidebar.v1")
        }
        window.center()
        window.setContentSize(contentSize)
        return window
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.settingsTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
    }

    private func enterActivationPolicyIfNeeded() {
        guard !ownsActivationPolicy else { return }
        ownsActivationPolicy = true
        activationPolicy.enterTemporaryRegularMode()
    }

    private func leaveActivationPolicyIfNeeded() {
        guard ownsActivationPolicy else { return }
        ownsActivationPolicy = false
        activationPolicy.leaveTemporaryRegularMode()
    }

    private func setPreviewWindowVisible(_ visible: Bool) {
        guard isPreviewWindowVisible != visible else { return }
        isPreviewWindowVisible = visible
        previewVisibilityObserver?(visible)
    }
}

extension Notification.Name {
    /// Set by the status panel when it needs the Settings window to reveal a
    /// particular sidebar tab (for example the app's own battery settings).
    static let settingsSelectSection = Notification.Name(
        "StatusTrio.settingsSelectSection"
    )
}
