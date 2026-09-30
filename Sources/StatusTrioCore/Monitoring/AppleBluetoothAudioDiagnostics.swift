import Foundation
import OSLog

enum AppleBluetoothAudioDiagnosticSource: String, Equatable, Sendable {
    case bluetooth
    case coreAudio
}

struct AppleBluetoothAudioDiagnosticRecord: Equatable, Sendable {
    let source: AppleBluetoothAudioDiagnosticSource
    let name: String?
    let address: String?
    let vendorID: Int?
    let productID: Int?
    let deviceUID: String?
    let majorType: String?
    let minorType: String?
    let modelUID: String?

    static func bluetooth(
        name: String,
        address: String,
        kind: BluetoothDeviceKind,
        vendorID: Int?,
        productID: Int?,
        majorType: String?,
        minorType: String?
    ) -> Self? {
        guard vendorID == AirPodsModel.appleVendorID,
              kind.isAudio,
              let productID,
              productID > 0,
              AppleBluetoothAudioResolver.airPodsModel(productID: productID, vendorID: vendorID) == nil else {
            return nil
        }

        return Self(
            source: .bluetooth,
            name: name,
            address: address,
            vendorID: vendorID,
            productID: productID,
            deviceUID: nil,
            majorType: majorType,
            minorType: minorType,
            modelUID: nil
        )
    }

    static func coreAudio(
        name: String?,
        transport: AudioOutputTransport?,
        modelUID: String?,
        deviceUID: String? = nil
    ) -> Self? {
        guard transport?.isBluetooth == true else { return nil }
        let tokens = (modelUID ?? "").split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2,
              let productID = BluetoothHexIdentifier.value(from: String(tokens[0])),
              let vendorID = BluetoothHexIdentifier.value(from: String(tokens[1])),
              vendorID == AirPodsModel.appleVendorID,
              productID > 0,
              AppleBluetoothAudioResolver.airPodsModel(productID: productID, vendorID: vendorID) == nil else {
            return nil
        }

        return Self(
            source: .coreAudio,
            name: name,
            address: nil,
            vendorID: vendorID,
            productID: productID,
            deviceUID: deviceUID,
            majorType: nil,
            minorType: nil,
            modelUID: modelUID
        )
    }
}

final class AppleBluetoothAudioDiagnosticReporter: @unchecked Sendable {
    static let capacity = 128

    private struct Fingerprint: Hashable {
        let identity: String
        let vendorID: Int?
        let productID: Int?

        init(_ record: AppleBluetoothAudioDiagnosticRecord) {
            identity = record.address ?? record.deviceUID ?? record.modelUID ?? record.name ?? ""
            vendorID = record.vendorID
            productID = record.productID
        }
    }

    private static let logger = Logger(
        subsystem: "com.lingsmbp.StatusTrio",
        category: "AppleBluetoothAudio"
    )

    private let lock = NSLock()
    private var fingerprints: Set<Fingerprint> = []
    private var insertionOrder: [Fingerprint] = []

    @discardableResult
    func report(_ record: AppleBluetoothAudioDiagnosticRecord) -> Bool {
        let fingerprint = Fingerprint(record)
        let shouldLog = lock.withLock {
            guard fingerprints.insert(fingerprint).inserted else { return false }
            insertionOrder.append(fingerprint)
            if insertionOrder.count > Self.capacity {
                let evicted = insertionOrder.removeFirst()
                fingerprints.remove(evicted)
            }
            return true
        }
        guard shouldLog else { return false }

        Self.logger.debug(
            "Unknown Apple Bluetooth audio device source=\(record.source.rawValue, privacy: .public) name=\(record.name ?? "-", privacy: .private) address=\(record.address ?? "-", privacy: .private) vendorID=\(record.vendorID ?? -1, privacy: .public) productID=\(record.productID ?? -1, privacy: .public) majorType=\(record.majorType ?? "-", privacy: .private) minorType=\(record.minorType ?? "-", privacy: .private) modelUID=\(record.modelUID ?? "-", privacy: .private) deviceUID=\(record.deviceUID ?? "-", privacy: .private)"
        )
        return true
    }

    var retainedFingerprintCount: Int {
        lock.withLock { fingerprints.count }
    }
}
