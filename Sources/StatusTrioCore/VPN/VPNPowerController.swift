import Foundation

enum VPNConnectionResult: Equatable, Sendable {
    case confirmed
    case rejected
    case failed
    case timedOut
}

protocol VPNConnectionControlling: AnyObject, Sendable {
    func setConnected(_ connected: Bool, serviceID: String) async -> VPNConnectionResult
}

enum VPNPowerFailure: Equatable, Sendable {
    case requestRejected
    case failed
    case timedOut
}

struct VPNPowerState: Equatable, Sendable {
    var isChanging = false
    var failure: VPNPowerFailure?
}

/// Owns one in-flight user request per row. `SCNetworkConnectionStart/Stop`
/// returning true only means the system accepted the request; the result here
/// comes from the backend's status callback or its bounded timeout.
@MainActor
final class VPNPowerController: ObservableObject {
    private let backend: any VPNConnectionControlling
    var refresh: @MainActor () -> Void
    private var failureClearTask: Task<Void, Never>?

    @Published private(set) var state = VPNPowerState()

    init(
        backend: any VPNConnectionControlling,
        refresh: @escaping @MainActor () -> Void = {}
    ) {
        self.backend = backend
        self.refresh = refresh
    }

    /// `enabled` is the switch's desired state. While a request is pending the
    /// row is disabled, so a second action cannot race the first.
    func setPower(_ enabled: Bool, status: VPNStatus) async {
        guard !state.isChanging,
              status.showsPowerControl,
              let service = status.powerControlService,
              enabled != status.powerControlIsOn else {
            return
        }

        failureClearTask?.cancel()
        state = VPNPowerState(isChanging: true)
        let result = await backend.setConnected(enabled, serviceID: service.serviceID)
        state.isChanging = false

        switch result {
        case .confirmed:
            state.failure = nil
        case .rejected:
            publishFailure(.requestRejected)
        case .failed:
            publishFailure(.failed)
        case .timedOut:
            publishFailure(.timedOut)
        }
        // Always re-read. A timeout is not proof of failure, and a rejection can
        // still leave the system reporting a transition.
        refresh()
    }

    private func publishFailure(_ failure: VPNPowerFailure) {
        state.failure = failure
        failureClearTask?.cancel()
        failureClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.state.failure = nil
        }
    }
}
