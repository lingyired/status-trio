import Combine
import Foundation

/// Reconciles the resolved live-source demand with the surfaces that are
/// actually drawing the icon.
///
/// The scene resolver is surface-agnostic: it reports every binding the icon
/// would need. The menu bar and the Dock share that scene, but a hidden surface
/// must not keep an external package's file watcher alive. `stop()` only drops
/// subscriptions; `start()` replays the current demand and placement so a
/// restarted environment resumes the same watchers.
@MainActor
final class IconLiveDemandWiring {
    private let apply: (Set<IconContentBinding>) -> Void
    private var latestDemand: IconPresentationDemand
    private var latestPlacement: AppIconPlacement
    private var cancellables = Set<AnyCancellable>()

    init(
        demand: IconPresentationDemand = .none,
        placement: AppIconPlacement,
        apply: @escaping (Set<IconContentBinding>) -> Void
    ) {
        self.latestDemand = demand
        self.latestPlacement = placement
        self.apply = apply
    }

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

    var activeSubscriptionCount: Int { cancellables.count }

    func reconcile() {
        apply(IconLiveDemandPolicy.subscribedBindings(
            demand: latestDemand,
            showsMenuBar: latestPlacement.showsMenuBarIcon,
            showsDock: latestPlacement.showsDockIcon
        ))
    }
}

enum IconLiveDemandPolicy {
    /// No visible surface owns any file watcher or metric read.
    static func subscribedBindings(
        demand: IconPresentationDemand,
        showsMenuBar: Bool,
        showsDock: Bool
    ) -> Set<IconContentBinding> {
        guard showsMenuBar || showsDock else { return [] }
        return demand.subscribedBindings
    }
}
