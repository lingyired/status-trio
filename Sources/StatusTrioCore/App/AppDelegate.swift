import AppKit
import os

private let singleInstanceLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "SingleInstance"
)

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var singleInstanceGuard: SingleInstanceGuard?
    private let environmentFactory: @MainActor () -> AppEnvironment
    private let shouldAcquireSingleInstanceGuard: Bool

    public override init() {
        environmentFactory = { AppEnvironment.live() }
        shouldAcquireSingleInstanceGuard = true
        super.init()
    }

    init(
        environmentFactory: @escaping @MainActor () -> AppEnvironment,
        acquireSingleInstanceGuard: Bool = true
    ) {
        self.environmentFactory = environmentFactory
        self.shouldAcquireSingleInstanceGuard = acquireSingleInstanceGuard
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if shouldAcquireSingleInstanceGuard {
            switch SingleInstanceGuard.acquire() {
            case .acquired(let guardInstance):
                self.singleInstanceGuard = guardInstance
            case .rejected(let rejection):
                reportSingleInstanceRejection(rejection)
                NSApplication.shared.terminate(nil)
                return
            }
        }

        let environment = environmentFactory()
        self.environment = environment
        environment.start()
    }

    /// Keeps "another copy is running" and "the lock is unusable" apart in the
    /// log. Both end the launch: running a second instance is never the
    /// fallback.
    private func reportSingleInstanceRejection(_ rejection: SingleInstanceGuard.Rejection) {
        switch rejection {
        case .alreadyRunning:
            singleInstanceLogger.notice(
                "another StatusTrio instance holds the lock; terminating"
            )
        case .lockUnavailable(let reason):
            singleInstanceLogger.error(
                "single-instance lock is unusable, terminating: \(reason, privacy: .public)"
            )
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let environment else { return false }

        let event = AppleEventSenderResolver.currentActivation()
        let placement = environment.settings.appIconPlacement
        let action = DockActivationAction.resolve(
            isReopenEvent: event.kind == .reopen,
            sender: event.sender,
            showsPersistentDockIcon: placement.showsDockIcon
        )
        let settingsWindow = environment.settingsWindowController.window
        dockActivationLogger.notice(
            """
            reopen callback event=\(event.kind.rawValue, privacy: .public) \
            class=\(event.eventClass ?? 0) id=\(event.eventID ?? 0) \
            sender=\(event.senderBundleIdentifier ?? "Unknown", privacy: .public) \
            senderPID=\(event.senderPID ?? 0) \
            placement=\(placement.rawValue, privacy: .public) \
            policy=\(sender.activationPolicy().rawValue) hasVisibleWindows=\(flag) \
            settingsExists=\(settingsWindow != nil) settingsVisible=\(settingsWindow?.isVisible ?? false) \
            settingsKey=\(settingsWindow?.isKeyWindow ?? false) action=\(action.rawValue, privacy: .public)
            """
        )
        switch action {
        case .showPopover:
            environment.statusBarController.togglePopover(
                anchoredAtScreenPoint: NSEvent.mouseLocation
            )
        case .openSettings:
            environment.settingsWindowController.show()
        case .none:
            break
        }
        // The selected action owns presentation; AppKit must not also restore
        // an existing Settings window through its default reopen behavior.
        return false
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let environment else { return nil }

        return AppDockMenu.make(
            localization: environment.localization,
            target: self,
            action: #selector(handleDockMenuSettings)
        )
    }

    @objc private func handleDockMenuSettings() {
        environment?.settingsWindowController.show()
    }
}
