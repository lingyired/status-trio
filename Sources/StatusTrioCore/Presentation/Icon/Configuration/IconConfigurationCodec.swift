import Foundation

enum IconConfigurationCodecError: Error, Equatable {
    case invalidRoot
    case missingSchemaVersion
    case unsupportedSchemaVersion(Int)
    case malformedData
}

enum IconConfigurationCodec {
    static func encode(_ value: IconConfigurationV1) throws -> Data {
        guard value.schemaVersion == 1 else {
            throw IconConfigurationCodecError.unsupportedSchemaVersion(value.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value.normalized())
    }

    static func decode(_ data: Data) throws -> IconConfigurationV1 {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw IconConfigurationCodecError.malformedData
        }
        guard let object = root as? [String: Any] else {
            throw IconConfigurationCodecError.invalidRoot
        }
        guard let version = object["schemaVersion"] as? Int else {
            throw IconConfigurationCodecError.missingSchemaVersion
        }
        guard version == 1 else {
            throw IconConfigurationCodecError.unsupportedSchemaVersion(version)
        }
        do {
            return try JSONDecoder().decode(IconConfigurationV1.self, from: data).normalized()
        } catch {
            throw IconConfigurationCodecError.malformedData
        }
    }
}
