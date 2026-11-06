import Combine
import Foundation

/// One refresh's worth of shared power rails. `system` is the whole-machine
/// total the icon/panel use; `input` and `battery` are only read when a surface
/// (the provisional power info bar) actually shows them.
struct PowerSamplingReading: Equatable, Sendable {
    var system: SystemPowerSample?
    var input: SystemPowerSample?
    var battery: BatteryPowerSample?

    static let empty = Self()
}

/// The one owner of periodic (`PSTR` and, on demand, input/battery) power reads.
///
/// The menu-bar/Dock centre slot, the status panel summary, the provisional
/// power info bar and the battery details page each need a power reading. They
/// register a demand here instead of starting their own timer, so one surface
/// ending never cuts the sample another surface is still using, and the SMC is
/// never read twice for the same refresh.
///
/// Every demand shares one rhythm: an open panel, the details page and the
/// power info bar need live watts and read every two seconds. The icon alone
/// updates only a menu-bar/Dock number, so it samples at five seconds — a
/// panel opening registers `.panel` and reads immediately, which is what keeps
/// the first open responsive while the idle icon stops waking the SMC as often.
/// The sampler still stops once the last demand ends; this is not a promise of
/// no extra wakeups.
@MainActor
final class PowerSamplingService: ObservableObject {
    enum Demand: Hashable, Sendable {
        /// The centre slot is set to show watts.
        case icon
        /// The status panel can present power (the battery summary or a
        /// no-battery device's power title).
        case panel
        /// The provisional power info bar is enabled and the panel is open, so
        /// the input and battery rails are needed too.
        case powerInfoBar
        /// The battery details page is open.
        case details
    }

    typealias Reader = @Sendable (_ includeAuxiliaryRails: Bool) -> PowerSamplingReading

    static let interval: Duration = .seconds(2)
    /// Cadence when the icon's watts are the only live surface. Opening a panel
    /// adds `.panel`, which restores `interval` and reads immediately on begin.
    static let iconOnlyInterval: Duration = .seconds(5)

    @Published private(set) var systemPower: SystemPowerSample?
    @Published private(set) var inputPower: SystemPowerSample?
    @Published private(set) var batteryPower: BatteryPowerSample?
    /// Whether a whole-machine read has completed since the sampler last stopped.
    /// The panel uses it to tell "still loading" from "no rail to show", so it can
    /// reserve the info-bar height with a skeleton instead of growing on arrival.
    @Published private(set) var hasCompletedFirstRead = false
    /// Exposed for tests and diagnostics.
    private(set) var demands: Set<Demand> = []
    private(set) var isRunning = false

    /// The cadence the next tick uses. The panel and details page need live
    /// watts; an icon-only demand does not.
    var samplingInterval: Duration {
        demands.isSubset(of: [.icon]) ? Self.iconOnlyInterval : Self.interval
    }

    private static let queue = DispatchQueue(
        label: "com.lingsmbp.StatusTrio.power-sampling",
        qos: .utility
    )
    private let reader: Reader
    private var loopTask: Task<Void, Never>?
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false

    init(reader: @escaping Reader = { includeAuxiliaryRails in
        let sensors = SystemPowerReader().readSensors(
            system: true,
            input: includeAuxiliaryRails,
            battery: includeAuxiliaryRails
        )
        return PowerSamplingReading(
            system: sensors.system,
            input: sensors.input,
            battery: sensors.battery
        )
    }) {
        self.reader = reader
    }

    deinit { loopTask?.cancel() }

    /// Idempotent: calling `begin` for a demand already registered does nothing.
    func begin(_ demand: Demand) {
        guard demands.insert(demand).inserted else { return }
        if !isRunning {
            isRunning = true
            startLoop()
        }
        // The first demand must not wait a full cycle.
        refresh()
    }

    func end(_ demand: Demand) {
        guard demands.remove(demand) != nil else { return }
        if demands.isEmpty {
            stopLoop()
        } else if demand == .powerInfoBar {
            // Stop showing input/battery as soon as nothing displays them.
            clearAuxiliaryRails()
        }
    }

    func stopAll() {
        demands.removeAll()
        stopLoop()
    }

    /// Reads now instead of waiting for the next tick. Tests use it; production
    /// reaches the same path through `begin` and the loop.
    func refresh() {
        guard isRunning else { return }
        if inFlight {
            needsRefresh = true
            return
        }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let reader = reader
        let includeAuxiliaryRails = demands.contains(.powerInfoBar)
        Self.queue.async { [weak self] in
            let reading = reader(includeAuxiliaryRails)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.isRunning, self.generation == generation {
                    if self.systemPower != reading.system { self.systemPower = reading.system }
                    if includeAuxiliaryRails, self.demands.contains(.powerInfoBar) {
                        if self.inputPower != reading.input { self.inputPower = reading.input }
                        if self.batteryPower != reading.battery { self.batteryPower = reading.battery }
                    }
                    if !self.hasCompletedFirstRead { self.hasCompletedFirstRead = true }
                }
                if self.needsRefresh {
                    self.needsRefresh = false
                    self.refresh()
                }
            }
        }
    }

    private func startLoop() {
        generation += 1
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Read the cadence without retaining the service across the
                // sleep; the demand set can change meanwhile.
                let interval = self?.samplingInterval ?? Self.interval
                do {
                    try await Task.sleep(for: interval, tolerance: .milliseconds(200))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        generation += 1
        needsRefresh = false
        // A stopped sampler must not leave a value behind for a surface that
        // opens later; a fresh demand starts a new read.
        if systemPower != nil { systemPower = nil }
        clearAuxiliaryRails()
        hasCompletedFirstRead = false
    }

    private func clearAuxiliaryRails() {
        if inputPower != nil { inputPower = nil }
        if batteryPower != nil { batteryPower = nil }
    }
}
