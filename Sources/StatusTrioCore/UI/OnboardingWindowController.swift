import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(
        width: IconGuideOnboardingView.contentWidth,
        height: 700
    )

    private let settings: SettingsStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private let distributionChannel: DistributionChannel
    private let systemIconAppearance: () -> SystemIconAppearanceTheme
    private var localizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var previewVisibilityObserver: ((Bool) -> Void)?
    private var isPreviewWindowVisible = false
    var openSettings: (() -> Void)?

    init(
        settings: SettingsStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        distributionChannel: DistributionChannel = .current,
        systemIconAppearance: @escaping () -> SystemIconAppearanceTheme = {
            .default
        }
    ) {
        self.settings = settings
        self.localization = localization
        self.activationPolicy = activationPolicy
        self.distributionChannel = distributionChannel
        self.systemIconAppearance = systemIconAppearance
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

    func startPreviewResourceObservation(_ observer: @escaping (Bool) -> Void) {
        guard previewVisibilityObserver == nil else { return }
        previewVisibilityObserver = observer
        observer(isPreviewWindowVisible)
    }

    func stopPreviewResourceObservation() {
        guard previewVisibilityObserver != nil else { return }
        previewVisibilityObserver = nil
    }

    func showIfNeeded() {
        guard IconGuideOnboardingPolicy.shouldPresentGuide(
            settings: settings,
            channel: distributionChannel
        ) else { return }
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
        setPreviewWindowVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        leaveActivationPolicyIfNeeded()
        setPreviewWindowVisible(false)
        window?.contentView = nil
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let rootView = LocalizedRootView(localization: localization) {
            IconGuideOnboardingView(
                settings: settings,
                allowsTelemetryConsent: IconGuideOnboardingPolicy.showsTelemetryConsent(
                    settings: settings,
                    channel: distributionChannel
                ),
                onCustomize: { [weak self] in self?.handleCustomize() },
                onDone: { [weak self] in self?.window?.close() }
            )
            .environment(\.systemIconAppearance, systemIconAppearance)
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.contentSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.contentMinSize = NSSize(
            width: IconGuideOnboardingView.contentWidth,
            height: 420
        )
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
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

    private func setPreviewWindowVisible(_ visible: Bool) {
        guard isPreviewWindowVisible != visible else { return }
        isPreviewWindowVisible = visible
        previewVisibilityObserver?(visible)
    }
}
