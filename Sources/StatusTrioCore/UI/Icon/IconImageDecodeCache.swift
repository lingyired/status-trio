import AppKit

/// The file version is part of an icon's cache identity. A source can keep the
/// same URL while replacing its artwork, so URL alone is not a stable image key.
struct IconImageFileIdentity: Hashable {
    let url: URL
    let modificationDate: Date?
    let fileSize: Int?

    init(url: URL) {
        let standardizedURL = url.standardizedFileURL
        let attributes = try? standardizedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        self.url = standardizedURL
        self.modificationDate = attributes?.contentModificationDate
        self.fileSize = attributes?.fileSize
    }

    var hasFileVersion: Bool {
        modificationDate != nil && fileSize != nil
    }

    var cacheToken: String {
        let modified = modificationDate.map { String($0.timeIntervalSince1970.bitPattern, radix: 16) } ?? "missing"
        let size = fileSize.map { String($0) } ?? "missing"
        return "\(url.path)|mtime=\(modified)|bytes=\(size)"
    }
}

/// Bounded cache of decoded icon images keyed by their file URL.
///
/// The menu bar draws through an `NSImage` drawing handler on every display
/// pass, so without this each pass would re-read and re-decode the same input
/// source or audio-device icon from disk. URL plus modification date and file
/// size identify each version; the oldest entries fall out beyond the bound.
/// The panel's monochrome version is derived from the same cached decoded image.
final class IconImageDecodeCache: @unchecked Sendable {
    static let shared = IconImageDecodeCache()

    private enum Kind: Hashable {
        case decoded
        case inputSourceMask
    }

    private struct Key: Hashable {
        let url: URL
        let kind: Kind
    }

    private struct Entry {
        let image: NSImage
        let fileIdentity: IconImageFileIdentity
    }

    private let lock = NSLock()
    private let maximumEntries: Int
    private var storage: [Key: Entry] = [:]
    private var order: [Key] = []

    init(maximumEntries: Int = 8) {
        precondition(maximumEntries > 0, "the cache needs room for at least one image")
        self.maximumEntries = maximumEntries
    }

    /// Returns the cached image for `url`, loading it when absent or when its
    /// modification date or size changes. Failed loads are not cached. If the
    /// file disappears, keep serving the last image for the visible icon.
    func image(for url: URL, load: (URL) -> NSImage?) -> NSImage? {
        let identity = IconImageFileIdentity(url: url)
        return image(for: Key(url: identity.url, kind: .decoded), identity: identity) {
            load(identity.url)
        }
    }

    /// The single-colour mark the status panel draws for an input source.
    ///
    /// See `InputSourceIconMask`: the panel tints its rows, so an icon has to
    /// survive as ink rather than as its own palette, and the conversion is not
    /// something the SwiftUI body may repeat per pass.
    func monochromeInputSourceIcon(for url: URL) -> NSImage? {
        let identity = IconImageFileIdentity(url: url)
        return image(for: Key(url: identity.url, kind: .inputSourceMask), identity: identity) {
            guard let image = decodedImage(for: identity) else { return nil }
            return InputSourceIconMask.make(from: image)
        }
    }

    private func image(for key: Key, identity: IconImageFileIdentity, load: () -> NSImage?) -> NSImage? {
        lock.lock()
        if let cached = storage[key] {
            if !identity.hasFileVersion || cached.fileIdentity == identity {
                touch(key)
                lock.unlock()
                return cached.image
            }
        }
        lock.unlock()

        guard let image = load() else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[key] {
            if !identity.hasFileVersion || existing.fileIdentity == identity {
                touch(key)
                return existing.image
            }
        }
        storage[key] = Entry(image: image, fileIdentity: identity)
        touch(key)
        while order.count > maximumEntries {
            let oldest = order.removeFirst()
            storage[oldest] = nil
        }
        return image
    }

    /// Convenience for callers whose loader is `NSImage(contentsOf:)`.
    func decodedImage(for url: URL) -> NSImage? {
        decodedImage(for: IconImageFileIdentity(url: url))
    }

    func decodedImage(for identity: IconImageFileIdentity) -> NSImage? {
        image(for: Key(url: identity.url, kind: .decoded), identity: identity) {
            NSImage(contentsOf: identity.url)
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
