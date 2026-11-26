import Combine
import Foundation

/// Owns the optional low-frequency `.background` hardware demand for the whole
/// app lifetime. The status-panel view model stops its own subscriptions when
/// the popover closes, so background history cannot live there without leaking
/// a sampling loop or silently ignoring later setting changes.
///
/// This controller never starts a second sampling loop: it only adds/removes a
/// demand entry on the shared `HardwareMetricsService`.
@MainActor
final class HardwareBackgroundDemandController {
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var reconcileScheduled = false

    init(store: SystemStatusStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$hardwareBackgroundHistoryEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$enabledPopupSections.map { _ in () }.eraseToAnyPublisher(),
            settings.$showsHardwareRings.map { _ in () }.eraseToAnyPublisher(),
            settings.$showsHardwareSummaryRow.map { _ in () }.eraseToAnyPublisher(),
            settings.$enabledHardwareRingSlots.map { _ in () }.eraseToAnyPublisher(),
            settings.$enabledHardwareSummaryMetrics.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareCPUUsageRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareGPUUsageRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareMemoryRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareNetworkRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareTemperatureRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            settings.$hardwareDiskRefreshSeconds.map { _ in () }.eraseToAnyPublisher(),
            store.$isPopoverVisible.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(triggers)
            .sink { [weak self] in self?.scheduleReconcile() }
            .store(in: &cancellables)
        reconcile()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        reconcileScheduled = false
        cancellables.removeAll()
        store.hardwareMetrics.end(.background)
    }

    /// Coalesce a burst of setting changes into one demand evaluation, running
    /// after `@Published` has committed the new value (it fires in willSet).
    private func scheduleReconcile() {
        guard isStarted, !reconcileScheduled else { return }
        reconcileScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.reconcileScheduled = false
            guard self.isStarted else { return }
            self.reconcile()
        }
    }

    private func reconcile() {
        guard isStarted else { return }
        let sectionOn = settings.enabledPopupSections.contains(.hardwareMonitor)
        let panelOpen = store.isPopoverVisible
        store.hardwareMetrics.backgroundCadenceProvider = { [settings] group in
            TimeInterval(settings.hardwareRefreshSeconds(for: group))
        }
        guard sectionOn, !panelOpen, settings.hardwareBackgroundHistoryEnabled else {
            store.hardwareMetrics.end(.background)
            return
        }
        let summary = HardwareMetricDemandResolver.PanelSummaryInputs(
            showsHardwareRings: settings.showsHardwareRings,
            enabledRingSlots: settings.enabledHardwareRingSlots,
            showsHardwareSummaryRow: settings.showsHardwareSummaryRow,
            enabledSummaryMetrics: settings.enabledHardwareSummaryMetrics
        )
        let metrics = HardwareMetricDemandResolver.backgroundHistoryMetrics(summary: summary)
        if metrics.isEmpty {
            store.hardwareMetrics.end(.background)
        } else {
            store.hardwareMetrics.begin(.background, metrics: metrics)
        }
    }
}
