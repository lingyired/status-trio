import Combine
import Foundation
import PowerHelperProtocol

/// Owns the High Power Mode write path and the state the UI shows.
///
/// Mirrors `LowPowerModeController`: it only talks to the privileged helper
/// while the helper-backed power control is enabled, so the daemon is never
/// started for a Mac that never opted in. High Power Mode is mutually exclusive
/// with Low Power Mode; the daemon clears the other mode before switching, so
/// the app does not issue a second write of its own.
@MainActor
final class HighPowerModeController: ObservableObject {
    /// Whether this Mac reports High Power Mode support. False hides the control.
    @Published private(set) var isSupported = false
    @Published private(set) var isHighPowerMode = false
    @Published private(set) var isApplying = false
    @Published private(set) var lastError: String?
    /// The daemon answered the legacy surface but not the version handshake.
    /// The app cannot use the High Power Mode methods until the helper is
    /// replaced by the one shipped with this build, so the UI says so instead of
    /// failing silently.
    @Published private(set) var needsHelperUpdate = false
    /// True once a probe has completed, so the UI does not flash a control
    /// before the first answer.
    @Published private(set) var hasProbed = false

    /// Fired after a write the helper accepted with the mode turned on, so the
    /// display layer can re-read the mutually-exclusive Low Power Mode state.
    /// Set by `SystemStatusStore`; nil until bound.
    var onSuccessfulWrite: (() -> Void)?

    private let client: any HighPowerModeClienting
    private var isEnabled = false
    private var isStopped = false
    private var probeTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    private let platformSupported: Bool

    static var supportsCurrentPlatform: Bool {
#if arch(arm64)
        if #available(macOS 26.4, *) { return true }
#endif
        return false
    }

    init(
        client: any HighPowerModeClienting = XPCPrivilegedHighPowerClient(),
        platformSupported: Bool = HighPowerModeController.supportsCurrentPlatform
    ) {
        self.client = client
        self.platformSupported = platformSupported
    }

    deinit {
        probeTask?.cancel()
    }

    /// Gates the controller from the helper opt-in. Disabling stops further
    /// helper contact and clears the state the UI was showing.
    func setEnabled(_ enabled: Bool) {
        guard !isStopped, isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            refresh()
            return
        }
        generation &+= 1
        probeTask?.cancel()
        probeTask = nil
        isApplying = false
        lastError = nil
        needsHelperUpdate = false
        isSupported = false
        isHighPowerMode = false
        hasProbed = false
    }

    /// Re-probes support and the current state without writing anything.
    func refresh() {
        guard !isStopped, isEnabled, !isApplying, platformSupported else { return }
        generation &+= 1
        let requestGeneration = generation
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let version: Int
            do {
                version = try await self.client.protocolVersion()
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                await self.classifyProbeFailure()
                return
            }
            do {
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.needsHelperUpdate = false
                guard version >= PowerHelperProtocolVersion.highPowerMode else {
                    self.needsHelperUpdate = true
                    self.isSupported = false
                    self.hasProbed = true
                    return
                }
                let supported = try await self.client.highPowerModeSupported()
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.needsHelperUpdate = false
                self.isSupported = supported
                self.lastError = nil
                guard supported else {
                    self.hasProbed = true
                    return
                }
                let enabled = try await self.client.readHighPowerMode()
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.isHighPowerMode = enabled
                self.hasProbed = true
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.needsHelperUpdate = false
                self.lastError = error.localizedDescription
                self.hasProbed = true
            }
        }
    }

    /// A call to a selector the daemon does not implement invalidates the
    /// connection. Asking the legacy Low Power Mode read separates an outdated
    /// helper (answers it) from a helper that is simply not reachable (does not).
    private func classifyProbeFailure() async {
        let legacyAnswers = await client.canReadLowPowerMode()
        guard !Task.isCancelled else { return }
        needsHelperUpdate = legacyAnswers
        isSupported = false
        hasProbed = true
        lastError = nil
    }

    func setHighPowerMode(_ enabled: Bool) {
        guard !isStopped, isEnabled, !isApplying, isSupported, !needsHelperUpdate else { return }
        isApplying = true
        lastError = nil
        let previous = isHighPowerMode
        isHighPowerMode = enabled
        generation &+= 1
        let requestGeneration = generation
        Task { [weak self] in
            guard let self, !Task.isCancelled, !self.isStopped, self.isEnabled,
                  self.generation == requestGeneration else { return }
            var turnedOn = false
            do {
                let observed = try await self.client.setHighPowerMode(enabled)
                guard self.generation == requestGeneration else { return }
                self.isHighPowerMode = observed
                turnedOn = observed
            } catch {
                guard self.generation == requestGeneration else { return }
                self.isHighPowerMode = previous
                self.lastError = error.localizedDescription
            }
            guard self.generation == requestGeneration else { return }
            self.isApplying = false
            if turnedOn { self.onSuccessfulWrite?() }
        }
    }

    func stop() {
        isStopped = true
        generation &+= 1
        probeTask?.cancel()
        probeTask = nil
    }
}
