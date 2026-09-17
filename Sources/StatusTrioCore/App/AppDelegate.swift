import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var singleInstanceGuard: SingleInstanceGuard?
    private let updaterManager = UpdaterManager.shared

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let singleInstanceGuard = SingleInstanceGuard() else {
            NSApplication.shared.terminate(nil)
            return
        }
        self.singleInstanceGuard = singleInstanceGuard

        let environment = AppEnvironment.live()
        self.environment = environment
        environment.start()
        updaterManager.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let environment else { return false }

        let pointer = NSEvent.mouseLocation
        switch DockActivationAction.resolve(
            isReopenEvent: currentEventIsReopen(),
            hasDockTile: environment.activationPolicy.isRegularApp,
            isPointerInDockArea: isPointerInDockArea(pointer)
        ) {
        case .showPopover:
            environment.statusBarController.togglePopover(
                anchoredAtScreenPoint: pointer
            )
        case .openSettings:
            environment.settingsWindowController.show()
        case .none:
            break
        }
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

    /// A Dock icon click arrives as a reopen event; a cold launch (including the
    /// login item) does not, and must not pop the status popover open.
    private func currentEventIsReopen() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventClass == AEEventClass(kCoreEventClass)
            && event.eventID == AEEventID(kAEReopenApplication)
    }

    private func isPointerInDockArea(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main else {
            return false
        }
        let placement = DockPlacement.resolve(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        return placement.containsPointer(
            point,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }
}
