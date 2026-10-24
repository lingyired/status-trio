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
    private let helper: PrivilegedHelperFacade
    private let updaterManager: UpdateStateFacade
    var platformServicesForTesting: (updater: UpdateStateFacade, helper: PrivilegedHelperFacade) {
        (updaterManager, helper)
    }
    var distributionCapabilityPolicyForTesting: DistributionCapabilityPolicy {
        capabilityPolicy
    }
    private let capabilityPolicy: DistributionCapabilityPolicy
    private let activationPolicy: AppActivationPolicy
    private let showIconGuide: () -> Void
    private var localizationCancellable: AnyCancellable?
    private var authorizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var previewVisibilityObserver: ((Bool) -> Void)?
    private var isPreviewWindowVisible = false
    /// Track the published initial state as well as subsequent updates, so a
    /// refresh of an already-known grant is not mistaken for a permission decision.
    private var lastBluetoothAuthorization: BluetoothAuthorizationStatus

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        showIconGuide: @escaping () -> Void,
        chargingEffectClock: ChargingEffectClock = ChargingEffectClock(),
        inputSourceController: InputSourceController? = nil,
        globalShortcutController: GlobalShortcutController? = nil,
        helper: PrivilegedHelperFacade = PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService()),
        updaterManager: UpdateStateFacade = UpdateStateFacade(service: SystemManagedUpdateService()),
        capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    ) {
        self.store = store
        self.statusStore = statusStore
        self.chargingEffectClock = chargingEffectClock
        self.localization = localization
        self.inputSourceController = inputSourceController ?? InputSourceController()
        self.globalShortcutController = globalShortcutController
        self.helper = helper
        self.updaterManager = updaterManager
        self.capabilityPolicy = capabilityPolicy
        self.activationPolicy = activationPolicy
        self.showIconGuide = showIconGuide
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
        dockActivationLogger.notice("Settings.show existing=\(self.window != nil)")
        let window = window ?? makeWindow()
        self.window = window
        statusStore.setSettingsVisible(true)
        applyLocalization()
        enterActivationPolicyIfNeeded()
        // The user may have approved the power helper in System Settings since
        // the last look; refresh so the toggle and its approval note are current.
        if !capabilityPolicy.blocksControl(.privilegedHelper) {
            helper.refresh()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        setPreviewWindowVisible(true)
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
        // Opening the status panel can publish the first authorization read.
        // Settings must not steal that user interaction or dismiss its panel.
        guard !statusStore.isPopoverVisible else {
            dockActivationLogger.notice("Settings.resurface suppressed while status popover is visible")
            return
        }
        dockActivationLogger.notice("Settings.resurface existing=true")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
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
                updaterManager: updaterManager,
                helper: helper,
                capabilityPolicy: capabilityPolicy,
                onShowIconGuide: showIconGuide
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
        window.setFrameAutosaveName("SettingsWindow.Sidebar.v1")
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
