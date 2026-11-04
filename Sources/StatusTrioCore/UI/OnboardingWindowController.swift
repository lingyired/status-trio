import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(
        width: IconGuideOnboardingView.contentWidth,
        height: 700
    )
    /// Lower bound keeps a very short localized page from producing a window
    /// too small to read; the upper bound is the initial/default height above.
    static let minimumContentHeight: CGFloat = 420

    private let settings: SettingsStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private let backgroundUITesting: BackgroundUITestingConfiguration
    private let presentWindow: @MainActor (NSWindow, SettingsWindowPresentation) -> Void
    private var localizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var previewVisibilityObserver: ((Bool) -> Void)?
    private var isPreviewWindowVisible = false
    /// Latest content height reported by the guide view, applied on the next
    /// main-runloop turn so we never resize inside SwiftUI's layout pass.
    private var pendingContentHeight: CGFloat?
    /// The largest content height seen since the guide opened. The window grows
    /// to fit a taller page but never shrinks for a shorter one, so switching
    /// steps does not resize (the gallery page is slightly shorter than anatomy).
    private var maximumContentHeight: CGFloat = 0
    private var isContentResizeScheduled = false
    var openSettings: (() -> Void)?

    init(
        settings: SettingsStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
        presentWindow: @escaping @MainActor (NSWindow, SettingsWindowPresentation) -> Void = {
            window, presentation in presentation.present(window)
        }
    ) {
        self.settings = settings
        self.localization = localization
        self.activationPolicy = activationPolicy
        self.backgroundUITesting = backgroundUITesting
        self.presentWindow = presentWindow
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

    @discardableResult
    func showIfNeeded() -> Bool {
        guard IconGuideOnboardingPolicy.shouldPresentGuide(settings: settings) else {
            return false
        }
        show()
        return true
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyLocalization()
        // Let the guide lay out once so its reported content height settles
        // before the first presentation, avoiding a visible resize flash.
        window.contentView?.layoutSubtreeIfNeeded()
        applyPendingContentHeight()
        if !window.isVisible {
            window.center()
        }
        if backgroundUITesting.isEnabled {
            BackgroundUIWindowPlacement.position(window, display: backgroundUITesting.display)
        } else {
            enterActivationPolicyIfNeeded()
        }
        presentWindow(window, backgroundUITesting.isEnabled ? .background : .activating)
        setPreviewWindowVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        leaveActivationPolicyIfNeeded()
        setPreviewWindowVisible(false)
        pendingContentHeight = nil
        maximumContentHeight = 0
        isContentResizeScheduled = false
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
                onCustomize: { [weak self] in self?.handleCustomize() },
                onDone: { [weak self] in self?.window?.close() },
                onContentHeightChange: { [weak self] height in
                    self?.handleContentHeightChange(height)
                }
            )
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
            height: Self.minimumContentHeight
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

    /// Resizes the window to the guide's intrinsic content height. Scheduled on
    /// the next main-runloop turn so the window is never mutated during
    /// SwiftUI's layout/preference pass (the path that recursed on Ventura).
    private func handleContentHeightChange(_ height: CGFloat) {
        guard height > 0 else { return }
        pendingContentHeight = height
        guard !isContentResizeScheduled else { return }
        isContentResizeScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isContentResizeScheduled = false
            self.applyPendingContentHeight()
        }
    }

    private func applyPendingContentHeight() {
        guard let window, let height = pendingContentHeight else { return }
        maximumContentHeight = max(maximumContentHeight, height)
        var target = maximumContentHeight
        if let screen = window.screen ?? NSScreen.main {
            // Leave room for the menu bar and Dock so the window is never
            // taller than the usable screen.
            target = min(target, screen.visibleFrame.height - 40)
        }
        target = max(target, Self.minimumContentHeight)
        let currentHeight = window.contentRect(forFrameRect: window.frame).height
        guard abs(currentHeight - target) > 0.5 else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: Self.contentSize.width, height: target))
        window.setFrameOrigin(
            NSPoint(x: window.frame.origin.x, y: top - window.frame.height)
        )
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        maximumContentHeight = 0
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
