import AppKit
import Combine

enum ManagedChargeLimitStatus: Equatable, Sendable {
    case systemManaged
    case checking
    case active(Int)
    case temporarilyOverridden(Int)
    case failed
    case externalChange
}

/// One writer for both managed limits and the existing temporary-full action.
/// Monitoring exists only while the user has opted into a managed limit.
@MainActor
final class ManagedChargeLimitController: ObservableObject, BatteryChargeControlling {
    @Published private(set) var selectedLimit: Int?
    @Published private(set) var availableLimits: [Int] = []
    @Published private(set) var isApplying = false
    @Published private(set) var status: ManagedChargeLimitStatus = .systemManaged

    var capability: ChargeToFullNowCapability { backend.capability }
    var isAvailable: Bool { capability.isAvailable }
    var managedRestoreLimit: Int? {
        guard let session, !session.isPaused, !session.isPending else { return nil }
        return session.limit
    }

    private let backend: any BatteryChargeControlling
    private let sessionStore: any ManagedChargeLimitSessionStoring
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var session: ManagedChargeLimitSession?
    private var batteries: AnyPublisher<BatteryStatus, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var previousBattery: BatteryStatus?
    private var isSleeping = false
    private var hasStopped = false
    private var automaticTask: Task<Void, Never>?
    private var needsReconciliation = false
    private var needsOverrideResume = false

    init(
        backend: any BatteryChargeControlling,
        sessionStore: any ManagedChargeLimitSessionStoring = VolatileManagedChargeLimitSessionStore(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.notificationCenter = notificationCenter
        self.now = now
        let saved = sessionStore.load()
        session = saved?.isValid == true ? saved : nil
        selectedLimit = session?.limit
        if let session {
            status = session.isPaused ? .externalChange
                : session.isTemporarilyOverridden ? .temporarilyOverridden(session.limit)
                : .checking
        }
    }

    func start(batteries: AnyPublisher<BatteryStatus, Never>) {
        guard self.batteries == nil, !hasStopped else { return }
        self.batteries = batteries
        installMonitoringIfNeeded()
    }

    func stop() {
        hasStopped = true
        automaticTask?.cancel()
        automaticTask = nil
        cancellables.removeAll()
        batteries = nil
        previousBattery = nil
        needsReconciliation = false
        needsOverrideResume = false
    }

    func readState() -> ChargeToFullNowDeviceState { backend.readState() }

    /// Settings demand only; the default/system-managed mode never polls PowerUI.
    func refresh() {
        guard !hasStopped, isAvailable, !isApplying else { return }
        let state = backend.readState()
        updateChoices(state)
        guard state.errorMessage == nil else { status = .failed; return }
        guard var saved = session else { status = .systemManaged; return }
        if saved.isRestoringSystem {
            if ChargeToFullNowController.restoreIsVerified(limit: saved.originalLimit, state: state) {
                clearSession()
            } else { status = .failed }
            return
        }
        if saved.isPaused { status = .externalChange; return }
        if state.mclEnabledRawValue == 1, state.mclLimit == saved.limit,
           !shouldPreserveOverride(saved, state: state) {
            saved.isPending = false
            saved.isTemporarilyOverridden = false
            saved.overrideAcceptedAt = nil
            save(saved)
            status = .active(saved.limit)
        } else if saved.isPending {
            status = .failed
        } else if hasExternalLimit(state, comparedTo: saved.limit) {
            saved.isPaused = true
            save(saved)
            status = .externalChange
        } else if shouldPreserveOverride(saved, state: state) {
            saved.isTemporarilyOverridden = true
            if saved.overrideAcceptedAt == nil { saved.overrideAcceptedAt = now() }
            save(saved)
            status = .temporarilyOverridden(saved.limit)
        } else {
            status = .checking
        }
    }

    func selectLimit(_ limit: Int?) async {
        _ = await applySelection(limit)
    }

    func reapply() async {
        guard let selectedLimit else { return }
        _ = await applySelection(selectedLimit)
    }

    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        guard canWrite else { return .failure }
        isApplying = true
        defer { finishOperation() }
        let result = await backend.chargeToFullNow()
        guard !hasStopped, !Task.isCancelled else { return .failure }
        if result.succeeded, var session, !session.isPaused, !session.isPending {
            session.isTemporarilyOverridden = true
            session.overrideAcceptedAt = now()
            save(session)
            status = .temporarilyOverridden(session.limit)
        }
        return result
    }

    func restoreChargeLimit(to limit: Int) async -> ChargeToFullNowWriteResult {
        if let managedRestoreLimit { return await applySelection(managedRestoreLimit) }
        guard canWrite else { return .failure }
        isApplying = true
        defer { finishOperation() }
        return await backend.restoreChargeLimit(to: limit)
    }

    /// Called by existing battery snapshots, with connection/completion de-duplication.
    func updateBattery(_ battery: BatteryStatus) async {
        guard !hasStopped, session != nil, battery.isPresent else { return }
        let previous = previousBattery
        previousBattery = battery
        let full = battery.isCharged || battery.percentage >= 100
        let wasFull = previous.map { $0.isCharged || $0.percentage >= 100 }
        guard previous == nil || previous?.isConnectedToPower != battery.isConnectedToPower
                || wasFull != full else { return }
        await reconcile(resumeOverride: !battery.isConnectedToPower || full)
    }

    func handleWake() async {
        guard !hasStopped, session != nil else { return }
        isSleeping = false
        let resume = previousBattery.map {
            !$0.isConnectedToPower || $0.isCharged || $0.percentage >= 100
        } ?? false
        await reconcile(resumeOverride: resume)
    }

    private var canWrite: Bool {
        !hasStopped && !isSleeping && !isApplying && !Task.isCancelled && isAvailable
    }

    private func applySelection(
        _ requested: Int?, automatic: Bool = false, resumeOverride: Bool = false
    ) async -> ChargeToFullNowWriteResult {
        guard !hasStopped, !isSleeping, !Task.isCancelled else { return .failure }
        if requested == nil, session == nil {
            status = .systemManaged
            return .success
        }
        guard canWrite else { return .failure }
        if automatic, session?.isPaused == true { return .failure }

        let before = backend.readState()
        updateChoices(before)
        guard before.errorMessage == nil,
              let current = before.mclLimit, (0...100).contains(current),
              [0, 1, 3].contains(before.mclEnabledRawValue) else {
            status = .failed
            return .failure
        }
        let restoring = requested == nil || (automatic && session?.isRestoringSystem == true)
        let target = restoring ? session?.originalLimit ?? 100 : requested ?? 100
        let alreadyApplied = before.mclEnabledRawValue == 1 && current == target
        guard target == 100 || availableLimits.contains(target) || alreadyApplied else {
            status = .failed
            return .failure
        }

        if automatic, var saved = session {
            if saved.isPending, !alreadyApplied {
                status = .failed
                return .failure
            }
            if !restoring, hasExternalLimit(before, comparedTo: saved.limit) {
                saved.isPaused = true
                save(saved)
                status = .externalChange
                return .failure
            }
            if !restoring, !resumeOverride, shouldPreserveOverride(saved, state: before) {
                saved.isTemporarilyOverridden = true
                if saved.overrideAcceptedAt == nil { saved.overrideAcceptedAt = now() }
                save(saved)
                status = .temporarilyOverridden(saved.limit)
                return .success
            }
        }

        let original = session?.originalLimit
            ?? ((80...100).contains(current) && before.mclEnabledRawValue != 0 ? current : 100)
        isApplying = true
        defer { finishOperation() }
        if !restoring, let requested {
            // The write may partially succeed or the process may stop before readback.
            // Keep the original limit recoverable in either case; never auto-retry it.
            save(ManagedChargeLimitSession(limit: requested, originalLimit: original, isPending: true))
        } else if var saved = session {
            saved.isPending = true
            saved.isRestoringSystem = true
            saved.isPaused = false
            save(saved)
        }
        let result: ChargeToFullNowWriteResult
        if alreadyApplied {
            result = .success
        } else {
            result = await backend.setChargeLimit(to: target, expectedState: before)
        }
        guard !hasStopped, !Task.isCancelled else { return .failure }
        let after = backend.readState()
        guard result.succeeded, ChargeToFullNowController.restoreIsVerified(limit: target, state: after) else {
            status = .failed
            return .failure
        }
        if !restoring, let requested {
            save(ManagedChargeLimitSession(limit: requested, originalLimit: original))
            status = .active(requested)
            installMonitoringIfNeeded()
        } else {
            clearSession()
        }
        return .success
    }

    private func reconcile(resumeOverride: Bool) async {
        guard let session, !hasStopped, !isSleeping else { return }
        if isApplying {
            needsReconciliation = true
            needsOverrideResume = needsOverrideResume || resumeOverride
            return
        }
        _ = await applySelection(session.limit, automatic: true, resumeOverride: resumeOverride)
    }

    private func finishOperation() {
        isApplying = false
        guard needsReconciliation, !hasStopped else { return }
        let resume = needsOverrideResume
        needsReconciliation = false
        needsOverrideResume = false
        automaticTask = Task { @MainActor [weak self] in
            await self?.reconcile(resumeOverride: resume)
        }
    }

    private func save(_ value: ManagedChargeLimitSession) {
        session = value
        selectedLimit = value.limit
        sessionStore.save(value)
    }

    private func updateChoices(_ state: ChargeToFullNowDeviceState) {
        availableLimits = state.errorMessage == nil
            ? Array(Set(state.availableChargeLimits.filter { (80..<100).contains($0) })).sorted()
            : []
    }

    private func hasExternalLimit(_ state: ChargeToFullNowDeviceState, comparedTo limit: Int) -> Bool {
        state.errorMessage == nil && state.mclEnabledRawValue == 1
            && state.mclLimit.map { (80..<100).contains($0) && $0 != limit } == true
    }

    private func shouldPreserveOverride(_ saved: ManagedChargeLimitSession, state: ChargeToFullNowDeviceState) -> Bool {
        if state.indicatesTemporaryOverride { return true }
        guard saved.isTemporarilyOverridden else { return false }
        guard state.mclEnabledRawValue == 1, state.mclLimit == saved.limit else { return true }
        // A successful native request can take up to ten seconds to propagate.
        // Evaluate grace only on existing events; there is no timer or polling.
        guard let acceptedAt = saved.overrideAcceptedAt else { return false }
        return (0..<15).contains(now().timeIntervalSince(acceptedAt))
    }

    private func clearSession() {
        session = nil
        selectedLimit = nil
        sessionStore.clear()
        cancellables.removeAll()
        previousBattery = nil
        status = .systemManaged
    }

    private func installMonitoringIfNeeded() {
        guard session != nil, cancellables.isEmpty, let batteries, !hasStopped else { return }
        batteries.removeDuplicates { lhs, rhs in
            lhs.isPresent == rhs.isPresent && lhs.isConnectedToPower == rhs.isConnectedToPower
                && (lhs.isCharged || lhs.percentage >= 100) == (rhs.isCharged || rhs.percentage >= 100)
        }
        .sink { [weak self] battery in
            Task { @MainActor [weak self] in await self?.updateBattery(battery) }
        }.store(in: &cancellables)
        notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.handleWake() }
            }.store(in: &cancellables)
        notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.isSleeping = true }
            }.store(in: &cancellables)
    }
}
