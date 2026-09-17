import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private var localizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    var openSettings: (() -> Void)?

    init(
        settings: SettingsStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy
    ) {
        self.settings = settings
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

    func showIfNeeded() {
        guard IconGuideOnboardingPolicy.consumeIfNeeded(settings: settings) else { return }
        show()
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
        let contentSize = NSSize(width: 480, height: 360)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let rootView = LocalizedRootView(localization: localization) {
            IconGuideOnboardingView(
                settings: settings,
                onCustomize: { [weak self] in self?.handleCustomize() },
                onDone: { [weak self] in self?.window?.close() }
            )
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.setContentSize(contentSize)
        return window
    }

    private func handleCustomize() {
        window?.close()
        openSettings?()
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.guideTitle, language: language)
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
