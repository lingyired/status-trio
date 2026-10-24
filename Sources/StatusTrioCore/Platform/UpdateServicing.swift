import Combine
import Foundation

@MainActor
protocol UpdateServicing: AnyObject {
    var state: UpdateControlState { get }
    var statePublisher: AnyPublisher<UpdateControlState, Never> { get }
    func start()
    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
}

@MainActor
final class UpdateStateFacade: ObservableObject {
    @Published private(set) var state: UpdateControlState

    let service: any UpdateServicing
    private var cancellable: AnyCancellable?

    init(service: any UpdateServicing) {
        self.service = service
        state = service.state
        cancellable = service.statePublisher
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, self.state != state else { return }
                self.state = state
            }
    }

    var canCheckForUpdates: Bool { state.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool { state.automaticallyChecksForUpdates }
    var delivery: UpdateDelivery { state.delivery }

    func start() {
        service.start()
        refresh()
    }

    func checkForUpdates() {
        service.checkForUpdates()
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        service.setAutomaticallyChecksForUpdates(enabled)
        refresh()
    }

    private func refresh() {
        if state != service.state {
            state = service.state
        }
    }
}

@MainActor
final class SystemManagedUpdateService: UpdateServicing {
    let state = UpdateControlState.systemManaged
    var statePublisher: AnyPublisher<UpdateControlState, Never> {
        Just(state).eraseToAnyPublisher()
    }

    func start() {}
    func checkForUpdates() {}
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {}
}

struct PlatformUpdateStatus: Equatable, Sendable {
    let delivery: UpdateDelivery
    let availability: CapabilityAvailability
    let reason: String

    static let storeSystemManaged = PlatformUpdateStatus(
        delivery: .systemManaged,
        availability: .available,
        reason: "distribution.system-managed-updates"
    )
}
