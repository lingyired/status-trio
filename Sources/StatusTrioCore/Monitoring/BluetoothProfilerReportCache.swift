import Foundation

/// One `system_profiler -json SPBluetoothDataType` run feeds both the paired
/// device list and the battery levels: both parsers read the same JSON, so a
/// second process would only repeat work the first one already did. The device
/// worker fills the cache, the battery worker reads it, and neither owns the
/// other, so the app shares a single instance.
final class BluetoothProfilerReportCache: @unchecked Sendable {
    typealias ReaderToken = UUID

    static let shared = BluetoothProfilerReportCache()

    /// A report is treated as absent once this long has passed since the last
    /// `store` — the moment the report was produced — rather than since some
    /// earlier production. The workers store only the bytes they fetch, so a
    /// read that merely reuses a report does not move the window forward: a
    /// battery read that happens on its own still asks the system for current
    /// data instead of reusing a level that may already be stale.
    static let defaultMaxAge: TimeInterval = 5

    private let lock = NSLock()
    private var entry: (data: Data, storedAt: Date)?
    private var epoch: UInt64 = 0
    private var readers: Set<ReaderToken> = []

    func store(_ data: Data, at date: Date = Date()) {
        lock.withLock { entry = (data, date) }
    }

    var currentEpoch: UInt64 {
        lock.withLock { epoch }
    }

    @discardableResult
    func store(_ data: Data, at date: Date = Date(), ifCurrent capturedEpoch: UInt64) -> Bool {
        lock.withLock {
            guard capturedEpoch == epoch else { return false }
            entry = (data, date)
            return true
        }
    }

    func freshData(
        maxAge: TimeInterval = BluetoothProfilerReportCache.defaultMaxAge,
        now: Date = Date()
    ) -> Data? {
        lock.withLock {
            guard let entry else { return nil }
            guard now.timeIntervalSince(entry.storedAt) < maxAge else {
                self.entry = nil
                return nil
            }
            return entry.data
        }
    }

    func reset() {
        lock.withLock {
            resetLocked()
        }
    }

    /// Registers a lifecycle owner that may read the shared report. The final
    /// release discards the bytes and invalidates fetches that started before it.
    func acquireReader() -> ReaderToken {
        lock.withLock {
            let token = UUID()
            readers.insert(token)
            return token
        }
    }

    func releaseReader(_ token: ReaderToken) {
        lock.withLock {
            guard readers.remove(token) != nil, readers.isEmpty else { return }
            resetLocked()
        }
    }

    /// Clears the shared report only when no owning reader remains. A controller
    /// deactivation may therefore leave another subsystem's in-flight read alone.
    @discardableResult
    func resetIfUnused() -> Bool {
        lock.withLock {
            guard readers.isEmpty else { return false }
            resetLocked()
            return true
        }
    }

    var storedEntryCount: Int {
        lock.withLock { entry == nil ? 0 : 1 }
    }

    var activeReaderCount: Int {
        lock.withLock { readers.count }
    }

    private func resetLocked() {
        entry = nil
        epoch &+= 1
    }
}
