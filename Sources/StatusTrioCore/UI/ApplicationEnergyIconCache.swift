import AppKit

/// Keeps the real bundle icons used by the high-energy application list.
///
/// The list is refreshed by the energy sampler, so a SwiftUI body can be
/// evaluated repeatedly while the panel is open. The cache is deliberately
/// small and keyed by the bundle path and requested raster size; a failed
/// lookup is not stored, allowing a temporarily missing bundle to recover.
@MainActor
final class ApplicationEnergyIconCache {
    typealias Loader = @MainActor (URL) -> NSImage?

    static let shared = ApplicationEnergyIconCache()
    static let defaultMaximumEntries = 8

    private struct Key: Hashable {
        let path: String
        let pixelLength: Int
    }

    private let maximumEntries: Int
    private let loader: Loader
    private var entries: [Key: NSImage] = [:]
    private var order: [Key] = []

    init(
        maximumEntries: Int = ApplicationEnergyIconCache.defaultMaximumEntries,
        loader: @escaping Loader = ApplicationEnergyIconCache.loadSystemIcon
    ) {
        self.maximumEntries = max(1, maximumEntries)
        self.loader = loader
    }

    var entryCount: Int { entries.count }

    func image(for path: String, pixelLength: Int = 32) -> NSImage? {
        guard !path.isEmpty else { return nil }

        let key = Key(path: path, pixelLength: max(1, pixelLength))
        if let cached = entries[key] {
            touch(key)
            return cached
        }

        guard let image = loader(URL(fileURLWithPath: path)) else { return nil }
        entries[key] = image
        order.append(key)
        trimToLimit()
        return image
    }

    func reset() {
        entries.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trimToLimit() {
        while order.count > maximumEntries {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    private static func loadSystemIcon(at url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
