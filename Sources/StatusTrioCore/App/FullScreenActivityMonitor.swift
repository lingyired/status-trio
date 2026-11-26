import AppKit

/// Watches for the end of another app's full-screen session so the updater can
/// re-run the background check it postponed.
///
/// macOS exposes no notification for "a full-screen app released the screen",
/// but every transition out of a full-screen Space accompanies a Space change,
/// an app activation or a display-parameter change. Each of those fires a
/// single debounced re-probe instead of a timer loop, so the app stays at rest
/// while nothing changes.
@MainActor
final class FullScreenActivityMonitor {
    struct Timing {
        let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static func live() -> Timing {
            Timing(schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Task { @MainActor in action() }
                }
            })
        }
    }

    private struct Registration {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private let probe: @MainActor () -> Bool
    private let workspaceNotificationCenter: NotificationCenter
    private let defaultNotificationCenter: NotificationCenter
    private let reevaluationDelay: TimeInterval
    private let timing: Timing

    private var registrations: [Registration] = []
    private var isReevaluationScheduled = false

    private(set) var isFullScreenActive = false
    var onExitFullScreen: (() -> Void)?

    init(
        probe: @escaping @MainActor () -> Bool = { FullScreenActivity.isActive() },
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        defaultNotificationCenter: NotificationCenter = .default,
        reevaluationDelay: TimeInterval = 0.6,
        timing: Timing = .live()
    ) {
        self.probe = probe
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.defaultNotificationCenter = defaultNotificationCenter
        self.reevaluationDelay = reevaluationDelay
        self.timing = timing
    }

    func start() {
        guard registrations.isEmpty else { return }
        let registrations: [(NotificationCenter, Notification.Name)] = [
            (workspaceNotificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (workspaceNotificationCenter, NSWorkspace.didActivateApplicationNotification),
            (defaultNotificationCenter, NSApplication.didChangeScreenParametersNotification),
        ]
        self.registrations = registrations.map { center, name in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReevaluation() }
            }
            return Registration(center: center, token: token)
        }
        isFullScreenActive = probe()
    }

    func stop() {
        for registration in registrations {
            registration.center.removeObserver(registration.token)
        }
        registrations.removeAll()
        isReevaluationScheduled = false
    }

    private func scheduleReevaluation() {
        guard !isReevaluationScheduled else { return }
        isReevaluationScheduled = true
        timing.schedule(reevaluationDelay) { [weak self] in
            guard let self else { return }
            self.isReevaluationScheduled = false
            self.reevaluate()
        }
    }

    /// Re-probes immediately. Called by the debounced notification path and
    /// directly by tests so the transition logic is deterministic.
    func reevaluate() {
        let next = probe()
        guard next != isFullScreenActive else { return }
        let wasFullScreen = isFullScreenActive
        isFullScreenActive = next
        if wasFullScreen && !next {
            onExitFullScreen?()
        }
    }
}
