import Foundation
import notify

/// Listens for the system's power-mode notifications that Foundation does not
/// expose.
///
/// `ProcessInfo` only surfaces Low Power Mode (`isLowPowerModeEnabled` and
/// `NSProcessInfoPowerStateDidChange`). High Power Mode shares the same
/// `powermode` switch but has no public reader or notification, so a change made
/// in System Settings or Control Center would otherwise stay invisible until the
/// app re-read it for another reason. `powerd` publishes the unified state on
/// the `com.apple.system.highpowermode` notify key; observing that key turns the
/// change into an event instead of a poll. The key is only a signal — the
/// controller still reads the authoritative value through the helper.
protocol PowerModeNotificationMonitoring: AnyObject, Sendable {
    /// Starts delivering `handler` on the main actor whenever a monitored key
    /// changes. Calling it again while running does nothing.
    func start(handler: @escaping @MainActor () -> Void)
    /// Stops observing and releases every notification token.
    func stop()
}

/// Production monitor backed by `notify_register_dispatch`.
///
/// Not `@MainActor`: the store owns one for the whole process and its
/// `nonisolated` `deinit` must be able to cancel the tokens. `start` is called
/// from the main actor, but `stop` can arrive from any thread; the lock is what
/// keeps the token array from being read while it is emptied, which would
/// otherwise cancel a token twice or leak one.
final class PowerModeNotificationMonitor: PowerModeNotificationMonitoring, @unchecked Sendable {
    static let notificationNames = ["com.apple.system.highpowermode"]

    private let names: [String]
    private let tokenLock = NSLock()
    /// Guarded by `tokenLock`.
    private var tokens: [Int32] = []

    init(names: [String] = PowerModeNotificationMonitor.notificationNames) {
        self.names = names
    }

    func start(handler: @escaping @MainActor () -> Void) {
        // Registration is serialized with `stop`, but the block only queues a
        // main-actor task, so it never takes this lock re-entrantly.
        tokenLock.lock()
        defer { tokenLock.unlock() }
        guard tokens.isEmpty else { return }
        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, DispatchQueue.main) { _ in
                Task { @MainActor in handler() }
            }
            if status == 0 {
                tokens.append(token)
            }
        }
    }

    func stop() {
        let tokens = tokenLock.withLock {
            let tokens = self.tokens
            self.tokens.removeAll()
            return tokens
        }
        for token in tokens {
            notify_cancel(token)
        }
    }
}
