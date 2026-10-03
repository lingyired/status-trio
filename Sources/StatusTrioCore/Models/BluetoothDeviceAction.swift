import Foundation

/// What tapping a device row asks the system to do.
enum BluetoothDeviceAction: Equatable, Sendable {
    case connect
    case disconnect

    /// The state a row shows while this action is in flight.
    var inFlightState: BluetoothDeviceActionState {
        switch self {
        case .connect: .connecting
        case .disconnect: .disconnecting
        }
    }
}

/// A row's action state. No entry for a device means the row reports the
/// device's own connection state.
enum BluetoothDeviceActionState: Equatable, Sendable {
    case connecting
    case disconnecting
    /// The action did not take effect; the row shows this for a few seconds.
    case failed(BluetoothDeviceAction)
}

/// What a row reports about a device: its connection, or what an action is doing
/// to it. A row keeps this for its accessibility value either way.
enum BluetoothDeviceRowStatus: Equatable, Sendable {
    case connected
    case notConnected
    case connecting
    case disconnecting
    case connectFailed
    case disconnectFailed

    /// Whether the row writes this state out as text.
    ///
    /// A resting state is already told by the row's own appearance — the icon is
    /// ringed in the accent colour and a checkmark follows the name when the
    /// device is connected — so it is not spelled out, and the trailing space is
    /// left to the battery level. Something the appearance cannot say, an action
    /// in flight or a failure, is written out.
    var drawsText: Bool {
        switch self {
        case .connected, .notConnected: false
        case .connecting, .disconnecting, .connectFailed, .disconnectFailed: true
        }
    }
}

/// The rules a row's action follows, kept out of the views so both surfaces
/// agree and the rules can be unit-tested.
enum BluetoothDeviceActionPolicy {
    /// Whether a tap on this row has anything to ask the system for.
    ///
    /// A row supplied only by an external reading has no paired connection for
    /// this app to control. Its provider ID is not a Bluetooth address, so the
    /// row is read-only.
    static func isActionable(_ device: BluetoothDevice) -> Bool {
        !device.isReadOverTheAir
    }

    /// Which action a tap requests, from the device's current state.
    static func action(for device: BluetoothDevice) -> BluetoothDeviceAction {
        device.isConnected ? .disconnect : .connect
    }

    /// Disconnecting an input device would cut the user off from their own
    /// keyboard or mouse, so that one action is confirmed in place first. A
    /// connect never needs confirmation, and neither does disconnecting
    /// anything else.
    ///
    /// A peripheral the class wording did not narrow down counts as an input
    /// device too. A connected unknown device does as well: ambiguous HID
    /// capabilities intentionally preserve `.unknown`, so one extra tap costs
    /// less than disconnecting an input device without warning.
    static func requiresConfirmation(for device: BluetoothDevice) -> Bool {
        device.isConnected && (device.kind.isPeripheral || device.kind == .unknown)
    }

    /// What the row shows in place of its connection state.
    static func status(
        for device: BluetoothDevice,
        actionState: BluetoothDeviceActionState?
    ) -> BluetoothDeviceRowStatus {
        switch actionState {
        case .connecting: .connecting
        case .disconnecting: .disconnecting
        case .failed(.connect): .connectFailed
        case .failed(.disconnect): .disconnectFailed
        case nil: device.isConnected ? .connected : .notConnected
        }
    }
}
