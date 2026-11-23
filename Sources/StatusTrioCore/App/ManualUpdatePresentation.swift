import AppKit

@MainActor
protocol ApplicationActivating: AnyObject {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ApplicationActivating {}

/// The app-level presentation a user-initiated update check needs: Sparkle's
/// windows have to come to the front, and that needs the app to own a Dock tile
/// for as long as the update UI is up.
///
/// It borrows regular mode from `AppActivationPolicy` rather than writing
/// `NSApp.activationPolicy` itself. That keeps the policy's single owner — and
/// therefore `isRegularApp` — in sync with AppKit, so a placement that asked for
/// a Dock icon never loses its tile, and a check started from the Settings
/// window nests inside the regular mode that window already holds.
@MainActor
final class ManualUpdatePresentation {
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationActivating
    private var isPresenting = false

    init(
        activationPolicy: AppActivationPolicy,
        application: any ApplicationActivating = NSApplication.shared
    ) {
        self.activationPolicy = activationPolicy
        self.application = application
    }

    func begin() {
        guard !isPresenting else { return }
        isPresenting = true
        activationPolicy.enterTemporaryRegularMode()
        application.activate(ignoringOtherApps: true)
    }

    /// Background checks finish update cycles too, so ending without a matching
    /// `begin()` must leave the activation policy untouched.
    func end() {
        guard isPresenting else { return }
        isPresenting = false
        activationPolicy.leaveTemporaryRegularMode()
    }
}
