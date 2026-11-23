import Foundation
import IOKit.ps

/// One public IOPS power-source dictionary, reduced to the fields this app
/// needs before it leaves the provider's queue.
struct PublicAccessoryPowerSource: Equatable, Sendable {
    let type: String?
    let name: String?
    let vendorID: Int?
    let productID: Int?
    let currentCapacity: Int?
    let maxCapacity: Int?
    let isPresent: Bool?
}

/// A snapshot from the public IOPS power-source API.
///
/// `.sources([])` means the API answered with no candidate power sources.
/// `.unavailable` and `.failed` are distinct from that empty answer.
enum PublicAccessoryBatterySnapshot: Equatable, Sendable {
    case sources([PublicAccessoryPowerSource])
    case unavailable
    case failed
}

/// The value boundary around IOKit's unmanaged IOPS objects. Keeping this
/// separate makes malformed payloads testable without invoking the system API.
enum PublicAccessoryIOPSPayload {
    case descriptions([[String: Any]?])
    case unavailable
    case malformed
}

/// Reads accessory battery levels through the public IOPS API.
///
/// The public IOPS headers define the source dictionary keys used here. They do
/// not define a public accessory-source type or a part identifier key, so this
/// provider does not invent either: every published reading has `part == nil`.
/// The unavailable part metadata is recorded as a limitation rather than
/// replaced with a guessed channel.
final class PublicAccessoryBatteryReader: @unchecked Sendable, BluetoothAccessoryBatteryReading {
    typealias SnapshotProvider = @Sendable () -> PublicAccessoryBatterySnapshot

    private static let queueLabel = "StatusTrio.PublicAccessoryBatteryReader"
    private static let maximumOutstandingReads = 2
    static let internalBatteryType = kIOPSInternalBatteryType
    static let upsType = kIOPSUPSType

    /// IOPS has no cancellation path. Bound the uncancellable calls instead of
    /// creating one queue per retry while a public call is wedged.
    private let stateLock = NSLock()
    private var outstandingReads = 0
    private var isShutdown = false
    private let snapshotProvider: SnapshotProvider

    init(
        snapshotProvider: @escaping SnapshotProvider = { PublicAccessoryBatteryReader.readSnapshot() }
    ) {
        self.snapshotProvider = snapshotProvider
    }

    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        let accepted = stateLock.withLock {
            guard !isShutdown,
                  outstandingReads < Self.maximumOutstandingReads else {
                return false
            }
            outstandingReads += 1
            return true
        }
        guard accepted else {
            completion(nil)
            return
        }

        let snapshotProvider = self.snapshotProvider
        DispatchQueue(label: Self.queueLabel, qos: .utility).async { [weak self] in
            let levels = Self.levels(from: snapshotProvider())
            if let self {
                self.stateLock.withLock {
                    if self.outstandingReads > 0 {
                        self.outstandingReads -= 1
                    }
                }
            }
            completion(levels)
        }
    }

    /// Stops accepting new IOPS reads without pretending to cancel one already
    /// blocked in the public API.
    func shutdown() {
        stateLock.withLock {
            isShutdown = true
        }
    }

    deinit {
        shutdown()
    }

    /// Maps a snapshot to the existing accessory-level model. A missing or
    /// invalid capacity is omitted rather than becoming `0`.
    static func levels(
        from snapshot: PublicAccessoryBatterySnapshot
    ) -> [BluetoothAccessoryBatteryLevel]? {
        switch snapshot {
        case let .sources(sources):
            return sources.compactMap(level(from:))
        case .unavailable, .failed:
            return nil
        }
    }

    private static func level(
        from source: PublicAccessoryPowerSource
    ) -> BluetoothAccessoryBatteryLevel? {
        guard source.isPresent != false,
              source.type != internalBatteryType,
              source.type != upsType,
              let percentage = percentage(from: source) else {
            return nil
        }
        return BluetoothAccessoryBatteryLevel(
            name: source.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            vendorID: source.vendorID,
            productID: source.productID,
            part: nil,
            percentage: percentage
        )
    }

    private static func percentage(from source: PublicAccessoryPowerSource) -> Int? {
        guard let current = source.currentCapacity,
              let maximum = source.maxCapacity,
              maximum > 0,
              current >= 0,
              current <= maximum else {
            return nil
        }
        let value = Int((Double(current) / Double(maximum) * 100).rounded())
        guard (0...100).contains(value) else { return nil }
        return value
    }

    /// The default provider reads one public IOPS snapshot. A missing IOPS
    /// handle/list is unavailable; a malformed list, description, or known value
    /// type is failed rather than silently becoming an empty accessory list.
    static func readSnapshot() -> PublicAccessoryBatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable
        }
        guard let rawSources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else {
            return .unavailable
        }
        let sources = rawSources as [CFTypeRef]

        var descriptions: [[String: Any]?] = []
        for source in sources {
            descriptions.append(
                IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any]
            )
        }
        return snapshot(from: .descriptions(descriptions))
    }

    static func snapshot(
        from payload: PublicAccessoryIOPSPayload
    ) -> PublicAccessoryBatterySnapshot {
        switch payload {
        case .unavailable:
            return .unavailable
        case .malformed:
            return .failed
        case let .descriptions(descriptions):
            var result: [PublicAccessoryPowerSource] = []
            for description in descriptions {
                guard let description,
                      let source = powerSource(from: description) else {
                    return .failed
                }
                result.append(source)
            }
            return .sources(result)
        }
    }

    private static func powerSource(
        from description: [String: Any]
    ) -> PublicAccessoryPowerSource? {
        if let rawType = description[kIOPSTypeKey], !(rawType is String) {
            return nil
        }
        if let rawName = description[kIOPSNameKey], !(rawName is String) {
            return nil
        }
        let integerValues: [(String, Int?)] = [
            (kIOPSVendorIDKey, integer(description[kIOPSVendorIDKey])),
            (kIOPSProductIDKey, integer(description[kIOPSProductIDKey])),
            (kIOPSCurrentCapacityKey, integer(description[kIOPSCurrentCapacityKey])),
            (kIOPSMaxCapacityKey, integer(description[kIOPSMaxCapacityKey]))
        ]
        for (key, parsed) in integerValues {
            if description[key] != nil && parsed == nil {
                return nil
            }
        }
        let isPresent = boolean(description[kIOPSIsPresentKey])
        if description[kIOPSIsPresentKey] != nil && isPresent == nil {
            return nil
        }
        return PublicAccessoryPowerSource(
            type: description[kIOPSTypeKey] as? String,
            name: description[kIOPSNameKey] as? String,
            vendorID: integerValues[0].1,
            productID: integerValues[1].1,
            currentCapacity: integerValues[2].1,
            maxCapacity: integerValues[3].1,
            isPresent: isPresent
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value,
              let number = value as? NSNumber else {
            return nil
        }
        let cfValue = number as CFTypeRef
        guard CFGetTypeID(cfValue) == CFNumberGetTypeID(),
              !CFNumberIsFloatType(number) else {
            return nil
        }
        return number.intValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value,
              let number = value as? NSNumber else {
            return nil
        }
        guard CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }
}
