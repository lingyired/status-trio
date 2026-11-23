import Foundation
import Combine

/// Production provider. Resolves the shared manager lazily so a store that
/// never binds the low-power settings does not touch the helper at all.
@MainActor
struct SharedHelperReadiness: HelperReadinessProviding {
    var isReady: Bool { PrivilegedHelperManager.shared.isReady }

    var readinessPublisher: AnyPublisher<Bool, Never> {
        PrivilegedHelperManager.shared.readinessPublisher
    }

    func refreshStatus() { PrivilegedHelperManager.shared.refreshForUse() }
    func setBackgroundRecoveryNeeded(_ needed: Bool) {
        PrivilegedHelperManager.shared.setBackgroundRecoveryNeeded(needed)
    }
    var recoveryProbePublisher: AnyPublisher<Void, Never> {
        PrivilegedHelperManager.shared.recoveryProbePublisher
    }
    func verifyForUse() async -> Bool { await PrivilegedHelperManager.shared.verifyForUse() }
}

extension PrivilegedHelperManager: HelperReadinessProviding {
    /// The same `isReady` rule the UI gates the switches with, re-published so
    /// the automation can re-evaluate when approval or responsiveness lands.
    func refreshStatus() { refreshForUse() }

    var readinessPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3($isEnabled, $status, $isHelperResponsive)
            .map { enabled, status, isResponsive in
                enabled && status != .notRegistered && isResponsive
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
