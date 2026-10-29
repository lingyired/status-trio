import Foundation

enum WiFiEventSignal: Equatable, Sendable {
    case connectionInterrupted
    case connectionInvalidated
    case powerChanged
    case ssidChanged
    case bssidChanged
    case linkChanged
    case linkQuality(rssi: Int)
    case modeChanged
}

struct WiFiEventBatch: Equatable, Sendable {
    var connectionInterrupted = false
    var connectionInvalidated = false
    var associationChanged = false
    var needsRefresh = false
    var latestRSSI: Int?
}

struct WiFiEventCounts: Equatable, Sendable {
    var connectionInterrupted: UInt64 = 0
    var connectionInvalidated: UInt64 = 0
    var powerChanged: UInt64 = 0
    var ssidChanged: UInt64 = 0
    var bssidChanged: UInt64 = 0
    var linkChanged: UInt64 = 0
    var linkQualityChanged: UInt64 = 0
    var modeChanged: UInt64 = 0
}

struct WiFiEventDiagnosticsSnapshot: Equatable, Sendable {
    var counts = WiFiEventCounts()
    var deliveredBatches: UInt64 = 0
    var maximumPendingSignals = 0
    var activeGeneration: UInt64 = 0
}

/// Coalesces CoreWLAN delegate callbacks before they reach the main actor.
///
/// CoreWLAN may deliver callbacks faster than SwiftUI and the status pipeline can
/// consume them. Creating one unstructured task per callback turns that burst
/// into an unbounded retained queue, so only the callback that opens a delivery
/// window is allowed to schedule main-actor work.
final class WiFiEventMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = WiFiEventBatch()
    private var deliveryScheduled = false
    private var isClosed = false
    private var diagnostics = WiFiEventDiagnosticsSnapshot()
    private var pendingSignalCount = 0

    @discardableResult
    func activate(generation: UInt64) -> WiFiEventBatch? {
        lock.withLock {
            guard !isClosed else { return nil }

            let supersededBatch = pending
            diagnostics.activeGeneration = generation
            pending = WiFiEventBatch()
            deliveryScheduled = false
            pendingSignalCount = 0
            return supersededBatch
        }
    }

    @discardableResult
    func enqueue(_ event: WiFiEventSignal, generation: UInt64) -> Bool {
        lock.withLock {
            guard !isClosed, generation == diagnostics.activeGeneration else {
                return false
            }

            pending.merge(event)
            diagnostics.counts.record(event)
            pendingSignalCount &+= 1
            diagnostics.maximumPendingSignals = max(
                diagnostics.maximumPendingSignals,
                pendingSignalCount
            )

            guard !deliveryScheduled else { return false }
            deliveryScheduled = true
            return true
        }
    }

    func take() -> WiFiEventBatch? {
        lock.withLock {
            guard !isClosed, deliveryScheduled else { return nil }

            deliveryScheduled = false
            let batch = pending
            pending = WiFiEventBatch()
            pendingSignalCount = 0
            diagnostics.deliveredBatches &+= 1
            return batch
        }
    }

    func close() {
        lock.withLock {
            isClosed = true
            deliveryScheduled = false
            pending = WiFiEventBatch()
            pendingSignalCount = 0
        }
    }

    func diagnosticsSnapshot() -> WiFiEventDiagnosticsSnapshot {
        lock.withLock { diagnostics }
    }
}

private extension WiFiEventBatch {
    mutating func merge(_ event: WiFiEventSignal) {
        switch event {
        case .connectionInterrupted:
            connectionInterrupted = true
            needsRefresh = true
        case .connectionInvalidated:
            connectionInvalidated = true
            needsRefresh = true
        case .powerChanged, .ssidChanged, .bssidChanged, .linkChanged:
            associationChanged = true
            needsRefresh = true
            // The association changed after any signal delivered earlier in this
            // batch, so that value belongs to the previous network.
            latestRSSI = nil
        case .linkQuality(let rssi):
            latestRSSI = rssi
            needsRefresh = true
        case .modeChanged:
            needsRefresh = true
        }
    }
}

private extension WiFiEventCounts {
    mutating func record(_ event: WiFiEventSignal) {
        switch event {
        case .connectionInterrupted:
            connectionInterrupted &+= 1
        case .connectionInvalidated:
            connectionInvalidated &+= 1
        case .powerChanged:
            powerChanged &+= 1
        case .ssidChanged:
            ssidChanged &+= 1
        case .bssidChanged:
            bssidChanged &+= 1
        case .linkChanged:
            linkChanged &+= 1
        case .linkQuality:
            linkQualityChanged &+= 1
        case .modeChanged:
            modeChanged &+= 1
        }
    }
}
