import Foundation
import IOBluetooth

/// The IOBluetooth surface an OPPO control connection drives, behind a seam so
/// tests can substitute fakes and the transport stays device-agnostic.
///
/// Mirrors `RedmiBluetoothDevice`: it narrows `IOBluetoothDevice` to the calls the
/// OPPO flow needs (SDP lookup by UUID, RFCOMM channel open) without leaking the
/// concrete type through the transport.
protocol OppoBluetoothDevice: AnyObject, Sendable {
    var addressString: String? { get }
    func isConnected() -> Bool
    /// The persisted SDP record for the vendor service, if the system cache holds
    /// it already.
    func cachedControlService() -> IOBluetoothSDPServiceRecord?
    /// Starts a query for every service. Returns `true` when the query was
    /// accepted.
    func queryForControlService() -> Bool
    /// Opens an async RFCOMM channel with the given id.
    func openControlChannel(
        id: BluetoothRFCOMMChannelID,
        delegate: IOBluetoothRFCOMMChannelDelegate
    ) -> IOReturn
    /// The RFCOMM channel id a service record maps to, or `nil`.
    func rfcommChannelID(for record: IOBluetoothSDPServiceRecord) -> BluetoothRFCOMMChannelID?
    /// The vendor control service's channel, resolved from whatever the device
    /// publishes. `nil` means the caller has to run its own SDP query.
    func vendorControlChannelID() -> BluetoothRFCOMMChannelID?
}

extension OppoBluetoothDevice {
    func rfcommChannelID(for record: IOBluetoothSDPServiceRecord) -> BluetoothRFCOMMChannelID? {
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess, id > 0 else { return nil }
        return id
    }

    /// Default: no resolution, so a test fake needs no SDP plumbing.
    func vendorControlChannelID() -> BluetoothRFCOMMChannelID? { nil }
}

/// `IOBluetoothDevice` bound to the OPPO control flow.
final class IOBluetoothOppoDevice: OppoBluetoothDevice, @unchecked Sendable {
    /// The vendor SPP service the HeyMelody family publishes.
    static let controlServiceUUID16: BluetoothSDPUUID16 = 0x1107

    /// The same service's published name when a model omits the UUID record.
    /// Measured on an Enco X3, which lists `ELNK` on RFCOMM channel 15 and no
    /// `0x1107` record at all.
    static let controlServiceName = "elnk"

    private let device: IOBluetoothDevice

    init(_ device: IOBluetoothDevice) {
        self.device = device
    }

    var addressString: String? { device.addressString }

    func isConnected() -> Bool { device.isConnected() }

    func cachedControlService() -> IOBluetoothSDPServiceRecord? {
        guard let uuid = IOBluetoothSDPUUID(uuid16: Self.controlServiceUUID16) else { return nil }
        return device.getServiceRecord(for: uuid)
    }

    /// The vendor control service's channel.
    ///
    /// Two models, two answers: a device may publish the `0x1107` record, or it may
    /// publish the same service under the name **ELNK** with no `0x1107` entry at
    /// all — which is what an Enco X3 does, on RFCOMM channel 15. Both speak the
    /// identical frame layout, so the name is matched when the UUID is absent
    /// rather than paying for an SDP round trip that cannot succeed.
    func vendorControlChannelID() -> BluetoothRFCOMMChannelID? {
        if let record = cachedControlService(), let id = rfcommChannelID(for: record) {
            return id
        }
        for item in device.services ?? [] {
            guard let record = item as? IOBluetoothSDPServiceRecord,
                  let name = record.getServiceName()?.lowercased(),
                  name.contains(Self.controlServiceName) else {
                continue
            }
            if let id = rfcommChannelID(for: record) { return id }
        }
        return nil
    }

    func queryForControlService() -> Bool {
        // `performSDPQuery` is asynchronous even though it returns a status; the
        // record lands in the system cache a moment later and the session polls
        // for it, matching what the HUAWEI and Redmi transports do.
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

/// Errors an OPPO control operation can surface, in terms the UI can present.
enum OppoListeningModeError: Error, Equatable {
    case serviceQueryFailed
    case controlServiceNotFound
    case noRFCOMMChannel
    case channelConnectionFailed(Int32)
    case handshakeRejected(UInt8)
    case handshakeTimeout
    case unsupportedModel
    case modeUnavailable
    case writeFailed(Int32)
    case notOpen
    case maxTransmissionUnitTooSmall
    case connectionClosedByDevice
    case timeout
}

/// The write/read seam the listening-mode controller drives.
///
/// Unlike the Redmi seam this speaks `BluetoothListeningMode` directly: the
/// per-model index table lives in `OppoNoiseProfile`, so the mapping is data the
/// transport owns rather than a second switch statement in the controller.
protocol OppoListeningModeTransporting: Sendable {
    func state(address: String) async throws -> OppoNoiseState
    func setMode(_ mode: BluetoothListeningMode, address: String) async throws -> OppoNoiseState
    func closeAll()
    /// Drops the persistent session for one device without disturbing the others.
    func close(address: String)
}

extension OppoListeningModeTransporting {
    /// Default no-op so simple conformers (e.g. test fakes) need not implement it.
    func close(address: String) {}
}

/// IOBluetooth-backed OPPO control transport over the vendor SPP channel.
///
/// Holds one persistent control session per device for the life of the
/// listening-mode surface, exactly as the Redmi transport does: the first
/// `state`/`setMode` opens and handshakes, later calls reuse the authenticated
/// channel (which stays open receiving event pushes), and a dropped link
/// reconnects on the next request.
final class OppoRFCOMMTransport: OppoListeningModeTransporting, @unchecked Sendable {
    private let resolveDevice: @Sendable (String) -> (any OppoBluetoothDevice)?
    private let sessionFactory: @Sendable (any OppoBluetoothDevice, String) -> OppoControlSession
    private let lock = NSLock()
    private var sessions: [String: OppoControlSession] = [:]

    init(
        resolveDevice: @escaping @Sendable (String) -> (any OppoBluetoothDevice)?,
        sessionFactory: @escaping @Sendable (any OppoBluetoothDevice, String) -> OppoControlSession
    ) {
        self.resolveDevice = resolveDevice
        self.sessionFactory = sessionFactory
    }

    convenience init() {
        self.init(
            resolveDevice: { address in OppoRFCOMMTransport.pairedDevice(matching: address) },
            sessionFactory: { OppoControlSession(device: $0, address: $1) }
        )
    }

    /// Looks up a paired device whose normalized address matches.
    static func pairedDevice(matching normalizedAddress: String) -> (any OppoBluetoothDevice)? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired {
            guard let raw = device.addressString,
                  BluetoothBatteryReader.normalizedAddress(raw) == normalizedAddress else {
                continue
            }
            return IOBluetoothOppoDevice(device)
        }
        return nil
    }

    func state(address: String) async throws -> OppoNoiseState {
        let session = try session(for: address)
        return try await session.readState()
    }

    func setMode(_ mode: BluetoothListeningMode, address: String) async throws -> OppoNoiseState {
        let session = try session(for: address)
        return try await session.setMode(mode)
    }

    func close(address: String) {
        lock.lock()
        let session = sessions.removeValue(forKey: address)
        lock.unlock()
        session?.close()
    }

    func closeAll() {
        lock.lock()
        let all = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        all.forEach { $0.close() }
    }

    /// Returns the persistent session for `address`, creating it on first use.
    private func session(for address: String) throws -> OppoControlSession {
        lock.lock()
        if let existing = sessions[address] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let device = resolveDevice(address) else {
            throw OppoListeningModeError.controlServiceNotFound
        }

        lock.lock()
        if let existing = sessions[address] {
            lock.unlock()
            return existing
        }
        let session = sessionFactory(device, address)
        sessions[address] = session
        lock.unlock()
        return session
    }
}
