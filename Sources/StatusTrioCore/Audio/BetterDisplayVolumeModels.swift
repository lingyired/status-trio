import CoreAudio
import Foundation

enum VolumeMuteState: Equatable, Sendable {
    case muted
    case unmuted
    case unknown
}

enum BetterDisplayAvailability: Equatable, Sendable {
    case idle
    case discovering
    case available
    case syncing
    case appAbsent
    case unresponsive
    case deviceUnassociated
    case invalidResponse
    case requestFailed
    case writeNotConfirmed
}

struct BetterDisplayDevice: Equatable, Sendable {
    let uuid: String
    let name: String?
    var registryLocation: String? = nil
}

struct BetterDisplayCatalogUpdate: Equatable, Sendable {
    let devices: [BetterDisplayDevice]
    let availability: BetterDisplayAvailability
    let isCatalogLoaded: Bool
    let outputUID: String?
    let displayUUID: String?
    let canSetVolume: Bool
    let automaticDisplayUUID: String?

    init(
        devices: [BetterDisplayDevice],
        availability: BetterDisplayAvailability,
        isCatalogLoaded: Bool? = nil,
        outputUID: String? = nil,
        displayUUID: String? = nil,
        canSetVolume: Bool = false,
        automaticDisplayUUID: String? = nil
    ) {
        self.devices = devices
        self.availability = availability
        self.isCatalogLoaded = isCatalogLoaded
            ?? (availability == .available || availability == .deviceUnassociated)
        self.outputUID = outputUID
        self.displayUUID = displayUUID
        self.canSetVolume = canSetVolume
        self.automaticDisplayUUID = automaticDisplayUUID
    }
}

struct BetterDisplayVolumeUpdate: Equatable, Sendable {
    let outputID: AudioDeviceID
    let uid: String
    let displayUUID: String?
    let generation: UInt64
    let scalar: Double?
    let muteState: VolumeMuteState
    let canSetVolume: Bool
    let canMute: Bool
    let availability: BetterDisplayAvailability
    let commandID: UInt64?
}

struct BetterDisplayVolumeRange: Equatable, Sendable {
    let current: Double
    let minimum: Double
    let maximum: Double

    var normalizedScalar: Double {
        (current - minimum) / (maximum - minimum)
    }

    func rawValue(for normalizedScalar: Double) -> Double {
        let clamped = min(1, max(0, normalizedScalar))
        return minimum + clamped * (maximum - minimum)
    }
}

enum BetterDisplayVolumeParserError: Error, Equatable, Sendable {
    case invalidPayload
    case duplicateDisplayIdentity
}

enum BetterDisplayVolumeParser {
    private struct DeviceRecord: Decodable {
        let uuid: String?
        let deviceType: String?
        let name: String?
        let registryLocation: String?

        enum CodingKeys: String, CodingKey {
            case uuid = "UUID"
            case deviceType
            case name
            case registryLocation
        }
    }

    static func parseDevices(_ payload: String) throws -> [BetterDisplayDevice] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BetterDisplayVolumeParserError.invalidPayload
        }

        let records: [DeviceRecord]
        if let decoded = try? JSONDecoder().decode([DeviceRecord].self, from: Data(trimmed.utf8)) {
            records = decoded
        } else if let decoded = try? JSONDecoder().decode(
            [DeviceRecord].self,
            from: Data(("[\(trimmed)]").utf8)
        ) {
            records = decoded
        } else {
            throw BetterDisplayVolumeParserError.invalidPayload
        }

        var seen = Set<String>()
        var devices: [BetterDisplayDevice] = []
        for record in records {
            guard record.deviceType == "Display",
                  let uuid = record.uuid?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !uuid.isEmpty
            else {
                continue
            }
            guard seen.insert(uuid).inserted else {
                throw BetterDisplayVolumeParserError.duplicateDisplayIdentity
            }
            let name = record.name?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let registryLocation = record.registryLocation?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            devices.append(
                BetterDisplayDevice(
                    uuid: uuid,
                    name: name?.isEmpty == false ? name : nil,
                    registryLocation: registryLocation?.isEmpty == false ? registryLocation : nil
                )
            )
        }
        return devices
    }

    static func parseVolumeRange(_ payload: String) throws -> BetterDisplayVolumeRange {
        let values = payload
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.count == 3,
              let current = Double(values[0]),
              let minimum = Double(values[1]),
              let maximum = Double(values[2]),
              current.isFinite,
              minimum.isFinite,
              maximum.isFinite,
              maximum > minimum,
              current >= minimum,
              current <= maximum
        else {
            throw BetterDisplayVolumeParserError.invalidPayload
        }
        return BetterDisplayVolumeRange(
            current: current,
            minimum: minimum,
            maximum: maximum
        )
    }

    static func parseMuteState(_ payload: String?) -> VolumeMuteState {
        switch payload?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "on":
            return .muted
        case "off":
            return .unmuted
        default:
            return .unknown
        }
    }
}
