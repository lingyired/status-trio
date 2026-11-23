import Combine
import Foundation

/// Store-side stand-in for the Direct-only `PrivilegedHelperManager`.
///
/// The App Store build has no privileged helper by design, so every helper-backed
/// control is permanently unavailable. This type supplies the same observable
/// surface the shared UI reads so the views compile unchanged and render a
/// disabled/needs-setup state. It never registers anything.
@MainActor
final class PrivilegedHelperManager: ObservableObject {
    static let shared = PrivilegedHelperManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var isReady = false
    @Published private(set) var didFailLastOperation = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isHelperResponsive = false

    var isAvailable: Bool { false }
    var requiresApproval: Bool { false }

    func refreshForApprovalSettings() {}
    func openLoginItemsSettings() {}
    func setEnabled(_ enabled: Bool) { isEnabled = false }
    func refreshForUse() {}
    func refreshAfterActivation() {}
    func setBackgroundRecoveryNeeded(_ needed: Bool) {}
    func verifyForUse() async -> Bool { false }

    var readinessPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var recoveryProbePublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
}

extension PrivilegedHelperManager: PrivilegedHelperControlling {}
