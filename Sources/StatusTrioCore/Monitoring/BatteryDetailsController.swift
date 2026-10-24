import Combine
import Foundation

/// The existing battery icon monitor remains event-driven. Only the expanded
/// details view activates this store-owned collector; closing ends periodic work.
@MainActor
final class BatteryDetailsController: ObservableObject {
    typealias Reader = @Sendable (BatteryPowerState, Date?) -> BatteryDetails
    @Published private(set) var details: BatteryDetails?
    /// True while the collector owns periodic work. The popover uses this to
    /// treat an open battery page like its Wi-Fi and Bluetooth counterparts.
    var isActive: Bool { active }
    private let reader: Reader
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.battery-details", qos: .utility)
    private var active = false
    private var state: BatteryPowerState?
    private var notBefore: Date?
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false
    private var refreshTask: Task<Void, Never>?

    init(
        systemPowerReader: any SystemPowerReading = UnavailableSystemPowerReader(),
        reader: (@Sendable (BatteryPowerState, Date?) -> BatteryDetails)? = nil
    ) {
        self.reader = reader ?? { state, notBefore in
            BatteryDetailsReader(systemPowerReader: systemPowerReader)
                .read(state: state, notBefore: notBefore)
        }
    }

    deinit { refreshTask?.cancel() }

    func activate(state: BatteryPowerState, now: Date = Date()) {
        if let previous = self.state, previous != state {
            notBefore = now
        }
        self.state = state
        active = true
        generation += 1
        details = nil
        refresh()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15), tolerance: .seconds(3)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func deactivate() {
        active = false
        refreshTask?.cancel()
        refreshTask = nil
        generation += 1
        needsRefresh = false
        details = nil
    }

    func refresh(now: Date = Date()) {
        guard active, let state else { return }
        // Expire even when the previous system read is still blocked.
        if let sample = details?.power, !sample.isFresh(at: now) {
            details?.power = nil
            details?.powerAvailability = .collecting
        }
        if let sample = details?.systemPower, !sample.isFresh(at: now) {
            details?.systemPower = nil
        }
        guard !inFlight else {
            needsRefresh = true
            return
        }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let notBefore = notBefore
        let reader = reader
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let result = reader(state, notBefore)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.active && self.generation == generation {
                    var current = result
                    // System IPC and delivery to the main actor can both be delayed.
                    if let sample = current.power, !sample.isFresh(at: Date(), notBefore: self.notBefore) {
                        current.power = nil
                        current.powerAvailability = .collecting
                    }
                    if let sample = current.systemPower, !sample.isFresh(at: Date(), notBefore: self.notBefore) {
                        current.systemPower = nil
                    }
                    self.details = current
                }
                if self.needsRefresh { self.refresh() }
            }
        }
    }
}
