import Foundation

private let wiFiStatusReaderQueueLabel = "StatusTrio.WiFiStatusReader"

struct WiFiStatusReading: Sendable {
    let interface: WiFiSystemReading?
    let sharingActive: Bool
}

@MainActor
protocol WiFiStatusReadingProviding: AnyObject {
    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    )
}

/// CoreWLAN and SystemConfiguration reads are synchronous IPC. Keep them off
/// both the main actor and Swift's cooperative executor, on one serial queue.
@MainActor
final class CoreWLANStatusReader: WiFiStatusReadingProviding {
    private var queue = DispatchQueue(label: wiFiStatusReaderQueueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let readSystem: @Sendable (Bool) -> WiFiStatusReading

    init(readSystem: @escaping @Sendable (Bool) -> WiFiStatusReading = { includeSSID in
        let reading = CoreWLANWiFiSystemReader().read(includeSSID: includeSSID)
        let sharing = reading.map { $0.powerOn && $0.serviceActive } == true
            && SystemInternetSharingDetector().isActive() == true
        return WiFiStatusReading(interface: reading, sharingActive: sharing)
    }) {
        self.readSystem = readSystem
    }

    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    ) {
        // A read that never returned would block this one behind it on the same
        // serial queue for the lifetime of the process, so retire that queue and
        // give this read a fresh one. The abandoned block keeps the old queue
        // alive until it eventually returns.
        if hasOutstandingRead {
            queueGeneration &+= 1
            queue = DispatchQueue(label: wiFiStatusReaderQueueLabel, qos: .utility)
        }
        hasOutstandingRead = true
        let generation = queueGeneration
        let currentQueue = queue
        let readSystem = readSystem
        currentQueue.async { [weak self] in
            let reading = readSystem(includeSSID)
            Task { @MainActor in
                // Only the read on the current queue may clear the flag; a late
                // completion from a retired queue must not.
                if let self, generation == self.queueGeneration {
                    self.hasOutstandingRead = false
                }
                completion(reading)
            }
        }
    }
}
