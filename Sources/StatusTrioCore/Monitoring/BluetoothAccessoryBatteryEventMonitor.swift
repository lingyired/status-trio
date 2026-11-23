import Foundation
import notify

/// Accessory battery change notifications.
///
/// `notify(3)` is a public libSystem mechanism; only the key names are Apple's
/// own. The power manager posts them when an accessory's capacity, its power
/// source, or the set of attached accessories changes, which is the moment a
/// level is worth re-reading — long before the safety-net poll would reach it.
///
/// The callbacks are delivered on the queue the registration was made with, so
/// the implementation is nonisolated and lock-guarded, and the controller hops
/// to the main actor inside the handler it passes in. That is the same shape the
/// IOBluetooth connect monitor uses.
protocol BluetoothAccessoryBatteryEventMonitoring: AnyObject {
    /// Registers for accessory notifications and hands back whether the system
    /// accepted any registration. A `false` result leaves the safety-net poll as
    /// the only source of battery state.
    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

/// A registration handed back by the notification centre. `cancel()` is the only
/// thing that invalidates it, so keeping the handle abstract lets the lifetime
/// bookkeeping be tested with counted fakes instead of the system's notification
/// centre.
protocol AccessoryBatteryEventToken: AnyObject {
    func cancel()
}

final class AccessoryPowerNotifyEventMonitor: BluetoothAccessoryBatteryEventMonitoring, @unchecked Sendable {
    /// What registers one key. Injected so a test can drive the bookkeeping
    /// without touching the system's notification centre, the way the
    /// IOBluetooth monitor separates its registration step.
    typealias KeyRegistrar = @Sendable (String, @escaping @Sendable () -> Void) -> (any AccessoryBatteryEventToken)?

    /// The keys the power manager posts on. Capacity and time remaining move
    /// together, so one registration covers both, and the attach key is what
    /// covers an accessory that appears already carrying a level.
    static let notificationKeys = [
        "com.apple.system.accpowersources.timeremaining",
        "com.apple.system.accpowersources.attach"
    ]

    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var tokens: [any AccessoryBatteryEventToken] = []
    private let register: KeyRegistrar

    init(register: KeyRegistrar? = nil) {
        let queue = DispatchQueue(label: "StatusTrio.AccessoryPowerNotifyEventMonitor")
        self.register = register ?? { key, handler in
            var token: Int32 = 0
            let status = key.withCString { name in
                notify_register_dispatch(name, &token, queue) { _ in handler() }
            }
            guard status == NOTIFY_STATUS_OK else { return nil }
            return NotifyBatteryEventToken(token: token)
        }
    }

    /// Registers every key, and answers `false` only when the system refused all
    /// of them. A key the system accepts but never posts is not a failure: the
    /// handler simply never runs, and the safety-net poll still carries the
    /// levels.
    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { self.handler = handler }
        let registered = Self.notificationKeys.compactMap { key in
            register(key) { [weak self] in self?.deliver() }
        }
        // A registration displaced by a repeated `start` is cancelled, not just
        // dropped: `notify_cancel` is the only thing that invalidates it, so
        // clearing the entry alone would leave the callback armed.
        let displaced = lock.withLock { () -> [any AccessoryBatteryEventToken] in
            let displaced = tokens
            tokens = registered
            return displaced
        }
        for token in displaced {
            token.cancel()
        }
        return !registered.isEmpty
    }

    func stop() {
        let tokens = lock.withLock { () -> [any AccessoryBatteryEventToken] in
            let tokens = self.tokens
            self.tokens = []
            self.handler = nil
            return tokens
        }
        // Cancelled outside the lock: `notify_cancel` is a system call, and
        // holding the lock across it would let a notification callback that is
        // already running deadlock against teardown.
        for token in tokens {
            token.cancel()
        }
    }

    /// Whether the system accepted a registration.
    var isRegistered: Bool {
        lock.withLock { !tokens.isEmpty }
    }

    private func deliver() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

/// One `notify(3)` registration. `notify_cancel` is what invalidates it, so
/// dropping the last reference to one would leave the callback armed.
private final class NotifyBatteryEventToken: AccessoryBatteryEventToken, @unchecked Sendable {
    private let token: Int32

    init(token: Int32) {
        self.token = token
    }

    func cancel() {
        notify_cancel(token)
    }
}
