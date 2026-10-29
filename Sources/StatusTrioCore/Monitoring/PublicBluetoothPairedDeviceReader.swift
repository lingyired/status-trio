import Foundation
import IOBluetooth

/// A snapshot of the public IOBluetooth paired-device API.
///
/// IOBluetooth objects are not allowed to cross the reader's serial queue:
/// `IOBluetoothDevice` is an Objective-C object whose lifetime and connection
/// state belong to the Bluetooth stack. The default provider therefore converts
/// each object into this small value type before the reader publishes anything.
enum PublicBluetoothPairedSnapshot: Equatable, Sendable {
    struct Device: Equatable, Sendable {
        let address: String?
        let name: String?
        let majorClass: Int
        let minorClass: Int
        let isConnected: Bool
    }

    case devices([Device])
    case poweredOff
    case unavailable
    case failed
}

/// The public Bluetooth device-class constants used by IOBluetooth.
///
/// The numeric values are from the public `BluetoothAssignedNumbers.h` header.
/// They are kept here rather than passed through the profiler's wording table:
/// the profiler and IOBluetooth are different sources, and changing one must not
/// silently change the other's classification.
enum PublicBluetoothDeviceClass {
    static let majorMiscellaneous = 0x00
    static let majorComputer = 0x01
    static let majorPhone = 0x02
    static let majorAudio = 0x04
    static let majorPeripheral = 0x05
    static let majorImaging = 0x06
    static let majorWearable = 0x07
    static let majorToy = 0x08
    static let majorHealth = 0x09

    static let minorComputerDesktop = 0x01
    static let minorComputerServer = 0x02
    static let minorComputerLaptop = 0x03
    static let minorComputerHandheld = 0x04
    static let minorComputerPalmSized = 0x05
    static let minorComputerWearable = 0x06

    static let minorPeripheralKeyboard = 0x10
    static let minorPeripheralPointing = 0x20
    static let minorPeripheralCombo = 0x30

    static let minorPeripheralPointingJoystick = 0x01
    static let minorPeripheralPointingGamepad = 0x02
    static let minorPeripheralPointingDigitizerTablet = 0x05

    static let minorImagingDisplay = 0x04
    static let minorImagingCamera = 0x08
    static let minorImagingScanner = 0x10
    static let minorImagingPrinter = 0x20

    static let minorWearableWatch = 0x01

    static func kind(major: Int, minor: Int) -> BluetoothDeviceKind {
        switch major {
        case majorComputer:
            switch minor {
            case minorComputerDesktop, minorComputerServer:
                return .computer(.desktop)
            case minorComputerLaptop:
                return .computer(.laptop)
            default:
                return .computer(.unclassified)
            }
        case majorPhone:
            return .mobile(.phone)
        case majorAudio:
            return .audio
        case majorPeripheral:
            return peripheralKind(minor: minor)
        case majorImaging:
            return imagingKind(minor: minor)
        case majorWearable:
            return minor == minorWearableWatch ? .mobile(.watch) : .unknown
        case majorToy:
            return .toy
        case majorHealth:
            return .health
        default:
            return .unknown
        }
    }

    private static func peripheralKind(minor: Int) -> BluetoothDeviceKind {
        switch minor & 0x30 {
        case minorPeripheralKeyboard:
            return .peripheral(.keyboard)
        case minorPeripheralCombo:
            return .peripheral(.unclassified)
        case minorPeripheralPointing:
            switch minor & 0x0F {
            case 0:
                return .peripheral(.mouse)
            case minorPeripheralPointingJoystick, minorPeripheralPointingGamepad:
                return .peripheral(.gamepad)
            case minorPeripheralPointingDigitizerTablet:
                return .peripheral(.trackpad)
            default:
                return .peripheral(.unclassified)
            }
        default:
            return .peripheral(.unclassified)
        }
    }

    private static func imagingKind(minor: Int) -> BluetoothDeviceKind {
        if minor & minorImagingPrinter != 0 {
            return .imaging(.printer)
        }
        if minor & minorImagingScanner != 0 {
            return .imaging(.scanner)
        }
        if minor & minorImagingCamera != 0 {
            return .imaging(.camera)
        }
        if minor & minorImagingDisplay != 0 {
            return .imaging(.display)
        }
        return .imaging(.unclassified)
    }
}

/// Reads the system's paired-device database through the public
/// `IOBluetoothDevice.pairedDevices()` API.
///
/// This provider deliberately does not ask IOBluetooth for battery details:
/// the public paired-device API exposes identity and connection state, not the
/// per-device levels the Direct profiler path reads. Those levels stay absent
/// rather than being guessed or fetched through a private selector.
final class PublicBluetoothPairedDeviceReader: @unchecked Sendable, BluetoothPairedDeviceReading {
    typealias SnapshotProvider = @Sendable () -> PublicBluetoothPairedSnapshot

    private static let queueLabel = "StatusTrio.PublicBluetoothPairedDeviceReader"
    private static let maximumOutstandingReads = 2

    /// The public APIs used here cannot be cancelled. Two concurrent reads are
    /// enough to keep one wedged call from blocking the next request without
    /// allowing a hung provider to accumulate workers indefinitely.
    private let stateLock = NSLock()
    private var outstandingReads = 0
    private var isShutdown = false
    private let snapshotProvider: SnapshotProvider

    init(
        snapshotProvider: @escaping SnapshotProvider = { PublicBluetoothPairedDeviceReader.readSnapshot() }
    ) {
        self.snapshotProvider = snapshotProvider
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        let accepted = stateLock.withLock {
            guard !isShutdown,
                  outstandingReads < Self.maximumOutstandingReads else {
                return false
            }
            outstandingReads += 1
            return true
        }
        guard accepted else {
            completion(.unavailable)
            return
        }

        let snapshotProvider = self.snapshotProvider
        DispatchQueue(label: Self.queueLabel, qos: .utility).async { [weak self] in
            let result = Self.result(from: snapshotProvider())
            if let self {
                self.stateLock.withLock {
                    if self.outstandingReads > 0 {
                        self.outstandingReads -= 1
                    }
                }
            }
            completion(result)
        }
    }

    /// Stops accepting new work. This does not claim to cancel an IOBluetooth
    /// call that is already blocked; it only gives the owner a lifecycle stop
    /// point so no additional queues are created.
    func shutdown() {
        stateLock.withLock {
            isShutdown = true
        }
    }

    deinit {
        shutdown()
    }

    /// Converts a public snapshot into the protocol's result without retaining
    /// IOBluetooth objects or publishing a partially valid device list.
    static func result(from snapshot: PublicBluetoothPairedSnapshot) -> BluetoothWorkerResult {
        switch snapshot {
        case let .devices(devices):
            return .success(mappedDevices(from: devices))
        case .poweredOff:
            return .poweredOff
        case .unavailable:
            return .unavailable
        case .failed:
            return .failed
        }
    }

    /// The default provider performs one public IOBluetooth query per read.
    /// `nil` from `pairedDevices()` means there are no paired devices, not that
    /// the API failed; the distinction is documented in the SDK header.
    static func readSnapshot() -> PublicBluetoothPairedSnapshot {
        guard let controller = IOBluetoothHostController.default() else {
            return .unavailable
        }
        let powerState = controller.powerState
        switch powerState {
        case kBluetoothHCIPowerStateOFF:
            return .poweredOff
        case kBluetoothHCIPowerStateUnintialized:
            return .unavailable
        case kBluetoothHCIPowerStateON:
            break
        default:
            return .failed
        }

        guard let rawDevices = IOBluetoothDevice.pairedDevices() else {
            return .devices([])
        }
        guard let devices = rawDevices as? [IOBluetoothDevice] else {
            return .failed
        }
        return .devices(devices.map { device in
            PublicBluetoothPairedSnapshot.Device(
                address: device.addressString,
                name: device.nameOrAddress,
                majorClass: Int(device.deviceClassMajor),
                minorClass: Int(device.deviceClassMinor),
                isConnected: device.isConnected()
            )
        })
    }

    private static func mappedDevices(
        from snapshots: [PublicBluetoothPairedSnapshot.Device]
    ) -> [BluetoothDevice] {
        let ordered = snapshots.sorted {
            if $0.isConnected != $1.isConnected {
                return $0.isConnected && !$1.isConnected
            }
            let left = normalizedAddress($0.address) ?? ""
            let right = normalizedAddress($1.address) ?? ""
            if left != right {
                return left < right
            }
            return ($0.name ?? "") < ($1.name ?? "")
        }

        var addresses: Set<String> = []
        var result: [BluetoothDevice] = []
        for snapshot in ordered {
            guard let address = validAddress(snapshot.address),
                  let name = trimmedNonEmpty(snapshot.name) else {
                continue
            }
            let normalized = BluetoothBatteryReader.normalizedAddress(address)
            guard !normalized.isEmpty, addresses.insert(normalized).inserted else {
                continue
            }
            result.append(BluetoothDevice(
                id: address,
                name: name,
                kind: PublicBluetoothDeviceClass.kind(
                    major: snapshot.majorClass,
                    minor: snapshot.minorClass
                ),
                isConnected: snapshot.isConnected
            ))
        }
        return result
    }

    private static func validAddress(_ raw: String?) -> String? {
        guard let trimmed = trimmedNonEmpty(raw) else { return nil }
        let compact = trimmed.filter { $0 != ":" && $0 != "-" }
        guard compact.count == 12,
              compact.allSatisfy(\.isHexDigit) else {
            return nil
        }
        if trimmed.count == compact.count {
            return trimmed
        }
        guard trimmed.count == 17 else {
            return nil
        }
        let separators = [2, 5, 8, 11, 14].map { offset in
            trimmed[trimmed.index(trimmed.startIndex, offsetBy: offset)]
        }
        guard separators.allSatisfy({ $0 == ":" || $0 == "-" }),
              separators.allSatisfy({ $0 == separators.first }) else {
            return nil
        }
        return trimmed
    }

    private static func normalizedAddress(_ raw: String?) -> String? {
        guard let address = validAddress(raw) else { return nil }
        let normalized = BluetoothBatteryReader.normalizedAddress(address)
        return normalized.isEmpty ? nil : normalized
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
