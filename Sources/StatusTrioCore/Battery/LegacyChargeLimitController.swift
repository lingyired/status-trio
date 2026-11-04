import Combine
import Foundation

/// App-facing state for the legacy charge limiter (macOS 13–15).
///
/// It owns the user intent and the UI status; the *hardware* ownership record
/// lives in the helper's journal so a crash cannot lose the stock value. The
/// controller never writes SMC keys: every command is a typed request.
@MainActor
final class LegacyChargeLimitController: ObservableObject {
    static let limits = Array(stride(from: 80, through: 100, by: 5))

    @Published private(set) var availability: LegacyChargeLimitAvailability = .unavailable(.helperUnavailable)
    @Published private(set) var status: LegacyChargeLimitStatus = .notEnabled
    @Published private(set) var selectedLimit: Int?
    @Published private(set) var isApplying = false

    private let client: any LegacyChargeLimitClienting
    private let sessionStore: any LegacyChargeLimitSessionStoring
    private let architecture: LegacyRuntimeArchitecture
    private let osBand: LegacyOSBand
    private var session: LegacyChargeLimitSession?
    private var started = false
    private var cancellables: Set<AnyCancellable> = []
    private var batteries: (any Publisher<BatteryStatus, Never>)?
    /// Last gate decision this controller asked for, so hysteresis does not
    /// flap on small level wobbles and we do not write on every battery tick.
    private var lastAppliedAllowsCharging: Bool?

    init(
        client: any LegacyChargeLimitClienting = XPCPrivilegedLegacyChargeClient(),
        sessionStore: any LegacyChargeLimitSessionStoring = UserDefaultsLegacyChargeLimitSessionStore(defaults: .standard),
        architecture: LegacyRuntimeArchitecture = LegacyRuntimeArchitecture.current,
        osBand: LegacyOSBand = LegacyOSBand.current
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.architecture = architecture
        self.osBand = osBand
    }

    var isAvailable: Bool { availability.isAvailable }

    // MARK: - Lifecycle

    /// App launch must not start the root helper: the plan limits health probes
    /// to an active limit or a visible Settings pane. A saved session is the
    /// only reason to verify at launch (it owns the hardware).
    func start() {
        guard !started else { return }
        started = true
        guard sessionStore.load() != nil else {
            status = .notEnabled
            client.releaseConnection()
            return
        }
        taskRefresh()
    }

    /// Event-driven hysteresis. The app's existing battery snapshot is the
    /// trigger; no polling timer is introduced. Only a decision change writes.
    func start(batteries: AnyPublisher<BatteryStatus, Never>) {
        self.batteries = batteries
        guard cancellables.isEmpty else { return }
        batteries
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] battery in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleBattery(level: battery.percentage,
                                             isOnAC: battery.isConnectedToPower)
                }
            }
            .store(in: &cancellables)
    }

    func handleBattery(level: Int, isOnAC: Bool) async {
        guard isAvailable, let session, status != .temporarilyChargingToFull else { return }
        guard session.requestedLimit > 0 else { return }
        if !isOnAC {
            // No AC means nothing to gate; do not touch the hardware.
            lastAppliedAllowsCharging = nil
            return
        }
        let decision = LegacyChargeLimitEngine(limit: session.requestedLimit).decide(
            batteryLevel: level,
            isOnAC: isOnAC,
            currentlyAllowing: lastAppliedAllowsCharging
        )
        switch decision {
        case .none:
            return
        case .allowCharging:
            lastAppliedAllowsCharging = true
        case .inhibitCharging:
            lastAppliedAllowsCharging = false
        }
        await reapply(limit: session.requestedLimit)
    }

    /// Called when the battery Settings pane becomes visible. This is the only
    /// place availability is probed, so an idle app never spawns the helper.
    func refreshAvailability() async {
        await refresh()
    }

    func stop() {
        started = false
        cancellables.removeAll()
        batteries = nil
        lastAppliedAllowsCharging = nil
        client.releaseConnection()
    }

    // MARK: - Commands

    func refresh() async {
        guard osBand.allowsLegacyLimiter else {
            availability = .unavailable(.unsupportedOS)
            status = .notEnabled
            return
        }
        let probe: LegacyChargeLimitProbeFacts
        do {
            probe = try await client.probe()
        } catch {
            availability = .unavailable(.helperUnavailable)
            status = .notEnabled
            return
        }
        availability = LegacyChargeLimitAvailability.resolve(
            probe: probe,
            architecture: architecture,
            osBand: osBand,
            helperAvailable: true
        )
        guard let loaded = sessionStore.load() else {
            session = nil
            selectedLimit = nil
            status = .notEnabled
            // No active limit owns the hardware: let the helper idle-exit.
            client.releaseConnection()
            return
        }
        session = loaded
        selectedLimit = loaded.requestedLimit
        status = .checkingHardware
        let outcome = try? await client.verify(loaded.requestedLimit)
        if let outcome, outcome.verified {
            status = .holding(at: loaded.requestedLimit)
        } else {
            status = .unverified
        }
    }

    @discardableResult
    func setLimit(_ limit: Int) async -> Bool {
        guard isAvailable else {
            status = .unsupported
            return false
        }
        guard Self.limits.contains(limit) else { return false }
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.setLimit(limit, expectedLimit: session?.requestedLimit)
            guard outcome.succeeded else {
                status = outcome.error == .ownershipConflict ? .externalChange : .failed
                return false
            }
            let newSession = LegacyChargeLimitSession(
                requestedLimit: limit,
                originalLimit: session?.originalLimit
            )
            saveSession(newSession)
            selectedLimit = limit
            status = .holding(at: limit)
            return true
        } catch LegacyChargeLimitClientError.helperUnavailable {
            availability = .unavailable(.helperUnavailable)
            status = .notEnabled
            return false
        } catch {
            status = .failed
            return false
        }
    }

    @discardableResult
    func disable() async -> Bool {
        guard isAvailable else {
            status = .unsupported
            return false
        }
        isApplying = true
        defer { isApplying = false }
        do {
            // The helper owns the stock value; the app only knows its intent, so
            // it must not fabricate an "expected hardware value" here. Ownership
            // is enforced by the helper's journal, not by a client guess.
            let outcome = try await client.disable(expectedLimit: nil)
            guard outcome.succeeded else {
                status = .restoreFailed
                return false
            }
            saveSession(nil)
            selectedLimit = nil
            status = .notEnabled
            client.releaseConnection()
            return true
        } catch {
            status = .restoreFailed
            return false
        }
    }

    @discardableResult
    func chargeToFullOnce() async -> Bool {
        guard isAvailable, session != nil else { return false }
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.chargeToFullOnce()
            guard outcome.succeeded else {
                status = .failed
                return false
            }
            status = .temporarilyChargingToFull
            return true
        } catch {
            status = .failed
            return false
        }
    }

    @discardableResult
    func cancelChargeToFull() async -> Bool {
        guard isAvailable, let session else { return false }
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await client.cancelChargeToFull()
            guard outcome.succeeded else {
                status = .restoreFailed
                return false
            }
            status = .holding(at: session.requestedLimit)
            return true
        } catch {
            status = .restoreFailed
            return false
        }
    }

    /// Re-applies the held limit after wake or a power-source change.
    ///
    /// Only runs when a session exists and no temporary override is in flight:
    /// a full-charge override must not be interrupted by ordinary battery
    /// events. A failure here is surfaced, never silently retried.
    func handleWake() async {
        guard isAvailable, let session, status != .temporarilyChargingToFull else { return }
        // The previous gate is untrusted after sleep; re-evaluate from scratch.
        lastAppliedAllowsCharging = nil
        do {
            let outcome = try await client.setLimit(session.requestedLimit, expectedLimit: session.requestedLimit)
            if outcome.succeeded {
                status = .holding(at: session.requestedLimit)
            } else if outcome.error == .ownershipConflict {
                status = .externalChange
            } else {
                status = .failed
            }
        } catch {
            status = .failed
        }
    }

    // MARK: - Helpers

    private func reapply(limit: Int) async {
        do {
            let outcome = try await client.setLimit(limit, expectedLimit: limit)
            if outcome.succeeded {
                status = .holding(at: limit)
            } else if outcome.error == .ownershipConflict {
                status = .externalChange
            }
        } catch {
            status = .failed
        }
    }

    private func saveSession(_ session: LegacyChargeLimitSession?) {
        self.session = session
        if let session {
            sessionStore.save(session)
        } else {
            sessionStore.clear()
        }
    }
}

private extension LegacyChargeLimitController {
    nonisolated func taskRefresh() {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }
}