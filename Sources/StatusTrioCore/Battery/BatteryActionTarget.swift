import Foundation

enum KnownBatteryAppID: String, Codable, CaseIterable {
    case alDente
    case batFi
}

struct ExternalApplicationTarget: Codable, Equatable {
    let displayName: String
    let bundleIdentifier: String?
    let fallbackPath: String?
}

enum BatteryActionTarget: Codable, Equatable {
    case systemSettings
    case knownApp(KnownBatteryAppID)
    case customApp(ExternalApplicationTarget)
    case customURL(String)

    private enum Kind: String, Codable {
        case systemSettings
        case knownApp
        case customApp
        case customURL
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case knownAppID
        case application
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .systemSettings:
            self = .systemSettings
        case .knownApp:
            self = .knownApp(try container.decode(KnownBatteryAppID.self, forKey: .knownAppID))
        case .customApp:
            self = .customApp(try container.decode(ExternalApplicationTarget.self, forKey: .application))
        case .customURL:
            self = .customURL(try container.decode(String.self, forKey: .url))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemSettings:
            try container.encode(Kind.systemSettings, forKey: .type)
        case .knownApp(let id):
            try container.encode(Kind.knownApp, forKey: .type)
            try container.encode(id, forKey: .knownAppID)
        case .customApp(let application):
            try container.encode(Kind.customApp, forKey: .type)
            try container.encode(application, forKey: .application)
        case .customURL(let text):
            try container.encode(Kind.customURL, forKey: .type)
            try container.encode(text, forKey: .url)
        }
    }
}
