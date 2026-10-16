import Combine
import Foundation

/// Owns the Low Power Mode write path and the state the UI shows.
///
/// It only talks to the privileged helper when the feature is enabled, so the
/// daemon is never contacted — and therefore never started — while the opt-in
/// is off. Mirrors the demand-gated shape of `MobileBatteryController`.
@MainActor
final class LowPowerModeController: ObservableObject {
    /// The optimistic state shown while a change is in flight, seeded from the
    /// read side the app already has (`BatteryStatus.isLowPowerMode`).
    @Published private(set) var isLowPowerMode: Bool
    @Published private(set) var isApplying = false
    @Published private(set) var lastError: String?

    private let client: any LowPowerModeClienting
    private var isEnabled = false
    /// True once the helper has answered a read, after which its value is the
    /// source of truth and the lagging `ProcessInfo` seed is ignored.
    private var hasAuthoritativeReading = false
    private var isStopped = false
    private var refreshTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        client: any LowPowerModeClienting = XPCPrivilegedHelperClient(),
        initialIsLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) {
        self.client = client
        self.isLowPowerMode = initialIsLowPowerMode
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Gates the controller from the opt-in. Disabling clears any error and
    /// stops further helper contact.
    func setEnabled(_ enabled: Bool) {
        guard !isStopped, isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled {
            generation &+= 1
            refreshTask?.cancel()
            refreshTask = nil
            isApplying = false
            lastError = nil
        }
    }

    /// Seeds the displayed value from the system read side without contacting
    /// the helper. Called when `BatteryMonitor` reports a fresh snapshot.
    ///
    /// Only a fallback: `ProcessInfo.isLowPowerModeEnabled` is cached per process
    /// and can lag the real system state, so once the helper has answered a read
    /// this value must not overwrite it.
    func updateFromSystemRead(_ enabled: Bool) {
        guard !isStopped, !isApplying, !hasAuthoritativeReading else { return }
        isLowPowerMode = enabled
    }

    func refresh() {
        // A visibility-driven read must not supersede an accepted write.
        guard !isStopped, isEnabled, !isApplying else { return }
        generation &+= 1
        let requestGeneration = generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled, !self.isStopped, self.isEnabled,
                  self.generation == requestGeneration else { return }
            do {
                let enabled = try await self.client.readLowPowerMode()
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.isLowPowerMode = enabled
                self.hasAuthoritativeReading = true
                self.lastError = nil
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.lastError = error.localizedDescription
            }
        }
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard !isStopped, isEnabled, !isApplying else { return }
        isApplying = true
        lastError = nil
        let previous = isLowPowerMode
        isLowPowerMode = enabled
        generation &+= 1
        let requestGeneration = generation
        Task { [weak self] in
            guard let self, !Task.isCancelled, !self.isStopped, self.isEnabled,
                  self.generation == requestGeneration else { return }
            do {
                let observed = try await self.client.setLowPowerMode(enabled)
                guard self.generation == requestGeneration else { return }
                self.isLowPowerMode = observed
                self.hasAuthoritativeReading = true
            } catch {
                guard self.generation == requestGeneration else { return }
                self.isLowPowerMode = previous
                self.lastError = error.localizedDescription
            }
            guard self.generation == requestGeneration else { return }
            self.isApplying = false
        }
    }

    func stop() {
        isStopped = true
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
    }
}
