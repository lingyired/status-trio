import Foundation

/// Lifecycle boundaries for accessory battery change notifications.
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
