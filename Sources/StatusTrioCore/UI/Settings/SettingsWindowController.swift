import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private var localizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy
    ) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        self.activationPolicy = activationPolicy
        super.init(window: nil)

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLocalization(language: language)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyLocalization()
        enterActivationPolicyIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        leaveActivationPolicyIfNeeded()
        window = nil
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
                localization: localization
            )
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
}
