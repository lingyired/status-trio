import Combine
import Foundation

/// The existing battery icon monitor remains event-driven. Only the expanded
/// details view activates this store-owned collector; closing ends periodic work.
@MainActor
final class BatteryDetailsController: ObservableObject {
    typealias Reader = @Sendable (BatteryPowerState, Date?) -> BatteryDetails
    @Published private(set) var details: BatteryDetails?
    let energyApps: ApplicationEnergyController
    /// True while the collector owns periodic work. The popover uses this to
    /// treat an open battery page like its Wi-Fi and Bluetooth counterparts.
    var isActive: Bool { active }
    private let reader: Reader?
    /// The shared system-power sampler. Set once by the store after both objects
    /// exist; nil in previews and standalone tests that do not need it.
    var powerSampling: PowerSamplingService?
    private var options = BatteryPowerDisplayOptions.default
    private var showsHighEnergyApps = false
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.battery-details", qos: .utility)
    private var active = false
    private var state: BatteryPowerState?
    private var notBefore: Date?
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false
    private var refreshTask: Task<Void, Never>?

    init(reader: Reader? = nil, energyApps: ApplicationEnergyController? = nil) {
        self.reader = reader
        self.energyApps = energyApps ?? ApplicationEnergyController()
    }

    deinit { refreshTask?.cancel() }

    func activate(state: BatteryPowerState, now: Date = Date()) {
        // The route and the detail view can both request the same presentation
        // during one open. Keep the existing read and its demand alive.
        if active, self.state == state { return }
        if let previous = self.state, previous != state {
            notBefore = now
        }
        self.state = state
        active = true
        generation += 1
        details = nil
        if showsHighEnergyApps { energyApps.activate() }
        updatePowerDemand()
        refresh()
        startRefreshLoop()
    }

    /// The details page is the only surface that reads a split or a charging
    /// sample, but the whole-machine total it shows is owned by the shared
    /// sampler. Register the demand only when this page can actually present it.
    private func updatePowerDemand() {
        guard let powerSampling else { return }
        let wantsSystemPower: Bool
        if active, let state {
            wantsSystemPower = BatteryDetailsReader.readsSystemPower(for: state)
                && (!state.isPresent || options.showsSystem)
        } else {
            wantsSystemPower = false
        }
        if wantsSystemPower {
            powerSampling.begin(.details)
        } else {
            powerSampling.end(.details)
        }
    }

    func configure(options: BatteryPowerDisplayOptions, showsHighEnergyApps: Bool) {
        let changed = self.options != options
        self.options = options
        self.showsHighEnergyApps = showsHighEnergyApps
        if active && showsHighEnergyApps { energyApps.activate() } else { energyApps.deactivate() }
        if changed && active {
            updatePowerDemand()
            refresh()
            startRefreshLoop()
        }
    }

    /// Keeps the collector's power-source context current while its page stays
    /// open. `activate` only sees the state at presentation; a plugin or a
    /// charge-limit pulse that starts later must reach the next read too.
    func update(state: BatteryPowerState, now: Date = Date()) {
        guard active, self.state != state else { return }
        if self.state?.isConnected != state.isConnected
            || self.state?.isCharging != state.isCharging {
            // A registry sample from before the transition cannot stand in for
            // the new state.
            notBefore = now
        }
        self.state = state
        updatePowerDemand()
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        let interval: Duration = options.showsAnyPower ? .seconds(2) : .seconds(15)
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval, tolerance: .milliseconds(250)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func deactivate() {
        powerSampling?.end(.details)
        active = false
        refreshTask?.cancel()
        refreshTask = nil
        generation += 1
        needsRefresh = false
        details = nil
        energyApps.deactivate()
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
        if let sample = details?.inputPower, !sample.isFresh(at: now) {
            details?.inputPower = nil
        }
        if let split = details?.breakdown,
           now.timeIntervalSince(split.readAt) > BatteryDetailsReader.breakdownHoldSeconds {
            details?.breakdown = nil
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
        let options = options
        let previousBreakdown = details?.breakdown
        // The shared sampler owns the SMC whole-machine read. Hand its latest
        // sample to the reader so the details page never opens a second
        // system-power connection of its own.
        let sharedSystemPower = powerSampling?.systemPower
        let usesSharedSystemPower = powerSampling != nil
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let result = reader?(state, notBefore)
                ?? BatteryDetailsReader().read(state: state, notBefore: notBefore, options: options,
                                                previousBreakdown: previousBreakdown,
                                                systemPower: sharedSystemPower,
                                                usesSharedSystemPower: usesSharedSystemPower)
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
                    if let sample = current.inputPower, !sample.isFresh(at: Date(), notBefore: self.notBefore) {
                        current.inputPower = nil
                    }
                    if let split = current.breakdown,
                       Date().timeIntervalSince(split.readAt) > BatteryDetailsReader.breakdownHoldSeconds {
                        current.breakdown = nil
                    }
                    self.details = current
                }
                if self.needsRefresh { self.refresh() }
            }
        }
    }
}
