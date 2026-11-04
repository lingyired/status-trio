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

    func start() {
        guard !started else { return }
        started = true
        taskRefresh()
    }

    func stop() {
        started = false
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
            let outcome = try await client.disable(expectedLimit: session?.requestedLimit)
            guard outcome.succeeded else {
                status = .restoreFailed
                return false
            }
            saveSession(nil)
            selectedLimit = nil
            status = .notEnabled
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