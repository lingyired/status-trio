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

/// Bounded cache of decoded icon images keyed by their file URL and size.
///
/// The menu bar draws through an `NSImage` drawing handler on every display
/// pass, so without this each pass would re-read and re-decode the same input
/// source or audio-device icon from disk. URL plus modification date and file
/// size identify each version. Decoded images and their monochrome masks share
/// one bitmap-byte budget; images too large for that budget are returned without
/// retention.
final class IconImageDecodeCache: @unchecked Sendable {
    static let shared = IconImageDecodeCache()

    private enum Kind: Int, Hashable {
        case decoded = 0
        case inputSourceMask = 1
    }

    private struct Key: Hashable {
        let identity: IconImageFileIdentity
        let normalizedPixelLength: Int
        let kind: Kind
    }

    private struct Entry {
        let image: NSImage
        let byteCount: Int
    }

    private let lock = NSLock()
    private let maximumEntries: Int
    private let maximumResidentBytes: Int
    private var storage: [Key: Entry] = [:]
    private var order: [Key] = []
    private var residentBytes = 0
    private var epoch: UInt64 = 0
    private var lastKnownFileVersions: [URL: IconImageFileIdentity] = [:]

    init(
        maximumEntries: Int = 8,
        maximumResidentBytes: Int = 8 * 1024 * 1024
    ) {
        precondition(maximumEntries > 0, "the cache needs room for at least one image")
        precondition(maximumResidentBytes > 0, "the cache needs room for at least one byte")
        self.maximumEntries = maximumEntries
        self.maximumResidentBytes = maximumResidentBytes
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    var residentByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return residentBytes
    }

    /// Returns the cached image for `url`, loading it through `load` once when
    /// absent or when its file version changes. A failed load is not cached.
    func image(
        for url: URL,
        maximumPixelLength: Int = 512,
        load: (URL) -> NSImage?
    ) -> NSImage? {
        let identity = resolvedIdentity(for: url)
        return image(
            for: Key(
                identity: identity,
                normalizedPixelLength: maximumPixelLength,
                kind: .decoded
            ),
            load: {
                load(identity.url)
            }
        )
    }

    /// The single-colour mark the status panel draws for an input source.
    ///
    /// See `InputSourceIconMask`: the panel tints its rows, so an icon has to
    /// survive as ink rather than as its own palette, and the conversion is not
    /// something the SwiftUI body may repeat per pass.
    func monochromeInputSourceIcon(
        for url: URL,
        maximumPixelLength: Int = InputSourceIconMask.defaultMaximumPixelLength
    ) -> NSImage? {
        let identity = resolvedIdentity(for: url)
        return image(
            for: Key(
                identity: identity,
                normalizedPixelLength: maximumPixelLength,
                kind: .inputSourceMask
            ),
            load: {
                guard let image = decodedImage(
                    for: identity,
                    maximumPixelLength: maximumPixelLength
                ) else { return nil }
                return InputSourceIconMask.make(
                    from: image,
                    maximumPixelLength: maximumPixelLength
                )
            }
        )
    }

    private func image(for key: Key, load: () -> NSImage?) -> NSImage? {
        let loadEpoch: UInt64
        lock.lock()
        if let cached = storage[key] {
            touch(key)
            let image = cached.image
            lock.unlock()
            return image
        }
        loadEpoch = epoch
        lock.unlock()

        guard let image = load() else { return nil }
        guard let byteCount = Self.bitmapByteCount(of: image) else { return image }

        guard byteCount <= maximumResidentBytes else { return image }

        lock.lock()
        defer { lock.unlock() }
        guard epoch == loadEpoch else { return image }
        if let existing = storage[key] {
            touch(key)
            return existing.image
        }

        storage[key] = Entry(image: image, byteCount: byteCount)
        residentBytes += byteCount
        order.append(key)
        while order.count > maximumEntries || residentBytes > maximumResidentBytes {
            let oldest = order.removeFirst()
            if let removed = storage.removeValue(forKey: oldest) {
                residentBytes -= removed.byteCount
            }
        }
        return image
    }

    /// Convenience for callers whose loader is the bounded image rasterizer.
    func decodedImage(
        for identity: IconImageFileIdentity,
        maximumPixelLength: Int = 512
    ) -> NSImage? {
        image(
            for: Key(
                identity: identity,
                normalizedPixelLength: maximumPixelLength,
                kind: .decoded
            ),
            load: {
                IconImageRasterizer.image(
                    at: identity.url,
                    maximumPixelLength: maximumPixelLength
                )
            }
        )
    }

    func decodedImage(
        for url: URL,
        maximumPixelLength: Int = 512
    ) -> NSImage? {
        decodedImage(
            for: resolvedIdentity(for: url),
            maximumPixelLength: maximumPixelLength
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        storage.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
        residentBytes = 0
        lastKnownFileVersions.removeAll(keepingCapacity: false)
    }

    private func resolvedIdentity(for url: URL) -> IconImageFileIdentity {
        let standardizedURL = url.standardizedFileURL
        let current = IconImageFileIdentity(url: standardizedURL)
        lock.lock()
        defer { lock.unlock() }
        if current.hasFileVersion {
            lastKnownFileVersions[standardizedURL] = current
            return current
        }
        return lastKnownFileVersions[standardizedURL] ?? current
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func bitmapByteCount(of image: NSImage) -> Int? {
        guard !image.representations.isEmpty else { return 0 }

        var total = 0
        for representation in image.representations {
            guard let bitmap = representation as? NSBitmapImageRep else {
                return nil
            }
            let planeCount = max(1, bitmap.numberOfPlanes)
            let bytesPerPlane = bitmap.isPlanar
                ? max(0, bitmap.bytesPerPlane)
                : max(0, bitmap.bytesPerRow) * max(0, bitmap.pixelsHigh)
            total += planeCount * bytesPerPlane
        }
        return total
    }
}
