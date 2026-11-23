import Foundation
import IOBluetooth

/// System-wide Bluetooth connect and disconnect notifications.
///
/// CoreBluetooth only reports `didConnect` for peripherals this process
/// connected itself, and the app never connects one: the paired-device database
/// belongs to macOS. `IOBluetoothDevice` connects are reported for every device
/// the system connects, which is what the summary row needs.
///
/// The callbacks are delivered on the thread that registered the notification,
/// so the implementation is nonisolated and lock-guarded, and the controller
/// hops to the main actor inside the handler it passes in.
protocol BluetoothConnectionEventMonitoring: AnyObject {
    /// Registers for connect notifications and hands back whether the system
    /// accepted the registration. A `false` result leaves the safety-net poll
    /// as the only source of device state.
    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

/// A registration handed back by IOBluetooth. `unregister()` is the SDK's
/// invalidation mechanism, so dropping the last reference to one does not
/// deregister it. Keeping the handle abstract lets the lifetime bookkeeping be
/// tested with counted fakes instead of the system's Bluetooth service.
protocol BluetoothNotificationToken: AnyObject {
    func unregister()
}

extension IOBluetoothUserNotification: BluetoothNotificationToken {}

final class IOBluetoothConnectionEventMonitor: NSObject, BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var connectNotification: (any BluetoothNotificationToken)?
    private var disconnectNotifications: [String: any BluetoothNotificationToken] = [:]

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { self.handler = handler }
        let notification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        let accepted = lock.withLock {
            connectNotification = notification
            return notification != nil
        }
        // A device that was already connected when monitoring began never
        // delivers a connect notification, so under the connect path alone
        // nothing would register its per-device disconnect. Such a device would
        // then only be seen to leave by the deliberately slow safety-net poll,
        // leaving the panel showing "connected" (and its last battery) for up to
        // a whole poll interval after it was put away. Adopting the connections
        // that already exist turns that departure into a notification like any
        // other.
        adoptConnectedDevices(currentlyConnectedDevices())
        return accepted
    }

    func stop() {
        let (connect, disconnects) = lock.withLock {
            () -> ((any BluetoothNotificationToken)?, [any BluetoothNotificationToken]) in
            let connect = connectNotification
            let disconnects = Array(disconnectNotifications.values)
            connectNotification = nil
            disconnectNotifications.removeAll()
            handler = nil
            return (connect, disconnects)
        }
        // Unregistered outside the lock: `unregister()` is an SDK call, and
        // holding the lock across it would let a notification callback that is
        // already running deadlock against teardown.
        connect?.unregister()
        for notification in disconnects {
            notification.unregister()
        }
    }

    /// The connect notification is system-wide; the disconnect notification is
    /// per device, so each device that connects is watched as it arrives. A
    /// device's entry is unregistered before it is dropped — both when the
    /// device disconnects and when a reconnect replaces it — and `stop()`
    /// releases whatever is still registered, so no registration outlives the
    /// device state it describes.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceConnected(
            identity: Self.deviceIdentity(addressString: device.addressString, name: device.name)
        ) {
            device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceDisconnected(
            identity: Self.deviceIdentity(addressString: device.addressString, name: device.name)
        )
    }

    /// The key a device is registered and removed under. Both callbacks derive
    /// it the same way: a device with no address falls back to its name, so the
    /// disconnect path removes exactly the key the connect path inserted.
    static func deviceIdentity(addressString: String?, name: String?) -> String {
        addressString ?? name ?? ""
    }

    /// The bookkeeping behind the connect callback, with the registration
    /// supplied by the caller, so registration and unregistration can be counted
    /// without touching the system's Bluetooth service.
    func handleDeviceConnected(
        identity: String,
        registerDisconnect: () -> (any BluetoothNotificationToken)?
    ) {
        if !identity.isEmpty, let token = registerDisconnect() {
            // Replaced under the lock and unregistered outside it: `unregister()`
            // is an SDK call and must not run while the lock is held.
            let replaced = lock.withLock { disconnectNotifications.updateValue(token, forKey: identity) }
            replaced?.unregister()
        }
        lock.withLock { handler }?()
    }

    /// The bookkeeping behind the disconnect callback. The token is unregistered
    /// before it is dropped: `unregister()` is what invalidates the
    /// registration, so clearing the entry alone would leave the callback armed
    /// and fire it again on the next disconnect.
    func handleDeviceDisconnected(identity: String) {
        let removed = lock.withLock { disconnectNotifications.removeValue(forKey: identity) }
        removed?.unregister()
        lock.withLock { handler }?()
    }

    /// A paired device that is already connected when monitoring starts, and so
    /// has to be handed a disconnect observation without a connect callback to
    /// build it from.
    ///
    /// `registerDisconnect` performs the SDK registration, so the adoption loop
    /// can be counted with fake tokens instead of the system's Bluetooth
    /// service, exactly like `handleDeviceConnected`.
    struct ConnectedDevice {
        let identity: String
        let registerDisconnect: () -> (any BluetoothNotificationToken)?
    }

    /// Adopts a snapshot of the devices that were connected before monitoring
    /// began. This is not a state change — the caller is already loading the
    /// current state — so the handler is deliberately not invoked; only the
    /// per-device disconnect registration is installed.
    func adoptConnectedDevices(_ devices: [ConnectedDevice]) {
        for device in devices {
            adoptConnectedDevice(identity: device.identity, registerDisconnect: device.registerDisconnect)
        }
    }

    /// Bookkeeping for adopting one already-connected device, with the
    /// registration supplied by the caller so it can be counted without touching
    /// the system's Bluetooth service.
    func adoptConnectedDevice(
        identity: String,
        registerDisconnect: () -> (any BluetoothNotificationToken)?
    ) {
        guard !identity.isEmpty, let token = registerDisconnect() else { return }
        let replaced = lock.withLock { disconnectNotifications.updateValue(token, forKey: identity) }
        replaced?.unregister()
    }

    /// The paired devices that are connected right now, each paired with the
    /// registration that observes its disconnect. A device with no address and
    /// no name cannot be keyed, so it is left out and behaves as before (poll
    /// only).
    private func currentlyConnectedDevices() -> [ConnectedDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.compactMap { device in
            guard device.isConnected() else { return nil }
            let identity = Self.deviceIdentity(addressString: device.addressString, name: device.name)
            guard !identity.isEmpty else { return nil }
            return ConnectedDevice(identity: identity) {
                device.register(
                    forDisconnectNotification: self,
                    selector: #selector(self.deviceDisconnected(_:device:))
                )
            }
        }
    }
}
