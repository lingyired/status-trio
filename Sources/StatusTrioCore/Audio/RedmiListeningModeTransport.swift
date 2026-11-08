import Foundation
import IOBluetooth

/// The IOBluetooth surface a Redmi control connection drives, behind a seam so
/// tests can substitute fakes and the transport stays device-agnostic.
///
/// Mirrors `HuaweiBluetoothDevice`'s role: it narrows `IOBluetoothDevice` to the
/// calls the Redmi flow needs (SDP lookup, RFCOMM channel open) without leaking
/// the concrete type through the transport.
protocol RedmiBluetoothDevice: AnyObject, Sendable {
    var addressString: String? { get }
    func isConnected() -> Bool
    /// The persisted SDP record for the `FD2D` control service, if the system
    /// cache already holds it.
    func cachedControlService() -> IOBluetoothSDPServiceRecord?
    /// Starts a query for the `FD2D` control service. Returns `true` when the
    /// query was accepted.
    func queryForControlService() -> Bool
    /// Opens an async RFCOMM control channel with the given id.
    func openControlChannel(
        id: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> IOReturn
    /// The RFCOMM channel id a control service record maps to, or `nil`.
    func rfcommChannelID(for record: IOBluetoothSDPServiceRecord) -> BluetoothRFCOMMChannelID?
}

extension RedmiBluetoothDevice {
    func rfcommChannelID(for record: IOBluetoothSDPServiceRecord) -> BluetoothRFCOMMChannelID? {
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess, id > 0 else { return nil }
        return id
    }
}

/// `IOBluetoothDevice` bound to the Redmi control flow.
final class IOBluetoothRedmiDevice: RedmiBluetoothDevice, @unchecked Sendable {
    private let device: IOBluetoothDevice

    init(_ device: IOBluetoothDevice) {
        self.device = device
    }

    var addressString: String? { device.addressString }

    func isConnected() -> Bool { device.isConnected() }

    func cachedControlService() -> IOBluetoothSDPServiceRecord? {
        device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0xFD2D)!)
    }

    func queryForControlService() -> Bool {
        // `performSDPQuery` is asynchronous even though it returns a status; the
        // resolved record lands in the system cache a moment later. The session
        // polls `cachedControlService()` after issuing this, matching the sequence
        // the HUAWEI transport and the reference implementation use.
        device.performSDPQuery(nil) == kIOReturnSuccess
    }

    func openControlChannel(
        id: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> IOReturn {
        var channel: IOBluetoothRFCOMMChannel?
        return device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: delegate)
    }
}

/// Errors a Redmi control operation can surface, in terms the UI can present.
enum RedmiListeningModeError: Error, Equatable {
    case serviceQueryFailed
    case controlServiceNotFound
    case noRFCOMMChannel
    case channelConnectionFailed(Int32)
    case authenticationRejected(UInt8)
    case authenticationTimeout
    case writeFailed(Int32)
    case notOpen
    case maxTransmissionUnitTooSmall
    case connectionClosedByDevice
}

/// The mode state a Redmi transport operation returns. A thread-safe value type.
struct RedmiNoiseState: Equatable, Sendable {
    let mode: RedmiNoiseMode

    /// The shared listening-mode this state maps to.
    var listeningMode: BluetoothListeningMode {
        switch mode {
        case .off: return .off
        case .cancellation: return .noiseCancellation
        case .transparency: return .transparency
        }
    }

    /// The modes this device family offers. `off` is one of the three modes the
    /// hardware itself cycles through, so it is offered exactly like HUAWEI does.
    static let selectableListeningModes: [BluetoothListeningMode] = [
        .noiseCancellation, .transparency, .off
    ]
}

/// The write/read seam the listening-mode controller drives.
///
/// `setMode` returns the mode read back after the write; the controller treats a
/// mismatch as unconfirmed, exactly as the CoreAudio and HUAWEI paths do.
protocol RedmiListeningModeTransporting: Sendable {
    func state(address: String) async throws -> RedmiNoiseState
    func setMode(_ mode: RedmiNoiseMode, address: String) async throws -> RedmiNoiseState
    func closeAll()
}

/// IOBluetooth-backed Redmi control transport over the vendor `FD2D` SPP channel.
///
/// Each `state`/`setMode` runs one owned control session: look up the control
/// service, open the RFCOMM channel, complete the challenge handshake, perform
/// the read/write, then release the channel.
final class RedmiRFCOMMTransport: RedmiListeningModeTransporting, @unchecked Sendable {
    /// Resolves a paired IOBluetooth device for a normalized address.
    private let resolveDevice: @Sendable (String) -> (any RedmiBluetoothDevice)?
    /// Builds a session for a resolved device + transport address.
    private let sessionFactory: @Sendable (any RedmiBluetoothDevice, String) -> RedmiControlSession

    init(
        resolveDevice: @escaping @Sendable (String) -> (any RedmiBluetoothDevice)?,
        sessionFactory: @escaping @Sendable (any RedmiBluetoothDevice, String) -> RedmiControlSession
    ) {
        self.resolveDevice = resolveDevice
        self.sessionFactory = sessionFactory
    }

    convenience init() {
        self.init(
            resolveDevice: { address in RedmiRFCOMMTransport.pairedDevice(matching: address) },
            sessionFactory: { RedmiControlSession(device: $0, address: $1) }
        )
    }

    /// Looks up a paired device whose normalized address matches.
    static func pairedDevice(matching normalizedAddress: String) -> (any RedmiBluetoothDevice)? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired {
            guard let raw = device.addressString,
                  BluetoothBatteryReader.normalizedAddress(raw) == normalizedAddress else {
                continue
            }
            return IOBluetoothRedmiDevice(device)
        }
        return nil
    }

    func state(address: String) async throws -> RedmiNoiseState {
        guard let device = resolveDevice(address) else {
            throw RedmiListeningModeError.controlServiceNotFound
        }
        let session = sessionFactory(device, address)
        let state = try await session.readState()
        session.close()
        return state
    }

    func setMode(_ mode: RedmiNoiseMode, address: String) async throws -> RedmiNoiseState {
        guard let device = resolveDevice(address) else {
            throw RedmiListeningModeError.controlServiceNotFound
        }
        let session = sessionFactory(device, address)
        let state = try await session.setMode(mode)
        session.close()
        return state
    }

    func closeAll() {
        // Sessions are per-operation and self-owned; there is nothing retained
        // between calls. This is a no-op satisfying the seam.
    }
}