import AppKit
import Foundation

/// Owns the AppKit and workspace observers a controller installs, so teardown is
/// one idempotent call. `deinit` is nonisolated, so the bag keeps its
/// registrations in lock-guarded, teardown-owned storage: it never touches
/// actor-isolated state, which is what makes it safe to release from `deinit`.
final class SystemEventObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var registrations: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    var isEmpty: Bool {
        lock.withLock { registrations.isEmpty }
    }

    /// Installs the standard observers plus the optional display-wake one.
    /// Installing again while they are registered is a no-op, so a repeated
    /// `activate()` cannot stack duplicates that only one `removeAll()` would
    /// release.
    func install(
        applicationActivated: @escaping @Sendable () -> Void,
        didWake: @escaping @Sendable () -> Void,
        screensDidWake: (@Sendable () -> Void)? = nil
    ) {
        lock.withLock {
            guard registrations.isEmpty else { return }
            var next = [
                (
                    notificationCenter,
                    notificationCenter.addObserver(
                        forName: NSApplication.didBecomeActiveNotification,
                        object: nil,
                        queue: .main
                    ) { _ in applicationActivated() }
                ),
                (
                    workspaceNotificationCenter,
                    workspaceNotificationCenter.addObserver(
                        forName: NSWorkspace.didWakeNotification,
                        object: nil,
                        queue: .main
                    ) { _ in didWake() }
                )
            ]
            if let screensDidWake {
                next.append(
                    (
                        workspaceNotificationCenter,
                        workspaceNotificationCenter.addObserver(
                            forName: NSWorkspace.screensDidWakeNotification,
                            object: nil,
                            queue: .main
                        ) { _ in screensDidWake() }
                    )
                )
            }
            registrations = next
        }
    }

    func removeAll() {
        let removed = lock.withLock { () -> [(center: NotificationCenter, token: NSObjectProtocol)] in
            let removed = registrations
            registrations = []
            return removed
        }
        for registration in removed {
            registration.center.removeObserver(registration.token)
        }
    }

    /// A bag released without `removeAll()` would otherwise leak the blocks its
    /// tokens keep alive for the life of the process — the exact failure this
    /// type exists to prevent. The registrations live in lock-guarded,
    /// teardown-owned storage, so this stays nonisolated and is safe on
    /// whichever thread drops the last reference. `removeAll()` is idempotent,
    /// so a bag that was already emptied here removes nothing twice.
    deinit {
        removeAll()
    }
}
