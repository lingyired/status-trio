import Foundation
import CoreFoundation

enum MobileBatteryTransport: String, Codable, Sendable {
    case usb
    case network
}

struct MobileBatterySnapshot: Equatable, Sendable {
    let id: String
    let parentID: String?
    let name: String?
    let model: String
    let batteryLevel: Int
    let isCharging: Bool?
    let transport: MobileBatteryTransport
    let observedAt: Date

    var identity: String {
        if let parentID { "watch:\(parentID):\(id)" }
        else { "phone:\(id)" }
    }
}

struct MobileBatteryReadFailure: Equatable, Sendable {
    let category: String
    let deviceID: String?
}

struct MobileBatteryReadResult: Sendable {
    var snapshots: [MobileBatterySnapshot]
    var failures: [MobileBatteryReadFailure]

    init(snapshots: [MobileBatterySnapshot] = [], failures: [MobileBatteryReadFailure] = []) {
        self.snapshots = snapshots
        self.failures = failures
    }
}

protocol MobileBatteryReading: Sendable {
    func read() async throws -> MobileBatteryReadResult
}

enum MobileBatteryWireError: Error, Equatable {
    case invalidEnvelope
    case unsupportedSchema(Int)
}

enum MobileBatteryWire {
    static func decode(
        _ data: Data,
        expectedParentID: String?,
        observedAt: Date
    ) throws -> MobileBatteryReadResult {
        let envelope = try JSONDecoder().decode(DeviceEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw MobileBatteryWireError.unsupportedSchema(envelope.schemaVersion) }
        var result = MobileBatteryReadResult(failures: envelope.failures.map { failure in
            MobileBatteryReadFailure(failure)
        })
        let integerSyntax = StrictBatteryNumberSyntax.flags(in: data)

        for (index, entry) in envelope.devices.enumerated() {
            do {
                guard integerSyntax.indices.contains(index), integerSyntax[index] else {
                    throw MobileBatteryWireError.invalidEnvelope
                }
                guard let wire = entry.device else { throw MobileBatteryWireError.invalidEnvelope }
                guard !wire.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !wire.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MobileBatteryWireError.invalidEnvelope
                }
                let family = wire.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let isWatch = family.lowercased().hasPrefix("watch")
                if isWatch {
                    guard let parentID = wire.parentID,
                          !parentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          expectedParentID == parentID else { throw MobileBatteryWireError.invalidEnvelope }
                } else {
                    guard wire.parentID == nil,
                          family.lowercased().hasPrefix("iphone") else {
                        throw MobileBatteryWireError.invalidEnvelope
                    }
                }
                guard (0...100).contains(wire.batteryLevel) else { throw MobileBatteryWireError.invalidEnvelope }
                result.snapshots.append(MobileBatterySnapshot(
                    id: wire.id,
                    parentID: wire.parentID,
                    name: wire.name,
                    model: wire.model,
                    batteryLevel: wire.batteryLevel,
                    isCharging: wire.isCharging,
                    transport: wire.transport,
                    observedAt: observedAt
                ))
            } catch {
                result.failures.append(MobileBatteryReadFailure(category: "invalid-device", deviceID: nil))
            }
        }
        return result
    }

    static func decodeListing(_ data: Data) throws -> [PhoneRoute] {
        let listing = try JSONDecoder().decode(ListingEnvelope.self, from: data)
        guard listing.schemaVersion == 1 else { throw MobileBatteryWireError.unsupportedSchema(listing.schemaVersion) }
        var routes: [String: [MobileBatteryTransport]] = [:]
        for phone in listing.phones {
            guard !phone.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let discovered = phone.availableTransports ?? [phone.transport]
            let valid = Array(Set(discovered)).sorted { $0 == .usb && $1 == .network }
            let transports = valid.isEmpty ? [phone.transport] : valid
            routes[phone.id, default: []].append(contentsOf: transports)
        }
        return routes.map { id, candidates in
            let available = Set(candidates)
            let ordered: [MobileBatteryTransport] = ([.usb, .network] as [MobileBatteryTransport]).filter { available.contains($0) }
            return PhoneRoute(id: id, transports: ordered)
        }.sorted { $0.id < $1.id }
    }

    static func decodeWatchCandidates(_ data: Data, expectedParentID: String) throws -> [WatchRoute] {
        let envelope = try JSONDecoder().decode(WatchCandidateEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw MobileBatteryWireError.unsupportedSchema(envelope.schemaVersion) }
        return (envelope.watchCandidates ?? []).compactMap { entry in
            guard let candidate = entry.candidate else { return nil }
            guard candidate.parentID == expectedParentID,
                  !candidate.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return WatchRoute(id: candidate.id, parentID: candidate.parentID, transport: candidate.transport)
        }
    }
}

struct PhoneRoute: Sendable {
    let id: String
    let transports: [MobileBatteryTransport]
    var preferredTransport: MobileBatteryTransport { transports.first ?? .usb }
}

struct WatchRoute: Hashable, Sendable {
    let id: String
    let parentID: String
    let transport: MobileBatteryTransport
}

private struct DeviceEnvelope: Decodable {
    let schemaVersion: Int
    let devices: [DeviceEntry]
    let failures: [WireFailure]
}

private struct DeviceEntry: Decodable {
    let device: Device?

    init(from decoder: Decoder) throws {
        device = try? Device(from: decoder)
    }
}

private struct Device: Decodable {
    let id: String
    let parentID: String?
    let name: String?
    let model: String
    let batteryLevel: Int
    let isCharging: Bool?
    let transport: MobileBatteryTransport
}

private struct WireFailure: Decodable {
    let id: String?
    let category: String

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        category = try values.decode(String.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey { case id, error }
}

private extension MobileBatteryReadFailure {
    init(_ failure: WireFailure) { self.init(category: failure.category, deviceID: failure.id) }
}

private struct ListingEnvelope: Decodable {
    let schemaVersion: Int
    let phones: [Phone]
}

private struct WatchCandidateEnvelope: Decodable {
    let schemaVersion: Int
    let watchCandidates: [CandidateEntry]?
}

private struct CandidateEntry: Decodable {
    let candidate: Candidate?

    init(from decoder: Decoder) throws {
        candidate = try? Candidate(from: decoder)
    }
}

private struct Candidate: Decodable {
    let id: String
    let parentID: String
    let transport: MobileBatteryTransport
}

private struct Phone: Decodable {
    let id: String
    let transport: MobileBatteryTransport
    let availableTransports: [MobileBatteryTransport]?
}

/// JSONDecoder's `Int` accepts an integral decimal token such as `72.0`. Foundation
/// preserves integer, floating-point, and boolean number types for this check.
private enum StrictBatteryNumberSyntax {
    static func flags(in data: Data) -> [Bool] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              let devices = envelope["devices"] as? [Any] else { return [] }
        return devices.map { value in
            guard let device = value as? [String: Any],
                  let percentage = device["batteryLevel"] as? NSNumber else { return false }
            return CFGetTypeID(percentage) != CFBooleanGetTypeID() && !CFNumberIsFloatType(percentage)
        }
    }
}
