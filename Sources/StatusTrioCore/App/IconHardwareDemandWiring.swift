import Combine
import Foundation

/// Turns the icon view model's separately published source demand into the
/// per-surface hardware-metric owner claims.
///
/// Demand is deliberately not derived from the scene's pixels or from the
/// persisted `iconConfiguration`: two bindings can draw the same picture while
/// needing different samples, and the persisted snapshot is only rewritten by
/// the editor API. Extracted from `AppEnvironment` so tests can drive the real
/// view model and demand publisher without building the whole application.
@MainActor
final class IconHardwareDemandWiring {
    private let apply: (IconSourceDemandPolicy.HardwareRingDemands) -> Void
    private var latestDemand: IconPresentationDemand
    private var latestPlacement: AppIconPlacement
    private var latestMetrics: IconSourceDemandPolicy.HardwareRingDemands?
    private var cancellables = Set<AnyCancellable>()

    init(
        demand: IconPresentationDemand = .none,
        placement: AppIconPlacement,
        apply: @escaping (IconSourceDemandPolicy.HardwareRingDemands) -> Void
    ) {
        self.latestDemand = demand
        self.latestPlacement = placement
        self.apply = apply
    }

    /// Subscribes to the resolved source demand and the icon placement. Demand is
    /// published independently from the scene pixels, so a binding switch that
    /// draws the same picture still starts or stops sampling.
    func start(
        demands: AnyPublisher<IconPresentationDemand, Never>,
        placements: AnyPublisher<AppIconPlacement, Never>
    ) {
        Publishers.CombineLatest(demands, placements)
            .sink { [weak self] demand, placement in
                guard let self else { return }
                self.latestDemand = demand
                self.latestPlacement = placement
                self.reconcile()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    /// Recomputes the per-surface metric demand from the latest resolution.
    func reconcile() {
        let metrics = latestDemand.hardwareMetricIDs
        let demands: IconSourceDemandPolicy.HardwareRingDemands
        if metrics.isEmpty {
            demands = .none
        } else {
            demands = .init(
                menuBar: latestPlacement.showsMenuBarIcon ? metrics : nil,
                dock: latestPlacement.showsDockIcon ? metrics : nil
            )
        }
        guard demands != latestMetrics else { return }
        latestMetrics = demands
        apply(demands)
    }
}
