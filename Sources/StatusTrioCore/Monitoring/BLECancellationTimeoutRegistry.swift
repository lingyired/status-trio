import Foundation

/// Owns the timeout for GATT cancellations that wait for CoreBluetooth to
/// report `didDisconnect`.
///
/// A session retires by calling `cancelPeripheralConnection` and keeping the
/// peripheral until the callback arrives. The callback is not guaranteed: a
/// radio reset, a powered-off stack, or a peripheral that vanishes can drop it,
/// and the scanner would then keep the session, the delegate and the central
/// manager alive forever. This registry runs the same teardown after a bounded
/// interval instead.
@MainActor
final class BLECancellationTimeoutRegistry {
    /// Long enough for a normal disconnect round-trip, short enough that a lost
    /// callback cannot pin a session for the life of the process.
    static let defaultTimeout: Duration = .seconds(10)

    private struct Entry {
        let sessionID: UUID
        let onTimeout: @MainActor () -> Void
    }

    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var entries: [UUID: Entry] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        timeout: Duration = BLECancellationTimeoutRegistry.defaultTimeout,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.timeout = timeout
        self.sleep = sleep
    }

    var pendingCount: Int { entries.count }

    /// Starts the timeout for a retired session. Replacing an entry with the
    /// same identifier cancels the previous timer.
    func begin(id: UUID, sessionID: UUID, onTimeout: @escaping @MainActor () -> Void) {
        finish(id: id)
        entries[id] = Entry(sessionID: sessionID, onTimeout: onTimeout)
        let interval = timeout
        let sleep = self.sleep
        tasks[id] = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                return
            }
            guard let self else { return }
            self.fire(id: id, expectedSession: sessionID)
        }
    }

    /// Marks the cancellation as finished, normally from `didDisconnect`.
    func finish(id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        entries[id] = nil
    }

    /// Runs an entry's timeout immediately. Test seam; production waits.
    func expireNow(id: UUID) {
        guard let entry = entries[id] else { return }
        fire(id: id, expectedSession: entry.sessionID)
    }

    private func fire(id: UUID, expectedSession: UUID) {
        guard let entry = entries[id], entry.sessionID == expectedSession else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        entries[id] = nil
        entry.onTimeout()
    }
}
