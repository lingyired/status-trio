import Foundation

/// A portable, human-readable document used to share one menu-bar instance.
///
/// The wrapper leaves room to evolve the file format; decoding also accepts a
/// bare `MenuBarInstance` JSON for files produced by early development builds.
struct MenuBarInstanceDocument: Codable, Sendable {
    static let formatIdentifier = "status-trio.menu-bar-instance"
    static let currentVersion = 1

    var format: String
    var version: Int
    var instance: MenuBarInstance

    init(instance: MenuBarInstance) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.instance = instance
    }
}

enum MenuBarInstanceTransfer {
    static func encode(_ instance: MenuBarInstance) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(MenuBarInstanceDocument(instance: instance))
    }

    static func decode(_ data: Data) throws -> MenuBarInstance {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(MenuBarInstanceDocument.self, from: data),
           document.format == MenuBarInstanceDocument.formatIdentifier {
            return document.instance
        }
        return try decoder.decode(MenuBarInstance.self, from: data)
    }
}
