import AppKit
import CoreGraphics

@MainActor
protocol DockVisibilityMonitoring: AnyObject {
    var isDockVisible: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
}

/// Probes the Dock window's compositor state when the shared system-appearance
/// poll fires because macOS has no public visibility notification.
@MainActor
final class DockVisibilityMonitor: DockVisibilityMonitoring {
    private let probe: @MainActor () -> Bool
    private var isMonitoring = false

    private(set) var isDockVisible = true
    var onChange: ((Bool) -> Void)?

    init(
        probe: @escaping @MainActor () -> Bool = {
            DockVisibilityMonitor.liveVisibility()
        }
    ) {
        self.probe = probe
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()
    }

    func stop() {
        isMonitoring = false
        // A stopped monitor must not leave the Dock permanently considered
        // hidden. The next start performs a fresh probe immediately.
        isDockVisible = true
    }

    func refresh() {
        guard isMonitoring else { return }
        let nextValue = probe()
        guard nextValue != isDockVisible else { return }
        isDockVisible = nextValue
        onChange?(nextValue)
    }

    static func liveVisibility() -> Bool {
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
        else {
            return true
        }
        let onScreenWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        if !dockWindows(in: onScreenWindows, dockPID: dockPID).isEmpty {
            return true
        }
        let allWindows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return isDockVisible(
            in: allWindows,
            onScreenWindows: onScreenWindows,
            dockPID: dockPID
        )
    }

    static func isDockVisible(
        in allWindows: [[String: Any]],
        onScreenWindows: [[String: Any]],
        dockPID: pid_t
    ) -> Bool {
        let allDockWindows = dockWindows(in: allWindows, dockPID: dockPID)
        guard !allDockWindows.isEmpty else {
            // Window metadata can be unavailable in restricted environments.
            // Fail open so the animation is not silently disabled.
            return true
        }
        return !dockWindows(in: onScreenWindows, dockPID: dockPID).isEmpty
    }

    private static func dockWindows(
        in windows: [[String: Any]],
        dockPID: pid_t
    ) -> [[String: Any]] {
        let dockWindowLevel = Int(CGWindowLevelForKey(.dockWindow))
        return windows.filter { window in
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let level = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
            return ownerPID == dockPID && level == dockWindowLevel
        }
    }
}
