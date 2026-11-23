import Combine
import Foundation

enum LocalIconPluginDataError: Error, Equatable {
    case unreadable
    case tooLarge
    case invalidJSON
    case unsupportedSchemaVersion(Int)
    case invalidObservedAt
    case futureObservedAt
    case staleReading
    case olderThanCurrent
    case invalidValue(String)
}

enum LocalIconPluginValue: Equatable, Sendable {
    case text(String)
    case fraction(Double)
}

struct LocalIconPluginReading: Equatable, Sendable {
    static let maximumLifetime: TimeInterval = 15
    static let maximumFutureSkew: TimeInterval = 2
    static let maximumTextLength = 16

    let schemaVersion: Int
    let observedAt: Date
    let values: [String: LocalIconPluginValue]

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(observedAt) <= Self.maximumLifetime
    }
}

enum LocalIconPluginDataReader {
    static func load(
        directory: URL,
        manifest: LocalIconPluginManifest,
        now: Date,
        lastAccepted: Date?
    ) throws -> LocalIconPluginReading {
        let data: Data
        do {
            data = try LocalIconFileReader.readRegularFile(
                at: "data.json",
                inDirectory: directory,
                maximumBytes: LocalIconPluginManifest.maximumFileBytes
            )
        } catch LocalIconPluginManifestError.tooLarge {
            throw LocalIconPluginDataError.tooLarge
        } catch {
            throw LocalIconPluginDataError.unreadable
        }
        return try decode(data: data, manifest: manifest, now: now, lastAccepted: lastAccepted)
    }

    static func decode(
        data: Data,
        manifest: LocalIconPluginManifest,
        now: Date,
        lastAccepted: Date?
    ) throws -> LocalIconPluginReading {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LocalIconPluginDataError.invalidJSON
        }
        guard let object = root as? [String: Any] else {
            throw LocalIconPluginDataError.invalidJSON
        }
        guard let version = object["schemaVersion"] as? Int else {
            throw LocalIconPluginDataError.invalidJSON
        }
        guard version == LocalIconPluginManifest.schemaVersion else {
            throw LocalIconPluginDataError.unsupportedSchemaVersion(version)
        }
        guard let rawObservedAt = object["observedAt"] as? String,
              let observedAt = Self.parseISO8601(rawObservedAt) else {
            throw LocalIconPluginDataError.invalidObservedAt
        }
        if observedAt.timeIntervalSince(now) > LocalIconPluginReading.maximumFutureSkew {
            throw LocalIconPluginDataError.futureObservedAt
        }
        if now.timeIntervalSince(observedAt) > LocalIconPluginReading.maximumLifetime {
            throw LocalIconPluginDataError.staleReading
        }
        if let lastAccepted, observedAt < lastAccepted {
            throw LocalIconPluginDataError.olderThanCurrent
        }
        guard let rawValues = object["values"] as? [String: Any] else {
            throw LocalIconPluginDataError.invalidJSON
        }
        let kinds = Dictionary(uniqueKeysWithValues: manifest.presentations.map { ($0.id, $0.kind) })
        var values: [String: LocalIconPluginValue] = [:]
        for (presentationID, kind) in kinds {
            guard let raw = rawValues[presentationID] else { continue }
            switch kind {
            case .text:
                guard let text = raw as? String,
                      !text.isEmpty,
                      text.count <= LocalIconPluginReading.maximumTextLength,
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw LocalIconPluginDataError.invalidValue(presentationID)
                }
                values[presentationID] = .text(text)
            case .fraction:
                guard !Self.isBoolean(raw),
                      let number = raw as? NSNumber else {
                    throw LocalIconPluginDataError.invalidValue(presentationID)
                }
                let fraction = number.doubleValue
                guard fraction.isFinite, (0...1).contains(fraction) else {
                    throw LocalIconPluginDataError.invalidValue(presentationID)
                }
                values[presentationID] = .fraction(fraction)
            }
        }
        return LocalIconPluginReading(
            schemaVersion: version,
            observedAt: observedAt,
            values: values
        )
    }

    static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func isBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }
}

/// The value side of a local package, safe to read from the plugin's resolve
/// call on the main thread while the feed writes from its own task.
final class LocalIconPluginValueStore: @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [String: LocalIconPluginReading] = [:]

    func update(pluginID: String, reading: LocalIconPluginReading?) {
        lock.lock()
        defer { lock.unlock() }
        readings[pluginID] = reading
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        readings.removeAll()
    }

    func value(pluginID: String, presentationID: String, now: Date) -> LocalIconPluginValue? {
        lock.lock()
        defer { lock.unlock() }
        guard let reading = readings[pluginID], reading.isFresh(at: now) else { return nil }
        return reading.values[presentationID]
    }
}

@MainActor
protocol LocalIconPluginExpiryScheduling: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class TaskLocalIconPluginExpiryScheduler: LocalIconPluginExpiryScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Watches one package's `data.json` and publishes the latest accepted reading.
///
/// It never polls: a directory vnode source reacts to atomic replacement, and a
/// scheduled expiry clears the reading after 15 seconds even when the producer
/// stops writing. A file that is missing or malformed clears the value
/// immediately so the host can fall back without waiting for the deadline.
enum LocalIconPluginFeedLoadResult: Sendable {
    case reading(LocalIconPluginReading)
    case missingOrInvalid
    case olderThanCurrent
}

@MainActor
final class LocalIconPluginFeed {
    typealias Loader = @Sendable (URL, LocalIconPluginManifest, Date, Date?) -> LocalIconPluginFeedLoadResult

    let pluginID: String
    @Published private(set) var reading: LocalIconPluginReading?
    private let directory: URL
    private let manifest: LocalIconPluginManifest
    private let now: @MainActor () -> Date
    private let expiry: any LocalIconPluginExpiryScheduling
    private let loader: Loader
    private let fileWatching: Bool
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchDescriptor: Int32 = -1
    private var isStarted = false
    private var readingGeneration = 0
    /// Monotonic token for the single in-flight read. `stop()` and every newer
    /// read advance it, so a late result from an older generation is dropped.
    private var loadGeneration = 0
    /// Distinguishes a stop/start pair even when the new session has not issued
    /// its first read yet; a result from the previous session must never appear
    /// in the restarted feed.
    private var sessionGeneration = 0
    private var isReloading = false
    private var reloadPending = false

    init(
        directory: URL,
        manifest: LocalIconPluginManifest,
        now: @escaping @MainActor () -> Date = Date.init,
        expiry: (any LocalIconPluginExpiryScheduling)? = nil,
        fileWatching: Bool = true,
        loader: @escaping Loader = { directory, manifest, now, lastAccepted in
            do {
                return .reading(try LocalIconPluginDataReader.load(
                    directory: directory, manifest: manifest, now: now, lastAccepted: lastAccepted))
            } catch LocalIconPluginDataError.olderThanCurrent {
                return .olderThanCurrent
            } catch {
                return .missingOrInvalid
            }
        }
    ) {
        self.directory = directory
        self.manifest = manifest
        self.pluginID = manifest.pluginID
        self.now = now
        self.expiry = expiry ?? TaskLocalIconPluginExpiryScheduler()
        self.fileWatching = fileWatching
        self.loader = loader
    }

    func start(reloadImmediately: Bool = true) {
        guard !isStarted else { return }
        isStarted = true
        sessionGeneration += 1
        if fileWatching { startWatching() }
        if reloadImmediately { Task { await reload() } }
    }

    var isRunning: Bool { isStarted }

    func stop() {
        isStarted = false
        sessionGeneration += 1
        loadGeneration += 1
        readingGeneration += 1
        reloadPending = false
        reading = nil
        if let watchSource {
            watchSource.cancel()
            self.watchSource = nil
            watchDescriptor = -1
        } else if watchDescriptor >= 0 {
            close(watchDescriptor)
            watchDescriptor = -1
        }
        expiry.cancel()
    }

    /// Reads `data.json` at most once at a time.
    ///
    /// Directory events can arrive in bursts (a script rewriting the file, a
    /// package being replaced). While a read is in flight further requests only
    /// set one pending flag; when the read finishes the feed performs at most one
    /// more read for all of them. `loadGeneration` rejects a result whose read
    /// started before a newer read or before `stop()`.
    func reload() async {
        guard isStarted else { return }
        if isReloading {
            reloadPending = true
            return
        }
        isReloading = true
        repeat {
            reloadPending = false
            await performReload()
        } while reloadPending && isStarted
        isReloading = false
    }

    var hasPendingReload: Bool { reloadPending }

    private func performReload() async {
        guard isStarted else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let session = sessionGeneration
        let directory = self.directory
        let manifest = self.manifest
        let date = now()
        let lastAccepted = reading?.observedAt
        let loader = self.loader
        let loaded: LocalIconPluginFeedLoadResult = await Task.detached(priority: .utility) {
            loader(directory, manifest, date, lastAccepted)
        }.value
        guard isStarted, session == sessionGeneration, generation == loadGeneration else { return }

        switch loaded {
        case let .reading(loaded):
            // The file can expire while the read is in flight; applying it then
            // would re-publish data whose deadline already passed.
            guard loaded.isFresh(at: now()) else { return }
            // A newer write could have landed while an older read was in flight.
            if let current = reading, loaded.observedAt < current.observedAt { return }
            reading = loaded
            readingGeneration += 1
            scheduleExpiry(for: loaded, generation: readingGeneration)
        case .olderThanCurrent:
            // Keep the in-use value; an older read must not clear or overwrite it.
            return
        case .missingOrInvalid:
            // Missing/malformed data releases the slot immediately; the
            // configured fallback then draws without waiting for the deadline.
            reading = nil
            readingGeneration += 1
            expiry.cancel()
        }
    }

    private func scheduleExpiry(for reading: LocalIconPluginReading, generation: Int) {
        let remaining = LocalIconPluginReading.maximumLifetime
            + reading.observedAt.timeIntervalSince(now())
        expiry.schedule(after: max(0, remaining)) { [weak self] in
            guard let self, self.readingGeneration == generation else { return }
            self.reading = nil
        }
    }

    private func startWatching() {
        let descriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_EVTONLY)
        }
        guard descriptor >= 0 else { return }
        watchDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.reload() }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        watchSource = source
    }
}
